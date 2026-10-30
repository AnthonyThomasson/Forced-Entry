"""The `architecture` and `domain-testing` skills are each a short SKILL.md map plus side files read on demand
(`architecture/interfaces/NN-<slug>.md`, `domain-testing/perf.md`, ...). These checks keep the map and its files in
step, reading the checkout as text (nothing written to it, nothing run but tools/test_coverage.py):
  - every path into either skill folder written in a skill, AGENTS.md or docs/ names a file that exists: rooted
    (`architecture/interfaces/07-character-and-controller.md`, `.claude/skills/domain-testing/perf.md`) anywhere, or
    relative to the skill folder (`interfaces/07-...md`, `perf.md`) inside it;
  - the interface index in architecture/SKILL.md and the files under interfaces/ match one to one, numbered 1..N with
    no gap (N the index's line count);
  - no orphan: every side file is pointed to from its SKILL.md;
  - each SKILL.md stays at most 30 KB;
  - each section another file cites against a split skill (`<skill>`, "<section>", or "<section>" (`<skill>`)) is
    still a heading in its SKILL.md;
  - each section a split skill's file cites in a named file (`perf.md`, "Rendered too") is still a heading or a
    `**<label>:**` bold label of that file;
  - tools/test_coverage.py still reads the `COVERAGE_NAMES` interface names out of the interface files.
"""
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".claude" / "skills"
SPLIT = ("architecture", "domain-testing")
CEILING = 30 * 1024
# The `Class.method` names tools/test_coverage.py reads out of the interface files: bump it when an interface file
# gains or loses one.
COVERAGE_NAMES = 175

# A path into a split skill's folder, rooted at the skills dir or the repo, placeholders and globs captured too.
ROOTED = re.compile(r"(?<![\w/.-])(?:(?:\.claude/)?skills/)?(architecture|domain-testing)/([\w./*<>-]*[\w*>])")
# A backticked `.md` path inside a split skill's folder, read there first, then in the repo root or the skills dir.
RELATIVE = re.compile(r"`((?:[\w-]+/)*[\w.-]+\.md)`")
# A section cited by name against a split skill: `<skill>`, "<section>" or "<section>" (`<skill>`).
CITATION = re.compile(r'`(?P<skill>architecture|domain-testing)`(?: skill)?, "(?P<name>[^"]+)"'
                      r'|"(?P<name_first>[^"]+)" \(`(?P<skill_after>architecture|domain-testing)`')
# A section cited in a named file: `perf.md`, "Rendered too".
FILE_CITATION = re.compile(r'`([\w./-]+\.md)`, "([^"]+)"')
# A glob or placeholder in a path (`NN-*.md`, `domain-<name>/`): prose, not a pointer.
PLACEHOLDER = re.compile(r"[*<>]")
HEADING = re.compile(r"#+ (.+)$")
# A code fence's opening or closing run: three or more backticks or tildes, indented at most three spaces.
FENCE = re.compile(r" {0,3}(`{3,}|~{3,})")
INDEX_LINE = re.compile(r"^(\d+)\. .*`interfaces/((\d\d)-[\w-]+\.md)`", re.M)


def citing_files() -> list[Path]:
    return sorted([*SKILLS.rglob("*.md"), ROOT / "AGENTS.md", *(ROOT / "docs").rglob("*.md")])


def cited_sections(text: str) -> set[tuple[str, str]]:
    """The (skill, section) pairs `text` cites by name, a name wrapped over lines read as one line."""
    return {(m["skill"] or m["skill_after"], one_line(m["name"] or m["name_first"])) for m in CITATION.finditer(text)}


def one_line(text: str) -> str:
    return " ".join(text.split())


def headings(text: str) -> list[str]:
    """The headings of `text`, a `#` line inside a code fence (a `## doc comment` in GDScript) left out. A fence closes
    on a run of its own char at least as long with nothing after it; a backtick run with a backtick after it opens
    none (it is inline code)."""
    found, fence = [], ""
    for line in text.splitlines():
        opener = FENCE.match(line)
        rest = line.strip()[len(opener[1]):] if opener else ""
        if fence:
            if opener and opener[1].startswith(fence) and not rest:
                fence = ""
        elif opener and not (opener[1][0] == "`" and "`" in rest):
            fence = opener[1]
        elif m := HEADING.match(line):
            found.append(m[1])
    return found


