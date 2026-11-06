extends Node
## Online play between two browsers (phones). The page's osnet.js (PeerJS / WebRTC) carries the
## data; this node polls it. Loaded as the autoload `OrbitNet`, so it outlives scene changes.
##
## Matches run in lockstep: both sides send their commands for every simulation tick, and a
## tick is simulated only once both sides' commands for it are known. Same seed + same inputs
## = the same game on both phones, so only inputs ever cross the network.

signal changed  # state or error text changed (menus redraw)

enum State { OFF, WAITING, CONNECTING, CONNECTED, CLOSED, FAILED }
const DELAY := 8  # input delay in ticks (~0.13 s) that hides network latency
const MAIN_SCENE := "res://scenes/main.tscn"

var state := State.OFF
var is_host := false
var room_code := ""
var error := ""  # Thai text key (menus translate it)
var error_detail := ""
var active := false  # an online match is being played
var match_seed := 0
var local_team := 0
var _inputs := {}  # tick -> [host commands or null, guest commands or null]
var _sums := {}  # tick -> [host checksum, guest checksum]
var desync := false
var _connect_time := 0.0
const CONNECT_TIMEOUT := 20.0


func available() -> bool:
	return OS.has_feature("web") and str(JavaScriptBridge.eval("typeof window.osNet", true)) == "object"


func connected() -> bool:
	return state == State.CONNECTED


func host_room() -> void:
	is_host = true
	local_team = 0
	room_code = str(randi_range(1000, 9999))
	error = ""
	state = State.WAITING
	JavaScriptBridge.eval("osNet.host('%s')" % room_code, true)
	changed.emit()


func join_room(code: String) -> void:
	is_host = false
	local_team = 1
	room_code = code
	error = ""
	state = State.CONNECTING
	_connect_time = 0.0
	JavaScriptBridge.eval("osNet.join('%s')" % code.validate_filename(), true)
	changed.emit()


func close() -> void:
	if state == State.OFF:
		return
	if state == State.CONNECTED:
		send({"k": "bye"})
	if available():
		JavaScriptBridge.eval("osNet.close()", true)
	state = State.OFF
	active = false
	changed.emit()


func send(data: Dictionary) -> void:
	if state == State.CONNECTED:
		JavaScriptBridge.eval("osNet.send(%s)" % JSON.stringify(JSON.stringify(data, "", false, true)), true)


## Host only: pick the map and seed, tell the guest, and both open the match.
func start_match(stage_id: String) -> void:
	var data := {"k": "start", "stage": stage_id, "seed": randi()}
	send(data)
	_begin(data)


func _begin(data: Dictionary) -> void:
	const GameSettings := preload("res://scripts/game/game_settings.gd")
	GameSettings.stage = str(data.stage)
	GameSettings.debug = false  # never in an online match
	match_seed = int(data.seed)
	_inputs.clear()
	_sums.clear()
	desync = false
	active = true
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_SCENE)


# --- Lockstep -------------------------------------------------------------

## Our commands for `tick`. Returns them as the remote side will read them (JSON round
## trip), so both phones apply bit-identical values.
func send_tick(tick: int, commands: Array) -> void:
	var data := {"k": "in", "t": tick, "c": commands}
	send(data)
	_store(tick, local_team, JSON.parse_string(JSON.stringify(data, "", false, true)).c)


func has_tick(tick: int) -> bool:
	return _inputs.has(tick) and _inputs[tick][0] != null and _inputs[tick][1] != null


## Host commands first, then guest commands. Each side may only steer its own team.
func take_tick(tick: int) -> Array:
	var out := []
	for team in 2:
		for cmd in _inputs[tick][team]:
			if cmd is Dictionary:
				cmd.team = team
				for key in ["dir", "index"]:
					if cmd.has(key):
						cmd[key] = int(cmd[key])
				out.append(cmd)
	_inputs.erase(tick)
	return out


func send_sum(tick: int, value: int) -> void:
	send({"k": "sum", "t": tick, "v": value})
	_store_sum(tick, local_team, value)


func _store(tick: int, team: int, commands) -> void:
	if not _inputs.has(tick):
		_inputs[tick] = [null, null]
	_inputs[tick][team] = commands if commands is Array else []


func _store_sum(tick: int, team: int, value: int) -> void:
	if not _sums.has(tick):
		_sums[tick] = [null, null]
	_sums[tick][team] = value
	if _sums[tick][0] != null and _sums[tick][1] != null:
		if _sums[tick][0] != _sums[tick][1]:
			desync = true
			push_warning("online desync at tick %d" % tick)
		_sums.erase(tick)


# --- Polling the page -----------------------------------------------------

func _process(delta: float) -> void:
	if state == State.OFF or state == State.CLOSED or state == State.FAILED or not available():
		return
	if state == State.CONNECTING:
		_connect_time += delta
		if _connect_time > CONNECT_TIMEOUT:
			_fail("เชื่อมต่อไม่ได้", "timeout")
			return
	var events = JSON.parse_string(str(JavaScriptBridge.eval("osNet.poll()", true)))
	if not events is Array:
		return
	for e in events:
		match str(e.get("t", "")):
			"conn":
				state = State.CONNECTED
				changed.emit()
			"msg":
				var data = JSON.parse_string(str(e.get("d", "")))
				if data is Dictionary:
					_on_message(data)
			"close":
				_lost("")
			"err":
				var kind := str(e.get("e", ""))
				if kind == "unavailable-id" and is_host and state == State.WAITING:
					host_room()  # that code is taken; pick another
				elif kind == "peer-unavailable":
					_fail("ไม่พบห้องนี้ ตรวจรหัสอีกครั้ง")
				elif state != State.CONNECTED:
					_fail("เชื่อมต่อไม่ได้", kind)


func _on_message(data: Dictionary) -> void:
	var remote := 1 - local_team
	match str(data.get("k", "")):
		"start":
			if not is_host:
				_begin(data)
		"in":
			_store(int(data.t), remote, data.get("c"))
		"sum":
			_store_sum(int(data.t), remote, int(data.v))
		"bye":
			_lost("")


## Give up on the other phone (it stopped sending).
func drop() -> void:
	if state == State.CONNECTED:
		send({"k": "bye"})
	_lost("")


func _fail(text: String, detail := "") -> void:
	error = text
	error_detail = detail
	state = State.FAILED
	if available():
		JavaScriptBridge.eval("osNet.close()", true)
	changed.emit()


func _lost(_why: String) -> void:
	if state == State.CONNECTED or state == State.CONNECTING:
		state = State.CLOSED
		if available():
			JavaScriptBridge.eval("osNet.close()", true)
		changed.emit()
