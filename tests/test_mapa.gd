extends Node
## Pruebas de la Fase 9A: país por chunks, costuras, chunk del pueblo idéntico, revelado,
## propiedad (owner_of), compra que se une al instante, guardado/carga, migración, costo de vías
## por terreno, municipios y tiempos de construcción de chunks.
## godot --headless res://tests/test_mapa.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de la Fase 9A (mapa del país) ==")
	_test_countries()
	_test_town_chunk_identical()
	_test_seams()
	_test_reveal()
	_test_owner_and_purchase()
	_test_expedition()
	_test_trade_reveal()
	_test_terrain_cost()
	_test_save_load()
	_test_migration()
	_test_chunk_timing()
	await _test_world_streaming()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Terreno viejo de referencia (copia literal de la versión de 400 m) ----------------------------

class OldTerrain:
	var cfg: Dictionary
	var map_type: String
	var water_level := 0.0
	var _noise := FastNoiseLite.new()
	var _detail := FastNoiseLite.new()
	var _ridge := FastNoiseLite.new()

	func _init(p_type: String, p_seed: int) -> void:
		map_type = p_type
		cfg = GameData.map_type(p_type)
		water_level = float(cfg.get("water_level", 0.0))
		for pair in [[_noise, p_seed, 0.006, 4], [_detail, p_seed + 11, 0.035, 2], [_ridge, p_seed + 23, 0.009, 3]]:
			var n: FastNoiseLite = pair[0]
			n.seed = pair[1]
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = pair[2]
			n.fractal_octaves = pair[3]

	func height_fn(x: float, z: float) -> float:
		var h := float(cfg.get("base_height", 4.5)) + _noise.get_noise_2d(x, z) * float(cfg.get("hill_amp", 7.0))
		h += _detail.get_noise_2d(x, z) * 1.2
		if map_type == "montana":
			var r := 1.0 - absf(_ridge.get_noise_2d(x, z))
			r *= r
			var mask := smoothstep(-20.0, -170.0, z)
			h += r * 55.0 * mask + r * 3.0
		var dist := Vector2(x, z).length()
		h = lerpf(3.0, h, smoothstep(30.0, 30.0 + 22.0, dist))
		match map_type:
			"costa":
				var coast := 85.0 + _ridge.get_noise_1d(z) * 15.0
				h = lerpf(h, -9.0, smoothstep(coast - 30.0, coast + 25.0, x))
			"rio":
				var rx := 62.0 + sin(z * 0.012) * 30.0 + _ridge.get_noise_1d(z * 0.5) * 12.0
				h = lerpf(water_level - 2.5, h, smoothstep(5.0, 18.0, absf(x - rx)))
		return h


# --- Pruebas ---------------------------------------------------------------------------------------

func _test_countries() -> void:
	print("-- Países y municipios --")
	var ids := MapSim.country_ids()
	check(ids.size() >= 4, "hay %d países de ejemplo" % ids.size())
	for cid in ids:
		var cd := MapSim.country_def(str(cid))
		var sz := int(cd.get("size", 0))
		check(sz >= 24 and sz <= 40, "%s mide %d chunks por lado (24–40)" % [cid, sz])
		check(cd.has("currency") and cd.has("base_inflation") and cd.has("exchange_rate_to_ref"), "%s tiene moneda, inflación y cambio" % cid)
		var g := CountryGen.new().init("interior", 77, str(cid))
		var hist := {}
		var n := 40
		for j in range(n):
			for i in range(n):
				var x := g.x_min + (i + 0.5) * (g.x_max - g.x_min) / n
				var z := g.x_min + (j + 0.5) * (g.x_max - g.x_min) / n
				var b := g.biome_at(x, z)
				hist[b] = int(hist.get(b, 0)) + 1
		var towns := g.zones.filter(func(zz): return bool(zz["town"])).size()
		var free := g.zones.size() - towns
		print("    %s: %d municipios (%d con pueblo, %d libres) biomas %s" % [cid, g.zones.size(), towns, free, hist])
		check(hist.size() >= 4, "%s tiene variedad de biomas (%d)" % [cid, hist.size()])
		check(bool(g.zones[0]["player"]) and g.zones[0]["town_chunk"] == Vector2i.ZERO, "%s: el municipio del jugador tiene su pueblo en el chunk central" % cid)
		check(towns >= 3 and free >= 1, "%s: municipios con pueblo y zonas libres" % cid)
		check(g.height(0, 0) > g.water_level, "%s: la plaza está en tierra" % cid)
	var andes := CountryGen.new().init("montana", 5, "andoria")
	var desert := CountryGen.new().init("interior", 5, "arenalia")
	check(_count_biome(andes, "montana") + _count_biome(andes, "nevado") > _count_biome(desert, "montana") + _count_biome(desert, "nevado"), "el país andino tiene más montaña que el desértico")
	check(_count_biome(desert, "desierto") > _count_biome(andes, "desierto"), "el país desértico tiene más desierto")


