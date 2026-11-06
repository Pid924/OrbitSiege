extends Node
## Lets the UI fill any screen shape. The game uses stretch aspect "expand": the screen is at
## least 1600x900 canvas units and wider phones (iPhone ~2.17:1) or taller tablets get more.
## Every UI piece is laid out for 1600x900; this node, added under a CanvasLayer, moves each
## top-level control to the edge or middle it belongs to and keeps clear of the iPhone notch.
##
## Rules for each control under the layer (and inside full-screen containers):
## - full-screen (1600x900) controls grow to the screen and their children are fitted too;
##   with meta "fit_center" their children just move with the screen middle (dense grids).
## - full-width controls (1600 wide) grow in width.
## - meta "fit_mid" keeps a control with the screen middle (rows that belong together).
## - others keep their distance to the nearest third: left, middle or right (same for y).

const BASE := Vector2(1600, 900)

var _pending := false


func _ready() -> void:
	get_viewport().size_changed.connect(refit)
	get_tree().node_added.connect(func(n):
		if n is Control and get_parent().is_ancestor_of(n):
			refit())
	refit()


func refit() -> void:
	if _pending:
		return
	_pending = true
	_apply_deferred.call_deferred()


func _apply_deferred() -> void:
	_pending = false
	if not is_inside_tree():
		return
	var screen := get_viewport().get_visible_rect().size
	_fit(get_parent(), screen, _safe_margins(screen), false)


func _fit(root: Node, screen: Vector2, safe: Vector2, center: bool) -> void:
	var extra := screen - BASE
	for c in root.get_children():
		if not c is Control:
			continue
		if not c.has_meta("fit_base"):
			c.set_meta("fit_base", Rect2(c.position, c.size))
		var base: Rect2 = c.get_meta("fit_base")
		if base.size.x >= BASE.x and base.size.y >= BASE.y:
			c.position = Vector2.ZERO
			c.size = screen
			_fit(c, screen, safe, c.has_meta("fit_center"))
			continue
		var pos := base.position
		if center:
			c.position = pos + extra / 2.0
			continue
		if base.size.x >= BASE.x:
			pos.x = 0.0
			c.size.x = screen.x
		else:
			var cx := pos.x + base.size.x / 2.0
			if c.has_meta("fit_mid"):
				pos.x += extra.x / 2.0
			elif cx < BASE.x / 3.0:
				pos.x += safe.x
			elif cx > BASE.x * 2.0 / 3.0:
				pos.x += extra.x - safe.y
			else:
				pos.x += extra.x / 2.0
		var cy := pos.y + base.size.y / 2.0
		if cy > BASE.y * 2.0 / 3.0:
			pos.y += extra.y
		elif cy > BASE.y / 3.0:
			pos.y += extra.y / 2.0
		c.position = pos


## Notch / rounded-corner insets (left, right) in canvas units; zero outside a browser.
static func _safe_margins(screen: Vector2) -> Vector2:
	if not OS.has_feature("web"):
		return Vector2.ZERO
	var raw = JavaScriptBridge.eval("(function(){var d=document.createElement('div');d.style.cssText='position:fixed;visibility:hidden;padding-left:env(safe-area-inset-left);padding-right:env(safe-area-inset-right)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[parseFloat(s.paddingLeft)||0,parseFloat(s.paddingRight)||0,window.innerWidth||1];d.remove();return r.join(',');})()", true)
	var parts := str(raw).split(",")
	if parts.size() < 3:
		return Vector2.ZERO
	var scale := screen.x / maxf(1.0, parts[2].to_float())
	return Vector2(parts[0].to_float(), parts[1].to_float()) * scale
