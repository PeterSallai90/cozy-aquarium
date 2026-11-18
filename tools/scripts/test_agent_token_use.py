"""Checks for the agent token-use rules (#142) in .claude/agents and CLAUDE.md.

Frontmatter values are hard-coded from develop on purpose: CI uses a shallow checkout, so
there is nothing to diff against.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / ".claude" / "agents"
CLAUDE_MD = ROOT / "CLAUDE.md"

LABELS = [
    "Batch commands:",
    "Parallel calls:",
    "One script for repeated steps:",
    "Log to file:",
    "Read by line range:",
]
CONTACT_LABEL = "Contact sheet:"
SHEET_ITEMS = [
    "Scale reference",
    "Required views",
    "Recognisable features",
    "Triangle budget",
    "Colouring",
    "Shading and bad-render",
    "Catalog size fields",
]
NOTE_LABELS = [
    "Issue:",
    "Branch:",
    "HEAD:",
    "Stage:",
    "Decisions:",
    "Files:",
    "Catalog resources:",
    "Open problems:",
    "Next step:",
    "Checks:",
]
FULL_TOKEN_AGENTS = ["technical-artist", "tester"]
SHORT_TOKEN_AGENTS = ["developer", "code-reviewer", "architect"]

# name, tools, model, effort (None = no effort line), as on develop.
EXPECTED_FRONTMATTER: dict[str, tuple[str, str, str, str | None]] = {
    "architect": ("architect", "Read, Grep, Glob, Bash, Write, Edit", "opus", None),
    "board-keeper": ("board-keeper", "Bash", "haiku", None),
    "code-reviewer": ("code-reviewer", "Read, Grep, Glob, Bash, Write", "opus", "high"),
    "consultant-analyst": (
        "consultant-analyst",
        "Read, Grep, Glob, Bash, Write, Edit, WebSearch, WebFetch",
        "claude-fable-5-2",
        "medium",
    ),
    "consultant-security": (
        "consultant-security",
        "Read, Grep, Glob, Bash, Write, Edit, WebSearch, WebFetch",
        "claude-fable-5-2",
        "medium",
    ),
    "developer": ("developer", "Read, Grep, Glob, Bash, Write, Edit", "sonnet", None),
    "domain-ba": ("domain-ba", "Read, Grep, Glob, Bash", "sonnet", None),
    "product-ba": ("product-ba", "Read, Grep, Glob, Bash", "sonnet", None),
    "requirements-reviewer": ("requirements-reviewer", "Read, Grep, Glob, Bash", "sonnet", None),
    "technical-artist": (
        "technical-artist",
        "Read, Grep, Glob, Bash, Write, Edit, mcp__godot__*",
        "opus",
        "high",
    ),
    "tester": ("tester", "Read, Grep, Glob, Bash, Write, Edit, mcp__godot__*", "sonnet", None),
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def agent_text(name: str) -> str:
    return read(AGENTS / f"{name}.md")


def frontmatter(name: str) -> dict[str, str]:
    lines = agent_text(name).split("\n")
    assert lines[0] == "---", f"{name}: no frontmatter"
    end = lines.index("---", 1)
    result: dict[str, str] = {}
    for line in lines[1:end]:
        match = re.match(r"^([A-Za-z][\w-]*):\s*(.*)$", line)
        if match:
            result[match.group(1)] = match.group(2).strip()
    return result


def sections(text: str, title: str) -> list[str]:
    """Bodies of every `## <title>` section (up to the next `## ` heading)."""
    found: list[str] = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        if lines[i].rstrip() == f"## {title}":
            j = i + 1
            while j < len(lines) and not lines[j].startswith("## "):
                j += 1
            found.append("\n".join(lines[i + 1 : j]))
            i = j
        else:
            i += 1
    return found


def heading_index(text: str, title: str) -> int:
    return text.find(f"\n## {title}\n")


def bullet(section: str, label: str) -> str | None:
    """Text of the top-level bullet starting with `- <label>` (continuation lines included)."""
    lines = section.split("\n")
    pattern = re.compile(r"^- (\*\*)?`?" + re.escape(label))
    for i, line in enumerate(lines):
        if pattern.match(line):
            j = i + 1
            while j < len(lines) and not lines[j].startswith("- "):
                j += 1
            return "\n".join(lines[i:j])
    return None


class AgentTokenUseTest(unittest.TestCase):
    def token_section(self, name: str) -> str:
        found = sections(agent_text(name), "Token use")
        self.assertEqual(len(found), 1, f"{name}: expected exactly one '## Token use'")
        return found[0]

    def assert_labels(self, name: str, labels: list[str]) -> str:
        section = self.token_section(name)
        for label in labels:
            self.assertIsNotNone(bullet(section, label), f"{name}: missing bullet {label}")
        return section

    # AC 1
    def test_ac1_full_token_use_blocks(self) -> None:
        for name in FULL_TOKEN_AGENTS:
            self.assert_labels(name, LABELS)

    def test_ac1_token_use_before_next_section(self) -> None:
        ta = agent_text("technical-artist")
        self.assertTrue(0 < heading_index(ta, "Token use") < heading_index(ta, "Report"))
        tester = agent_text("tester")
        self.assertTrue(0 < heading_index(tester, "Token use") < heading_index(tester, "Rules"))

    def test_ac1_script_bullet_scratchpad_rules(self) -> None:
        for name in FULL_TOKEN_AGENTS:
            text = bullet(self.token_section(name), "One script for repeated steps:") or ""
            self.assertIn("scratchpad", text, name)
            self.assertRegex(text, r"never committed|not committed", name)
            self.assertIn("tools/blender", text, name)

    # AC 2
    def test_ac2_log_to_file_keeps_warnings_visible(self) -> None:
        for name in FULL_TOKEN_AGENTS:
            text = bullet(self.token_section(name), "Log to file:") or ""
            for phrase in [
                "FAIL|ERROR|SCRIPT ERROR|WARNING|push_error|push_warning",
                "test.log",
                "check_godot_log.py",
                "scratchpad",
                "in full",
            ]:
                self.assertIn(phrase, text, f"{name}: Log to file lacks {phrase!r}")

    # AC 3
    def test_ac3_contact_sheet_values(self) -> None:
        section = self.assert_labels("technical-artist", LABELS + [CONTACT_LABEL])
        text = bullet(section, CONTACT_LABEL) or ""
        for phrase in ["512 px", "6 cells", "1024 px", "adult_length_cm"] + SHEET_ITEMS:
            self.assertIn(phrase, text, f"Contact sheet lacks {phrase!r}")

    def test_ac3_contact_sheet_only_in_technical_artist(self) -> None:
        for name in EXPECTED_FRONTMATTER:
            if name == "technical-artist":
                continue
            self.assertNotIn(CONTACT_LABEL, agent_text(name), name)

    # AC 4
    def test_ac4_short_token_use_blocks(self) -> None:
        for name in SHORT_TOKEN_AGENTS:
            self.assert_labels(name, LABELS)
            self.assertIsNone(bullet(self.token_section(name), CONTACT_LABEL), name)

    def test_ac4_short_blocks_before_rules(self) -> None:
        for name in SHORT_TOKEN_AGENTS:
            text = agent_text(name)
            self.assertTrue(0 < heading_index(text, "Token use") < heading_index(text, "Rules"))

    # AC 5
    def test_ac5_frontmatter_unchanged(self) -> None:
        self.assertEqual(sorted(p.stem for p in AGENTS.glob("*.md")), sorted(EXPECTED_FRONTMATTER))
        for name, (e_name, e_tools, e_model, e_effort) in EXPECTED_FRONTMATTER.items():
            fm = frontmatter(name)
            self.assertEqual(fm.get("name"), e_name, name)
            self.assertEqual(fm.get("tools"), e_tools, name)
            self.assertEqual(fm.get("model"), e_model, name)
            self.assertEqual(fm.get("effort"), e_effort, name)

    def test_ac5_no_auto_compact_window_anywhere(self) -> None:
        # Owner decision C2: item 2 dropped, no compaction setting in any agent file.
        for name in EXPECTED_FRONTMATTER:
            self.assertNotIn("autoCompactWindow", frontmatter(name), name)
            self.assertNotIn("autoCompactWindow", agent_text(name), name)

    # AC 8
    def test_ac8_handoff_note_section(self) -> None:
        text = agent_text("technical-artist")
        found = sections(text, "Handoff note")
        self.assertEqual(len(found), 1, "expected exactly one '## Handoff note'")
        section = found[0]
        self.assertGreater(heading_index(text, "Handoff note"), heading_index(text, "Mixed issues"))
        self.assertLess(heading_index(text, "Handoff note"), heading_index(text, "Look and feel"))
        for phrase in [".claude/state/handoff/", "stage-0.md", "G1", "G2", "G3"] + NOTE_LABELS:
            self.assertIn(phrase, section, f"Handoff note lacks {phrase!r}")
        self.assertRegex(section, r"(?i)\bstop")

    def test_ac8_claude_md_delivery_step4_sentence(self) -> None:
        text = read(CLAUDE_MD)
        match = re.search(r"\n4\. Routing:.*?(?=\n5\. )", text, re.S)
        self.assertIsNotNone(match, "Delivery flow step 4 not found")
        step = match.group(0) if match else ""
        self.assertEqual(text.count(".claude/state/handoff/"), 1)
        for phrase in [
            "Long technical-artist work runs in stages",
            ".claude/state/handoff/<issue>/",
            ".claude/agents/technical-artist.md",
            "Handoff note",
            "orchestrator writes the first note",
            "stops the next run",
        ]:
            self.assertIn(phrase, step, f"CLAUDE.md step 4 lacks {phrase!r}")


if __name__ == "__main__":
    unittest.main()
