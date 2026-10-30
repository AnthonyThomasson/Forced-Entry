"""The `architecture` and `domain-testing` skills are each a short SKILL.md map plus side files read on demand
(`architecture/interfaces/NN-<slug>.md`, `domain-testing/perf.md`, ...). These checks keep the map and its files in
step, reading the checkout as text (nothing written, nothing run but tools/test_coverage.py):
  - every path into either skill folder written in a skill, AGENTS.md or docs/ names a file that exists: rooted
    (`architecture/interfaces/07-character-controller.md`, `.claude/skills/domain-testing/perf.md`) anywhere, or
    relative to the skill folder (`interfaces/07-...md`, `perf.md`) inside it;
  - the interface index in architecture/SKILL.md and the files under interfaces/ match one to one, numbers 1..23;
  - no orphan: every side file is pointed to from its SKILL.md;
  - each SKILL.md stays at most 30 KB;
  - each section another file cites by name (`domain-testing`, "Running tests") is still a heading in its SKILL.md;
  - tools/test_coverage.py still reads the 163 interface names out of the interface files.
"""
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".claude" / "skills"
SPLIT = ("architecture", "domain-testing")
CEILING = 30 * 1024
INTERFACES = 23
COVERAGE_NAMES = 163

# A path into a split skill's folder, rooted at the skills dir or the repo; globs and placeholders (`NN-*.md`,
# `domain-<name>/`) are prose, not pointers.
ROOTED = re.compile(r"(?<![\w/.-])(?:\.claude/skills/)?(architecture|domain-testing)/([\w./*<>-]*[\w*>])")
# A backticked `.md` path inside a split skill's folder, read relative to that folder unless it names a repo file.
RELATIVE = re.compile(r"`((?:[\w-]+/)*[\w.-]+\.md)`")
CITATION = re.compile(r'`(architecture|domain-testing)`(?: skill)?, "([^"]+)"')
INDEX_LINE = re.compile(r"^(\d+)\. .*`interfaces/(\d\d)-[\w-]+\.md`", re.M)


def citing_files() -> list[Path]:
    return sorted([*SKILLS.rglob("*.md"), ROOT / "AGENTS.md", *(ROOT / "docs").rglob("*.md")])


def side_files(skill: str) -> list[Path]:
    folder = SKILLS / skill
    return sorted(p for p in folder.rglob("*.md") if p != folder / "SKILL.md")


def relative_pointers(skill: str, text: str) -> set[str]:
    return {p for p in RELATIVE.findall(text) if not (ROOT / p).exists() and not (SKILLS / p).exists()
            and not p.startswith(SPLIT)}


class SkillPointerTests(unittest.TestCase):
    def test_every_rooted_path_into_a_split_skill_names_a_file(self):
        missing = []
        for f in citing_files():
            for n, line in enumerate(f.read_text().splitlines(), 1):
                for skill, rest in ROOTED.findall(line):
                    if re.search(r"[*<>]", rest):
                        continue
                    if not (SKILLS / skill / rest).exists():
                        missing.append(f"{f.relative_to(ROOT)}:{n}: {skill}/{rest}")
        self.assertEqual(missing, [], "paths into a split skill that name no file")

    def test_every_relative_path_inside_a_split_skill_names_a_file(self):
        missing = []
        for skill in SPLIT:
            for f in [SKILLS / skill / "SKILL.md", *side_files(skill)]:
                for p in sorted(relative_pointers(skill, f.read_text())):
                    if not (SKILLS / skill / p).exists():
                        missing.append(f"{f.relative_to(ROOT)}: {p}")
        self.assertEqual(missing, [], "relative paths that name no file in their skill folder")

    def test_the_interface_index_and_the_interface_files_match_one_to_one(self):
        text = (SKILLS / "architecture" / "SKILL.md").read_text()
        index = INDEX_LINE.findall(text)
        for number, file_number in index:
            self.assertEqual(int(number), int(file_number), f"index line {number} points at file {file_number}")
        numbers = sorted(int(n) for n, _ in index)
        self.assertEqual(numbers, list(range(1, INTERFACES + 1)), "index lines: one per interface 1..23")
        files = sorted((SKILLS / "architecture" / "interfaces").glob("*.md"))
        names = [f.name for f in files]
        self.assertEqual([n for n in names if not re.fullmatch(r"\d\d-[a-z0-9-]+\.md", n)], [], "file names")
        self.assertEqual(sorted(int(n[:2]) for n in names), list(range(1, INTERFACES + 1)),
                         "interface files: exactly one per number 1..23")
        for f in files:
            self.assertIn(f"`interfaces/{f.name}`", text, f"{f.name} has no index line")

    def test_no_side_file_is_an_orphan(self):
        orphans = []
        for skill in SPLIT:
            pointed = relative_pointers(skill, (SKILLS / skill / "SKILL.md").read_text())
            for f in side_files(skill):
                if str(f.relative_to(SKILLS / skill)) not in pointed:
                    orphans.append(str(f.relative_to(ROOT)))
        self.assertEqual(orphans, [], "side files their SKILL.md does not point to")

    def test_each_split_skill_md_is_at_most_30_kb(self):
        for skill in SPLIT:
            size = (SKILLS / skill / "SKILL.md").stat().st_size
            self.assertLessEqual(size, CEILING, f"{skill}/SKILL.md is {size} bytes")

    def test_every_cited_section_is_a_heading(self):
        headings = {s: re.findall(r"^#+ (.+)$", (SKILLS / s / "SKILL.md").read_text(), re.M) for s in SPLIT}
        cited = set()
        for f in [*citing_files(), *(ROOT / "tools").rglob("*.py"), *(ROOT / "tools").rglob("*.sh")]:
            cited |= {(s, " ".join(name.split())) for s, name in CITATION.findall(f.read_text())}
        self.assertIn(("domain-testing", "Running tests"), cited, "premise: the citations are found")
        unknown = sorted(f"{s}, {name!r}" for s, name in cited if not any(h.startswith(name) for h in headings[s]))
        self.assertEqual(unknown, [], "sections cited by name that are no heading in their SKILL.md")

    def test_the_coverage_tool_still_checks_every_interface_name(self):
        out = subprocess.run([sys.executable, str(ROOT / "tools" / "test_coverage.py")], capture_output=True,
                             text=True, check=True).stdout
        self.assertTrue(out.rstrip().endswith(f"{COVERAGE_NAMES} interface names checked."), out[-300:])


if __name__ == "__main__":
    unittest.main()
