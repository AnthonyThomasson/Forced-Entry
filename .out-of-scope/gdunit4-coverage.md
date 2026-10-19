# gdUnit4-coverage

Code coverage through gdUnit4-coverage (https://github.com/godot-gdunit-labs/gdUnit4-coverage) is not adopted. The
project measures what runs with its own dev tool, `tools/coverage/` (an instrumented copy of the tree, matches and
tests, `docs/adr/0001-dev-tools-stay-outside-the-game.md`), and that tool stays.

Why:

- **It needs a newer engine and a newer gdUnit4.** gdUnit4-coverage requires Godot 4.7 and gdUnit4 6.2. The project is
  on Godot 4.4 with gdUnit4 5.1.1, the last gdUnit4 line that supports it (`docs/adr/0002-tests-run-through-gdunit4.md`);
  gdUnit4 6.x itself needs Godot 4.5 or later. Adopting it means upgrading the engine first, a change of its own across
  every domain.
- **It needs a closed-source, patched engine.** Its coverage hooks are not in the stock Godot build: it runs on a
  patched engine whose source is not published, so the project could not build, audit or pin the engine it tests on.
- **The public build caps a session at 20 files.** The game has hundreds of scripts, so a session covers a small slice
  of the tree; a whole-tree report would need many sessions stitched together.

Revisiting it is the follow-up ticket for the Godot 4.7 and gdUnit4 6.2 upgrade, which would weigh these again once the
engine is current.

## Prior requests

- #70 — "use gdunit and gdstyle"
