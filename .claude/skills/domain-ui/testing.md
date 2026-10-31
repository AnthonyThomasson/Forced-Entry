# UI testing (`scenes/ui/testing/`)

The two widgets the Testing domain's browser and runner show (interface 13: nothing depends on Testing). Both take plain dicts and emit signals; the
host side is `domain-testing`. Tests: `tests/ui/test_browser_window_test.gd` (real mouse events), `test_browser_category_rows_test.gd`,
`test_result_hud_clicks_through_test.gd`.

## `test_browser_window.gd` — `TestBrowserWindow` (CanvasLayer, hosted by `test_browser.tscn`)

- `open(tests, sandboxes, results, matcher, state: TestBrowserState = null)`: `tests` and `sandboxes` are descriptor dicts, `matcher(test, text)` is the host's search.
  `TestBrowserState` (`test_browser_state.gd`: `filter`, `selected`, `checked`) restores the last view; null restores nothing.
- Signals out: `play_requested(path)` (Play, double-click, Enter), `back_requested`, `filter_changed(text)`, `run_requested(domain)` (Run all, or a domain row's ▶; `""` is every
  test, and the row's ▶ always means the whole domain whatever the search shows), `checked_changed(ids)` (the host persists them), `run_queue_requested(paths)` (**Run N checked**:
  every ticked test's script path in list order, for the headed one-by-one run; disabled at 0 and during a headless run). The host answers with `set_run_status(text, running)`
  (running disables Run all and every ▶) and `set_results(results)` (redraws the marks; ○ marks a GAP test).
- **Checkboxes.** Every test row has one (not sandboxes, nor a test whose script fails to load). A domain or topic row's box is tri-state over *its shown tests* and toggles
  exactly those; **Check shown / Uncheck shown** does the same for every shown test. Bulk checks therefore respect the search, and ticks of hidden tests survive it.
- Double-clicking a test's label opens it. Godot raises `item_activated` for rows without a checkbox and for Enter, but not for a double-click on an editable check cell,
  so `test_browser_list.gd`'s `_on_tree_input` handles that one.
- **The list** is `test_browser_list.gd`, a `Tree` subclass (`TestBrowserList`, preloaded) that the window builds and holds as `_tree`. It owns the rows (grouped by domain, then by
  topic folder such as `tests/ai/entry/`), the ticks and their partial state, the ▶ buttons and their run lock, and the result marks. It reports through its own signals, which the window relays.

## `test_result_hud.gd` — `TestResultHUD` (CanvasLayer 10, top-left, built by the runner in interactive mode, `PROCESS_MODE_ALWAYS`)

- `show_running(entry)`, `show_status(text)`, `show_result(result)` (PASS / FAIL / TIMEOUT / SKIPPED; GAP for a `gap`-tagged test that failed as expected; MANUAL for a passing
  sandbox; each check ✓/✗, the sim time and, on a failure, each actor's final state from `result.snapshot`).
- Buttons emit `rerun_requested`, `back_requested`, `pause_requested` (`set_paused(on)` relabels it; `set_pause_enabled(on)` hides it when a test locks pause). In a queued run
  `show_queue(index, total)` hides Rerun and shows **Next ▸** (`next_requested`, enabled by `set_next_ready` once a verdict is up); `show_queue_done(summary)` ends it.
- Only the buttons take the mouse: the panel and its containers are `MOUSE_FILTER_IGNORE`, so a click on text or padding falls through to the world (a windowed test clicking a doorway the camera
  framed under the banner reaches it). Buttons take no focus, so keys stay with the game.
