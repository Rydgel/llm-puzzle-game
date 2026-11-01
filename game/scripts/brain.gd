extends Node
## Talks to VESPER's brain (brain/service.py) over HTTP. One turn at a time, 1–4 seconds each, streamed: her
## move comes back as soon as she's chosen it, then her line a sentence at a time, each with its voice, so the
## subject hears her first sentence while she writes the next. While a turn runs, one event waits, chosen by
## priority so a death isn't lost behind a cube pickup, and the state is read when it's sent. Her line about an
## event is dropped if it starts more than STALE seconds late and something newer has happened: she talks about
## the newer thing instead. Her move still applies. A new epoch (the chamber restarting) discards everything from
## before it. Without the brain she falls back to written barks.

## Each part of her turn as it arrives: {"move", "hint", "refused"}, then {"text", "audio", "sample_rate"} for each
## sentence ("first" on the first, "glitch" if it's corrupted), then {"line"} once it's all written. A line dropped
## as too late comes as {"stale", "late"} instead of its sentences.
signal replied(part: Dictionary)
signal unreachable(event: String)

const URL := "http://127.0.0.1:8090"
const PORT := 8090
const STALE := 5.0
const TIMEOUT := 60.0
const PENDING_EXPIRES := 8.0  # a waiting event older than this is dropped, unless it matters
const PRIORITIES := {"entered": 3, "exit opened": 3, "core": 3, "acid pit and was respawned": 2, "shot": 2}

var state_provider: Callable
var busy := false
var pending := {}
var epoch := 0
var last_event_at := 0.0


## `said`: what the subject typed to her. It goes to the brain as their words, never as an event of the
## facility's, and it matters: they're waiting for her answer. `scene`: where she is when it isn't the chamber
## (her core); there she only speaks.
func send(event: String, glitch := false, said := "", scene := "") -> void:
	var item := {"text": event, "said": said, "at": now(), "priority": 3 if said != "" else priority(event),
		"epoch": epoch, "glitch": glitch, "scene": scene}
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
	var turn := {"answered": false, "spoken": false, "done": false, "hint": false}
	var body := {"state": state_provider.call(), "glitch": item["glitch"], "stream": true}
	if item["scene"] != "":
		body["scene"] = item["scene"]
		body["speak_only"] = true
	if item["said"] != "":
		body["said"] = item["said"]
	else:
		body["event"] = item["text"]
	await _stream("/turn", body, _part.bind(item, turn))
	busy = false
	if item["epoch"] == epoch:
		if not turn["answered"]:
			unreachable.emit(item["text"])
		elif turn["spoken"] and not turn["done"]:
			replied.emit({"line": ""})  # the line broke off: let it end
	if not pending.is_empty():
		var next := pending
		pending = {}
		if next["epoch"] == epoch and (now() - next["at"] < PENDING_EXPIRES or next["priority"] >= 2):
			_run(next)


## One part of a turn, as it arrives. Returns false to hang up: the brain then stops writing the line.
func _part(part: Dictionary, item: Dictionary, turn: Dictionary) -> bool:
	turn["answered"] = true
	if item["epoch"] != epoch:
		return false
	if part.has("move"):
		turn["hint"] = part.get("hint") != null
	if part.has("text") and not turn["spoken"]:
		var late: float = now() - item["at"]
		# The big moments (entering, solving, her core, the subject talking to her) are worth hearing a little late,
		# and so is a hint.
		if late > STALE and last_event_at > item["at"] and item["priority"] < 3 and not turn["hint"]:
			replied.emit({"stale": true, "late": late})
			return false
		turn["spoken"] = true
		part["first"] = true
	if part.has("line"):
		turn["done"] = true
	part["glitch"] = item["glitch"]
	replied.emit(part)
	return true


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


## A streamed request: the reply is one JSON object per line, and each goes to `on_part` as soon as it arrives.
## `on_part` returns false to hang up.
func _stream(path: String, data: Dictionary, on_part: Callable) -> void:
	var http := HTTPClient.new()
	if http.connect_to_host("127.0.0.1", PORT) != OK:
		return
	while http.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		http.poll()
		await get_tree().process_frame
	if http.get_status() != HTTPClient.STATUS_CONNECTED or \
			http.request(HTTPClient.METHOD_POST, path, ["Content-Type: application/json"], JSON.stringify(data)) != OK:
		http.close()
		return
	var buffer := PackedByteArray()
	var heard_at := now()
	while now() - heard_at < TIMEOUT:
		http.poll()
		var status := http.get_status()
		if status == HTTPClient.STATUS_BODY and http.get_response_code() != 200:
			break
		if status != HTTPClient.STATUS_REQUESTING and status != HTTPClient.STATUS_BODY:
			break  # the reply is over, or the brain went away
		var chunk := http.read_response_body_chunk() if status == HTTPClient.STATUS_BODY else PackedByteArray()
		if chunk.is_empty():
			await get_tree().process_frame
			continue
		heard_at = now()
		buffer.append_array(chunk)
		var newline := buffer.find(10)
		while newline >= 0:
			var part = JSON.parse_string(buffer.slice(0, newline).get_string_from_utf8())
			buffer = buffer.slice(newline + 1)
			if part is Dictionary and not on_part.call(part):
				http.close()
				return
			newline = buffer.find(10)
	http.close()


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
