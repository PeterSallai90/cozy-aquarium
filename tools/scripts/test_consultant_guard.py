"""Regression tests for .claude/hooks/consultant_guard.py (run as a subprocess)."""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".claude" / "hooks" / "consultant_guard.py"


def run_hook(tool: str, tool_input: dict, notes: str = "security") -> int:
    payload = {"tool_name": tool, "tool_input": tool_input, "cwd": str(ROOT)}
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(ROOT))
    result = subprocess.run(
        [sys.executable, str(HOOK), notes],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    return result.returncode


class ConsultantGuardTest(unittest.TestCase):
    def assert_bash_blocked(self, command: str) -> None:
        self.assertEqual(run_hook("Bash", {"command": command}), 2, command)

    def assert_bash_allowed(self, command: str) -> None:
        self.assertEqual(run_hook("Bash", {"command": command}), 0, command)

    def assert_write(self, path: str, expected: int, tool: str = "Write") -> None:
        self.assertEqual(run_hook(tool, {"file_path": path}), expected, path)

    def test_bash_bypasses_are_blocked(self) -> None:
        for command in [
            "echo a#b > file",
            "ls a#b; rm -rf game",
            "echo x #c\nrm -rf game",
            "sort -ro out file",
            "sort -uo out file",
            "sort --outp=out file",
            "sort --compress-program=sh file",
            "git grep --open=sh foo",
            "git grep --open-files-in-pager=sh foo",
            "git grep -O foo",
            "git grep -nO foo",
            "git grep -o foo",
            "git log --output=out",
            "git log --outp=out",
            "git diff --ext-diff",
            "git diff --ext=sh",
            "git show --textconv HEAD",
            "git -c core.pager=sh log",
            "git --exec-path=x log",
            "git ls-remote --upload-pack=sh x",
            "git branch newbranch",
            "git branch -D foo",
            "git branch -m a b",
            "git tag v1",
            "git tag -d v1",
            "git remote add x y",
            "git reflog expire --all",
            "git reflog delete HEAD@{0}",
            "git config user.name x",
            "gdlint -d game",
            "gdlint",
            "gdformat game",
            "gdformat -d game",
            "gdformat --check --line-length=1 game",
            "file -C",
            "file x",
            "echo hi 2>/dev/nullX",
            "echo hi 2>/dev/null/x",
            "echo hi 2>&1x",
            "echo hi >&2",
            "tail -f log",
            "tail --follow log",
            "tail -nf log",
            "rg --pre sh foo",
            "rg --pre-glob x foo",
            "rg -z foo",
            "rg --search-zip foo",
            "find . -fprint out",
            "find . -fls out",
            "find . -delete",
            "find . -exec rm {} ;",
            "echo $'a'",
            "./ls",
        ]:
            with self.subTest(command=command):
                self.assert_bash_blocked(command)

    def test_earlier_cases_are_blocked(self) -> None:
        for command in [
            "gh issue comment 1 --body x",
            "gh issue create",
            "echo x > file",
            "echo x >> file",
            "echo $(rm -rf x)",
            "echo `rm x`",
            "ls\nrm -rf game",
            "ls && rm -rf game",
            "ls & rm x",
            "gh api -f a=b repos/x/y",
            "gh api -fa=b repos/x/y",
            "gh api -X POST repos/x/y",
            "gh api -XPOST repos/x/y",
            "gh api --method POST repos/x/y",
            "gh api --input x repos/x/y",
            "gh api graphql -f query=x",
            "gh api /graphql",
            "python tools/scripts/generate_pot.py",
            "python -c print(1)",
            "rm file",
            "curl http://example.com",
            "bash -c ls",
            "sh -c ls",
        ]:
            with self.subTest(command=command):
                self.assert_bash_blocked(command)

    def test_read_only_commands_are_allowed(self) -> None:
        for command in [
            "gh issue list --state all --json number,title 2>/dev/null | jq length",
            "gh issue view 135 --comments",
            "gh api repos/x/y/issues",
            "git log --oneline -20 && git show HEAD --stat",
            "git log --since=2.days -n 5 -p -- game/model",
            "git --no-pager diff --stat main..HEAD",
            "git status --short",
            "git ls-files game",
            "git blame -L 1,5 README.md",
            "git grep -n -i -l foo",
            "git grep -n foo -- game",
            "git rev-parse --show-toplevel",
            "git rev-parse HEAD",
            "git branch",
            "git branch -a",
            "git branch --contains HEAD",
            "git branch --merged main",
            "git reflog show",
            "git reflog -5",
            "git tag -l",
            "git tag --list v*",
            "git remote -v",
            "ls game | grep model",
            "ls a#b",
            "echo a#b",
            "cat README.md | head -5 | wc -l",
            "find game -name *.gd -type f",
            "grep -rn foo game 2>&1",
            "rg -n foo game",
            "tail -n 5 README.md",
            "gdlint game",
            "gdformat --check game",
            "python tools/scripts/generate_pot.py --check",
            "python tools/scripts/check_translations.py",
            "py -I tools/scripts/check_asset_licenses.py",
        ]:
            with self.subTest(command=command):
                self.assert_bash_allowed(command)

    def test_powershell_is_blocked(self) -> None:
        self.assertEqual(run_hook("PowerShell", {"command": "Get-ChildItem"}), 2)

    def test_file_writes(self) -> None:
        notes = ROOT / "consultants" / "security"
        self.assert_write(str(notes / "findings.md"), 0)
        self.assert_write(str(notes / "sub" / "x.txt"), 0, tool="Edit")
        self.assert_write("consultants/security/rel.md", 0)
        self.assert_write(str(ROOT / "game" / "x.md"), 2)
        self.assert_write(str(notes / ".." / ".." / "game" / "x.md"), 2)
        self.assert_write(str(notes / ".." / "analyst" / "x.md"), 2)
        self.assert_write(str(notes / "run.sh"), 2)
        self.assert_write(str(notes / "x.gd"), 2)
        self.assert_write(str(notes / "noext"), 2)
        self.assert_write(str(notes / "CLAUDE.md"), 2)
        self.assert_write(str(notes / "claude.MD"), 2)
        self.assert_write(str(notes / "sub" / "Claude.md"), 2)
        self.assert_write(str(ROOT / "CLAUDE.md"), 2)

    def test_misconfigured_hook_blocks(self) -> None:
        self.assertEqual(run_hook("Bash", {"command": "ls"}, notes="Bad Name"), 2)


if __name__ == "__main__":
    unittest.main()
