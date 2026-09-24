class_name RegionPreview
extends Control
## Mini-mapa del menú de nueva partida (Fase 6): terreno, zona inicial, pueblo y yacimientos
## del lugar elegido para fundar.

const SAMPLES := 48

var _cells := []          # Array[Color] SAMPLES×SAMPLES
var _deposits := []
var _key := ""


func _init() -> void:
	custom_minimum_size = Vector2(230, 230)


## Recalcula (solo si cambió el mapa, la semilla o la región).
func show_region(map_type: String, seed_value: int, region: Dictionary) -> void:
	var key := "%s:%d:%s" % [map_type, seed_value, str(region.get("id", ""))]
	if key == _key:
		return
	var terrain_key := "%s:%d" % [map_type, seed_value]
	if not _key.begins_with(terrain_key + ":") or _cells.is_empty():
		_cells = _sample_terrain(map_type, seed_value)
	_key = key
	_deposits = RegionSim.generate_deposits(map_type, seed_value, region)
	queue_redraw()


func _sample_terrain(map_type: String, seed_value: int) -> Array:
	var t := Terrain.new()
	t.generate(map_type, seed_value)
	var out := []
	var size: float = GameState.MAP_SIZE
	for j in range(SAMPLES):
		for i in range(SAMPLES):
			var x := -size * 0.5 + (i + 0.5) * size / SAMPLES
			var z := -size * 0.5 + (j + 0.5) * size / SAMPLES
			var h := t.height_at(x, z)
			var c: Color
			if h < t.water_level + 0.2:
				c = Color(0.2, 0.42, 0.6)
			elif h > 30.0:
				c = Color(0.85, 0.86, 0.9)
			elif h > 16.0:
				c = Color(0.5, 0.47, 0.4)
			else:
				c = Color(0.3, 0.5, 0.25).lerp(Color(0.45, 0.55, 0.3), clampf(h / 16.0, 0.0, 1.0))
			out.append(c)
	t.free()
	return out


func _draw() -> void:
	var side := minf(size.x, size.y)
	var cell := side / SAMPLES
	for j in range(SAMPLES):
		for i in range(SAMPLES):
			if _cells.size() > j * SAMPLES + i:
				draw_rect(Rect2(i * cell, j * cell, cell + 0.5, cell + 0.5), _cells[j * SAMPLES + i])
	var ms: float = GameState.MAP_SIZE
	var to_px := func(x: float, z: float) -> Vector2: return Vector2((x / ms + 0.5) * side, (z / ms + 0.5) * side)
	# Zonas (5×5) y terreno inicial.
	var zs := side / GameState.ZONE_GRID
	for k in range(1, GameState.ZONE_GRID):
		draw_line(Vector2(k * zs, 0), Vector2(k * zs, side), Color(0, 0, 0, 0.25))
		draw_line(Vector2(0, k * zs), Vector2(side, k * zs), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(2 * zs, 2 * zs, zs, zs), Color(1, 0.9, 0.5, 0.9), false, 2.0)
	var town: Vector2 = to_px.call(0.0, 0.0)
	draw_circle(town, 4.0, Color(0.95, 0.75, 0.3))
	draw_arc(town, float(LogisticsSim.wcfg().get("walk_reach", 30.0)) / ms * side, 0, TAU, 24, Color(1, 1, 1, 0.5), 1.0)
	for d in _deposits:
		var p: Vector2 = to_px.call(float(d["x"]), float(d["z"]))
		draw_circle(p, 5.0, Color(0, 0, 0, 0.7))
		draw_circle(p, 3.8, RegionSim.resource_color(str(d["type"])))
	draw_rect(Rect2(0, 0, side, side), Color(1, 1, 1, 0.3), false, 1.0)