func _count_biome(g: CountryGen, b: String) -> int:
	var n := 0
	for j in range(30):
		for i in range(30):
			if g.biome_at(g.x_min + (i + 0.5) * (g.x_max - g.x_min) / 30.0, g.x_min + (j + 0.5) * (g.x_max - g.x_min) / 30.0) == b:
				n += 1
	return n


func _test_town_chunk_identical() -> void:
	print("-- Chunk del pueblo idéntico al terreno viejo --")
	for m in GameData.map_types:
		GameState.new_game({"map_type": m, "seed": 4321})
		var old := OldTerrain.new(m, 4321)
		var t := Terrain.new()
		t.generate(m, 4321)
		var max_err := 0.0
		for j in range(0, Terrain.RES + 1, 7):
			for i in range(0, Terrain.RES + 1, 7):
				var x := -200.0 + i * 2.5
				var z := -200.0 + j * 2.5
				max_err = maxf(max_err, absf(t.heights[j * (Terrain.RES + 1) + i] - old.height_fn(x, z)))
		check(max_err < 1e-4, "mapa %s: rejilla del pueblo idéntica (error float32 %.6f)" % [m, max_err])
		var pts := [Vector2(0, 0), Vector2(37.3, -12.1), Vector2(-150.2, 88.8), Vector2(62.0, 40.0), Vector2(199.0, -199.0), Vector2(-120.5, -170.25)]
		var worst := 0.0
		for p in pts:
			# Referencia: interpolación bilineal de la rejilla vieja.
			var fx := clampf((p.x + 200.0) / 2.5, 0.0, 159.999)
			var fz := clampf((p.y + 200.0) / 2.5, 0.0, 159.999)
			var i0 := int(fx)
			var j0 := int(fz)
			var tx := fx - i0
			var tz := fz - j0
			var ref := lerpf(lerpf(old.height_fn(-200 + i0 * 2.5, -200 + j0 * 2.5), old.height_fn(-200 + (i0 + 1) * 2.5, -200 + j0 * 2.5), tx),
					lerpf(old.height_fn(-200 + i0 * 2.5, -200 + (j0 + 1) * 2.5), old.height_fn(-200 + (i0 + 1) * 2.5, -200 + (j0 + 1) * 2.5), tx), tz)
			worst = maxf(worst, absf(t.height_at(p.x, p.y) - ref))
		check(worst < 1e-4, "mapa %s: height_at igual en puntos del pueblo (error %.6f)" % [m, worst])
		t.free()


