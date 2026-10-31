"""Every skill under `.claude/skills/` is a short SKILL.md map plus side files read on demand (`architecture/interfaces/NN-<slug>.md`,
`domain-testing/perf.md`, `domain-ai/team.md`, `ticket/bug.md`, ...). These checks keep the maps and their files in
step, reading the checkout as text (nothing written to it, nothing run but tools/test_coverage.py):
  - every path into a skill folder written in a skill, AGENTS.md or docs/ names a file that exists: rooted
    (`architecture/interfaces/07-character-and-controller.md`, `.claude/skills/domain-testing/perf.md`) anywhere, or
    relative to the skill folder (`interfaces/07-...md`, `perf.md`) inside it; `domain-ai` (`team.md`) names `team.md`
    of that other skill, wherever it is written;
  - the interface index in architecture/SKILL.md and the files under interfaces/ match one to one, numbered 1..N with
    no gap (N the index's line count);
  - no orphan: every side file of every skill is reachable from its SKILL.md through relative pointers;
  - routing: every `domain-*` skill is in a row of architecture's domain table; ticket's routing table names only kind
    files that exist (a row that names none says `none`), names every kind and leaves no kind file out;
  - each section another file cites against a skill (`<skill>`, "<section>", or "<section>" (`<skill>`)) is still a
    heading in its SKILL.md;
  - each section a skill's file cites in a named file (`perf.md`, "Rendered too") is still a heading or a
    `**<label>:**` or `**<label>**:` bold label of that file;
  - tools/test_coverage.py still reads the `COVERAGE_NAMES` interface names out of the interface files.
Sizes, frontmatter, references and duplication: tools/tests/test_skills.py.
"""
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".claude" / "skills"
SKILL_NAMES = tuple(sorted(p.name for p in SKILLS.iterdir() if p.is_dir()))
# The ticket kinds the routing table sends to, and the files in `ticket/` that help a kind and are no kind.
TICKET_KINDS = ("story", "bug", "spike", "ai", "harness", "refactor", "assets")
TICKET_HELPERS = ("workers", "assets-showroom")
# The `Class.method` names tools/test_coverage.py reads out of the interface files: bump it when an interface file
# gains or loses one. 175 -> 173 (#169): interface 13 lost the sandbox sound API (`SoundBank.recipe_for`,
# `SoundSynth.render`), which no sandbox calls.
COVERAGE_NAMES = 173

def names_alternation(names) -> str:
    return "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True))


# A path into a skill's folder, rooted at the skills dir or the repo, placeholders and globs captured too.
ROOTED = re.compile(r"(?<![\w/.-])(?:(?:\.claude/)?skills/)?(" + names_alternation(SKILL_NAMES)
                    + r")/([\w./*<>-]*[\w*>])")
# A backticked `.md` path inside a split skill's folder, read there first, then in the repo root or the skills dir.
RELATIVE = re.compile(r"`((?:[\w-]+/)*[\w.-]+\.md)`")
# A section cited by name against a skill: `<skill>`, "<section>" or "<section>" (`<skill>`).
CITATION = re.compile(r'`(?P<skill>' + names_alternation(SKILL_NAMES) + r')`(?: skill)?, "(?P<name>[^"]+)"'
                      r'|"(?P<name_first>[^"]+)" \(`(?P<skill_after>' + names_alternation(SKILL_NAMES) + r')`')
# `<skill>` (`<file>.md`, `<file>.md`; ...): the backticked files right after a skill name are that skill's side files.
CROSS = re.compile(r"`(?P<skill>[\w-]+)`\s*\((?P<files>(?:\s*`[\w./-]+\.md`\s*[,;]?)+)")
# A section cited in a named file: `perf.md`, "Rendered too".
FILE_CITATION = re.compile(r'`([\w./-]+\.md)`, "([^"]+)"')
# A glob or placeholder in a path (`NN-*.md`, `domain-<name>/`): prose, not a pointer.
PLACEHOLDER = re.compile(r"[*<>]")
HEADING = re.compile(r"#+ (.+)$")
# A code fence's opening or closing run: three or more backticks or tildes, indented at most three spaces.
FENCE = re.compile(r" {0,3}(`{3,}|~{3,})")
BACKTICKED_MD = re.compile(r"`([\w./-]+\.md)`")
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
        if not any(h.startswith(label) for h in headings(cited)) and not any(b in cited for b in (f"**{label}:**", f"**{label}**:")):
            unknown.append(f"{name}, {label!r}")
    return unknown


