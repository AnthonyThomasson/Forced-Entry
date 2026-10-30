18. **Main → Audio: `Sound.focus`** (whose ears the player has; Audio stays a leaf)
    - `Sound.focus: Node` (a plain var on the `Sound` autoload): the character a bang deafens *for the player*. Main sets it to the human when there is
      one (`_build_stun_screen`) and clears it at teardown; null = nobody (a spectator match, a test). Audio reads only the focus's `stun.view()` (interface 7)
      duck-typed: while `stun.view().deaf` > 0, `Sound.muffled()` (test read) is true, the game audio goes through a low-pass and one `tinnitus/whine` sound
      (kind `&"tinnitus"`) plays per stun, following the deafness (`docs/grenades.md` G14). A blind-only stun, or the stun of any other character, changes nothing.
    - The sight half of the same stun is the UI's `StunScreen` (`ui/hud/stun_screen.gd`, `watch(character)`, `drawn()` (test read)), built by Main for the human and reading
      `stun.view()` (`blind`, `blind_total`) and the `&"stun"` event; it knows nothing of Audio, nor Audio of it.
