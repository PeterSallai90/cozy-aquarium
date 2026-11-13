"""PreToolUse hook for the consultant agents (consultant-security, consultant-analyst).

Usage (from the agent's frontmatter): py consultant_guard.py <notes-folder-name>

The consultants are read-only everywhere except their own notes folder
consultants/<notes-folder-name>/ (gitignored). This hook enforces that:

- Write / Edit / NotebookEdit: allowed only for .md and .txt files inside
  consultants/<notes-folder-name>/, never for a file named CLAUDE.md.
- Bash: allowed only when every command in the line is on a read-only allowlist
  (git history and diffs, gh read commands, file listing and searching, the
  project's read-only check scripts). Output redirection, command substitution
  and any option not explicitly allowed (git, gdlint, gdformat) are blocked.
- PowerShell: always blocked (the agents use Bash).

Exit code 2 blocks the tool call; stderr is shown to the agent as the reason.
The default is to block: anything not recognised as read-only is refused.
"""

import json
import os
import re
import shlex
import sys
from pathlib import Path

TEXT_SUFFIXES = {".md", ".txt"}

# Harmless stderr redirections, removed only as exact standalone tokens before the
# check for output redirection (so `2>/dev/nullX` is left alone and then blocked).
SAFE_REDIRECTS = re.compile(r"(?<!\S)(?:2>/dev/null|2>&1)(?=$|[\s;&|])")

OPERATORS = {"&&", "||", ";", "|"}

# Utilities with no way to write files or run programs (extra checks in check_command).
READ_UTILS = {
    "ls", "cat", "head", "tail", "wc", "grep", "rg", "find", "cut", "diff", "stat", "du",
    "pwd", "echo", "jq", "basename", "dirname", "realpath", "which",
}  # fmt: skip

FIND_BLOCKED_PREFIXES = ("-delete", "-exec", "-ok", "-fprint", "-fls")
RG_BLOCKED_PREFIXES = ("--pre", "--hostname", "--search-zip")

# git: explicit allowlist per subcommand. Long options must match exactly (git accepts
# abbreviated long options, so anything not listed here is refused, abbreviations too).
# Short options are checked letter by letter; digits are always allowed (-5, -U3).
GIT_LOG_LONG = {
    "--stat", "--oneline", "--patch", "--no-patch", "--name-only", "--name-status", "--graph",
    "--decorate", "--no-decorate", "--all", "--since", "--until", "--after", "--before",
    "--author", "--committer", "--grep", "--format", "--pretty", "--date", "--max-count",
    "--skip", "--no-merges", "--merges", "--first-parent", "--reverse", "--abbrev-commit",
    "--no-abbrev-commit", "--abbrev", "--numstat", "--shortstat", "--summary", "--follow",
    "--no-color", "--color", "--diff-filter", "--cached", "--staged", "--full-history",
    "--simplify-by-decoration", "--branches", "--tags", "--remotes", "--no-ext-diff",
    "--no-textconv", "--word-diff", "--color-words", "--check", "--exit-code", "--quiet",
    "--root", "--left-right", "--cherry-pick", "--ancestry-path", "--no-index", "--count",
    "--numbered", "--email", "--relative-date", "--dirstat", "--compact-summary",
}  # fmt: skip
GIT_LOG_SHORT = set("pnsSGwUqmcrtabMCRLiu")
GIT_SPECS: dict[str, tuple[set[str], set[str]]] = {
    "log": (GIT_LOG_LONG, GIT_LOG_SHORT),
    "show": (GIT_LOG_LONG, GIT_LOG_SHORT),
    "diff": (GIT_LOG_LONG, GIT_LOG_SHORT),
    "rev-list": (GIT_LOG_LONG, GIT_LOG_SHORT),
    "shortlog": (GIT_LOG_LONG, GIT_LOG_SHORT | set("e")),
    "reflog": (GIT_LOG_LONG, GIT_LOG_SHORT),
    "blame": (
        {"--porcelain", "--line-porcelain", "--show-name", "--show-number", "--date", "--abbrev"},
        set("LwMCplsetf"),
    ),
    "status": (
        {"--short", "--branch", "--porcelain", "--long", "--untracked-files", "--ignored", "--no-color"},
        set("sbuv"),
    ),
    "ls-files": (
        {"--cached", "--others", "--modified", "--deleted", "--stage", "--ignored", "--unmerged",
         "--exclude-standard", "--full-name", "--deduplicate", "--eol", "--killed"},
        set("comdsiukzt"),
    ),  # fmt: skip
    "ls-tree": (
        {"--name-only", "--long", "--full-name", "--full-tree", "--abbrev"},
        set("rtdlz"),
    ),
    "rev-parse": (
        {"--show-toplevel", "--abbrev-ref", "--short", "--verify", "--git-dir", "--git-common-dir",
         "--is-inside-work-tree", "--symbolic-full-name", "--show-prefix", "--show-cdup", "--all",
         "--branches", "--tags", "--remotes", "--quiet"},
        set("q"),
    ),  # fmt: skip
    "grep": (
        {"--line-number", "--ignore-case", "--files-with-matches", "--files-without-match",
         "--count", "--word-regexp", "--invert-match", "--fixed-strings", "--extended-regexp",
         "--basic-regexp", "--perl-regexp", "--no-color", "--color", "--cached", "--untracked",
         "--no-index", "--full-name", "--name-only", "--heading", "--break", "--show-function",
         "--function-context", "--context", "--after-context", "--before-context", "--max-depth",
         "--and", "--or", "--not", "--all-match", "--quiet", "--text"},
        set("nilLwvchHeEFGPaqzIpWABC"),
    ),  # fmt: skip
    "cat-file": (set(), set("ptse")),
    "describe": (
        {"--tags", "--always", "--abbrev", "--long", "--contains", "--match", "--exact-match"},
        set(),
    ),
}
GIT_BRANCH_LONG = {
    "--list", "--all", "--remotes", "--show-current", "--merged", "--no-merged", "--contains",
    "--no-contains", "--points-at", "--no-color", "--color", "--verbose", "--format", "--sort",
    "--abbrev",
}  # fmt: skip
# Flags that put `git branch` in list mode (positional arguments are then patterns).
GIT_BRANCH_LISTING = {"--list", "-l", "--merged", "--no-merged", "--contains", "--no-contains", "--points-at"}
GIT_TAG_LONG = {
    "--list", "--sort", "--contains", "--no-contains", "--merged", "--no-merged",
    "--points-at", "--format", "--no-color", "--color",
}  # fmt: skip

