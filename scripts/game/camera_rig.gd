extends Camera2D
## Follows whatever the match points it at. Mouse wheel zooms, right-drag pans.
## On touch screens one finger on empty space pans and two fingers pinch to zoom.

var target := Vector2.ZERO
var world := Rect2(0, 0, 1600, 900)
var shake := 0.0
var _pan := Vector2.ZERO
var _dragging := false
var _min_zoom := 0.5
var _bias := Vector2.ZERO
var _touches := {}  # finger index -> screen position, only fingers that started on empty space
var _pinch_dist := 0.0


## `bias` shifts the view from the followed point, e.g. down so the deadly abyss stays in sight.
func setup(world_rect: Rect2, bias := Vector2.ZERO) -> void:
	world = world_rect
	_bias = bias
	var view := get_viewport_rect().size
	_min_zoom = minf(1.0, minf(view.x / world.size.x, view.y / world.size.y))
	# Show the whole map when it nearly fits; otherwise start close and follow.
	zoom = Vector2.ONE * (_min_zoom if _min_zoom > 0.65 else 0.8)
	target = world.get_center()
	position = target


func follow(pos: Vector2, reset_pan := false) -> void:
	target = pos
	if reset_pan:
		_pan = Vector2.ZERO


func _process(delta: float) -> void:
	var view := get_viewport_rect().size / zoom
	var goal := target + _bias + _pan
	# Keep the view inside the world (with some sky above it), or centred if it is wider than the world.
	var lo := world.position + view / 2.0 - Vector2(0, 400)
	var hi := world.end - view / 2.0 + Vector2(0, 40)
	goal.x = world.get_center().x if lo.x > hi.x else clampf(goal.x, lo.x, hi.x)
	goal.y = world.get_center().y if lo.y > hi.y else clampf(goal.y, lo.y, hi.y)
	position = position.lerp(goal, minf(1.0, delta * 4.0))
	shake = maxf(0.0, shake - delta * 30.0)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake


func _zoom_by(factor: float) -> void:
	zoom = (zoom * factor).clamp(Vector2.ONE * _min_zoom, Vector2.ONE * 1.4)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_dist = _finger_distance()
		return
	if event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _finger_distance()
			# Ignore fingers that almost touch: the ratio jumps wildly there.
			if _pinch_dist > 40.0 and d > 40.0:
				_zoom_by(clampf(d / _pinch_dist, 0.8, 1.25))
			_pinch_dist = d
		else:
			_pan -= event.relative / zoom
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / 1.1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan -= event.relative / zoom


func _finger_distance() -> float:
	var points := _touches.values()
	return points[0].distance_to(points[1]) if points.size() >= 2 else 0.0