def unknown_file_sections(folder: Path, text: str) -> list[str]:
    """The `<file>.md`, "<label>" citations in `text` (the file read in the skill `folder` or, failing that, the repo
    root) whose label is neither a heading of that file (its start) nor one of its `**<label>:**` bold labels."""
    unknown = []
    for name, label in FILE_CITATION.findall(text):
        label = one_line(label)
        target = folder / name if (folder / name).is_file() else ROOT / name
        cited = target.read_text() if target.is_file() else ""
        if not any(h.startswith(label) for h in headings(cited)) and f"**{label}:**" not in cited:
            unknown.append(f"{name}, {label!r}")
    return unknown


def side_files(skill: str) -> list[Path]:
    folder = SKILLS / skill
    return sorted(p for p in folder.rglob("*.md") if p != folder / "SKILL.md")


def relative_pointers(folder: Path, text: str) -> set[str]:
    """The backticked `.md` paths in `text` that point into the skill `folder`: each read in `folder` first, then in the
    repo root and the skills dir, where one that is a file is a pointer out of the skill. A path missing from `folder`
    that names a root file (`GLOSSARY.md`) is therefore read as the root file, and one starting at a split skill's
    folder (`domain-testing/perf.md`) is a rooted path, checked by the rooted-path test."""
    return {p for p in RELATIVE.findall(text) if (folder / p).exists()
            or not ((ROOT / p).exists() or (SKILLS / p).exists() or p.startswith(SPLIT))}


