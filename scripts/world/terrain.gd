extends Node2D
## Pixel-based destructible terrain. The byte mask is the single source of truth for collisions;
## the image is only what gets drawn.

var width := 1600
var height := 900

# [crust, mantle, core] colours for each planet type.
const PALETTES := [
	[Color(0.75, 0.78, 0.82), Color(0.42, 0.44, 0.5), Color(0.2, 0.2, 0.26)],  # grey moon
	[Color(0.95, 0.55, 0.35), Color(0.62, 0.28, 0.2), Color(0.3, 0.1, 0.1)],  # rust world
	[Color(0.7, 0.92, 1.0), Color(0.3, 0.55, 0.75), Color(0.12, 0.2, 0.4)],  # ice world
	[Color(0.75, 0.6, 1.0), Color(0.42, 0.28, 0.65), Color(0.18, 0.1, 0.32)],  # crystal world
	[Color(0.6, 0.9, 0.5), Color(0.3, 0.5, 0.3), Color(0.12, 0.22, 0.14)],  # moss world
]

var image: Image
var texture: ImageTexture
var mask := PackedByteArray()
var _dirty := false


## Round planetoids, one per physics planet (the "orbit" stage).
func generate(physics, rng: RandomNumberGenerator) -> void:
	_clear()
	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = rng.randi()
	shape_noise.frequency = 0.9
	var speck := _speck_noise(rng)
	var first_palette := rng.randi() % PALETTES.size()
	for i in physics.planets.size():
		var palette: Array = PALETTES[(first_palette + i) % PALETTES.size()]
		_paint_planet(physics.planets[i], shape_noise, speck, palette, float(i) * 17.0)
	_finish()


## Floating rock islands with gaps between them. `cfg` is a stage entry from GameSettings.
## Returns [{"x0": float, "x1": float}, ...] from left to right, for spawning units.
func generate_islands(rng: RandomNumberGenerator, cfg: Dictionary) -> Array:
	var island_width: Vector2 = cfg.island_width
	var gap: Vector2 = cfg.gap
	var depth: Vector2 = cfg.depth
	_clear()
	var surface := FastNoiseLite.new()
	surface.seed = rng.randi()
	surface.frequency = 0.006
	var jag := FastNoiseLite.new()
	jag.seed = rng.randi()
	jag.frequency = 0.04
	var speck := _speck_noise(rng)
	var islands := []
	var palette_index := rng.randi() % PALETTES.size()
	var x := rng.randf_range(40.0, 90.0)
	while x < width - island_width.x * 0.6:
		var w := minf(rng.randf_range(island_width.x, island_width.y), width - 40.0 - x)
		var island := {
			"x0": x, "x1": x + w,
			"base": rng.randf_range(0.36, 0.5) * height,
			"depth": rng.randf_range(depth.x, depth.y),
		}
		if cfg.has("terrace"):
			_add_terraces(island, rng, cfg)
		_paint_island(island, surface, jag, speck, PALETTES[palette_index % PALETTES.size()])
		islands.append(island)
		x += w + rng.randf_range(gap.x, gap.y)
	# Small rocks hanging over the gaps. Spawns scan down from just above each island's top,
	# so rocks above islands sit higher than that (see Match._island_spots).
	var sky_rocks: int = cfg.get("sky_rocks", 0)
	for island in islands:
		for k in sky_rocks:
			var rx := lerpf(island.x0, island.x1, (k + rng.randf_range(0.2, 0.8)) / sky_rocks)
			var c := Vector2(rx, rng.randf_range(0.1, 0.24) * height)
			_paint_rock(c, rng.randf_range(18.0, 30.0), speck, PALETTES[(palette_index + 2) % PALETTES.size()])
	for i in range(islands.size() - 1):
		if sky_rocks == 0 and rng.randf() < 0.3:
			continue
		var gap_x: float = (islands[i].x1 + islands[i + 1].x0) / 2.0
		var c := Vector2(gap_x, rng.randf_range(0.18, 0.3) * height)
		var r := rng.randf_range(22.0, 34.0)
		_paint_rock(c, r, speck, PALETTES[(palette_index + 2) % PALETTES.size()])
	_finish()
	return islands


func set_size(size: Vector2) -> void:
	width = int(size.x)
	height = int(size.y)


func _clear() -> void:
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	mask.resize(width * height)
	mask.fill(0)


func _finish() -> void:
	texture = ImageTexture.create_from_image(image)
	queue_redraw()


func _speck_noise(rng: RandomNumberGenerator) -> FastNoiseLite:
	var speck := FastNoiseLite.new()
	speck.seed = rng.randi()
	speck.frequency = 0.06
	return speck