def side_files(skill: str) -> list[Path]:
    folder = SKILLS / skill
    return sorted(p for p in folder.rglob("*.md") if p != folder / "SKILL.md")


def cross_pointers(text: str, names=SKILL_NAMES) -> list[tuple[str, str]]:
    """The (skill, file) pairs `text` names as `<skill>` (`<file>.md`, ...): the files right after a skill name."""
    return [(m["skill"], f) for m in CROSS.finditer(text) if m["skill"] in names
            for f in BACKTICKED_MD.findall(m["files"])]


def relative_pointers(folder: Path, text: str, names=SKILL_NAMES) -> set[str]:
    """The backticked `.md` paths in `text` that point into the skill `folder`: each read in `folder` first, then in the
    repo root and the skills dir, where one that is a file is a pointer out of the skill. A path missing from `folder`
    that names a root file (`GLOSSARY.md`) is therefore read as the root file, and one starting at a skill's folder
    (`domain-testing/perf.md`) is a rooted path, checked by the rooted-path test. Files right after another skill's
    name (`domain-ai` (`team.md`)) are that skill's side files: `cross_pointers`."""
    own = CROSS.sub(lambda m: m[0] if m["skill"] not in names or m["skill"] == folder.name else "", text)
    return {p for p in RELATIVE.findall(own) if (folder / p).exists()
            or not ((ROOT / p).exists() or (SKILLS / p).exists() or p.split("/")[0] in names and "/" in p)}


def unreachable_side_files(skills: Path, skill: str) -> list[str]:
    """The side files of `skills`/`skill` (paths under the folder) that no chain of relative pointers from its SKILL.md
    reaches."""
    folder = skills / skill
    names = {p.name for p in skills.iterdir() if p.is_dir()}
    reached, todo = set(), ["SKILL.md"]
    while todo:
        for p in relative_pointers(folder, (folder / todo.pop()).read_text(), names):
            if p not in reached and (folder / p).is_file():
                reached.add(p)
                todo.append(p)
    side = {str(p.relative_to(folder)) for p in folder.rglob("*.md")} - {"SKILL.md"}
    return sorted(side - reached)


def missing_cross_pointers(skills: Path, file: Path) -> list[tuple[str, str]]:
    """The (skill, file) pairs `file` names as `<skill>` (`<file>.md`) where the other skill has no such file."""
    names = {p.name for p in skills.iterdir() if p.is_dir()}
    return [(s, p) for s, p in cross_pointers(file.read_text(), names) if not (skills / s / p).is_file()]


def table_rows(text: str, header: str) -> list[list[str]]:
    """The cells of each body row of the Markdown table whose header row starts with the cell `header`."""
    rows, inside = [], False
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.strip().startswith("|") else None
        if cells is None:
            inside = False
        elif cells[0] == header:
            inside = True
        elif inside and not set("".join(cells)) <= set("-: "):
            rows.append(cells)
    return rows


def domains_missing_from_table(skills: Path) -> list[str]:
    """The `domain-*` skills that no row of the domain table in architecture/SKILL.md names in its Skill column."""
    rows = table_rows((skills / "architecture" / "SKILL.md").read_text(), "Domain")
    named = {name for row in rows for name in re.findall(r"`(domain-[\w-]+)`", row[2] if len(row) > 2 else "")}
    return sorted(p.name for p in skills.glob("domain-*") if p.is_dir() and p.name not in named)


