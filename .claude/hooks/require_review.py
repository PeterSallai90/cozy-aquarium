"""PreToolUse hook for Bash and PowerShell commands.

Blocks `gh pr create` (alias `gh pr new`) unless the code reviewer's approval
record (.claude/state/review-approved: line 1 branch name, line 2 full HEAD SHA)
names the branch of the pull request and its current commit, and that commit
is pushed.

Blocks `gh pr merge` when the pull request targets main: only the product
owner merges into main.

Quoted strings and heredocs are masked before matching, so a commit message or
pull request body that mentions these commands is not mistaken for them; the
arguments are then read from the original command. This is a guard against
mistakes, not a security boundary: a command hidden in a quoted string, such as
`bash -c 'gh pr create'`, is not seen. The rulesets and the owner gate are the
boundary.

Exit code 2 blocks the tool call; stderr is shown to Claude as the reason.
"""

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

APPROVAL_FILE = Path(".claude") / "state" / "review-approved"

QUOTED = re.compile(r"""'[^']*'|"(?:[^"\\]|\\.)*\"""", re.DOTALL)
# A quoted program path such as 'C:\Program Files\GitHub CLI\gh.exe' stays visible.
GH_PATH = re.compile(r"""^(['"])[^'"\n]*[\\/]gh(?:\.exe)?\1$""", re.IGNORECASE)
# Bash heredocs (<<EOF, <<-'EOF') and PowerShell here-strings (@' '@, @" "@): the body is masked.
HEREDOC = re.compile(r"""<<-?\s*(['"]?)(\w+)\1[^\n]*\n(.*?^\s*\2\s*$)""", re.DOTALL | re.MULTILINE)
HERE_STRING = re.compile(r"""@(['"])\n(.*?^\1@)""", re.DOTALL | re.MULTILINE)

# gh, optionally with a path, and -R/--repo before or after the pr subcommand.
REPO_FLAG = r"(?:\s+(?:-R|--repo)(?:=|\s+)\S+)*"
GH_PR = r"(?<![\w.-])(?:[^\s;&|(){}]*[\\/])?gh(?:\.exe)?['\"]?" + REPO_FLAG + r"\s+pr" + REPO_FLAG
PR_CREATE = re.compile(GH_PR + r"\s+(?:create|new)\b", re.IGNORECASE)
PR_MERGE = re.compile(GH_PR + r"\s+merge\b", re.IGNORECASE)
SEPARATOR = re.compile(r"[;&|\n]")

# gh pr merge flags that take a value, so their value is not mistaken for the PR argument.
MERGE_VALUE_FLAGS = {
    "-A",
    "--author-email",
    "-b",
    "--body",
    "-F",
    "--body-file",
    "--match-head-commit",
    "-R",
    "--repo",
    "-t",
    "--subject",
}


def block(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(2)


def run(args: list[str], cwd: str) -> str | None:
    try:
        result = subprocess.run(
            args, cwd=cwd, capture_output=True, text=True, encoding="utf-8", timeout=20
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def mask(command: str) -> str:
    """Return the command with quoted and heredoc text replaced by '_', keeping every offset."""

    def mask_body(match: re.Match[str]) -> str:
        start = match.start(match.lastindex or 0) - match.start()
        text = match.group(0)
        return text[:start] + re.sub(r"[^\n]", "_", text[start:])

    def mask_quoted(match: re.Match[str]) -> str:
        text = match.group(0)
        if GH_PATH.match(text):
            return text.replace(" ", "_")
        return text[0] + "_" * (len(text) - 2) + text[-1]

    command = HEREDOC.sub(mask_body, command)
    command = HERE_STRING.sub(mask_body, command)
    return QUOTED.sub(mask_quoted, command)


def gh_tokens(command: str, masked: str, match: re.Match[str]) -> list[str]:
    """Tokens of the original gh command that the match starts, up to the next separator."""
    separator = SEPARATOR.search(masked, match.end())
    text = command[match.start() : separator.start() if separator else len(command)]
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


def flag_value(tokens: list[str], names: tuple[str, ...]) -> str | None:
    for index, token in enumerate(tokens):
        for name in names:
            if token == name:
                return tokens[index + 1] if index + 1 < len(tokens) else ""
            if token.startswith(name + "="):
                return token.split("=", 1)[1]
    return None


def check_pr_create(tokens: list[str], cwd: str) -> None:
    root = run(["git", "rev-parse", "--show-toplevel"], cwd)
    if not root:
        block("Blocked: gh pr create - could not find the Git repository.")

    head_flag = flag_value(tokens, ("-H", "--head"))
    if head_flag is not None:
        branch = head_flag.split(":")[-1]
    else:
        branch = run(["git", "branch", "--show-current"], cwd) or ""
    head = run(["git", "rev-parse", "--verify", "-q", f"refs/heads/{branch}"], cwd) if branch else None
    if not branch or not head:
        block(
            f"Blocked: gh pr create - could not find the local branch '{branch}' and its commit."
        )

    record = Path(root) / APPROVAL_FILE
    if not record.is_file():
        block(
            "Blocked: gh pr create needs a code review approval. "
            f"{APPROVAL_FILE.as_posix()} does not exist. "
            "Run the code-reviewer agent on this branch first."
        )

    lines = record.read_text(encoding="utf-8").split()
    approved_branch = lines[0] if len(lines) > 0 else ""
    approved_sha = lines[1] if len(lines) > 1 else ""
    if approved_branch != branch or approved_sha != head:
        block(
            "Blocked: gh pr create - the code review approval is not for the current commit. "
            f"Approved: branch '{approved_branch or '?'}' at {approved_sha or '?'}; "
            f"current: branch '{branch}' at {head}. "
            "Any change after the review needs a new review by the code-reviewer agent."
        )

    pushed = run(["git", "rev-parse", "--verify", "-q", f"refs/remotes/origin/{branch}"], cwd)
    if pushed != head:
        block(
            f"Blocked: gh pr create - origin/{branch} is not at the approved commit {head}. "
            "Push the approved commit first (git push -u origin <branch>), with no other changes."
        )


def check_pr_merge(tokens: list[str], cwd: str) -> None:
    lowered = [token.lower() for token in tokens]
    after_merge = tokens[lowered.index("merge") + 1 :] if "merge" in lowered else []
    pr_arg: list[str] = []
    skip_next = False
    for token in after_merge:
        if skip_next:
            skip_next = False
            continue
        if token in MERGE_VALUE_FLAGS:
            skip_next = True
            continue
        if token.startswith("-"):
            continue
        pr_arg = [token]
        break

    view = ["gh", "pr", "view", *pr_arg]
    repo = flag_value(tokens, ("-R", "--repo"))
    if repo is not None:
        view += ["--repo", repo]
    base = run([*view, "--json", "baseRefName", "-q", ".baseRefName"], cwd)
    if base is None:
        block(
            "Blocked: gh pr merge - could not find the pull request's base branch "
            "with gh pr view, so it cannot be checked against main."
        )
    if base == "main":
        block(
            "Blocked: gh pr merge on a pull request into main. "
            "Only the product owner merges into main (release pull requests)."
        )


def main() -> None:
    data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    command = str(data.get("tool_input", {}).get("command", ""))
    cwd = str(data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    masked = mask(command)

    for match in PR_CREATE.finditer(masked):
        check_pr_create(gh_tokens(command, masked, match), cwd)
    for match in PR_MERGE.finditer(masked):
        check_pr_merge(gh_tokens(command, masked, match), cwd)
    sys.exit(0)


if __name__ == "__main__":
    main()
