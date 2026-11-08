# AI · Debug words (`scenes/ai/debug/`): `text_in_world`, `card_lines()`, `drawn_texts()`

The overlays that say their status in words (`agent_debug`, `brain_debug`, `search_debug`, `entry_debug`) keep the words apart from the geometry, so the spectator's detail card
(`domain-ui` (`hud.md`)) shows them instead of the world. The overlays and their toggles are `debug.md`.

- `text_in_world` (on `debug_overlay.gd`, default true): off, those four draw no text (the agent label, brain badges and timers, search readout, entry badge, timer labels and short tags) and their geometry draws as ever.
  The inspector turns it off on every NPC at `setup` (through `OverlayRegistry.apply`); a played match and the test runner leave it on. The other overlays' short tags (the zone legend, a contact's reason) are not gated.
- **Brain.** With `text_in_world` off, `brain_debug.gd` draws **nothing at all** (no bars, no ring, no labels) unless its `brain_labels` (default false) is on; then it draws its bars, its next-decision ring and short labels
  by its indicators (the THINKING / FALLBACK badges, each level's node title, each bar's option and percentage, the ring's seconds), in the full layout. Facts, the timers line, the forced reason and an auto-picked level's pick stay card-only.
  With `text_in_world` on it draws the full overlay on every NPC in scope and `brain_labels` changes nothing. The inspector sets `brain_labels` on the selected NPC alone.
  In the file, card lines go through `_say` (gated by `text_in_world`), the short indicator labels straight through `DebugText.string` / `_label` (the paint that reaches them is already allowed to draw).
- `card_lines() -> PackedStringArray` (the four, base: empty): the lines the overlay draws as text with `text_in_world` on, in drawing order, whatever the toggles say; empty while it has nothing to say.
  `agent_debug`: the decision path (`debug_status()`); `brain_debug`: the badges, the timers, why the last decision was forced, the facts that hold and per level the node with Von's probability for each offered option;
  `search_debug`: `searched N/total  Ss left` while the NPC covers a room; `entry_debug`: the badge (slot · role · phase · pie progress · seen %) and the timer labels while an entry runs.
- Read-outs for tests: `drawn_texts() -> PackedStringArray` (every string the last paint drew, in order, cleared at each paint) and `BrainDebug.drawn() -> Array`, rebuilt from empty at every redraw (also one that draws nothing):
  `{ kind: &"bar", option, probability, picked }` per bar, `{ kind: &"ring", fraction, radius }` while the ring's arc has something to draw, `{ kind: &"label", text }` per string.
  Tests: `ai/debug/overlay_text_in_card` (with `text_in_world` off the four draw no text while `card_lines()` return what they draw with it on; with `brain_labels` on the brain draws exactly its badges, titles, bar labels and the ring's seconds; both off, `drawn()` is empty),
  `ui/inspector_scope` (only the right-clicked NPC's `drawn()` is non-empty).
