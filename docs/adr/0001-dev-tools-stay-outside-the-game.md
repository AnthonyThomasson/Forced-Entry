# Dev tools stay outside the game

A dev tool that studies the game (the runtime coverage tool, `tools/coverage/`) lives under `tools/` and is a one-way
dependency: it knows the project's layout, and the project never names it. It works on a throwaway copy of the tree,
kept in the gitignored `artifacts/tmp/` that Godot, the lint and the repo-wide tools never read, where it may rewrite
scripts and register its own autoload, and leaves the real tree byte-identical. The game never
naming it is enforced by a project lint rule (`coverage_isolation`, `tools/lint_rules/`), so deleting the tool breaks
nothing but the docs that describe it.

## Consequences

The tool hooks into the game dynamically, from inside the copy: its probe starts a match by emitting the setup window's
`start_requested(config)`, ends it at the MatchHUD's `match_ended`, and reads the running game test suite's current
entry and its test's context (its public `open_entry` / `open_ctx`, ending a test's hits at the context's `finished`),
all duck-typed. Those hooks are not `architecture` interfaces, so a rename in the game can break them unannounced; the
probe checks each one and fails loudly (an error, a failure file, exit code 3) rather than record a run that measured
nothing. A rule is a text scan: it cannot stop a tool
writing into the real tree at run time, so the tool checks the tree's hash after each run and fails if it changed.

## Considered options

- **Command-line arguments read by Main** (e.g. a flag that starts a match and records it): Main would name the tool,
  so the game would depend on it and the lint rule would need an exception, and a flagged start would skip the path a
  real click takes (the wait for the Von server).
- **Driving the game over the dev command server (`gcmd` over TCP):** a port and a socket client for every parallel
  game process, and the match would start through the command server's code instead of the setup window's, so the
  measured start would not be a real one.