def ticket_routing_findings(skills: Path, kinds=TICKET_KINDS, helpers=TICKET_HELPERS) -> list[str]:
    """Findings on the routing table of ticket/SKILL.md: a kind file it names that does not exist, a row that names
    none and does not say `none`, a kind it leaves out, a `.md` in ticket/ that is neither a kind nor a helper."""
    folder = skills / "ticket"
    named, found = set(), []
    for label, *cells in table_rows((folder / "SKILL.md").read_text(), "Label"):
        read = cells[0] if cells else ""
        files = BACKTICKED_MD.findall(read)
        if not files and not re.search(r"\bnone\b", read):
            found.append(f"row {label}: names no kind file and does not say none")
        for f in files:
            named.add(f)
            if f.removesuffix(".md") in helpers:
                found.append(f"row {label}: {f} is a helper, not a kind")
            elif not (folder / f).is_file():
                found.append(f"row {label}: {f} does not exist in ticket/")
    found += [f"the routing table does not name {k}.md" for k in kinds if f"{k}.md" not in named]
    allowed = {"SKILL.md", *(f"{n}.md" for n in (*kinds, *helpers))}
    found += [f"ticket/{p.name} is neither a kind nor a helper" for p in sorted(folder.glob("*.md"))
              if p.name not in allowed]
    return found


def make_skills(tmp: str, files: dict[str, str]) -> Path:
    """A skills root in `tmp` holding `files` (path under it -> text)."""
    skills = Path(tmp)
    for name, text in files.items():
        (skills / name).parent.mkdir(parents=True, exist_ok=True)
        (skills / name).write_text(text)
    return skills


class ReachabilityTests(unittest.TestCase):
    def unreachable(self, files: dict[str, str], skill: str = "alpha") -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            return unreachable_side_files(make_skills(tmp, files), skill)

    def test_a_side_file_pointed_to_through_a_chain_is_reachable(self):
        files = {"alpha/SKILL.md": "Read `one.md`.", "alpha/one.md": "Then `deep/two.md`.", "alpha/deep/two.md": "End."}
        self.assertEqual(self.unreachable(files), [])

    def test_a_side_file_nothing_points_to_is_an_orphan(self):
        files = {"alpha/SKILL.md": "Read `one.md`.", "alpha/one.md": "", "alpha/lost.md": "", "alpha/deep/lost2.md": ""}
        self.assertEqual(self.unreachable(files), ["deep/lost2.md", "lost.md"])

    def test_two_orphans_pointing_at_each_other_are_still_orphans(self):
        files = {"alpha/SKILL.md": "Nothing.", "alpha/a.md": "`b.md`", "alpha/b.md": "`a.md`"}
        self.assertEqual(self.unreachable(files), ["a.md", "b.md"])

    def test_a_pointer_into_another_skill_does_not_reach_a_side_file_of_this_one(self):
        files = {"alpha/SKILL.md": "See `beta` (`team.md`).", "alpha/team.md": "", "beta/SKILL.md": "", "beta/team.md": ""}
        self.assertEqual(self.unreachable(files), ["team.md"])

    def test_the_live_skills_have_no_orphan(self):
        orphans = {skill: found for skill in SKILL_NAMES if (found := unreachable_side_files(SKILLS, skill))}
        self.assertEqual(orphans, {}, "side files their SKILL.md does not reach through relative pointers")


