"""PreToolUse hook for Bash and PowerShell commands.

Blocks `gh pr create` unless the code reviewer's approval record
(.claude/state/review-approved: line 1 branch name, line 2 full HEAD SHA)
names the current branch and the current HEAD commit.

Blocks `gh pr merge` when the pull request targets main: only the product
owner merges into main.

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
# Only where a command starts (beginning, after ; & | newline ( or $( ), so that text such as a
# commit message mentioning "gh pr create" is not mistaken for the command.
COMMAND_START = r"(?:^|[;&|\n(]|\$\()\s*['\"]?(?:[^;&|\n'\"]*[\\/])?"
GH = r"gh(?:\.exe)?['\"]?\s+pr\s+"
PR_CREATE = re.compile(COMMAND_START + GH + r"create\b")
PR_MERGE = re.compile(COMMAND_START + GH + r"merge\b([^;&|\n]*)")
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


def check_pr_create(cwd: str) -> None:
    root = run(["git", "rev-parse", "--show-toplevel"], cwd)
    branch = run(["git", "branch", "--show-current"], cwd)
    head = run(["git", "rev-parse", "HEAD"], cwd)
    if not root or not branch or not head:
        block("Blocked: gh pr create - could not read the current branch and HEAD with git.")

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


def merge_pr_argument(arguments: str) -> list[str]:
    try:
        tokens = shlex.split(arguments)
    except ValueError:
        tokens = arguments.split()
    pr_args: list[str] = []
    repo_args: list[str] = []
    skip_next = False
    for index, token in enumerate(tokens):
        if skip_next:
            skip_next = False
            continue
        if token in MERGE_VALUE_FLAGS:
            skip_next = True
            if token in ("-R", "--repo") and index + 1 < len(tokens):
                repo_args = ["--repo", tokens[index + 1]]
            continue
        if token.startswith("--repo="):
            repo_args = ["--repo", token.split("=", 1)[1]]
            continue
        if token.startswith("-"):
            continue
        if not pr_args:
            pr_args = [token]
    return pr_args + repo_args


def check_pr_merge(arguments: str, cwd: str) -> None:
    view = ["gh", "pr", "view", *merge_pr_argument(arguments)]
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

    if PR_CREATE.search(command):
        check_pr_create(cwd)
    for match in PR_MERGE.finditer(command):
        check_pr_merge(match.group(1), cwd)
    sys.exit(0)


if __name__ == "__main__":
    main()