func _test_seams() -> void:
	print("-- Costuras: altura continua en los bordes de chunk --")
	GameState.new_game({"map_type": "rio", "seed": 99, "country_id": "andoria"})
	var t := Terrain.new()
	t.generate("rio", 99)
	var g := t.gen
	var worst_gen := 0.0
	var worst_t := 0.0
	var eps := 0.001
	for c: int in [-6, -1, 0, 1, 2, 5, 11]:
		var edge := c * 400.0 + 200.0
		for k in range(24):
			var z := -3000.0 + k * 263.7
			worst_gen = maxf(worst_gen, absf(g.height(edge - eps, z) - g.height(edge + eps, z)))
			worst_gen = maxf(worst_gen, absf(g.height(z, edge - eps) - g.height(z, edge + eps)))
			worst_t = maxf(worst_t, absf(t.height_at(edge - eps, z) - t.height_at(edge + eps, z)))
			worst_t = maxf(worst_t, absf(t.height_at(z, edge - eps) - t.height_at(z, edge + eps)))
	check(worst_gen < 0.05, "ruido global sin saltos en bordes de chunk (máx %.4f m)" % worst_gen)
	check(worst_t < 0.05, "height_at continuo en bordes de chunk, incluido el del pueblo (máx %.4f m)" % worst_t)
	# Mallas vecinas: el borde compartido tiene las mismas alturas en ambos chunks.
	var a: Dictionary = t._chunk_arrays(Vector2i(1, 0), Terrain.LOD_HIGH, {}, [])
	var b: Dictionary = t._chunk_arrays(Vector2i(2, 0), Terrain.LOD_HIGH, {}, [])
	var n := 81
	var diff := 0.0
	for j in range(n):
		diff = maxf(diff, absf((a["verts"][j * n + n - 1] as Vector3).y - (b["verts"][j * n] as Vector3).y))
	check(diff < 1e-4, "bordes de mallas vecinas coinciden (máx %.6f m)" % diff)
	# Río largo: agua en muchos chunks del país.
	var wet := {}
	for j in range(g.c0, g.c1 + 1):
		for i in range(-3, 4):
			for s in range(20):
				var x := i * 400.0 - 200.0 + s * 20.0
				if g.height(x, j * 400.0) < g.water_level - 0.3:
					wet[j] = true
	check(wet.size() > g.size / 2, "el río cruza varios chunks (%d filas con agua)" % wet.size())
	t.free()


func _test_reveal() -> void:
	print("-- Revelado --")
	GameState.new_game({"map_type": "interior", "seed": 1234})
	var gs = GameState
	check(str(gs.map.get("country_id", "")) == MapSim.default_country("interior"), "país por defecto según el tipo de mapa (%s)" % gs.map.get("country_id", ""))
	check(MapSim.revealed_count(gs) == 9, "al inicio: pueblo y 8 vecinos revelados (%d)" % MapSim.revealed_count(gs))
	check(MapSim.is_revealed(gs, 0, 0) and MapSim.is_revealed(gs, 1, 1) and MapSim.is_revealed(gs, -1, -1), "chunk del pueblo y vecinos revelados")
	check(not MapSim.is_revealed(gs, 2, 0), "chunk lejano sin revelar")
	check(MapSim.chunk_of(0, 0) == Vector2i.ZERO and MapSim.chunk_of(199.9, -199.9) == Vector2i(0, -1 + 1) and MapSim.chunk_of(200.1, 0) == Vector2i(1, 0) and MapSim.chunk_of(-600.1, 0) == Vector2i(-2, 0), "chunk_of con el pueblo en (0,0)")
	var n := MapSim.reveal_around(gs, Vector2(800, 0), 50.0)
	check(n == 1 and MapSim.is_revealed(gs, 2, 0), "reveal_around revela el chunk (2,0)")
	check(MapSim.reveal_around(gs, Vector3(800, 5, 0), 50.0) == 0, "revelar dos veces no duplica")
	check(MapSim.reveal_around(gs, Vector2(1e6, 0), 10.0) == 0, "fuera del país no se revela nada")
	var biome := MapSim.biome_at(0, 0)
	check(biome in CountryGen.BIOMES, "biome_at en la plaza: %s" % biome)
	check(not MapSim.region_at(gs, 0, 0).is_empty() and str(MapSim.region_at(gs, 0, 0)["id"]) == "region_1", "region_at: una sola región (stub)")
	check(bool(MapSim.municipality_at(gs, 0, 0).get("player", false)), "municipio del pueblo del jugador")


