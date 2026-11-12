18. **Main → Audio: `Sound.focus`, `Sound.warming()`** (whose ears the player has, and whether the sound library is still rendering; Audio stays a leaf)
    - `Sound.focus: Node` (a plain var on the `Sound` autoload): the character a bang deafens *for the player*. Main sets it to the human
      (`_build_stun_screen`) and clears it at teardown; null = nobody (a spectator match, a test). Audio reads only the focus's
      `stun.view()` (7), duck-typed: while `stun.view().deaf` > 0, `Sound.muffled()` (test read) is true, the game audio goes through a
      low-pass and one `tinnitus/whine` sound (kind `&"tinnitus"`) plays per stun, following the deafness (`docs/grenades.md` G14). A
      blind-only stun, or any other character's stun, changes nothing.
    - The sight half of the same stun is the UI's `StunScreen` (`ui/hud/stun_screen.gd`, `watch(character)`, `drawn()` test read), built by
      Main for the human; it reads `stun.view()` (`blind`, `blind_total`) and the `&"stun"` event. It knows nothing of Audio, nor Audio of it.
    - `Sound.warming() -> bool`: true while the library's pre-warm (a worker, ~9 s from launch, with a display only) still renders. Main waits on it
      before a match is built (`_on_setup_chosen` with the window up and a status line, `start_match` for any other start), so no sound is
      synthesized on the main thread in a fight; it is false at once headless. Audio knows nothing of Main.
