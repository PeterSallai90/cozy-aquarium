"""PreToolUse hook for the consultant agents (consultant-security, consultant-analyst).

Usage (from the agent's frontmatter): py consultant_guard.py <notes-folder-name>

The consultants are read-only everywhere except their own notes folder
consultants/<notes-folder-name>/ (gitignored). This hook enforces that:

- Write / Edit / NotebookEdit: allowed only for .md and .txt files inside
  consultants/<notes-folder-name>/.
- Bash: allowed only when every command in the line is on a read-only allowlist
  (git history and diffs, gh read commands, file listing and searching, the
  project's read-only check scripts). Output redirection, command substitution
  and write-capable flags are blocked.
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

# Harmless stderr redirections removed before checking for output redirection.
SAFE_REDIRECTS = re.compile(r"\s*2>\s*/dev/null|\s*2>&1")

OPERATORS = {"&&", "||", ";", "|"}

READ_UTILS = {
    "ls", "cat", "head", "tail", "wc", "grep", "rg", "find", "file", "sort", "cut",
    "diff", "stat", "du", "pwd", "echo", "jq", "basename", "dirname", "realpath", "which",
}  # fmt: skip

FIND_BLOCKED = {"-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"}

GIT_READ = {"log", "show", "diff", "status", "ls-files", "ls-tree", "blame", "rev-parse",
            "grep", "shortlog", "cat-file", "rev-list", "describe", "reflog", "remote"}  # fmt: skip
GIT_BRANCH_FLAGS = {"-a", "-r", "-v", "-vv", "--list", "--all", "--remotes", "--show-current",
                    "--merged", "--no-merged", "--contains", "--no-color"}  # fmt: skip
GIT_BLOCKED_ARGS = ("--output", "--ext-diff", "--textconv", "-o", "-O", "--open-files-in-pager")

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
GH_API_BLOCKED = {"-X", "--method", "-f", "-F", "--field", "--raw-field", "--input"}

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
    if target.suffix.lower() not in TEXT_SUFFIXES:
        block("Only .md and .txt text files may be written in your notes folder.")


def split_commands(command: str) -> list[list[str]]:
    command = command.replace("\r", " ").replace("\n", " ; ")
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
    lexer.whitespace_split = True
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


def check_git(args: list[str]) -> None:
    if args and args[0] == "--no-pager":
        args = args[1:]
    if not args:
        block("Bare git is not allowed.")
    sub = args[0]
    if any(a.startswith(GIT_BLOCKED_ARGS) for a in args[1:]):
        block("git output/ext-diff options are not allowed.")
    if sub == "branch":
        if all(a in GIT_BRANCH_FLAGS for a in args[1:]):
            return
        block("Only listing git branches is allowed.")
    if sub == "remote":
        if args[1:] in ([], ["-v"]):
            return
        block("Only `git remote -v` is allowed.")
    if sub == "reflog":
        if args[1:2] in ([], ["show"]) or args[1].startswith("-"):
            return
        block("Only reading the reflog is allowed.")
    if sub == "tag":
        if len(args) > 1 and args[1] in ("-l", "--list"):
            return
        block("Only `git tag --list` is allowed.")
    if sub not in GIT_READ:
        block(f"`git {sub}` is not on the read-only list.")


def check_gh(args: list[str]) -> None:
    if not args:
        block("Bare gh is not allowed.")
    if args[0] == "api":
        if any(a in GH_API_BLOCKED or a.startswith(tuple(GH_API_BLOCKED)) for a in args[1:]):
            block("gh api is allowed only as a plain GET (no -X, --method, -f, -F, --input).")
        if any(a.startswith("graphql") for a in args[1:]):
            block("gh api graphql is not allowed; use gh issue/pr/project commands.")
        return
    group = GH_READ.get(args[0])
    if group is None or len(args) < 2 or args[1] not in group:
        block(f"`gh {' '.join(args[:2])}` is not on the read-only list.")


def check_command(tokens: list[str]) -> None:
    prog = tokens[0].replace("\\", "/").rsplit("/", 1)[-1].lower().removesuffix(".exe")
    args = tokens[1:]
    if prog in READ_UTILS:
        if prog == "find" and any(a in FIND_BLOCKED for a in args):
            block("find actions that write or execute are not allowed.")
        if prog == "sort" and any(a.startswith(("-o", "--output")) for a in args):
            block("sort may not write an output file.")
        if prog == "rg" and any(a.startswith("--pre") for a in args):
            block("rg --pre runs a command and is not allowed.")
        return
    if prog == "git":
        check_git(args)
        return
    if prog == "gh":
        check_gh(args)
        return
    if prog == "gdlint":
        return
    if prog == "gdformat":
        if "--check" in args or "--diff" in args:
            return
        block("gdformat is allowed only with --check or --diff.")
    if prog in ("py", "python", "python3"):
        rest = tuple(a.replace("\\", "/") for a in args if a != "-I")
        if rest in PY_ALLOWED:
            return
        block("Only the project's read-only check scripts may be run with Python.")
    block(f"`{prog}` is not on the read-only command list.")


def check_bash(payload: dict) -> None:
    command = (payload.get("tool_input") or {}).get("command", "")
    if "`" in command or "$(" in command or "<(" in command or ">(" in command:
        block("Command substitution is not allowed.")
    for tokens in split_commands(SAFE_REDIRECTS.sub("", command)):
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