func _test_owner_and_purchase() -> void:
	print("-- Propiedad y compra que se une al instante --")
	GameState.new_game({"map_type": "interior", "seed": 1234, "difficulty": "facil"})
	var gs = GameState
	gs.money = 1e7
	check(MapSim.owner_of(gs, 0, 0) == "jugador", "owner_of plaza = jugador")
	check(MapSim.owner_of(gs, 100, 0) == "estado", "owner_of parcela sin comprar = estado")
	check(MapSim.owner_of(gs, 1e6, 0) == "", "owner_of fuera del país = vacío")
	check(ConstructionSim.zone_block_reason(gs, 12, 2) != "", "no se compra una parcela sin explorar (%s)" % ConstructionSim.zone_block_reason(gs, 12, 2))
	var t := Terrain.new()
	add_child(t)
	t.generate("interior", 1234)
	t.build_mesh()
	t.build_chunk_now(Vector2i(1, 0), Terrain.LOD_HIGH)
	var before := str(t.chunk_state(Vector2i(1, 0)).get("sig", ""))
	for zx in [3, 4, 5]:
		check(ConstructionSim.unlock_zone(gs, zx, 2) == "", "compra la parcela (%d, 2)" % zx)
	check(MapSim.owner_of(gs, 250.0, 0.0) == "jugador", "la parcela del chunk vecino es del jugador")
	check(MapSim.is_revealed(gs, 1, 0), "la parcela comprada queda revelada")
	t.build_mesh()   # lo que hace el mundo al recibir zones_changed
	var st := t.chunk_state(Vector2i(1, 0))
	check(str(st.get("sig", "")) != before and str(st.get("sig", "")).contains("5,2"), "el chunk vecino se rehizo al instante con la parcela propia")
	check(st.get("detail") != null and int(st.get("detail_lod", -1)) == Terrain.LOD_HIGH, "sigue en alta resolución, sin recargas")
	var reason := ConstructionSim.placement_block_reason(gs, "granja", 260.0, 0.0)
	check(not reason.begins_with("Terreno del gobierno") and reason != "Fuera del país", "se puede construir en la parcela nueva (%s)" % (reason if reason != "" else "ok"))
	check(abs(t.height_at(199.99, 10.0) - t.height_at(200.01, 10.0)) < 0.05, "terreno continuo entre el pueblo y lo comprado")
	# Parcela en un chunk más lejano: hay que explorar primero.
	MapSim.reveal(gs, 2, 0)
	for zx in [6, 7, 8, 9, 10]:
		ConstructionSim.unlock_zone(gs, zx, 2)
	check(MapSim.owner_of(gs, 610.0, 0.0) == "jugador", "compra encadenada hasta el chunk (2,0)")
	t.queue_free()


func _test_expedition() -> void:
	print("-- Expediciones --")
	GameState.new_game({"map_type": "interior", "seed": 1234, "difficulty": "facil"})
	var gs = GameState
	gs.money = 1e6
	check(MapSim.expedition_block_reason(gs, 5, 5) != "", "no se explora lejos de lo conocido")
	check(MapSim.expedition_block_reason(gs, 1, 1) == "Ya está explorado", "no se explora lo ya revelado")
	var cost := MapSim.expedition_cost(gs, 2, 0)
	var m0: float = gs.money
	check(MapSim.start_expedition(gs, 2, 0) == "", "expedición enviada (%s)" % Fmt.money(cost))
	check(absf(m0 - gs.money - cost) < 0.01, "la expedición se paga")
	check(not MapSim.is_revealed(gs, 2, 0), "aún no se revela")
	TimeManager.advance_days(MapSim.expedition_days(gs, 2, 0) + 1)
	check(MapSim.is_revealed(gs, 2, 0) and MapSim.is_revealed(gs, 3, 1), "al volver revela el chunk y sus vecinos")
	check(gs.map["expeditions"].is_empty(), "expedición terminada")


func _test_trade_reveal() -> void:
	print("-- Rutas comerciales revelan su pueblo --")
	GameState.new_game({"map_type": "interior", "seed": 1234})
	var gs = GameState
	var towns: Array = gs.trade.get("towns", [])
	if towns.is_empty():
		check(false, "hay pueblos de comercio")
		return
	var tid := str(towns[0]["id"])
	var p := MapSim.trade_town_pos(gs, tid)
	check(p != Vector2.INF, "el pueblo comercial tiene posición en el país")
	var before := MapSim.revealed_count(gs)
	gs.trade["connections"] = [{"town_id": tid}]
	MapSim.daily(gs)
	var c := MapSim.chunk_of(p.x, p.y)
	check(MapSim.is_revealed(gs, c.x, c.y) and MapSim.revealed_count(gs) > before, "abrir la ruta revela el pueblo y el camino (%d → %d)" % [before, MapSim.revealed_count(gs)])
	gs.trade["connections"] = []


