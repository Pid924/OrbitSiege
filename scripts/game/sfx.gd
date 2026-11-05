extends Node
## Sound effects, synthesized in code at startup (no audio files to ship or license).
## play("boom", 1.3) picks the sound and a pitch/size; a small pool lets sounds overlap.

const RATE := 22050
const SAVE_PATH := "user://settings.cfg"

static var _streams := {}
static var enabled := true
static var _loaded := false

var _players: Array = []
var _next := 0


static func load_setting() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		enabled = bool(cfg.get_value("ui", "sound", true))


static func set_enabled(on: bool) -> void:
	enabled = on
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("ui", "sound", on)
	cfg.save(SAVE_PATH)


func _ready() -> void:
	load_setting()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	if _streams.is_empty():
		_build()


## `size` above 1 makes it lower and louder (bigger explosions), below 1 higher and softer.
func play(name: String, size := 1.0) -> void:
	if not enabled or not _streams.has(name):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = clampf(1.0 / sqrt(maxf(size, 0.2)), 0.5, 2.0) * randf_range(0.95, 1.05)
	p.volume_db = clampf(linear_to_db(clampf(size, 0.4, 1.6)), -8.0, 4.0) - 4.0
	p.play()


func _build() -> void:
	_streams["fire"] = _make(0.22, func(t, n): return _sweep(t, 0.22, 700.0, 160.0) * 0.6 * _env(t, 0.005, 0.22) + n * 0.25 * _env(t, 0.0, 0.06))
	_streams["boom"] = _make(0.9, func(t, n): return _rumble(t, n) * _env(t, 0.004, 0.9))
	_streams["hit"] = _make(0.16, func(t, n): return (sin(TAU * 110.0 * t) * 0.7 + n * 0.4) * _env(t, 0.002, 0.16))
	_streams["pickup"] = _make(0.32, func(t, n): return sin(TAU * (660.0 if t < 0.12 else 990.0) * t) * 0.45 * _env(t, 0.005, 0.32))
	_streams["turn"] = _make(0.12, func(t, n): return sin(TAU * 520.0 * t) * 0.3 * _env(t, 0.004, 0.12))
	_streams["fall"] = _make(0.8, func(t, n): return _sweep(t, 0.8, 900.0, 120.0) * 0.4 * _env(t, 0.02, 0.8))
	_streams["heal"] = _make(0.5, func(t, n): return (sin(TAU * 880.0 * t) + sin(TAU * 1320.0 * t) * 0.6) * 0.25 * _env(t, 0.02, 0.5) * (0.6 + 0.4 * sin(TAU * 12.0 * t)))
	_streams["zap"] = _make(0.35, func(t, n): return (signf(sin(TAU * 240.0 * t)) * 0.25 + n * 0.25) * _env(t, 0.005, 0.35))
	_streams["beam"] = _make(0.9, func(t, n): return (_sweep(t, 0.9, 1400.0, 300.0) * 0.35 + n * 0.3) * _env(t, 0.05, 0.9))
	_streams["win"] = _make(0.9, func(t, n): return sin(TAU * [523.0, 659.0, 784.0, 1047.0][mini(int(t / 0.18), 3)] * t) * 0.35 * _env(t, 0.01, 0.9))
	_streams["lose"] = _make(0.9, func(t, n): return sin(TAU * [392.0, 330.0, 262.0, 196.0][mini(int(t / 0.2), 3)] * t) * 0.35 * _env(t, 0.01, 0.9))
	_streams["click"] = _make(0.05, func(t, n): return sin(TAU * 1200.0 * t) * 0.25 * _env(t, 0.001, 0.05))


## Renders `fn(time, white_noise)` into a 16-bit mono stream.
func _make(seconds: float, fn: Callable) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in count:
		var v: float = fn.call(float(i) / RATE, rng.randf_range(-1.0, 1.0))
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


## Attack, then exponential-ish decay to silence at `length`.
func _env(t: float, attack: float, length: float) -> float:
	if t < attack:
		return t / attack
	var x := clampf((t - attack) / maxf(length - attack, 0.001), 0.0, 1.0)
	return pow(1.0 - x, 2.0)


func _sweep(t: float, length: float, f0: float, f1: float) -> float:
	# Phase of a linear frequency glide from f0 to f1.
	var k := (f1 - f0) / length
	return sin(TAU * (f0 * t + 0.5 * k * t * t))


var _low := 0.0
func _rumble(t: float, n: float) -> float:
	# Low-passed noise plus a dropping thump: an explosion.
	_low = lerpf(_low, n, 0.08)
	return clampf(_low * 3.0 + sin(TAU * (60.0 - 30.0 * t) * t) * 0.5, -1.0, 1.0)