GH_READ = {
    "issue": {"list", "view", "status"},
    "pr": {"list", "view", "diff", "checks", "status"},
    "project": {"list", "view", "item-list", "field-list"},
    "run": {"list", "view"},
    "release": {"list", "view"},
    "label": {"list"},
    "ruleset": {"list", "view", "check"},
    "repo": {"view"},
    "search": {"issues", "prs", "code", "repos", "commits"},
    "workflow": {"list", "view"},
    "milestone": {"list", "view"},
}
GH_API_BLOCKED_LONG = ("--method", "--field", "--raw-field", "--input")
GH_API_SHORT_CLUSTER = re.compile(r"^-[A-Za-z]*[XfF]")

PY_ALLOWED = {
    ("tools/scripts/check_asset_licenses.py",),
    ("tools/scripts/check_translations.py",),
    ("tools/scripts/check_project_settings.py",),
    ("tools/scripts/generate_pot.py", "--check"),
}


def block(reason: str) -> None:
    sys.stderr.write(f"consultant_guard: blocked. {reason}\n")
    sys.exit(2)


def project_dir(payload: dict) -> Path:
    return Path(os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or ".").resolve()


def check_file_tool(payload: dict, notes: str) -> None:
    tool_input = payload.get("tool_input") or {}
    raw = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not raw:
        block("No file path given.")
    root = project_dir(payload)
    allowed = (root / "consultants" / notes).resolve()
    target = Path(raw)
    if not target.is_absolute():
        target = root / target
    target = target.resolve()
    if allowed != target and allowed not in target.parents:
        block(f"You may only write inside {allowed}. Everything else is read-only.")
    if target.name.lower() == "claude.md":
        block("Files named CLAUDE.md may not be written.")
    if target.suffix.lower() not in TEXT_SUFFIXES:
        block("Only .md and .txt text files may be written in your notes folder.")


def split_commands(command: str) -> list[list[str]]:
    command = command.replace("\r", " ").replace("\n", " ; ")
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
    lexer.whitespace_split = True
    lexer.commenters = ""  # bash only treats # as a comment at the start of a word
    commands: list[list[str]] = [[]]
    try:
        for token in lexer:
            if token in OPERATORS:
                commands.append([])
            elif token and set(token) <= set(";&|<>()"):
                block(f"Operator '{token}' is not allowed (no redirection, subshells or background jobs).")
            else:
                commands[-1].append(token)
    except ValueError as err:
        block(f"Could not parse the command: {err}")
    return [c for c in commands if c]


def check_options(label: str, args: list[str], long_ok: set[str], short_ok: set[str]) -> list[str]:
    """Refuse every option not explicitly allowed; return the positional arguments."""
    positional: list[str] = []
    for i, arg in enumerate(args):
        if arg == "--":
            positional.extend(args[i + 1 :])
            break
        if arg.startswith("--"):
            if arg.split("=", 1)[0] not in long_ok:
                block(f"`{label} {arg}` is not an allowed option.")
        elif arg.startswith("-") and len(arg) > 1:
            if any(not (c in short_ok or c.isdigit()) for c in arg[1:]):
                block(f"`{label} {arg}` is not an allowed option.")
        else:
            positional.append(arg)
    return positional


