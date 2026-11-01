7. **Character ↔ Controller** (enables non-player characters)
   The character reads intent from a pluggable **controller child**: any node with `control(character, delta)`. The controller writes
   `movement.move_input` / `movement.aim_point` / `movement.run_input` (hold run: faster, spends stamina, dry = walk until it refills;
   only a standing character runs) and calls the action API of the character's typed components (`movement`, `weapon`, `ammo`, `inventory`, `use`
   (`CharacterUse`), `anatomy`, `wardrobe`, `stun`; `typed-components.md`):
   - **Acts:** `movement.set_posture(p) -> bool` (`stand` / `crouch`; idempotent; the player's C is `movement.toggle_crouch()`), `weapon.melee()` (F), `anatomy.leg_kick() -> bool` (a right-leg kick along the facing, whatever is held;
     false while dead, crouched, busy or kicking; `anatomy.is_kicking()` is a test read; **not** the recoil `weapon.kick`),
     `weapon.shoot() -> bool` (LMB; true = a round left the barrel; ignored while running, reloading or with a long gun raised; a controller
     re-presses it every frame while `weapon.is_automatic()`),
     `ammo.reload()` (R: a timed swap to the fullest carried magazine; refused while running or busy, cancelled by running, switching
     items or dying), `inventory.select_slot(id)`, `use.try_interact()` / `use.interact_with(object, id)` / `use.end_interaction()`,
     `use.try_use()` (E: the nearer of a house door in reach and a vehicle; 19, 24), `use.use_target()` and `use.doors` (24), `inventory.set_loadout(kit: CharacterKit)` (`items/character_kit.gd`: carry only
     `slots`, hold `hold_slot`, `spare_types` magazines, the gun loaded with `loaded_magazine`, `grenades` counts, every item in
     `weapon_style`; how `MatchBuilder.arm` arms a spawn, 23).
   - **Reads:** `damage_taken()` (accumulated hit damage), `movement.posture()` / `is_running()` / `stamina_fraction()` /
     `run_speed()` / `walk_speed()` (px/s, slower while stunned or by outfit weight: how an AI judges whether it gets somewhere in time) / `posture_coverage(posture)` (the body's height on the coverage scale, what furniture must stand above to shield it);
     `ammo.rounds(slot := -1)` / `capacity(slot)` / `can_reload(slot)` / `spare_magazines()` / `is_reloading()` (slot -1 = held item;
     -1 rounds = no ammo); `inventory.item_name(slot := -1)` / `current_item()` / `current_slot()` / `item_reach()` / `has_item(id)` /
     `gun_slot()` (the held item if it takes ammo, else the lowest such slot, else −1) / `item_count(slot := -1)` (a grenade slot's count, 1
     for any other item, 0 for none) / `throw_stats(slot := -1)` (a carried grenade's `{ kind, max_range, danger_radius, fuse,
     flash_cover_reach, max_blind }`, `{}` otherwise) / `throw_release_offset(slot := -1)` (where a standing throw leaves the hand:
     `Vector2(px ahead, px right)` in the body's frame; the AI judges a lob from there); `anatomy.hands.is_attacking()`;
     `weapon.blocked()` / `raise()` / `is_automatic()` / `aim_target()` (the swayed point a grenade is thrown to, interface 6).
   - **Wardrobe** (`docs/outfits.md` O15, looks only): `wardrobe.style` (exported key of `CharacterStyleConfig.styles`: `zenitex` /
     `trauma` police, `merc` / `borg` defenders' crew; `zenitex` when never given), `wardrobe.look_seed`, `wardrobe.rank` (police: 0 trooper, 1 sergeant, 2 lead), `wardrobe.set_style(style, seed, rank := 0)`; `wardrobe.outfit` (an `Outfit`): `set_ids(ids)` (replaces
     the whole outfit; `LoadoutConfig.apply` calls both), `look(style)` / `revision` (what the art reads), `view()` (garment slot → name,
     plate slot → `{ type, name, condition }`; the debug panel and the inspector list it). `get_surface_at` (interface 3) places a round by
     height and side (O3, O4); outfit weight slows every pace.
   - **Stun** (flash and bang): `take_stun(blind, deaf)` (interface 3) and `stun.is_blind()` / `is_deaf()` / `level()` (0..1
     disorientation: slowed to `CharacterStunConfig.speed`, no running, aim sway) / `view()` (`{ blind, blind_total, deaf, level }`, for the
     UI); `weapon.one_handed()` (blind: the round spreads wider); `blast_push(from, impulse)` (an explosion's shove: knockback, or the
     fallen body's ragdoll thrown).
   - **Vehicle:** from the E press to the last step out `use.is_busy()` is true and `inventory.current_item()` is null.
   - **Identity:** `faction` (for hostility), exported `radius` (fixed; Vehicles and Lighting read it). Every character
     joins the group `characters` in `_ready`: how the AI's perception, `Explosion` and vehicles find characters.
   - **Priority:** the AI controller alone writes its character's `process_physics_priority`: 1 while a primed ambusher holds its post
     (`docs/leadership.md` LD15, D37), 0 after.

   **What the AI may read of another character:** `facing`, `damage_taken()`, `ammo.is_reloading()`, `movement.posture()`,
   `inventory.current_item()` and `faction` only while it SEES that character (aim, wounds, a reload and posture are perceived). Three
   reads of an unseen character's `faction` stand for knowing who is on its own team: a footstep's `character` (the `footfall` event,
   interface 10, `docs/hearing.md` H1), a hit's `attacker` and an explosion's `attacker` (`docs/grenades.md`). A member also knows its squad
   unseen (interface 21, `docs/leadership.md`): who is in it and leads it, and an order names its recipients and `faction`, so an NPC takes
   only its own side's orders; its squad reads the leader's `global_position` / `facing` and the members' `global_position` unseen (LD19
   to LD23).

   **Signals:** `hit_landed(body, damage, hand)` (hand 0/1 punch, 2 leg kick, −1 shot), `died` (read `is_dead` / `health`; a dead body
   falls as a ragdoll, leaves layer 1 and draws beneath the living). Observers attach by exported node path and read only the public API
   and signals.

   **The player's controller** (`player_controller.gd`) is the only *gameplay* file that touches `Keybinds` (Use, `Keybinds.USE`: 24); observers read one action
   each (Main `MENU`, the inspector `PAUSE`, the command menu `COMMAND`, the camera its pan and zoom; the runner `MENU`, `PAUSE`).

   **The AI controller** (`ai/goal_controller.gd`, a thin orchestrator over the sub-domains in `domain-ai`):
   - It is in the group `npc_controllers`, authored on its node in `ai/npc.tscn` (so it holds before the NPC joins the tree). HUDs find an
     NPC's controller as its child in that group (`hud_probe.gd`; a player's controller is never one).
   - Every NPC is the same goal-driven agent. The defender (`ai/npc_defender.tscn`) and invader (`ai/npc_invader.tscn`) inherit
     `ai/npc.tscn` (itself inheriting the controller-less `character/character_base.tscn`) and differ only in scene data: the `goal`
     string and the tunables of its `tuning` (`NpcTuning`, `ai/tuning/`: the `Tuning` child, a node per topic, `tuning.<topic>.<name>`; a
     preset overrides a topic node's values). A composer or test sets one by indexed path (`set_indexed("tuning:entry:enabled", …)`)
     before the NPC joins the tree.
   - A composer injects only `rooms`, `openings` and `entry_point` by the one bind rule `MatchBuilder.bind_npc`, before the NPC joins the
     tree (interface 23), and its side's squad by `MatchBuilder.bind_squad` (interface 21).
   - Observers: `current_act()` (the live decision path as ids, e.g. `combat/t_12/flank/side_left`), `debug_status()` (as labels),
     `debug_state() -> Dictionary` (the deep snapshot the command server's `ai` verb dumps), `debug_zones() -> Array` (the points the spectator inspector picks from;
     `debug_focus` rings one on the tactics overlay, `Vector2.INF` clears it), `known_contacts_for_display()`, and the overlays' `debug_*`
     getters (`debug_entry_view()`, `debug_grenades()`).
   - Each overlay is a child of the NPC with a `show_<x>` export named in the UI's `OverlayRegistry`; `MatchBuilder.set_overlay` (Main's
     match and Testing's world alike), the spectator inspector and Testing's actor spawn set those flags by that name, so an overlay's export
     is part of this surface.
