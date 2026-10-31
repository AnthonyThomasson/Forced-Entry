"""Checks on the project skills (`.claude/skills/`), `AGENTS.md`, `docs/agents/` and the `docs/` specs, read as text
(nothing written to the checkout). Each rule is a function that takes the skills root (and the files it reads); a
fixture test breaks the rule in a temp dir and expects the finding, and one live test runs the same function on the
real checkout:
  - frontmatter: `name` is the folder, the description is present, starts with "Use" and is at most 200 characters;
    the model-invocable descriptions (no `disable-model-invocation: true`) total at most 6144;
  - caps: a `SKILL.md` is at most 12288 bytes, any other `.md` in a skill folder at most 8192;
  - references: a backticked skill name (`domain-*`, `ticket-*`, a live or removed skill) names a skill folder, a
    backticked repo path exists; a `#` comment line of a `.gd`, `.py` or `.sh` file under `scenes/`, `tests/`, `tools/`
    is read for skill names too;
  - duplication: no paragraph of 200 characters or more appears in two of the skills, `AGENTS.md`, `docs/*.md`,
    `docs/agents`.
"""
import re
import tempfile
import unittest
from pathlib import Path

from tools.tests.skill_text import names_alternation, outside_fences


ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".claude" / "skills"
AGENTS = ROOT / "AGENTS.md"
DOCS = ROOT / "docs"
DESCRIPTION_MAX = 200
DESCRIPTIONS_TOTAL_MAX = 6144
SKILL_MD_MAX = 12288
SIDE_FILE_MAX = 8192
PARAGRAPH_MIN = 200
REPO_ROOTS = ("scenes", "tests", "tools", "docs", ".claude", "addons", "sandboxes", ".githooks")
INLINE_CODE = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)")
# Skills folded into a side file: a reference to one is stale. Add a skill's name here when it is removed, so a
# reference to it goes red once its folder is gone.
REMOVED_SKILLS = (
    *(f"domain-ai-{sub}" for sub in ("perception", "snapshot", "decision", "behavior", "combat", "coverage", "watch",
                                     "entry", "debug", "team")),
    *(f"domain-ui-{sub}" for sub in ("menus", "hud", "command", "overlays", "testing")),
    "domain-character-body",
    "domain-physics-blood",
    *(f"ticket-{kind}" for kind in ("story", "bug", "spike", "ai", "harness", "refactor", "assets")),
)


def skill_name_pattern(names) -> re.Pattern:
    """A skill name in a span: any `domain-*` / `ticket-*` token, or one of `names`, not part of a longer word or path
    segment (`session_retro`, `session-retro-notes`) and not a plugin's (`plugin:name`)."""
    return re.compile(r"(?<![\w:-])(?:(?:domain|ticket)-[\w-]*\w|" + names_alternation(names) + r")(?![\w-])")


SKILL_NAME = skill_name_pattern({*(p.name for p in SKILLS.iterdir() if p.is_dir()), *REMOVED_SKILLS})
COMMENT_ROOTS = ("scenes", "tests", "tools")
COMMENT_SUFFIXES = (".gd", ".py", ".sh")
PLACEHOLDER = re.compile(r"[*<>\[]")
# Paths a reference may name without the file being in the checkout, each with its reason.
NOT_TRACKED = (
    "sandboxes/showroom",  # a ticket's temporary showroom: it exists from the showroom phase to its removal
    "addons/gdUnit4/GdUnitRunner.cfg",  # written by the editor's GdUnit panel; gitignored
)


def skill_folders(skills: Path) -> list[Path]:
    return sorted(p for p in skills.iterdir() if p.is_dir())