def check_git(args: list[str]) -> None:
    if args and args[0] == "--no-pager":
        args = args[1:]
    if not args or args[0].startswith("-"):
        block("git needs a subcommand directly (no global options).")
    sub, rest = args[0], args[1:]
    if sub == "branch":
        positional = check_options("git branch", rest, GIT_BRANCH_LONG, set("arvl"))
        if positional and not any(a.split("=", 1)[0] in GIT_BRANCH_LISTING for a in rest):
            block("`git branch <name>` creates a branch; only listing is allowed.")
    elif sub == "tag":
        positional = check_options("git tag", rest, GIT_TAG_LONG, set("ln"))
        if positional and not any(a in ("-l", "--list") for a in rest):
            block("Only `git tag --list` is allowed.")
    elif sub == "remote":
        if rest not in ([], ["-v"], ["--verbose"]) and not (len(rest) == 2 and rest[0] == "get-url"):
            block("Only `git remote -v` and `git remote get-url <name>` are allowed.")
    elif sub in GIT_SPECS:
        if sub == "reflog" and rest[:1] and rest[0] in ("expire", "delete", "exists"):
            block("Only reading the reflog is allowed.")
        long_ok, short_ok = GIT_SPECS[sub]
        check_options(f"git {sub}", rest, long_ok, short_ok)
    else:
        block(f"`git {sub}` is not on the read-only list.")


def check_gh(args: list[str]) -> None:
    if not args:
        block("Bare gh is not allowed.")
    if args[0] == "api":
        for a in args[1:]:
            if a.startswith(GH_API_BLOCKED_LONG) or GH_API_SHORT_CLUSTER.match(a):
                block("gh api is allowed only as a plain GET (no -X, --method, -f, -F, --input).")
            if a.strip("/").lower().startswith("graphql"):
                block("gh api graphql is not allowed; use gh issue/pr/project commands.")
        return
    group = GH_READ.get(args[0])
    if group is None or len(args) < 2 or args[1] not in group:
        block(f"`gh {' '.join(args[:2])}` is not on the read-only list.")


def check_command(tokens: list[str]) -> None:
    if "/" in tokens[0] or "\\" in tokens[0]:
        block("Run programs by bare name, not by path.")
    prog = tokens[0].lower().removesuffix(".exe")
    args = tokens[1:]
    if prog in READ_UTILS:
        if prog == "find" and any(a.startswith(FIND_BLOCKED_PREFIXES) for a in args):
            block("find actions that write or execute are not allowed.")
        if prog == "rg" and any(a.startswith(RG_BLOCKED_PREFIXES) or re.match(r"^-[A-Za-z]*z", a) for a in args):
            block("rg options that run a command are not allowed.")
        if prog == "tail" and any(a.startswith("--f") or re.match(r"^-[A-Za-z]*[fF]", a) for a in args):
            block("tail --follow never ends; not allowed.")
        return
    if prog == "git":
        check_git(args)
        return
    if prog == "gh":
        check_gh(args)
        return
    if prog == "gdlint":
        if args and not any(a.startswith("-") for a in args):
            return
        block("gdlint is allowed only with path arguments and no options.")
    if prog == "gdformat":
        flags = [a for a in args if a.startswith("-")]
        paths = [a for a in args if not a.startswith("-")]
        if flags and paths and set(flags) <= {"--check", "--diff"}:
            return
        block("gdformat is allowed only as `gdformat --check|--diff <paths>`.")
    if prog in ("py", "python", "python3"):
        rest = tuple(a.replace("\\", "/") for a in args if a != "-I")
        if rest in PY_ALLOWED:
            return
        block("Only the project's read-only check scripts may be run with Python.")
    block(f"`{prog}` is not on the read-only command list.")


def check_bash(payload: dict) -> None:
    command = (payload.get("tool_input") or {}).get("command", "")
    if any(marker in command for marker in ("`", "$(", "<(", ">(", "$'", '$"')):
        block("Command substitution and $'..' quoting are not allowed.")
    for tokens in split_commands(SAFE_REDIRECTS.sub(" ", command)):
        check_command(tokens)


def main() -> None:
    if len(sys.argv) != 2 or not re.fullmatch(r"[a-z0-9-]+", sys.argv[1]):
        block("Hook misconfigured: expected the notes folder name as the only argument.")
    notes = sys.argv[1]
    payload = json.load(sys.stdin)
    tool = payload.get("tool_name", "")
    if tool in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
        check_file_tool(payload, notes)
    elif tool == "Bash":
        check_bash(payload)
    elif tool == "PowerShell":
        block("PowerShell is not available to consultants; use the read-only Bash commands.")
    sys.exit(0)


if __name__ == "__main__":
    main()
