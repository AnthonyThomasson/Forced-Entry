extends GameTest
## Harness self-test: the text a run writes into report.json and a failure bundle is valid JSON
## whatever a check message holds. A Von option id carries the key separator (a control character),
## and Godot's own `JSON.stringify` writes such a character raw, which every other JSON reader
## rejects.

const Bundle = preload("res://scenes/testing/test_bundle.gd")


func describe() -> Dictionary:
	return {
		"name": "Report JSON holds control characters",
		"tags": ["harness", "report"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var message := "ask a\u0001b\u001fc failed\tat \"x\"\nline two"
	var data := { "checks": [{ "ok": false, "message": message }], "n": 1 }
	for indent in ["", "  "]:
		var text := Bundle.json_text(data, indent)
		for code in range(1, 32):
			if code == 9 or code == 10 or code == 13:
				continue  # the indent's layout
			t.check(
				not text.contains(char(code)),
				"no raw control character %d in the text (indent '%s')" % [code, indent],
			)
		t.check(text.contains("\\u0001") and text.contains("\\u001f"), "they are escaped")
		var back: Variant = JSON.parse_string(text)
		t.require(back is Dictionary, "the text parses")
		t.expect_eq(back["checks"][0]["message"], message, "and reads back as it was")