func _test_terrain_cost() -> void:
	print("-- Costo de vías según el terreno --")
	GameState.new_game({"map_type": "montana", "seed": 31, "country_id": "andoria"})
	var gs = GameState
	var flat := MapSim.terrain_cost_mult(Vector2(-20, 0), Vector2(20, 0), gs)
	check(absf(flat - 1.0) < 0.001, "en la plaza llana cuesta lo normal (×%.2f)" % flat)
	# Busca un tramo de montaña y uno que cruce agua.
	var g := MapSim.gen(gs)
	var worst := 1.0
	var wet_mult := 1.0
	for k in range(400):
		var a := Vector2(g.x_min + fmod(k * 911.0, g.x_max - g.x_min), g.x_min + fmod(k * 577.0, g.x_max - g.x_min))
		var b := a + Vector2(120, 40)
		var h := g.height(a.x, a.y)
		var m := MapSim.terrain_cost_mult(a, b, gs)
		if h > 50.0:
			worst = maxf(worst, m)
		if h > 3.0 and g.height(a.x + 60, a.y + 20) < -1.0 and g.height(b.x, b.y) > 3.0:
			wet_mult = maxf(wet_mult, m)
	check(worst > 1.8, "en la montaña cuesta más (hasta ×%.2f)" % worst)
	var road := RoadSim.segment_cost(gs, Vector2(-20, 0), Vector2(20, 0), "barro")
	check(float(road["money"]) > 0.0, "RoadSim.segment_cost usa el multiplicador (%s)" % Fmt.money(road["money"]))
	print("    puente sobre agua: ×%.2f · pendiente plaza %.3f" % [wet_mult, MapSim.slope_at(0, 0, gs)])
	var cl := MapSim.climate_at(0, -5000, gs)
	check(cl.has("temp_offset_c") and cl.has("biome"), "climate_at da temperatura y bioma (%s, %+.1f °C)" % [cl["biome"], cl["temp_offset_c"]])


func _test_save_load() -> void:
	print("-- Guardar y cargar --")
	GameState.new_game({"map_type": "costa", "seed": 555, "difficulty": "facil"})
	var gs = GameState
	gs.money = 1e6
	MapSim.reveal_around(gs, Vector2(0, 900), 30.0)
	MapSim.start_expedition(gs, -2, 0)
	var rev_before: Dictionary = gs.map["chunks_revealed"].duplicate()
	var cid := str(gs.map["country_id"])
	check(SaveManager.save_game("test_mapa"), "partida guardada")
	GameState.new_game({"map_type": "interior", "seed": 1})
	check(SaveManager.load_game("test_mapa"), "partida cargada")
	check(str(gs.map.get("country_id", "")) == cid, "país conservado (%s)" % cid)
	check(gs.map["chunks_revealed"].size() == rev_before.size() and gs.map["chunks_revealed"].has("0,2"), "chunks revelados conservados (%d)" % rev_before.size())
	check(gs.map["expeditions"].size() == 1, "expedición en curso conservada")
	SaveManager.delete_save("test_mapa")


func _test_migration() -> void:
	print("-- Migración de partida vieja --")
	GameState.new_game({"map_type": "rio", "seed": 2468, "difficulty": "facil"})
	var gs = GameState
	gs.unlocked_zones.append([3, 2])
	var d: Dictionary = gs.to_dict()
	d.erase("map")
	d["settings"].erase("country_id")
	var h0 := MapSim.gen(gs).old_height(37.0, -55.0)
	gs.load_dict(d)
	check(gs.map.has("chunks_revealed") and MapSim.revealed_count(gs) == 9, "partida vieja convertida en país con 9 chunks revelados")
	check(str(gs.map.get("country_id", "")) == MapSim.default_country("rio"), "país según su tipo de mapa (%s)" % gs.map.get("country_id", ""))
	check(MapSim.owner_of(gs, 100, 0) == "jugador", "sus parcelas compradas siguen siendo suyas")
	var t := Terrain.new()
	t.generate("rio", 2468)
	check(absf(t.height_at(37.0, -55.0) - h0) < 0.2 and t.heights.size() == 161 * 161, "su mapa queda en el chunk central")
	t.free()