def frontmatter(text: str) -> dict[str, str] | None:
    """The `key: value` lines between the leading `---` fences of `text`, or None when there is no frontmatter."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    fields = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return fields
        key, sep, value = line.partition(":")
        if sep and not line.startswith((" ", "\t")):
            fields[key.strip()] = value.strip()
    return None


def check_frontmatter(skills: Path) -> list[str]:
    """Findings on the frontmatter of every skill folder under `skills`: `name` is the folder, the description is
    present, starts with "Use" and fits DESCRIPTION_MAX; the model-invocable ones fit DESCRIPTIONS_TOTAL_MAX together."""
    found, total = [], 0
    for folder in skill_folders(skills):
        skill_md = folder / "SKILL.md"
        if not skill_md.is_file():
            found.append(f"{folder.name}: no SKILL.md")
            continue
        fields = frontmatter(skill_md.read_text())
        if fields is None:
            found.append(f"{folder.name}: no frontmatter")
            continue
        if fields.get("name") != folder.name:
            found.append(f"{folder.name}: name is {fields.get('name')!r}, not the folder")
        description = fields.get("description", "")
        if not description:
            found.append(f"{folder.name}: description is missing")
            continue
        if not description.startswith("Use"):
            found.append(f'{folder.name}: description does not start with "Use"')
        if len(description) > DESCRIPTION_MAX:
            found.append(f"{folder.name}: description is {len(description)} characters, over {DESCRIPTION_MAX}")
        if fields.get("disable-model-invocation") != "true":
            total += len(description)
    if total > DESCRIPTIONS_TOTAL_MAX:
        found.append(f"model-invocable descriptions total {total} characters, over {DESCRIPTIONS_TOTAL_MAX}")
    return found


def write_skill(skills: Path, folder: str, name: str | None = None, description: str | None = "Use when testing.",
                extra: str = "", body: str = "# Body\n") -> Path:
    """A skill folder under `skills`; `description=None` leaves the line out."""
    (skills / folder).mkdir(parents=True, exist_ok=True)
    lines = ["---", f"name: {folder if name is None else name}"]
    if description is not None:
        lines.append(f"description: {description}")
    if extra:
        lines.append(extra)
    path = skills / folder / "SKILL.md"
    path.write_text("\n".join([*lines, "---", body]))
    return path


def check_caps(skills: Path) -> list[str]:
    """Findings on size: a `SKILL.md` over SKILL_MD_MAX bytes, any other `.md` under a skill folder over SIDE_FILE_MAX."""
    found = []
    for folder in skill_folders(skills):
        for path in sorted(folder.rglob("*.md")):
            cap = SKILL_MD_MAX if path == folder / "SKILL.md" else SIDE_FILE_MAX
            size = path.stat().st_size
            if size > cap:
                found.append(f"{path.relative_to(skills)}: {size} bytes, over {cap}")
    return found


def inline_spans(text: str):
    """(line number, code span) for every backticked span of `text` outside a code fence."""
    for n, line in outside_fences(text):
        for m in INLINE_CODE.finditer(line):
            yield n, m[2].strip()


def repo_paths(span: str):
    """The repo paths a code span names: each whitespace-separated word that starts at a repo root, `res://` read as
    the repo, a `:line`, `::member` or `#anchor` suffix and trailing punctuation cut off."""
    for word in span.split():
        word = word.removeprefix("res://")
        if word.split("/")[0] in REPO_ROOTS and "/" in word:
            path = re.split(r"[:#]", word)[0].rstrip(".,;)")
            if path.rstrip("/") not in NOT_TRACKED:
                yield path


def check_references(skills: Path, files: list[Path], repo: Path) -> list[str]:
    """Findings in the Markdown `files`: a backticked `domain-*` / `ticket-*` name that is no folder of `skills`, a
    backticked path at a repo root that does not exist under `repo`. A word of a span with a placeholder or glob in
    it is skipped, the rest of the span is checked."""
    found = []
    for f in files:
        for n, span in inline_spans(f.read_text()):
            where = f"{f.relative_to(repo)}:{n}"
            words = without_placeholders(span)
            found += [f"{where}: skill {name} does not exist" for name in missing_skills(skills, words)]
            for path in repo_paths(words):
                if not (repo / path).exists():
                    found.append(f"{where}: path {path} does not exist")
    return found


def without_placeholders(span: str) -> str:
    """The words of `span` with no placeholder or glob in them."""
    return " ".join(w for w in span.split() if not PLACEHOLDER.search(w))


def missing_skills(skills: Path, words: str) -> list[str]:
    """The skill names in `words` that are no folder of `skills`."""
    return [name for name in SKILL_NAME.findall(words) if not (skills / name).is_dir()]


def comment_files(repo: Path) -> list[Path]:
    """The source files whose comments are read for skill names: `.gd`, `.py` and `.sh` under `scenes`, `tests`, `tools`."""
    return sorted(f for root in COMMENT_ROOTS if (repo / root).is_dir() for f in (repo / root).rglob("*")
                  if f.suffix in COMMENT_SUFFIXES and f.is_file())


def check_comment_references(skills: Path, files: list[Path], repo: Path) -> list[str]:
    """Findings in the source `files`: a backticked skill name in a line that starts with `#` (a `##` doc comment too)
    that is no folder of `skills`. A word with a placeholder or glob in it is skipped."""
    found = []
    for f in files:
        for n, line in enumerate(f.read_text().splitlines(), 1):
            if line.lstrip().startswith("#"):
                for m in INLINE_CODE.finditer(line):
                    words = without_placeholders(m[2])
                    found += [f"{f.relative_to(repo)}:{n}: skill {name} does not exist"
                              for name in missing_skills(skills, words)]
    return found


def reference_files(skills: Path, agents: Path, docs: Path) -> list[Path]:
    """The Markdown read for references: every skill file, the `AGENTS.md` file and every Markdown file under `docs`."""
    return sorted([*skills.rglob("*.md"), agents, *docs.rglob("*.md")])


def check_duplicates(files: list[Path], repo: Path) -> list[str]:
    """Findings for each paragraph of PARAGRAPH_MIN characters or more (whitespace normalised, code fences included)
    that appears in more than one of the Markdown `files`."""
    homes: dict[str, list[str]] = {}
    for f in files:
        name = str(f.relative_to(repo))
        for paragraph in re.split(r"\n\s*\n", f.read_text()):
            text = " ".join(paragraph.split())
            if len(text) >= PARAGRAPH_MIN and name not in homes.setdefault(text, []):
                homes[text].append(name)
    return [f"{' and '.join(names)} share a paragraph: {text[:60]}..." for text, names in homes.items()
            if len(names) > 1]


def duplication_files(skills: Path, agents: Path, docs: Path) -> list[Path]:
    """The Markdown held to one source of truth: every skill file, `AGENTS.md`, `docs/*.md` and `docs/agents/*.md`."""
    return sorted([*skills.rglob("*.md"), agents, *docs.glob("*.md"), *(docs / "agents").glob("*.md")])


class FrontmatterTests(unittest.TestCase):
    def findings(self, build) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            skills = Path(tmp)
            build(skills)
            return check_frontmatter(skills)

    def test_a_well_formed_skill_has_no_finding(self):
        self.assertEqual(self.findings(lambda s: write_skill(s, "alpha")), [])

    def test_a_name_that_is_not_the_folder_is_a_finding(self):
        found = self.findings(lambda s: write_skill(s, "alpha", name="beta"))
        self.assertEqual(len(found), 1, found)
        self.assertIn("alpha", found[0])
        self.assertIn("name", found[0])

    def test_a_missing_description_is_a_finding(self):
        found = self.findings(lambda s: write_skill(s, "alpha", description=None))
        self.assertEqual(len(found), 1, found)
        self.assertIn("description", found[0])

    def test_a_description_must_start_with_use(self):
        found = self.findings(lambda s: write_skill(s, "alpha", description="When testing."))
        self.assertEqual(len(found), 1, found)
        self.assertIn('"Use"', found[0])

    def test_a_description_of_201_characters_is_a_finding_and_200_is_not(self):
        self.assertEqual(self.findings(lambda s: write_skill(s, "alpha", description="Use " + "x" * 196)), [])
        found = self.findings(lambda s: write_skill(s, "alpha", description="Use " + "x" * 197))
        self.assertEqual(len(found), 1, found)
        self.assertIn("201", found[0])

    def test_a_skill_with_no_skill_md_is_a_finding(self):
        def build(s: Path):
            (s / "alpha").mkdir()
            (s / "alpha" / "side.md").write_text("# Side\n")
        found = self.findings(build)
        self.assertEqual(len(found), 1, found)
        self.assertIn("SKILL.md", found[0])

    def test_model_invocable_descriptions_total_at_most_6144(self):
        def build(total_per_skill: int, count: int):
            def make(s: Path):
                for i in range(count):
                    write_skill(s, f"skill-{i}", description="Use " + "x" * (total_per_skill - 4))
            return make
        # 32 descriptions of 192 characters: exactly 6144.
        self.assertEqual(self.findings(build(192, 32)), [])
        found = self.findings(build(192, 33))
        self.assertEqual(len(found), 1, found)
        self.assertIn("6144", found[0])

    def test_a_manual_only_skill_is_left_out_of_the_total_but_not_the_per_description_cap(self):
        def build(s: Path):
            for i in range(32):
                write_skill(s, f"skill-{i}", description="Use " + "x" * 188)
            write_skill(s, "manual", description="Use " + "y" * 196, extra="disable-model-invocation: true")
        self.assertEqual(self.findings(build), [])

        def build_long(s: Path):
            write_skill(s, "manual", description="Use " + "y" * 197, extra="disable-model-invocation: true")
        found = self.findings(build_long)
        self.assertEqual(len(found), 1, found)
        self.assertIn("201", found[0])

    def test_the_live_skills_pass(self):
        self.assertEqual(check_frontmatter(SKILLS), [])


class CapTests(unittest.TestCase):
    def findings(self, build) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            skills = Path(tmp)
            build(skills)
            return check_caps(skills)

    def test_a_skill_md_of_12288_bytes_passes_and_one_byte_more_is_a_finding(self):
        def build(size: int):
            def make(s: Path):
                path = write_skill(s, "alpha")
                path.write_text(path.read_text() + "x" * (size - path.stat().st_size))
            return make
        self.assertEqual(self.findings(build(12288)), [])
        found = self.findings(build(12289))
        self.assertEqual(len(found), 1, found)
        self.assertIn("alpha/SKILL.md", found[0])
        self.assertIn("12289", found[0])

    def test_a_side_file_of_8192_bytes_passes_and_one_byte_more_is_a_finding(self):
        def build(size: int):
            def make(s: Path):
                write_skill(s, "alpha")
                (s / "alpha" / "deep").mkdir()
                (s / "alpha" / "deep" / "side.md").write_text("x" * size)
            return make
        self.assertEqual(self.findings(build(8192)), [])
        found = self.findings(build(8193))
        self.assertEqual(len(found), 1, found)
        self.assertIn("alpha/deep/side.md", found[0])

    def test_a_file_that_is_not_markdown_is_not_capped(self):
        def build(s: Path):
            write_skill(s, "alpha")
            (s / "alpha" / "wait.sh").write_text("x" * 20000)
        self.assertEqual(self.findings(build), [])

    def test_the_live_skills_are_within_their_caps(self):
        self.assertEqual(check_caps(SKILLS), [])


class ReferenceTests(unittest.TestCase):
    """`check_references(skills, files, repo)`: the skills under `repo/.claude/skills`, `files` the Markdown read."""

    def findings(self, text: str, build=None) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            skills = repo / ".claude" / "skills"
            write_skill(skills, "domain-alpha")
            write_skill(skills, "ticket")
            (repo / "scenes" / "ai").mkdir(parents=True)
            (repo / "scenes" / "ai" / "real.gd").write_text("")
            (repo / "docs").mkdir()
            doc = repo / "docs" / "spec.md"
            doc.write_text(text)
            if build:
                build(repo)
            return check_references(skills, [doc], repo)

    def test_a_skill_name_that_exists_and_a_path_that_exists_pass(self):
        self.assertEqual(self.findings("See `domain-alpha` and `scenes/ai/real.gd`, `scenes/ai/` too.\n"), [])

    def test_a_removed_skill_is_a_finding_with_its_line(self):
        found = self.findings("Intro\nSee `domain-gone`.\n")
        self.assertEqual(len(found), 1, found)
        self.assertIn("docs/spec.md:2", found[0])
        self.assertIn("domain-gone", found[0])

    def test_a_folded_ticket_skill_is_a_finding(self):
        found = self.findings("Run `ticket-bug` first.\n")
        self.assertEqual(len(found), 1, found)
        self.assertIn("ticket-bug", found[0])

    def test_a_skill_name_inside_a_longer_span_is_read(self):
        found = self.findings("`.claude/skills/domain-gone/SKILL.md`\n")
        self.assertTrue(any("domain-gone" in f for f in found), found)

    def test_a_missing_repo_path_is_a_finding_for_every_root(self):
        roots = ["scenes", "tests", "tools", "docs", ".claude", "addons", "sandboxes", ".githooks"]
        text = " ".join(f"`{r}/nope.md`" for r in roots)
        found = self.findings(text)
        self.assertEqual(len(found), len(roots), found)

    def test_a_path_is_read_out_of_a_command_and_trimmed_of_its_suffix(self):
        text = "`tools/run.sh --id=ai/x`, `scenes/ai/real.gd:42`, `scenes/ai/real.gd::func`, `scenes/ai/real.gd`."
        found = self.findings(text, lambda r: (r / "tools").mkdir() or (r / "tools" / "run.sh").write_text(""))
        self.assertEqual(found, [])
        self.assertEqual(len(self.findings("`tools/run.sh --id=ai/x`")), 1)

    def test_a_res_path_is_read_as_a_repo_path(self):
        self.assertEqual(self.findings("`res://scenes/ai/real.gd`"), [])
        self.assertEqual(len(self.findings("`res://scenes/ai/nope.gd`")), 1)

    def test_only_the_placeholder_word_is_skipped_not_the_rest_of_the_span(self):
        found = self.findings("`tools/nope.sh --base=<rev> --id=<id>` `domain-<name>` `scenes/<domain>/x.gd`")
        self.assertEqual(len(found), 1, found)
        self.assertIn("tools/nope.sh", found[0])

    def test_placeholders_and_globs_are_skipped(self):
        text = "`domain-<name>` `scenes/<domain>/x.gd` `scenes/ai/*.gd` `tests/**/x_test.gd` `ticket-*`"
        self.assertEqual(self.findings(text), [])

    def test_a_test_id_and_an_unrooted_name_are_no_path(self):
        self.assertEqual(self.findings("`ai/foo` `foo.gd` `real.gd` `other/scenes/x.gd` `src/scenes/x.gd`"), [])

    def test_a_code_fence_is_not_read(self):
        text = "```\n`domain-gone` `scenes/ai/nope.gd`\n```\nAfter `domain-gone2`.\n"
        found = self.findings(text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("domain-gone2", found[0])

    def test_a_skill_that_is_no_domain_or_ticket_is_read_too(self):
        # `session-retro` is no folder of the fixture's skills root.
        found = self.findings("Run `session-retro`, then `m-audit-everything`.\n")
        self.assertEqual(len(found), 2, found)
        self.assertIn("session-retro", found[0])

    def test_a_skill_that_exists_is_no_finding_whatever_its_name(self):
        def build(repo: Path):
            write_skill(repo / ".claude" / "skills", "session-retro")
        self.assertEqual(self.findings("Run `session-retro`.\n", build), [])

    def test_a_word_that_only_starts_with_a_skill_name_is_no_reference(self):
        self.assertEqual(self.findings("`session-retro-notes` `session_retro`\n"), [])

    def test_a_plugin_skill_is_no_project_skill(self):
        self.assertEqual(self.findings("`mattpocock-skills:domain-modeling`"), [])
        self.assertEqual(len(self.findings("`domain-modeling` and `/ticket-bug`")), 2)

    def test_a_bracketed_name_is_a_placeholder(self):
        self.assertEqual(self.findings("`.claude/skills/domain-alpha/[brief file]`"), [])

    def test_a_path_that_exists_only_while_a_ticket_or_a_run_makes_it_is_not_required(self):
        # The exceptions: a ticket's temporary showroom and the config the gdUnit panel writes (gitignored).
        self.assertEqual(self.findings("`sandboxes/showroom/` `addons/gdUnit4/GdUnitRunner.cfg`"), [])
        self.assertEqual(len(self.findings("`sandboxes/showroom/other.gd` `addons/gdUnit4/Other.cfg`")), 2)

    def test_the_live_references_exist(self):
        self.assertEqual(check_references(SKILLS, reference_files(SKILLS, AGENTS, DOCS), ROOT), [])


class CommentReferenceTests(unittest.TestCase):
    """`check_comment_references(skills, files, repo)`: a skill named in a backticked span of a `#` comment line."""

    def findings(self, text: str, name: str = "scenes/x.gd") -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            skills = repo / ".claude" / "skills"
            write_skill(skills, "domain-alpha")
            source = repo / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(text)
            return check_comment_references(skills, [source], repo)

    def test_a_removed_skill_in_a_comment_is_a_finding_with_its_line(self):
        found = self.findings("extends Node\n## See the `domain-gone` skill.\n")
        self.assertEqual(len(found), 1, found)
        self.assertIn("scenes/x.gd:2", found[0])
        self.assertIn("domain-gone", found[0])

    def test_a_single_hash_comment_and_an_indented_one_are_read(self):
        found = self.findings("def f():\n    # `session-retro` says so\n", "tools/x.py")
        self.assertEqual(len(found), 1, found)

    def test_a_skill_that_exists_is_no_finding(self):
        self.assertEqual(self.findings("# See `domain-alpha`.\n"), [])

    def test_a_line_that_is_not_a_comment_is_not_read(self):
        self.assertEqual(self.findings('var s := "`domain-gone`"\n'), [])

    def test_a_placeholder_is_skipped(self):
        self.assertEqual(self.findings("## the `domain-<name>` skills, `ticket-*`\n"), [])

    def test_the_live_comments_name_no_removed_skill(self):
        files = comment_files(ROOT)
        self.assertTrue(any(f.suffix == ".gd" for f in files) and any(f.suffix == ".py" for f in files)
                        and any(f.suffix == ".sh" for f in files), "premise: gd, py and sh files are read")
        self.assertEqual(check_comment_references(SKILLS, files, ROOT), [])


class FenceTests(unittest.TestCase):
    """A fence must not hide the lines after it: only a run that opens a fence, and a run that closes it, count."""

    def spans(self, text: str) -> list[str]:
        return [span for _, span in inline_spans(text)]

    def test_an_inline_triple_backtick_span_opens_no_fence(self):
        self.assertEqual(self.spans("```a``` is inline\n`scenes/nope.gd`\n"), ["a", "scenes/nope.gd"])

    def test_a_shorter_run_inside_a_longer_fence_does_not_close_it(self):
        self.assertEqual(self.spans("````\n```\n`inside.gd`\n````\n`scenes/nope.gd`\n"), ["scenes/nope.gd"])

    def test_a_tilde_fence_closes_on_tildes_only(self):
        self.assertEqual(self.spans("~~~\n```\n`inside.gd`\n~~~\n`scenes/nope.gd`\n"), ["scenes/nope.gd"])


class DuplicationTests(unittest.TestCase):
    def findings(self, **files: str) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            paths = []
            for name, text in files.items():
                path = repo / f"{name}.md"
                path.write_text(text)
                paths.append(path)
            return check_duplicates(paths, repo)

    def test_a_paragraph_of_200_characters_in_two_files_is_a_finding_naming_both(self):
        paragraph = "x" * 200
        found = self.findings(a=f"# A\n\n{paragraph}\n", b=f"{paragraph}\n\nOther.\n")
        self.assertEqual(len(found), 1, found)
        self.assertIn("a.md", found[0])
        self.assertIn("b.md", found[0])

    def test_a_paragraph_of_199_characters_is_not(self):
        self.assertEqual(self.findings(a="x" * 199, b="x" * 199), [])

    def test_whitespace_is_normalised(self):
        words = " ".join(["word"] * 60)
        wrapped = "\n  ".join(words.split(" "))
        found = self.findings(a=words, b=wrapped + "\n")
        self.assertEqual(len(found), 1, found)

    def test_one_file_repeating_itself_is_no_finding(self):
        paragraph = "x" * 200
        self.assertEqual(self.findings(a=f"{paragraph}\n\n{paragraph}\n"), [])

    def test_different_long_paragraphs_are_no_finding(self):
        self.assertEqual(self.findings(a="x" * 200, b="y" * 200), [])

    def test_a_code_fence_is_read_like_any_paragraph(self):
        block = "```\n" + "x" * 200 + "\n```"
        found = self.findings(a=block, b=block)
        self.assertEqual(len(found), 1, found)

    def test_a_docs_spec_is_held_to_the_same_rule_as_a_skill(self):
        paragraph = "x" * 200
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            skills, docs = repo / ".claude" / "skills", repo / "docs"
            write_skill(skills, "alpha", body=f"# A\n\n{paragraph}\n")
            (docs / "agents").mkdir(parents=True)
            (docs / "spec.md").write_text(f"{paragraph}\n")
            (docs / "agents" / "tracker.md").write_text(f"{paragraph}\n")
            (repo / "AGENTS.md").write_text("Other.\n")
            found = check_duplicates(duplication_files(skills, repo / "AGENTS.md", docs), repo)
        self.assertEqual(len(found), 1, found)
        for name in ("docs/spec.md", "docs/agents/tracker.md", "alpha/SKILL.md"):
            self.assertIn(name, found[0])

    def test_the_live_files_share_no_long_paragraph(self):
        self.assertEqual(check_duplicates(duplication_files(SKILLS, AGENTS, DOCS), ROOT), [])


if __name__ == "__main__":
    unittest.main()