class CrossPointerTests(unittest.TestCase):
    NAMES = {"alpha", "beta"}

    def test_a_backticked_md_right_after_a_skill_name_is_that_skills_side_file(self):
        text = "Read `alpha` (`one.md`), then `beta` (`two.md`, `deep/three.md`; `ui/<folder>/`) and `gamma` (`four.md`)."
        self.assertEqual(cross_pointers(text, self.NAMES), [("alpha", "one.md"), ("beta", "two.md"),
                                                            ("beta", "deep/three.md")])

    def test_an_md_not_right_after_a_skill_name_is_no_cross_pointer(self):
        self.assertEqual(cross_pointers("`alpha`, `one.md` and `alpha` and (`two.md`)", self.NAMES), [])

    def test_a_cross_pointer_is_no_relative_pointer(self):
        with tempfile.TemporaryDirectory() as tmp:
            text = "`alpha` (`one.md`) and `local.md`"
            self.assertEqual(relative_pointers(Path(tmp), text, self.NAMES), {"local.md"})

    def test_a_cross_pointer_that_names_no_file_is_a_finding(self):
        with tempfile.TemporaryDirectory() as tmp:
            skills = make_skills(tmp, {"alpha/SKILL.md": "`beta` (`here.md`, `gone.md`)", "beta/SKILL.md": "",
                                       "beta/here.md": ""})
            self.assertEqual(missing_cross_pointers(skills, skills / "alpha" / "SKILL.md"), [("beta", "gone.md")])

    def test_every_live_cross_pointer_names_a_file(self):
        missing, found = [], []
        for f in citing_files():
            found += cross_pointers(f.read_text())
            missing += [f"{f.relative_to(ROOT)}: {s} ({p})" for s, p in missing_cross_pointers(SKILLS, f)]
        self.assertIn(("domain-ai", "team.md"), found, "premise: the cross pointers are found")
        self.assertEqual(missing, [], "`<skill>` (`<file>.md`) pointers that name no file")


DOMAIN_TABLE = """| Domain | Folder | Skill | Owns |
|---|---|---|---|
| A | `a/` | `domain-a` (`side.md`) | x |
| B | `b/` | `domain-b` | y |
"""
ROUTING = """## Route
   | Label | Read |
   |---|---|
   | `spike` | `spike.md` |
   | `bug` | `bug.md` |
   | `wayfinder:map` | none: a decision ticket |

   | State | Then |
   |---|---|
   | none / `needs-triage` | go on |
"""


class RoutingTests(unittest.TestCase):
    def domains_missing(self, table: str, folders=("domain-a", "domain-b")) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            files = {"architecture/SKILL.md": table, **{f"{f}/SKILL.md": "" for f in folders}}
            return domains_missing_from_table(make_skills(tmp, files))

    def test_every_domain_skill_in_the_table_is_no_finding(self):
        self.assertEqual(self.domains_missing(DOMAIN_TABLE), [])

    def test_a_domain_skill_absent_from_the_table_is_a_finding(self):
        self.assertEqual(self.domains_missing(DOMAIN_TABLE, ("domain-a", "domain-b", "domain-c")), ["domain-c"])

    def test_a_domain_skill_named_only_in_prose_is_a_finding(self):
        self.assertEqual(self.domains_missing(DOMAIN_TABLE + "\nSee `domain-c`.\n", ("domain-a", "domain-b",
                                                                                      "domain-c")), ["domain-c"])

    def test_a_domain_skill_named_only_in_another_rows_owns_cell_is_a_finding(self):
        table = DOMAIN_TABLE.replace("| y |", "| y, next to `domain-c` |")
        self.assertEqual(self.domains_missing(table, ("domain-a", "domain-b", "domain-c")), ["domain-c"])

    def test_the_live_domain_table_names_every_domain_skill(self):
        self.assertEqual(domains_missing_from_table(SKILLS), [])

    def routing(self, ticket_md: str, extra: tuple[str, ...] = (), kinds: tuple[str, ...] = ("spike", "bug"),
                helpers: tuple[str, ...] = ("workers",)) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            files = {"ticket/SKILL.md": ticket_md, **{f"ticket/{k}.md": "" for k in (*kinds, *extra, *helpers)}}
            return ticket_routing_findings(make_skills(tmp, files), kinds, helpers)

    def test_a_table_naming_every_kind_file_that_exists_is_no_finding(self):
        self.assertEqual(self.routing(ROUTING), [])

    def test_a_named_kind_file_that_does_not_exist_is_a_finding(self):
        found = self.routing(ROUTING.replace("`bug.md`", "`bug.md`, `ghost.md`"))
        self.assertEqual(len(found), 1, found)
        self.assertIn("ghost.md", found[0])

    def test_a_kind_the_table_leaves_out_is_a_finding(self):
        found = self.routing(ROUTING.replace("| `spike` | `spike.md` |\n", ""))
        self.assertEqual(len(found), 1, found)
        self.assertIn("spike", found[0])

    def test_a_kind_file_in_the_folder_that_is_not_a_kind_or_a_helper_is_a_finding(self):
        found = self.routing(ROUTING, extra=("stray",))
        self.assertEqual(len(found), 1, found)
        self.assertIn("stray.md", found[0])

    def test_a_row_that_names_no_file_and_does_not_say_none_is_a_finding(self):
        found = self.routing(ROUTING.replace("none: a decision ticket", "a decision ticket"))
        self.assertEqual(len(found), 1, found)
        self.assertIn("wayfinder:map", found[0])

    def test_a_helper_file_in_the_routing_table_is_a_finding(self):
        found = self.routing(ROUTING.replace("`bug.md`", "`bug.md`, `workers.md`"))
        self.assertEqual(len(found), 1, found)
        self.assertIn("workers.md", found[0])

    def test_none_is_a_word_not_a_substring(self):
        found = self.routing(ROUTING.replace("none: a decision ticket", "nonetheless a decision ticket"))
        self.assertEqual(len(found), 1, found)

    def test_a_one_cell_row_is_a_finding_not_a_crash(self):
        found = self.routing(ROUTING.replace("| `bug` | `bug.md` |", "| `bug` |"))
        self.assertTrue(any("bug" in f for f in found), found)

    def test_the_live_routing_table_names_every_kind_file(self):
        self.assertEqual(ticket_routing_findings(SKILLS, TICKET_KINDS, TICKET_HELPERS), [])