func _test_chunk_timing() -> void:
	print("-- Tiempo de construcción de chunks --")
	GameState.new_game({"map_type": "interior", "seed": 1234, "country_id": "andoria"})
	var t := Terrain.new()
	add_child(t)
	t.generate("interior", 1234)
	t.build_mesh()
	var labels := ["alta (80×80, 5 m)", "media (20×20, 20 m)", "lejana (8×8, 50 m)"]
	for lod in [Terrain.LOD_HIGH, Terrain.LOD_MID, Terrain.LOD_FAR]:
		var t0 := Time.get_ticks_usec()
		var reps := 3 if lod == Terrain.LOD_HIGH else 10
		var trees := 0
		for k in range(reps):
			var r: Dictionary = t._chunk_arrays(Vector2i(3 + k, -2), lod, {}, [])
			trees += int(r.get("tree_n", 0))
		var calc := (Time.get_ticks_usec() - t0) / 1000.0 / reps
		var up := t.build_chunk_now(Vector2i(-4, 3), lod)
		print("    chunk %s: cálculo %.1f ms (en hilo), total con subida %.1f ms, ~%d árboles" % [labels[lod], calc, up, trees / reps])
		check(calc < 400.0, "chunk %s se calcula en menos de 400 ms" % labels[lod])
	var t1 := Time.get_ticks_usec()
	t._build_town_mesh()
	print("    chunk del pueblo (160×160, 2,5 m): %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	t.queue_free()


func _test_world_streaming() -> void:
	print("-- Mundo: streaming, cámara de país y minimapa --")
	GameState.new_game({"map_type": "interior", "seed": 21, "difficulty": "facil"})
	GameState.money = 1e6
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	var t: Terrain = world.terrain
	# Espera por tiempo (no por frames): con la máquina cargada los hilos tardan más.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
		if t.stats["high"] >= 5 and t.chunks[Vector2i(3, 3)].get("far") != null:
			break
	var far_n := 0
	for c in t.chunks:
		if t.chunks[c].get("far") != null:
			far_n += 1
	print("    tras %d frames: %d/%d chunks lejanos, %d en alta, %d en media, subidas %.1f ms en total" % [Engine.get_process_frames(), far_n, t.chunks.size(), t.stats["high"], t.stats["mid"], t.stats["upload_ms"]])
	check(t.stats["high"] >= 5, "chunks cercanos en alta resolución")
	check(far_n > 50, "capa lejana construida por partes")
	check(t.chunks[Vector2i(0, 0)]["lod"] == Terrain.LOD_HIGH and t.mesh_instance.visible, "el pueblo se ve con su malla de siempre")
	var cr: CameraRig = world.camera_rig
	check(cr.max_dist > 8000.0, "zoom máximo para ver el país (%.0f m)" % cr.max_dist)
	cr.view_country()
	for i in range(120):
		await get_tree().process_frame
	check(cr.distance > 6000.0 and cr.camera.far > cr.distance * 2.0, "vista de país: cámara a %.0f m, far %.0f m" % [cr.distance, cr.camera.far])
	check(t.stats["high"] == 0, "sin chunks detallados desde lejos (presupuesto)")
	var mm: Minimap = world.minimap
	mm.set_expanded(true)
	mm.clicked(Vector2(800, 0), true)
	await get_tree().process_frame
	check(mm.selected == Vector2i(2, 0), "clic en el minimapa selecciona el territorio")
	mm._send_expedition()
	check(GameState.map["expeditions"].size() == 1, "expedición desde el minimapa grande")
	mm.set_expanded(false)
	cr.view_town()
	for i in range(60):
		await get_tree().process_frame
	check(cr.distance < 200.0, "volver al pueblo")
	world.queue_free()
	await get_tree().process_frame
