"""PreToolUse hook for Bash and PowerShell commands.

Blocks `gh pr create` (alias `gh pr new`) unless the code reviewer's approval
record (.claude/state/review-approved: line 1 branch name, line 2 full HEAD SHA)
names the branch of the pull request and its current commit, and that commit
is pushed.

Blocks `gh pr merge` when the pull request targets main: only the product
owner merges into main.

Quoted strings and heredocs are removed before matching, so a commit message or
pull request body that mentions these commands is not mistaken for them. This
is a guard against mistakes, not a security boundary; the rulesets and the
owner gate are.

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

# A quoted program path such as & 'C:\Program Files\GitHub CLI\gh.exe' becomes plain gh.
QUOTED_GH_PATH = re.compile(r"""(['"])[^'"\n]*[\\/]gh(?:\.exe)?\1""", re.IGNORECASE)
# Bash heredocs (<<EOF, <<-'EOF') and PowerShell here-strings (@' '@, @" "@).
HEREDOC = re.compile(r"""<<-?\s*(['"]?)(\w+)\1[^\n]*\n.*?^\s*\2\s*$""", re.DOTALL | re.MULTILINE)
HERE_STRING = re.compile(r"""@(['"])\n.*?^\1@""", re.DOTALL | re.MULTILINE)
QUOTED = re.compile(r"""'[^']*'|"(?:[^"\\]|\\.)*\"""", re.DOTALL)

# gh, optionally with a path and global flags (-R/--repo) before the pr subcommand.
GH_PR = (
    r"(?<![\w.-])(?:[^\s;&|(){}]*[\\/])?gh(?:\.exe)?"
    r"(?:\s+(?:-R|--repo)(?:=|\s+)\S+)*\s+pr\s+"
)
PR_CREATE = re.compile(GH_PR + r"(?:create|new)\b([^;&|\n]*)", re.IGNORECASE)
PR_MERGE = re.compile(GH_PR + r"merge\b([^;&|\n]*)", re.IGNORECASE)

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


def strip_text(command: str) -> str:
    command = QUOTED_GH_PATH.sub(" gh", command)
    command = HEREDOC.sub(" ", command)
    command = HERE_STRING.sub(" ", command)
    return QUOTED.sub("''", command)


def tokens_of(arguments: str) -> list[str]:
    try:
        return shlex.split(arguments)
    except ValueError:
        return arguments.split()


def flag_value(tokens: list[str], names: tuple[str, ...]) -> str | None:
    for index, token in enumerate(tokens):
        for name in names:
            if token == name and index + 1 < len(tokens):
                return tokens[index + 1]
            if token.startswith(name + "="):
                return token.split("=", 1)[1]
    return None


def check_pr_create(arguments: str, cwd: str) -> None:
    root = run(["git", "rev-parse", "--show-toplevel"], cwd)
    if not root:
        block("Blocked: gh pr create - could not find the Git repository.")

    head_flag = flag_value(tokens_of(arguments), ("-H", "--head"))
    branch = head_flag.split(":")[-1] if head_flag else run(["git", "branch", "--show-current"], cwd)
    head = run(["git", "rev-parse", f"refs/heads/{branch}"], cwd) if branch else None
    if not branch or not head:
        block("Blocked: gh pr create - could not read the branch and its commit with git.")

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

    pushed = run(["git", "rev-parse", f"refs/remotes/origin/{branch}"], cwd)
    if pushed != head:
        block(
            f"Blocked: gh pr create - origin/{branch} is not at the approved commit {head}. "
            "Push the approved commit first (git push -u origin <branch>), with no other changes."
        )


def merge_pr_argument(arguments: str) -> list[str]:
    tokens = tokens_of(arguments)
    pr_args: list[str] = []
    skip_next = False
    for token in tokens:
        if skip_next:
            skip_next = False
            continue
        if token in MERGE_VALUE_FLAGS:
            skip_next = True
            continue
        if token.startswith("-"):
            continue
        if not pr_args:
            pr_args = [token]
    return pr_args


def check_pr_merge(match: re.Match[str], cwd: str) -> None:
    # Global and subcommand --repo both name the repository of the pull request.
    repo = flag_value(tokens_of(match.group(0)), ("-R", "--repo"))
    view = ["gh", "pr", "view", *merge_pr_argument(match.group(1))]
    if repo:
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
    command = strip_text(str(data.get("tool_input", {}).get("command", "")))
    cwd = str(data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())

    for match in PR_CREATE.finditer(command):
        check_pr_create(match.group(1), cwd)
    for match in PR_MERGE.finditer(command):
        check_pr_merge(match, cwd)
    sys.exit(0)


if __name__ == "__main__":
    main()