class SkillPointerTests(unittest.TestCase):
    def test_every_rooted_path_into_a_skill_names_a_file(self):
        missing = []
        for f in citing_files():
            for n, line in enumerate(f.read_text().splitlines(), 1):
                for skill, rest in ROOTED.findall(line):
                    if PLACEHOLDER.search(rest):
                        continue
                    if not (SKILLS / skill / rest).exists():
                        missing.append(f"{f.relative_to(ROOT)}:{n}: {skill}/{rest}")
        self.assertEqual(missing, [], "paths into a skill that name no file")

    def test_every_relative_path_inside_a_skill_names_a_file(self):
        missing = []
        for skill in SKILL_NAMES:
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

    def test_a_relative_path_is_read_in_the_skill_folder_first(self):
        text = "`GLOSSARY.md`, `gone.md`, `docs/hearing.md`, `architecture/nowhere.md`"
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.assertEqual(relative_pointers(folder, text), {"gone.md"})
            (folder / "GLOSSARY.md").write_text("# A side file named like the root one\n")
            self.assertEqual(relative_pointers(folder, text), {"GLOSSARY.md", "gone.md"})

    def test_every_cited_section_is_a_heading(self):
        known = {s: headings((SKILLS / s / "SKILL.md").read_text()) for s in SKILL_NAMES}
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
            (folder / "side.md").write_text("# Behaviour switches\n**Rendered too:** a bold label.\n"
                                            "- **Colon outside**: a bold label too.\n")
            cited = ('`side.md`, "Colon outside"; `side.md`, "Rendered too"; `side.md`, "Behaviour switches"; `side.md`, "Rendered never"; '
                     '`gone.md`, "Rendered too"')
            self.assertEqual(unknown_file_sections(folder, cited),
                             ["side.md, 'Rendered never'", "gone.md, 'Rendered too'"])

    def test_every_section_a_skill_cites_in_a_file_is_there(self):
        files = [(skill, f) for skill in SKILL_NAMES for f in [SKILLS / skill / "SKILL.md", *side_files(skill)]]
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
