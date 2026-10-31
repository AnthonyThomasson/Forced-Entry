7. **Character ↔ Controller** (enables non-player characters)
   The character reads intent from a pluggable **controller child** — any node with
   `control(character, delta)`. The controller writes its `movement` component's (`character_movement.gd`, `CharacterMovement`)
   `movement.move_input` / `movement.aim_point` / `movement.run_input` (hold run: a
   faster pace that spends stamina while moving, dry = walk until it refills; only a standing character runs) and calls the
   character's action API: `movement.set_posture(p) -> bool` (`stand` / `crouch`; idempotent, so a controller may write it every frame; the player's C calls
   `movement.toggle_crouch()`), `weapon.melee()` (F), `anatomy.leg_kick() -> bool` (a right-leg kick along the facing, whatever is held; false while dead, crouched, busy or a kick is under way; `anatomy.is_kicking()` (test read) is whether one is; **not** the recoil `weapon.kick(hand, strength)` above), `weapon.shoot() -> bool` (LMB; true = a round left the barrel; ignored while running, reloading,
   or with a long gun's barrel against a wall or object, and a gun holds back between rounds per its fire rate; a controller re-presses it
   every frame while the trigger is held when `weapon.is_automatic()`), `ammo.reload()` (R: a timed swap to
   the fullest carried magazine, taking the item's `ammo.reload_time()`; refused while running or busy and cancelled by running, switching items or
   dying), `inventory.select_slot(id)`, `use.try_interact()` /
   `use.interact_with(object, id)` / `use.end_interaction()`, `use.try_use_vehicle()` (E: get in or out, interface 19), and may read `damage_taken()` (accumulated hit
   damage, for injury sensing), `movement.posture()`, `movement.is_running()` / `movement.stamina_fraction()`, `movement.run_speed()` / `movement.walk_speed()` (px/s standing, running / walking, slower while stunned or weighed down by the outfit: how an AI works out whether it gets somewhere in time) / `movement.posture_coverage(posture)` (the body's height on the coverage scale in `stand` / `crouch`, what furniture must stand above to shield it), the reads of its `ammo` component (`character_ammo.gd`, `CharacterAmmo`) `ammo.rounds(slot := -1)` / `ammo.capacity(slot)` / `ammo.can_reload(slot)` /
   `ammo.spare_magazines()` / `ammo.is_reloading()` (the held item for slot -1; -1 rounds = no ammo), the reads of its `inventory` component (`character_inventory.gd`, `CharacterInventory`) `inventory.item_name(slot := -1)`, `inventory.current_item()` / `inventory.current_slot()` / `inventory.item_reach()` / `inventory.has_item(id)` (the held item, its slot and reach, and whether a slot is carried — what the AI's wording, the debug panel and `requires_item` interactions read), `anatomy.hands.is_attacking()` (a punch swing is under way), `inventory.gun_slot()` (the
   gun it fights with: the held item if it takes ammo, else the lowest such slot, else −1), the weapon reads (its `weapon` component, `character_weapon.gd`, `CharacterWeapon`) `weapon.blocked()` / `weapon.raise()` /
   `weapon.is_automatic()`, `inventory.item_count(slot := -1)` (a grenade slot's count, 1 for any other item, 0 for none), `inventory.throw_stats(slot := -1)` (what a grenade carried in the slot tells its holder, `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, `{}` for any other item or an empty slot: how the AI reads a grenade's numbers, instead of keeping a copy), `inventory.throw_release_offset(slot := -1)` (where a grenade leaves its hand when it throws one standing: the hand of its `throw` stance, as `Vector2(px ahead of the body centre, px to its right)` in its own frame; the AI judges a lob from there, instead of keeping a copy of the stance), `weapon.aim_target()` (the swayed aim point a grenade
   is thrown to, interface 6: where the AI expects its own grenade to come down), `inventory.set_loadout(kit: CharacterKit)` (`CharacterKit`, `items/character_kit.gd`, Items' vocabulary: `slots`, `hold_slot`, `spare_types`, `loaded_magazine` = &"",
   `grenades` = {}, `weapon_style` = &"police"; carry only those slots, holding one, with those spare
   magazines, the gun loaded with that type when it fits, a grenade slot with `grenades[slot]` of them, every item in that weapon style (`Item.art.style`): how `MatchBuilder.arm` arms a spawn with its side's loadout, interface 23);
   how it is drawn (`docs/outfits.md` O15, looks only), on its `wardrobe` (the `Wardrobe` child, `character_wardrobe.gd`, `CharacterWardrobe`):
   `wardrobe.style` (exported; a `CharacterStyleConfig.styles` key: `zenitex` / `trauma` the police units, `merc` / `borg`
   the defenders' crew; `zenitex` when never given one), `wardrobe.look_seed` (exported: its own variety within the style), `wardrobe.rank` (a police unit's: 0 trooper, 1 sergeant,
   2 lead) and `wardrobe.set_style(style, seed, rank := 0)` (`LoadoutConfig.apply` calls it);
   what it wears (`docs/outfits.md`): `wardrobe.outfit` (an `Outfit`): `wardrobe.outfit.set_ids(ids)` (`{ head, body, vest, pants, feet, front_plate, back_plate }`, replacing the whole outfit; `LoadoutConfig.apply`
   calls it), the `Outfit` its art reads `look(style)` and `revision` from, and `wardrobe.outfit.view()` (each garment slot -> its name, "" for none; each plate slot ->
   `{ type, name, condition }`: what the debug panel and the spectator inspector list), with
   `get_surface_at` (interface 3) placing a round by its height and side (the zones and sides: `docs/outfits.md` O3, O4); an outfit's weight slows `movement.run_speed()` and every pace;
   while the character rides a vehicle (interface 19, from the E press to its last step out) `use.is_busy()` is true, and `inventory.current_item()` is null
   while it is posed by the ride (the item put away);
   the stun (a grenade's flash and bang): `take_stun(blind, deaf)` (on the body, interface 3) and its `stun` component (`character_stun.gd`, `CharacterStun`): `stun.is_blind()`, `stun.is_deaf()`, `stun.level()` (0..1 disorientation: slowed to `CharacterStunConfig.speed`, no running, aim sway;
   drawn hunched and staggering, the free hand over the eyes while blind), `weapon.one_handed()` (blind, a held gun is in the weapon hand alone: its rounds spread wider), `stun.view()` (`{ blind, blind_total, deaf, level }`, for the UI) and `blast_push(from, impulse)` (an explosion's shove: knockback, or the fallen body's ragdoll thrown) and `faction` (allegiance tag, for AI hostility), and the exported `radius` (the body's collision radius, fixed: the Vehicles and Lighting domains read it). The AI controller also writes its own character's engine `process_physics_priority`:
   1 while it is a primed ambusher (holding the ambush of its live order at its post, `docs/leadership.md` LD15, D37: its body moves after
   every other in the frame), 0 again after; no other code sets it on a character. The AI also reads
   another character's `facing`, `damage_taken()`, `ammo.is_reloading()`, `movement.posture()`, `inventory.current_item()` and `faction` — but only while it can SEE that character
   (aim, visible wounds, a reload in progress and the posture are things it perceives); the exceptions are three reads of an unseen character's `faction`,
   which stand for knowing who its own team is: the faction of a character whose footstep it hears (the `footfall` event's `character`, interface 10), so its
   own side's steps are never taken for a stranger's (`docs/hearing.md` H1); of the attacker of a hit on or near it (the `hit` event's `attacker`), so an
   ally's round striking nearby is not fire at it; and of the thrower of a grenade that bursts (the `explosion` event's `attacker`), so it knows a burst as its
   own team's (`docs/grenades.md`). A member also knows its squad unseen (interface 21, `docs/leadership.md`): who is in it and leads it, and an
   order names its recipients and its side (`to`, `faction` on the `&"order"` event), so an NPC takes only its own side's orders that name it; and
   its squad reads the leader's `global_position` and `facing` (and its members' `global_position`) unseen, to lay the spots its followers keep
   to and the leash they fight within (LD19 to LD23). Every character joins the group `characters` in its `_ready`:
   that group is how the AI (its perception and tactics), the Projectile System's `Explosion` and a vehicle tell a character in the world, so it
   is part of this interface and is not renamed lightly.
   `player_controller.gd` is the human one and
   is the only *gameplay* file that touches `Keybinds` (observers read one thing each: Main `MENU`; the test runner `MENU`, `PAUSE` and the camera actions;
   the spectator inspector `PAUSE`; the human leader's command menu `COMMAND`, and `MENU` only to close itself; the camera its pan and zoom actions). Signals:
   `hit_landed(body, damage, hand)` (hand 0/1 = melee punch, hand 2 = leg kick, hand −1 = shot),
   `died` (with `is_dead` / `health` to read; a dead body
   falls as a ragdoll, leaves layer 1 and draws beneath the living). Observers (debug HUD, match HUD, camera) attach by
   exported node path and read only the public API/signals; the AI controller is in the group `npc_controllers` (authored on its node in `ai/npc.tscn`, so it holds before the NPC joins the tree), and
   the HUDs find an NPC's controller as its child in that group (the UI's `hud_probe.gd`; a player's controller is never one). The AI controller also exposes
   `current_act()` (its live decision path as ids, e.g. `combat/t_12/flank/side_left`) and
   `debug_status()` (the same path as labels, every level: `COMBAT - Intruder - FLANK - their left
   side (kitchen)`), `debug_state() -> Dictionary` (the deep snapshot the dev command server's `ai` verb dumps; its `confinement` is where the NPC may act now, its
   `decision.confinement` the copy the last decision walk decided over), `debug_zones() -> Array`
   (the tactical points the spectator inspector picks from; it rings the one it describes on the NPC's tactics overlay through the
   controller's `debug_focus`, the point, `Vector2.INF` clearing it), the draw-only overlays' `debug_*` getters (e.g. `debug_entry_view()` for the tactical-entry ones), `known_contacts_for_display()` (the spectator inspector's contact list) for those observers to show. Each overlay is a child of the NPC with a `show_<x>` export named in the UI's `OverlayRegistry` (`show_grenades` reads `debug_grenades()`: `{ known: [{ point, kind, fuse_left, fuse, radius, source }], escape: Vector2 (INF: none), throw: {} }`);
   `MatchBuilder.set_overlay` (interface 23: Main's match and the Testing world's alike), the spectator inspector and the Testing world's
   actor spawn set those flags by that name, so an overlay's export is part of this surface. Every NPC is the same generic goal-driven agent
   driven by `ai/goal_controller.gd`; the defender (`ai/npc_defender.tscn`) and the invader
   (`ai/npc_invader.tscn`), both inherited from `ai/npc.tscn` (itself an inherited scene of the controller-less
   `character/character_base.tscn`), differ only in data authored on the scene —
   a plain-language `goal` on the controller plus generic primitives (hostility rules, pursuit, territory) and
   decision-tree config, each a tunable on the controller's `tuning` (`NpcTuning`, `ai/tuning/`: its `Tuning` child, one node per
   topic, `tuning.<topic>.<name>`; a preset overrides a topic node's values, e.g. `GoalController/Tuning/Hostility`). The scene hands
   the hub its topics as node references, resolved at `instantiate`, so a composer or a test sets one by indexed path on the
   controller (`set_indexed("tuning:entry:enabled", …)`) before the NPC joins the tree. Its composer injects only `rooms` and `openings` (and `entry_point`), by the one bind rule `MatchBuilder.bind_npc`, before the
   NPC joins the tree (interface 23; the controller found by the group `npc_controllers`, authored on the scene), and its side's `squad`
   (`MatchBuilder.bind_squad`, interface 21); the AI finds and categorizes
   the characters it perceives by sight. Von walks a data-driven DECISION TREE ranked against the
   goal — a broad mode (combat / reload_quiet / investigate / search / idle), then a tactic (engage / flank / advance /
   retreat / reload / locate …), then a concrete option (a place, a firing spot, an object) — one `choice`
   request per level, ending in a behaviour primitive (move / engage / melee / interact / hold / reload / entry / throw / defend / ambush / follow) — no
   per-goal or per-NPC-type code. `goal_controller.gd` is only the thin orchestrator; the work is split
   across four isolated AI sub-domains (perception / decision / behaviour / debug). See the `domain-ai`
   overview and its `domain-ai-<name>` sub-skills.