class SkillPointerTests(unittest.TestCase):
    def test_every_rooted_path_into_a_split_skill_names_a_file(self):
        missing = []
        for f in citing_files():
            for n, line in enumerate(f.read_text().splitlines(), 1):
                for skill, rest in ROOTED.findall(line):
                    if PLACEHOLDER.search(rest):
                        continue
                    if not (SKILLS / skill / rest).exists():
                        missing.append(f"{f.relative_to(ROOT)}:{n}: {skill}/{rest}")
        self.assertEqual(missing, [], "paths into a split skill that name no file")

    def test_every_relative_path_inside_a_split_skill_names_a_file(self):
        missing = []
        for skill in SPLIT:
            for f in [SKILLS / skill / "SKILL.md", *side_files(skill)]:
                for p in sorted(relative_pointers(SKILLS / skill, f.read_text())):
                    if not (SKILLS / skill / p).exists():
                        missing.append(f"{f.relative_to(ROOT)}: {p}")
        self.assertEqual(missing, [], "relative paths that name no file in their skill folder")

    def test_the_interface_index_and_the_interface_files_match_one_to_one(self):
        text = (SKILLS / "architecture" / "SKILL.md").read_text()
        index = INDEX_LINE.findall(text)
        for number, name, file_number in index:
            self.assertEqual(int(number), int(file_number), f"index line {number} points at {name}")
        numbers = sorted(int(n) for n, _, _ in index)
        self.assertTrue(numbers, "premise: the index is read")
        self.assertEqual(numbers, list(range(1, len(numbers) + 1)), f"index lines: one per interface 1..{len(numbers)}")
        files = sorted((SKILLS / "architecture" / "interfaces").glob("*.md"))
        names = [f.name for f in files]
        self.assertEqual([n for n in names if not re.fullmatch(r"\d\d-[a-z0-9-]+\.md", n)], [], "file names")
        self.assertEqual(sorted(int(n[:2]) for n in names), numbers,
                         f"interface files: exactly one per number 1..{len(numbers)}")
        indexed = {name for _, name, _ in index}
        self.assertEqual([n for n in names if n not in indexed], [], "interface files with no index line")

    def test_no_side_file_is_an_orphan(self):
        orphans = []
        for skill in SPLIT:
            pointed = relative_pointers(SKILLS / skill, (SKILLS / skill / "SKILL.md").read_text())
            for f in side_files(skill):
                if str(f.relative_to(SKILLS / skill)) not in pointed:
                    orphans.append(str(f.relative_to(ROOT)))
        self.assertEqual(orphans, [], "side files their SKILL.md does not point to")

    def test_a_relative_path_is_read_in_the_skill_folder_first(self):
        text = "`GLOSSARY.md`, `gone.md`, `docs/hearing.md`, `architecture/nowhere.md`"
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertEqual(relative_pointers(folder, text), {"gone.md"})
            (folder / "GLOSSARY.md").write_text("# A side file named like the root one\n")
            self.assertEqual(relative_pointers(folder, text), {"GLOSSARY.md", "gone.md"})

    def test_each_split_skill_md_is_at_most_30_kb(self):
        for skill in SPLIT:
            size = (SKILLS / skill / "SKILL.md").stat().st_size
            self.assertLessEqual(size, CEILING, f"{skill}/SKILL.md is {size} bytes")

    def test_every_cited_section_is_a_heading(self):
        known = {s: headings((SKILLS / s / "SKILL.md").read_text()) for s in SPLIT}
        cited = set()
        for f in citing_files():
            cited |= cited_sections(f.read_text())
        self.assertIn(("domain-testing", "Running tests"), cited, "premise: the citations are found")
        for f in [*(ROOT / "tools").rglob("*.py"), *(ROOT / "tools").rglob("*.sh")]:
            cited |= cited_sections(f.read_text())
        unknown = sorted(f"{s}, {name!r}" for s, name in cited if not any(h.startswith(name) for h in known[s]))
        self.assertEqual(unknown, [], "sections cited by name that are no heading in their SKILL.md")

    def test_a_citation_is_read_in_either_order(self):
        skill = "domain-testing"  # kept out of the fixtures, so this file's own text cites nothing
        for text in (f'`{skill}`, "Running\n  tests"', f'"Running tests" (`{skill}`)'):
            with self.subTest(text=text):
                self.assertEqual(cited_sections(text), {("domain-testing", "Running tests")})

    def test_a_line_inside_a_code_fence_is_no_heading(self):
        text = ("# Map\n```gdscript\n## A doc comment\n```\n## Running tests\n````\n```\n# Still code\n````\n"
                "```a``` is inline code\n## Performance tests\n")
        self.assertEqual(headings(text), ["Map", "Running tests", "Performance tests"])

    def test_a_section_cited_in_a_file_is_a_heading_or_a_bold_label_of_that_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "side.md").write_text("# Behaviour switches\n**Rendered too:** a bold label.\n")
            cited = ('`side.md`, "Rendered too"; `side.md`, "Behaviour switches"; `side.md`, "Rendered never"; '
                     '`gone.md`, "Rendered too"')
            self.assertEqual(unknown_file_sections(folder, cited),
                             ["side.md, 'Rendered never'", "gone.md, 'Rendered too'"])

    def test_every_section_a_split_skill_cites_in_a_file_is_there(self):
        files = [(skill, f) for skill in SPLIT for f in [SKILLS / skill / "SKILL.md", *side_files(skill)]]
        cites = [c for _, f in files for c in FILE_CITATION.findall(f.read_text())]
        self.assertIn(("in-game-runner.md", "Locking interactions"), cites, "premise: the citations are found")
        unknown = [f"{f.relative_to(ROOT)}: {u}" for skill, f in files
                   for u in unknown_file_sections(SKILLS / skill, f.read_text())]
        self.assertEqual(unknown, [], "sections cited in a file that are no heading or bold label of it")

    def test_the_coverage_tool_still_checks_every_interface_name(self):
        out = subprocess.run([sys.executable, str(ROOT / "tools" / "test_coverage.py")], capture_output=True,
                             text=True, check=True).stdout
        self.assertTrue(out.rstrip().endswith(f"{COVERAGE_NAMES} interface names checked."), out[-300:])


if __name__ == "__main__":
    unittest.main()
