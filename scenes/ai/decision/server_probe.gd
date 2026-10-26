extends RefCounted
## AI DECISION sub-domain: the decision server launcher's readiness probe, a data leaf it builds
## once and holds as `_probe`: the HTTP request it asks the server to decide with, how many reuse
## probes are left, and, once it has launched its own server, that it is polling it and until when.

## Reused across probe attempts; freed (and null) once the server answers or the launcher gives up.
var request: HTTPRequest
## Reuse-probe attempts remaining before the launcher launches its own server.
var attempts_left := 0
## True once the launcher launched and is polling for the server's first answer.
var waiting_ready := false
## When to stop polling a launched server (see the launcher's `ready_timeout`).
var ready_deadline_ms := 0
