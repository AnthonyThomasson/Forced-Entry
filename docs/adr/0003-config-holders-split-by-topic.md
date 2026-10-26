# Config holders are split by topic, each 15 vars or fewer

Tuning lives in `class_name` holders of `static var`s, read as `<Holder>.<name>`, with no instance and no autoload. Ten
of them had grown past gdstyle's `quality/max-class-variables` (15): `CharacterConfig` 163 vars, `ObjectArtConfig` 135,
`BloodConfig` 90, `VehicleConfig` 52, `PhysicsConfig` 51, `SoundConfig` 33, `WorldGenConfig` 25, `LightingConfig` 21,
`ArtConfig` 18, `BallisticsConfig` 16. Issue #76 turns that rule on, at its default, with no exclusion.

Each is split into topic holders, one `class_name` per topic, each 15 vars or fewer, as `BloodConfig` was once split out
of `PhysicsConfig`. A topic is what a reader looks up together: one painter, one component, one effect. A holder is
named `<family stem><Topic>Config` (`CharacterStunConfig`, `ObjectArtFloorConfig`, `PhysicsRagdollConfig`), so a family
is one grep. A family's old name stays only where it holds the family's master switch or its per-kind rows (`BloodConfig`,
`PhysicsConfig`, `SoundConfig`, `LightingConfig`, `VehicleConfig`), and keeps only those values and what every file of
the family shares. The other five go. A var keeps its name, except that a prefix the holder's name already says is
dropped (`CharacterConfig`'s `stun_speed` → `CharacterStunConfig.speed`), never into the name of a GDScript global. Inside
a holder that serves several painters, a key keeps its painter's name as its prefix even where the holder names that word
too (`ObjectArtTableConfig.table_plank_px` beside `chair_slats`): that prefix names the painter, not the holder, so it
stays; a prefix that names only the holder is dropped. A holder sits beside the one it came from, or in the sub-domain
folder whose files alone read it. Nested tables (styles, stances, light specs, kinds) move whole, inside their var. Ten
holders became seventy; with the five that were not over, the game had seventy-five at this split.

## Consequences

Every reader, every test's `set_static` and every behaviour-switch row names the topic holder. A test that names a
static a holder lacks now fails (`TestWorld._set_static` errors instead of setting nothing), so a stale name cannot pass
silently. A new tunable goes in the holder of its topic. When that holder is full, or the tunable fits no topic, it starts a
new topic holder; it never goes into a kept family holder unless it is a family-wide switch or a per-kind row. The architecture skill
lists the holders by domain, and each domain skill says what each of its holders holds. Static reads cost the same:
they compile to a direct access on the holder's class.

## Considered options

- **Static Dictionaries inside the old holders** (`CharacterConfig.stun = { speed = 0.45, … }`): rejected. Every value
  loses its type, a misspelt key reads null at run time instead of failing to parse, and it meets the rule's letter while
  missing its point.
- **Constants:** rejected. Tests and behaviour switches set these at run time (`set_static`, `test_switches.gd`), and a
  `const` cannot be set.
- **An exclusion or a higher threshold for config holders:** rejected by #76 (no `gdstyle:ignore`, no widened
  `exclude`, no project threshold).
- **Every old name goes, master switches included:** rejected. It moves five of the eight switch rows and the master
  switches that interfaces 4, 13 and 20 name, and no reader looks a switch up anywhere else.
- **Holders split by size (`CharacterConfig1`, `CharacterConfig2`):** rejected. A reader cannot tell where a value
  lives.
