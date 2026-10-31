extends Node
## Talks to VESPER's brain (brain/service.py) over HTTP. One turn at a time, 1–4 seconds each. While a
## turn runs, one event waits, chosen by priority so a death isn't lost behind a cube pickup, and the
## state is read when it's sent. Her line about an event is dropped if it comes back more than STALE
## seconds late and something newer has happened: she talks about the newer thing instead. Her move
## still applies. A new epoch (the chamber restarting) discards everything from before it.
## Without the brain she falls back to written barks.

signal replied(reply: Dictionary)
signal unreachable(event: String)

const URL := "http://127.0.0.1:8090"
const STALE := 5.0
const PENDING_EXPIRES := 8.0  # a waiting event older than this is dropped, unless it matters
const PRIORITIES := {"entered": 3, "exit opened": 3, "core": 3, "acid pit and was respawned": 2, "shot": 2}

var state_provider: Callable
var busy := false
var pending := {}
var epoch := 0
var last_event_at := 0.0


func send(event: String, glitch := false) -> void:
	var item := {"text": event, "at": now(), "priority": priority(event), "epoch": epoch, "glitch": glitch}
	last_event_at = item["at"]
	if busy:
		if pending.is_empty() or item["priority"] >= pending["priority"]:
			pending = item
		return
	_run(item)


func new_epoch() -> void:
	epoch += 1
	pending = {}


func _run(item: Dictionary) -> void:
	busy = true
	var reply := await post("/turn", {"event": item["text"], "state": state_provider.call(), "glitch": item["glitch"]})
	busy = false
	if item["epoch"] == epoch:
		if reply.is_empty():
			unreachable.emit(item["text"])
		else:
			var late: float = now() - item["at"]
			reply["late"] = late
			reply["glitch"] = item["glitch"]
			# The big moments (entering, solving, her core) are worth hearing a little late.
			reply["stale"] = late > STALE and last_event_at > item["at"] and item["priority"] < 3
			replied.emit(reply)
	if not pending.is_empty():
		var next := pending
		pending = {}
		if next["epoch"] == epoch and (now() - next["at"] < PENDING_EXPIRES or next["priority"] >= 2):
			_run(next)


func priority(event: String) -> int:
	for key in PRIORITIES:
		if key in event:
			return PRIORITIES[key]
	return 1


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func health() -> Dictionary:
	return await _request("/health", HTTPClient.METHOD_GET, "", 3.0)


func post(path: String, data: Dictionary, timeout := 60.0) -> Dictionary:
	return await _request(path, HTTPClient.METHOD_POST, JSON.stringify(data), timeout)


func _request(path: String, method: int, body: String, timeout: float) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = timeout
	add_child(request)
	var error := request.request(URL + path, ["Content-Type: application/json"], method, body)
	if error != OK:
		request.queue_free()
		return {}
	var result: Array = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return {}
	var parsed = JSON.parse_string(result[3].get_string_from_utf8())
	return parsed if parsed is Dictionary else {}
