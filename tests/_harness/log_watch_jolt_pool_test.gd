extends GameTest
## Harness self-test: the log gate lets Godot's own Jolt job-pool warning pass and nothing else of
## Jolt's. The engine prints "Jolt Physics job system exceeded the maximum number of jobs" and then
## waits for the jobs to free (the engine's code goes on): a known engine bug
## (godotengine/godot#110724), set off by a headless `--fixed-fps` run, which steps physics back to
## back, on a machine whose workers do not get the CPU, and no project setting reaches it (a smaller
## worker pool does not stop it). It failed whichever test was open, so the gate allows exactly it;
## Jolt's other warnings (a full contact cache) are the project's to heed and still fail. Remove the
## allowance (and this test) when the project moves to a Godot that has the fix (upstream plans it
## for 4.8).

const LogWatch := preload("res://scenes/testing/log_watch.gd")
const POOL := (
	"Jolt Physics job system exceeded the maximum number of jobs. This should not happen. Please "
	+ "report this. Waiting for jobs to become available..."
)


func describe() -> Dictionary:
	return {
		"name": "LogWatch allows Godot's Jolt job-pool warning and no other Jolt warning",
		"tags": ["harness", "log"],
		"internal": true,
		"timeout": 4.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var pool := { "severity": "warning", "message": POOL, "location": "CreateJob (a.cpp:125)" }
	t.check(LogWatch.matches_any(pool, []), "the job-pool warning is allowed")
	var cache := {
		"severity": "warning",
		"message": "Jolt Physics manifold cache exceeded capacity and contacts were ignored.",
		"location": "step (b.cpp:1)",
	}
	t.check(not LogWatch.matches_any(cache, []), "another Jolt warning is not")
