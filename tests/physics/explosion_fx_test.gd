extends GameTest
## The look of a burst (Physics): `Physics.spawn_explosion(world, at, kind)` tells the 3D render a
## bright flash, a fireball puff and drifting smoke for a frag (a scorch mark stays under it), and
## only thin smoke for a stun: its white flash is the lighting's flash light (S8, ticket #56;
## `lighting/stun_flash_light`), no drawn disc; with `PhysicsExplosionConfig.fx_enabled` off it
## makes none of it. Read through the blasts the hook was told (`tests/_physics/fx_tap.gd`) and the
## world's scorch layer.

const FxTap := preload("res://tests/_physics/fx_tap.gd")
const AT := Vector2(300, 250)


func describe() -> Dictionary:
	return {
		"name": "An explosion makes its effects, and none with the switch off",
		"description": "spawn_explosion for a frag tells the render a flash, a fireball and smoke "
			+ "plus a scorch mark; for a stun thin smoke only (its flash is a light); with "
			+ "PhysicsExplosionConfig.fx_enabled off, nothing.",
		"tags": ["grenade", "explosion", "fx", "physics"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(PhysicsExplosionConfig, &"fx_enabled", true)


func run(t: TestContext) -> void:
	var tap := FxTap.new().attach()
	var scorch := ScorchDecals.layer(t.world)
	Physics.spawn_explosion(t.world, AT, &"frag")
	await t.frames(2)
	if not t.require(tap.blasts.size() == 1, "a frag makes one blast (%d)" % tap.blasts.size()):
		tap.detach()
		return
	var frag: Dictionary = tap.blasts[0]
	t.expect_eq(frag["at"], AT, "it bursts where the grenade went off")
	t.check(float(frag["look"]["flash_radius"]) > 0.0, "a frag makes a bright flash")
	t.check(float(frag["look"]["fireball_radius"]) > 0.0, "and a fireball puff")
	t.check(int(frag["look"]["smoke_puffs"]) > 0, "and smoke")
	t.expect_eq(scorch.count(), 1, "and leaves a scorch mark under it")

	await t.seconds(2.0)
	t.expect_eq(scorch.count(), 1, "the scorch stays after the burst")

	Physics.spawn_explosion(t.world, AT + Vector2(200, 0), &"stun")
	await t.frames(2)
	t.expect_eq(tap.blasts.size(), 2, "a stun makes a blast too")
	var stun: Dictionary = tap.blasts[1]
	t.check(
		float(stun["look"]["flash_radius"]) == 0.0,
		"a stun draws no white flash disc: the lighting shows its flash (S8)",
	)
	t.check(int(stun["look"]["smoke_puffs"]) > 0, "it makes thin smoke")
	t.check(float(stun["look"]["fireball_radius"]) == 0.0, "but no fireball")
	t.expect_eq(scorch.count(), 1, "and no scorch")

	PhysicsExplosionConfig.fx_enabled = false
	Physics.spawn_explosion(t.world, AT + Vector2(-200, 0), &"frag")
	Physics.spawn_explosion(t.world, AT + Vector2(0, 100), &"stun")
	await t.frames(2)
	tap.detach()
	t.expect_eq(tap.blasts.size(), 2, "with the master switch off no blast is made")
	t.expect_eq(scorch.count(), 1, "and no scorch is left")
