extends GameTest
## The sun and the camera of the 3D render are tuned together (#193 phase 3): a flat top face lies
## at N.L = sin(sun elevation), which must sit in the top of the toon material's bands
## (`PixelPostConfig. bands` of them: band k of n is k/n to (k+1)/n), so the sun lights a street top
## whole and only a shadow or a face turned from it steps down; and the sun is high enough that a
## wall's shadow is as short as the 2D drop shadow's reach (a few tens of px, not a streak). And the
## camera is the near top-down view: 78 to 82 degrees.


func describe() -> Dictionary:
	return {
		"name": "The 3D camera is near top-down and the sun lights a flat top in the top band",
		"description": "RenderConfig.pitch_degrees is 78 to 82 and starts at north; the sun's "
			+ "elevation puts N.L of an up-facing face in the top band of the toon material, and "
			+ "a wall's shadow is short.",
		"tags": ["render", "3d", "camera", "light"],
		"timeout": 4.0,
	}


func run(t: TestContext) -> void:
	t.check(
		RenderConfig.pitch_degrees >= 78.0 and RenderConfig.pitch_degrees <= 82.0,
		"the camera is near top-down (%s degrees)" % RenderConfig.pitch_degrees,
	)
	t.expect_eq(RenderConfig.yaw_degrees, 0.0, "the camera starts at north, as the 2D view faces")
	t.expect_eq(
		RenderConfig.art_pixel, ArtCanvasConfig.pixel_size, "an art pixel is the painters' pixel"
	)
	var bands := PixelPostConfig.bands
	t.expect_eq(bands, 3, "premise: three tone bands")
	var elevation := Lighting3DConfig.sun_elevation
	var up_lit := sin(deg_to_rad(elevation))
	t.check(
		up_lit >= float(bands - 1) / float(bands) + 0.05,
		"N.L of a flat top is %.3f, inside the top band (from %.3f) with a margin"
		% [up_lit, float(bands - 1) / float(bands)],
	)
	var wall := ObjectStructureMeshConfig.wall_height
	var shadow := wall / tan(deg_to_rad(elevation))
	t.check(
		shadow <= 30.0,
		"a wall of %.0f throws a %.0f px shadow, short like the 2D drop shadow's reach" % [
			wall,
			shadow,
		],
	)
