extends Camera2D
## Follows whatever the match points it at. Mouse wheel zooms, right-drag pans.

var target := Vector2.ZERO
var world := Rect2(0, 0, 1600, 900)
var shake := 0.0
var _pan := Vector2.ZERO
var _dragging := false
var _min_zoom := 0.5
var _bias := Vector2.ZERO


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = (zoom * 1.1).clamp(Vector2.ONE * _min_zoom, Vector2.ONE * 1.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = (zoom / 1.1).clamp(Vector2.ONE * _min_zoom, Vector2.ONE * 1.4)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan -= event.relative / zoom
