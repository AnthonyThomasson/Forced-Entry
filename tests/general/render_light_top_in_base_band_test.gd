extends GameTest
## The sun and the camera of the 3D render are tuned together (#193 phase 2b): a flat top face lies
## at N.L = sin(sun elevation), which must sit in the middle third of the toon material's bands
## (`PixelPostConfig.bands` of them: band k of n is k/n to (k+1)/n, the base tone is band 1 of 3),
## so every top shows its painted colour as it is and only a slope or a shadow steps to another
## tone. And the camera is the near top-down view: 78 to 82 degrees.


func describe() -> Dictionary:
	return {
		"name": "The 3D camera is near top-down and flat tops sit in the base tone band",
		"description": "RenderConfig.pitch_degrees is 78 to 82 and starts at north; the sun's "
			+ "elevation puts N.L of an up-facing face in the base band of the toon material.",
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
	var up_lit := sin(deg_to_rad(-RenderLightConfig.sun_rotation.x))
	t.check(
		up_lit >= 1.0 / float(bands) and up_lit < 2.0 / float(bands),
		"N.L of a flat top is %.3f, inside the base band [%.3f, %.3f)"
		% [up_lit, 1.0 / float(bands), 2.0 / float(bands)],
	)
	t.check(
		up_lit > 1.0 / float(bands) + 0.1 and up_lit < 2.0 / float(bands) - 0.05,
		"and a safe margin from both edges (a slight tilt keeps the band)",
	)