## Splits an island's top into flat steps at different heights with sheer cliffs between them.
## island.steps = [[x0, x1, lift], ...]; island.edges = cliff tops [Vector2(x, side)] where side
## points from the cliff toward the higher step (spawns use these to start units on the brink).
func _add_terraces(island: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var widths: Vector2 = cfg.terrace
	var max_lift: float = cfg.terrace_lift
	var steps := []
	var edges := []
	var x: float = island.x0
	var lift := rng.randf_range(0.0, max_lift)
	while x < island.x1:
		var w := rng.randf_range(widths.x, widths.y)
		if island.x1 - (x + w) < widths.x:
			w = island.x1 - x
		steps.append([x, x + w, lift])
		x += w
		var next := rng.randf_range(0.0, max_lift)
		if absf(next - lift) < 90.0:  # always a real cliff, never a gentle step
			next = lift + 120.0 if lift + 120.0 <= max_lift else lift - 120.0
		if x < island.x1:
			edges.append(Vector2(x, -1 if lift > next else 1))
		lift = next
	island.steps = steps
	island.edges = edges
	island.max_lift = max_lift


func _step_lift(island: Dictionary, x: float) -> float:
	for s in island.steps:
		if x >= s[0] and x < s[1]:
			return s[2]
	return island.steps[-1][2]


func _paint_island(island: Dictionary, surface: FastNoiseLite, jag: FastNoiseLite, speck: FastNoiseLite, palette: Array) -> void:
	var x0: float = island.x0
	var x1: float = island.x1
	var half := (x1 - x0) / 2.0
	var cx := x0 + half
	var terraced := island.has("steps")
	for x in range(int(x0), int(x1) + 1):
		var t := (x - cx) / half
		var edge := clampf(1.0 - t * t, 0.0, 1.0)
		# Flat-ish top that droops at the ends, tapering rocky underside.
		var top: float = island.base + 70.0 * surface.get_noise_1d(x) + 50.0 * (1.0 - sqrt(edge))
		var bottom: float = top + 20.0 + island.depth * sqrt(edge) + 18.0 * jag.get_noise_1d(x)
		if terraced:
			# Flat steps with only a little roughness, so cliffs stay sheer; the underside follows the base.
			top = island.base - _step_lift(island, x) + 8.0 * surface.get_noise_1d(x * 4.0) + 30.0 * (1.0 - sqrt(edge))
			bottom = island.base + 20.0 + island.depth * sqrt(edge) + 18.0 * jag.get_noise_1d(x)
		for y in range(maxi(0, int(top)), mini(height - 1, int(bottom)) + 1):
			_paint_pixel(x, y, float(y) - top, bottom - top, speck, palette)


func _paint_rock(center: Vector2, radius: float, speck: FastNoiseLite, palette: Array) -> void:
	for y in range(int(center.y - radius), int(center.y + radius) + 1):
		for x in range(int(center.x - radius * 1.3), int(center.x + radius * 1.3) + 1):
			var d := Vector2((x - center.x) / 1.3, y - center.y).length()
			var edge := radius * (1.0 + 0.15 * speck.get_noise_2d(x * 3.0, y * 3.0))
			if d <= edge:
				_paint_pixel(x, y, edge - d, edge, speck, palette)


func _paint_pixel(x: int, y: int, depth: float, thickness: float, speck: FastNoiseLite, palette: Array) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	var n := speck.get_noise_2d(x, y)
	var c: Color
	if depth < 5.0:
		c = palette[0]
	else:
		c = (palette[1] as Color).lerp(palette[2], clampf(depth / maxf(thickness, 1.0), 0.0, 1.0))
		if n > 0.35:
			c = c.darkened(0.25)
	c = c.lightened(n * 0.08)
	image.set_pixel(x, y, c)
	mask[y * width + x] = 1


func _paint_planet(p: Dictionary, shape_noise: FastNoiseLite, speck: FastNoiseLite, palette: Array, offset: float) -> void:
	var center: Vector2 = p.center
	var radius: float = p.radius
	var reach := radius * 1.2
	var x0 := maxi(0, int(center.x - reach))
	var x1 := mini(width - 1, int(center.x + reach))
	var y0 := maxi(0, int(center.y - reach))
	var y1 := mini(height - 1, int(center.y + reach))
	var crust: Color = palette[0]
	var mantle: Color = palette[1]
	var core: Color = palette[2]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x, y) - center
			var dist := d.length()
			if dist > reach:
				continue
			var dir := d / maxf(dist, 0.001)
			var edge := radius * (1.0 + minf(0.12, 40.0 / radius) * shape_noise.get_noise_2d(dir.x * 1.6 + offset, dir.y * 1.6))
			if dist > edge:
				continue
			var depth := edge - dist
			var n := speck.get_noise_2d(x, y)
			var c: Color
			if depth < 5.0:
				c = crust
			else:
				c = mantle.lerp(core, clampf(1.0 - dist / edge, 0.0, 1.0) * 1.2)
				# Old impact craters for a bit of texture.
				if n > 0.35:
					c = c.darkened(0.25)
			c = c.lightened(n * 0.08)
			image.set_pixel(x, y, c)
			mask[y * width + x] = 1


func is_solid(pos: Vector2) -> bool:
	var x := int(floor(pos.x))
	var y := int(floor(pos.y))
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	return mask[y * width + x] != 0


func carve(center: Vector2, radius: float) -> void:
	var rim := radius + 4.0
	var r_sq := radius * radius
	var rim_sq := rim * rim
	var x0 := maxi(0, int(center.x - rim))
	var x1 := mini(width - 1, int(center.x + rim))
	var y0 := maxi(0, int(center.y - rim))
	var y1 := mini(height - 1, int(center.y + rim))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var idx := y * width + x
			if mask[idx] == 0:
				continue
			var d_sq := center.distance_squared_to(Vector2(x, y))
			if d_sq <= r_sq:
				mask[idx] = 0
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d_sq <= rim_sq:
				image.set_pixel(x, y, image.get_pixel(x, y).darkened(0.3))
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		texture.update(image)
		queue_redraw()


func _draw() -> void:
	if texture:
		draw_texture(texture, Vector2.ZERO)
