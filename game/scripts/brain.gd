extends Node
## Talks to VESPER's brain (brain/service.py) over HTTP. One turn at a time: while a turn runs, only the
## newest event waits, and the state is read when it is sent, never stale. Without the brain she falls
## back to written barks.

signal replied(reply: Dictionary)
signal unreachable(event: String)

const URL := "http://127.0.0.1:8090"

var state_provider: Callable
var busy := false
var pending := ""


func send(event: String) -> void:
	if busy:
		pending = event
		return
	busy = true
	var reply := await post("/turn", {"event": event, "state": state_provider.call()})
	busy = false
	if reply.is_empty():
		unreachable.emit(event)
	else:
		replied.emit(reply)
	if pending != "":
		var next := pending
		pending = ""
		send(next)


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
