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
	print("== Dinastía: pruebas de las Fases 9A y 9B (mapa del país, municipios, tierras, países reales) ==")
	_test_countries()
	_test_town_chunk_identical()
	_test_seams()
	_test_reveal()
	_test_owner_and_purchase()
	_test_expedition()
	_test_trade_reveal()
	_test_terrain_cost()
	_test_municipalities()
	_test_region_policy()
	_test_land_market()
	_test_roads_outside()
	_test_real_countries()
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
		check(sz >= 56 and sz <= 80, "%s mide %d chunks por lado (56–80)" % [cid, sz])
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
	var g := MapSim.gen(gs)
	check(str(gs.map.get("country_id", "")) == MapSim.default_country("interior"), "país por defecto según el tipo de mapa (%s)" % gs.map.get("country_id", ""))
	var own_n := g.zone_chunks(0).size()
	check(MapSim.revealed_count(gs) >= own_n and own_n >= 36, "al inicio se revela TODO el municipio del jugador (%d chunks revelados, municipio de %d)" % [MapSim.revealed_count(gs), own_n])
	check(MapSim.is_revealed(gs, 0, 0) and MapSim.is_revealed(gs, 1, 1) and MapSim.is_revealed(gs, -1, -1), "chunk del pueblo y vecinos revelados")
	var far := _unrevealed_chunk(gs, 12)
	check(far != Vector2i(999, 999) and not MapSim.is_revealed(gs, far.x, far.y), "chunk lejano sin revelar (%d, %d)" % [far.x, far.y])
	check(MapSim.fog_level(gs, far.x, far.y) >= 1 and MapSim.fog_level(gs, 0, 0) == 0 and MapSim.fog_level(gs, g.c1 + 5, 0) == 3, "niveles de velo: explorado, vecino, sin explorar y fuera")
	check(MapSim.chunk_of(0, 0) == Vector2i.ZERO and MapSim.chunk_of(199.9, -199.9) == Vector2i(0, -1 + 1) and MapSim.chunk_of(200.1, 0) == Vector2i(1, 0) and MapSim.chunk_of(-600.1, 0) == Vector2i(-2, 0), "chunk_of con el pueblo en (0,0)")
	var p := Vector2(far) * 400.0
	var n := MapSim.reveal_around(gs, p, 50.0)
	check(n == 1 and MapSim.is_revealed(gs, far.x, far.y), "reveal_around revela el chunk (%d, %d)" % [far.x, far.y])
	check(MapSim.reveal_around(gs, Vector3(p.x, 5, p.y), 50.0) == 0, "revelar dos veces no duplica")
	check(MapSim.reveal_around(gs, Vector2(1e6, 0), 10.0) == 0, "fuera del país no se revela nada")
	var biome := MapSim.biome_at(0, 0)
	check(biome in CountryGen.BIOMES, "biome_at en la plaza: %s" % biome)
	var reg := MapSim.region_at(gs, 0, 0)
	check(not reg.is_empty() and str(reg["id"]) == "m0" and str(reg["name"]) == str(gs.settings.get("town_name", "")) and reg.has("policy") and reg.has("mayor"), "region_at: región real (%s, alcalde %s)" % [reg.get("name", ""), reg.get("mayor", {}).get("name", "")])
	check(bool(MapSim.municipality_at(gs, 0, 0).get("player", false)), "municipio del pueblo del jugador")


## Un chunk del país sin explorar a unos `d` chunks de la plaza.
func _unrevealed_chunk(gs, d: int) -> Vector2i:
	var g := MapSim.gen(gs)
	for r in range(d, g.size):
		for c in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r), Vector2i(r, r), Vector2i(-r, -r)]:
			if g.in_country_chunk(c.x, c.y) and not MapSim.is_revealed(gs, c.x, c.y):
				return c
	return Vector2i(999, 999)


## Un chunk sin explorar pegado a lo explorado (para expediciones).
func _frontier_chunk(gs) -> Vector2i:
	var g := MapSim.gen(gs)
	for r in range(1, g.size):
		for dx in range(-r, r + 1):
			for c in [Vector2i(dx, -r), Vector2i(dx, r), Vector2i(-r, dx), Vector2i(r, dx)]:
				if not g.in_country_chunk(c.x, c.y) or MapSim.is_revealed(gs, c.x, c.y):
					continue
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if MapSim.is_revealed(gs, c.x + ox, c.y + oy):
							return c
	return Vector2i(999, 999)


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
	var far := _unrevealed_chunk(gs, 20)
	check(MapSim.expedition_block_reason(gs, far.x, far.y) != "", "no se explora lejos de lo conocido")
	check(MapSim.expedition_block_reason(gs, 1, 1) == "Ya está explorado", "no se explora lo ya revelado")
	var t := _frontier_chunk(gs)
	var cost := MapSim.expedition_cost(gs, t.x, t.y)
	var m0: float = gs.money
	check(MapSim.start_expedition(gs, t.x, t.y) == "", "expedición enviada a (%d, %d) (%s)" % [t.x, t.y, Fmt.money(cost)])
	check(absf(m0 - gs.money - cost) < 0.01, "la expedición se paga")
	check(not MapSim.is_revealed(gs, t.x, t.y), "aún no se revela")
	TimeManager.advance_days(MapSim.expedition_days(gs, t.x, t.y) + 1)
	check(MapSim.is_revealed(gs, t.x, t.y), "al volver revela el chunk y sus vecinos")
	check(gs.map["expeditions"].is_empty(), "expedición terminada")


func _test_trade_reveal() -> void:
	print("-- Pueblos NPC en su municipio y rutas que revelan --")
	GameState.new_game({"map_type": "interior", "seed": 1234})
	var gs = GameState
	var towns: Array = gs.trade.get("towns", [])
	if towns.is_empty():
		check(false, "hay pueblos de comercio")
		return
	var g := MapSim.gen(gs)
	var tid := str(towns[0]["id"])
	var p := MapSim.trade_town_pos(gs, tid)
	var zid := MapSim.town_zone(gs, tid)
	check(p != Vector2.INF and zid > 0, "el pueblo comercial tiene posición real (%.0f, %.0f) en el municipio %d" % [p.x, p.y, zid])
	var c := MapSim.chunk_of(p.x, p.y)
	check(g.zone_index(c.x, c.y) == zid and bool(g.zones[zid]["town"]) and g.zones[zid]["town_pos"] == p, "el pueblo está dentro de su municipio (casco urbano)")
	check(MunicipalSim.region(gs, zid).get("trade_town_id", "") == tid and MunicipalSim.name_of(gs, zid) == str(towns[0]["name"]), "el municipio lleva el nombre del pueblo (%s)" % MunicipalSim.name_of(gs, zid))
	var all_assigned := true
	var dists := []
	for t in towns:
		dists.append("%s %s→%s km (real %s)" % [t["name"], t.get("distance_base", "?"), t["distance"], t.get("real_km", "?")])
		if MapSim.town_zone(gs, str(t["id"])) < 0 or not t.has("distance_base"):
			all_assigned = false
		elif absf(float(t["distance"]) / float(t["distance_base"]) - 1.0) > 0.16:
			all_assigned = false
	check(all_assigned, "todos los pueblos de comercio tienen municipio y su distancia real ajustada con límites (±15%%): %s" % ", ".join(PackedStringArray(dists)))
	var before := MapSim.revealed_count(gs)
	check(not MapSim.zone_revealed_any(gs, zid) or MapSim.revealed_count(gs) > 0, "el municipio del pueblo empieza sin explorar")
	gs.trade["connections"] = [{"town_id": tid}]
	MapSim.daily(gs)
	var all_rev := true
	for cc in g.zone_chunks(zid):
		if not MapSim.is_revealed(gs, cc.x, cc.y):
			all_rev = false
	check(MapSim.is_revealed(gs, c.x, c.y) and all_rev and MapSim.revealed_count(gs) > before, "abrir la ruta revela todo su municipio y el camino (%d → %d)" % [before, MapSim.revealed_count(gs)])
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
	gs.money = 1e7
	MapSim.reveal_around(gs, Vector2(0, 900), 30.0)
	var t := _frontier_chunk(gs)
	MapSim.start_expedition(gs, t.x, t.y)
	var zid := int(MapSim.gen(gs).zones[0]["neighbors"][0])
	MunicipalSim.region(gs, zid)["policy"]["local_tax"] = 0.07
	gs.map["parcels"]["30,30"] = {"owner": "npc", "name": "Prueba Pérez", "citizen_id": -1}
	gs.map["land_index"][str(zid)] = 1.23
	gs.map["land_offers"].append({"cx": 30, "cy": 30, "amount": 500.0, "price": 400.0, "reply_day": gs.today() + 3, "seller": "Prueba Pérez", "citizen_id": -1})
	var rev_before: Dictionary = gs.map["chunks_revealed"].duplicate()
	var cid := str(gs.map["country_id"])
	var tname := str(gs.trade["towns"][0]["name"]) if not gs.trade["towns"].is_empty() else ""
	check(SaveManager.save_game("test_mapa"), "partida guardada")
	GameState.new_game({"map_type": "interior", "seed": 1})
	check(SaveManager.load_game("test_mapa"), "partida cargada")
	check(str(gs.map.get("country_id", "")) == cid, "país conservado (%s)" % cid)
	check(gs.map["chunks_revealed"].size() == rev_before.size() and gs.map["chunks_revealed"].has("0,2"), "chunks revelados conservados (%d)" % rev_before.size())
	check(gs.map["expeditions"].size() == 1, "expedición en curso conservada")
	check(absf(float(MunicipalSim.region(gs, zid)["policy"]["local_tax"]) - 0.07) < 0.0001, "política municipal conservada")
	check(str(gs.map["parcels"].get("30,30", {}).get("name", "")) == "Prueba Pérez" and gs.map["land_offers"].size() == 1 and absf(float(gs.map["land_index"][str(zid)]) - 1.23) < 0.001, "dueños, ofertas e índices de tierra conservados")
	check(tname == "" or str(gs.trade["towns"][0]["name"]) == tname, "pueblos de comercio conservados")
	SaveManager.delete_save("test_mapa")


func _test_migration() -> void:
	print("-- Migración de partidas viejas y de la 9A --")
	GameState.new_game({"map_type": "rio", "seed": 2468, "difficulty": "facil"})
	var gs = GameState
	gs.unlocked_zones.append([3, 2])
	var d: Dictionary = gs.to_dict()
	d.erase("map")
	d["settings"].erase("country_id")
	var h0 := MapSim.gen(gs).old_height(37.0, -55.0)
	gs.load_dict(d)
	var own_n := MapSim.gen(gs).zone_chunks(0).size()
	check(gs.map.has("chunks_revealed") and MapSim.revealed_count(gs) == own_n, "partida vieja convertida en país con su municipio revelado (%d chunks)" % own_n)
	check(str(gs.map.get("country_id", "")) == MapSim.default_country("rio"), "país según su tipo de mapa (%s)" % gs.map.get("country_id", ""))
	check(MapSim.owner_of(gs, 100, 0) == "jugador", "sus parcelas compradas siguen siendo suyas")
	var t := Terrain.new()
	t.generate("rio", 2468)
	check(absf(t.height_at(37.0, -55.0) - h0) < 0.2 and t.heights.size() == 161 * 161, "su mapa queda en el chunk central")
	t.free()
	# Partida de la Fase 9A: mapa sin regiones ni mercado de tierras.
	var d2: Dictionary = gs.to_dict()
	var m9a := {"country_id": d2["map"]["country_id"], "chunks_revealed": {"0,0": true, "1,0": true}, "expeditions": [], "expeditions_done": 0, "parcels": {}, "regions": {}, "routes_revealed": {}}
	d2["map"] = m9a
	for t2 in d2["trade"].get("towns", []):
		t2.erase("distance_base")
	gs.load_dict(d2)
	check(gs.map["regions"].size() == MapSim.gen(gs).zones.size() and gs.map.has("departments") and gs.map.has("land_index") and gs.map.has("region_missions"), "partida 9A: municipios, departamentos y mercado de tierras creados")
	check(MapSim.revealed_count(gs) >= own_n, "partida 9A: se revela su municipio completo")
	check(gs.trade["towns"].is_empty() or MapSim.town_zone(gs, str(gs.trade["towns"][0]["id"])) > 0, "partida 9A: los pueblos de comercio reciben posición real")




func _test_municipalities() -> void:
	print("-- Municipios grandes (Fase 9B) --")
	for cid in MapSim.country_ids():
		var g := CountryGen.new().init("interior", 77, str(cid))
		var sizes := []
		for z in g.zones:
			sizes.append(int(z["chunks"]))
		sizes.sort()
		var med: int = sizes[sizes.size() / 2]
		check(g.zones.size() >= 30 and g.zones.size() <= 60, "%s: %d municipios (30–60)" % [cid, g.zones.size()])
		check(med >= 36 and med <= 100 and sizes[0] >= 16, "%s: municipios grandes (mediana %d chunks ≈ %.1f km de lado, mínimo %d)" % [cid, med, sqrt(float(med)) * 0.4, sizes[0]])
	GameState.new_game({"map_type": "interior", "seed": 5, "country_id": "pampaverde"})
	var gs = GameState
	var regs: Dictionary = gs.map.get("regions", {})
	var deps: Dictionary = gs.map.get("departments", {})
	check(regs.size() == MapSim.gen(gs).zones.size() and deps.size() >= 3, "%d municipios con política y %d departamentos con gobernador" % [regs.size(), deps.size()])
	var names := {}
	var with_policy := 0
	for k in regs:
		names[str(regs[k]["name"])] = true
		if absf(float(regs[k]["policy"]["local_tax"])) > 0.001 or float(regs[k]["policy"]["min_wage"]) > 0.0:
			with_policy += 1
	check(names.size() == regs.size(), "cada municipio tiene nombre propio")
	check(with_policy > regs.size() / 3, "los municipios tienen políticas distintas (%d con impuesto o salario local)" % with_policy)
	check(float(regs["0"]["policy"]["local_tax"]) == 0.0 and str(regs["0"]["policy"]["regulation"]) == "media", "tu municipio empieza con política neutra")


func _test_region_policy() -> void:
	print("-- Política municipal aplicada a un negocio --")
	GameState.new_game({"map_type": "interior", "seed": 1234, "difficulty": "facil"})
	var gs = GameState
	gs.money = 1e6
	var g := MapSim.gen(gs)
	# Un municipio vecino (explorado) con impuesto local y salario mínimo altos.
	var zid := int(g.zones[0]["neighbors"][0])
	MapSim.reveal_zone(gs, zid)
	var reg := MunicipalSim.region(gs, zid)
	reg["policy"]["local_tax"] = 0.08
	reg["policy"]["min_wage"] = 9.0
	reg["policy"]["regulation"] = "media"
	var cc: Vector2i = g.zone_chunks(zid)[0]
	var pos := Vector2(cc) * 400.0 + Vector2(40, 40)
	var b := ConstructionSim.make_building(gs, "granja", 1, pos.x, pos.y, 0.0, "jugador")
	gs.add_building(b)
	check(MunicipalSim.zone_of_building(gs, b) == zid, "el negocio está en %s" % MunicipalSim.name_of(gs, zid))
	b["ledger"]["last_month"] = {"ventas": 1000.0}
	var t0 := float(reg.get("treasury", 0.0))
	var m0: float = gs.money
	GovSim._collect_taxes(gs)
	var local := float(gs.government.get("local_taxes_last", 0.0))
	check(absf(local - 80.0) < 0.01 and float(reg["treasury"]) - t0 > 79.9, "impuesto local del 8%% sobre su ganancia: %s al municipio" % Fmt.money(local))
	check(gs.money < m0, "el negocio paga el impuesto local")
	# Rebaja (impuesto negativo).
	reg["policy"]["local_tax"] = -0.05
	var m1: float = gs.money
	var t_rebate := MunicipalSim.collect_local_tax(gs, b, 1000.0)
	check(t_rebate < 0.0 and gs.money > m1, "impuesto local negativo: el municipio devuelve %s" % Fmt.money(-t_rebate))
	# Salario mínimo municipal.
	var worker = null
	for c in gs.citizens.values():
		if c.id != gs.player_id and c.job_id < 0:
			worker = c
			break
	worker.job_id = int(b["id"])
	worker.job_kind = "empleo"
	worker.wage = 1.0
	GovSim._enforce_min_wage(gs)
	check(worker.wage >= 9.0 * gs.price_level() - 0.001, "salario mínimo municipal aplicado (%.2f/día)" % worker.wage)
	# Un negocio en tu pueblo no paga impuesto local.
	var home := ConstructionSim.make_building(gs, "granja", 1, 30.0, 30.0, 0.0, "jugador")
	gs.add_building(home)
	check(MunicipalSim.local_tax_rate(gs, home) == 0.0, "en tu municipio no hay impuesto local")
	# Misión regional.
	gs.map["region_missions"]["next_day"] = 0
	MunicipalSim.monthly(gs)
	var avail: Array = gs.map["region_missions"]["available"]
	check(not avail.is_empty(), "los alcaldes proponen misiones regionales (%s)" % (avail[0]["label"] if not avail.is_empty() else "-"))
	if not avail.is_empty():
		var m: Dictionary = avail[0]
		check(MunicipalSim.accept_mission(gs, 0) == "" and gs.map["region_missions"]["active"].size() == 1, "misión aceptada")
		check(float(m["reward_money"]) > 0.0 and int(m["deadline"]) > gs.today(), "tiene recompensa y plazo")


func _test_land_market() -> void:
	print("-- Mercado de tierras --")
	GameState.new_game({"map_type": "interior", "seed": 1234, "difficulty": "facil"})
	var gs = GameState
	gs.money = 1e7
	var g := MapSim.gen(gs)
	for z in g.zones:
		MapSim.reveal_zone_quiet(gs, int(z["id"]))
	var state_c := Vector2i(999, 999)
	var npc_cs := []
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			if maxi(absi(cx), absi(cy)) < 4 or not g.in_country_chunk(cx, cy):
				continue
			var o := str(LandSim.owner_info(gs, cx, cy)["owner"])
			if o == "estado" and state_c.x == 999 and float(LandSim.quick_info(gs, cx, cy)["land"]) >= 1.0:
				state_c = Vector2i(cx, cy)
			elif o == "npc" and npc_cs.size() < 3:
				npc_cs.append(Vector2i(cx, cy))
	check(state_c.x != 999 and npc_cs.size() == 3, "hay tierra del Estado y de particulares")
	var p := LandSim.chunk_price(gs, state_c.x, state_c.y)
	check(p > 0.0, "precio de mercado de un territorio: %s" % Fmt.money(p))
	var np: String = MapSim.owner_of(gs, float(npc_cs[0].x) * 400.0, float(npc_cs[0].y) * 400.0)
	check(np.begins_with("npc:"), "owner_of devuelve el particular (%s)" % np)
	# Estado: precio fijo (si la regulación lo permite) o licitación.
	var zid := g.zone_index(state_c.x, state_c.y)
	MunicipalSim.region(gs, zid)["policy"]["regulation"] = "media"
	var m0: float = gs.money
	var tr0 := float(gs.government.get("treasury", 0.0))
	check(LandSim.buy_from_state(gs, state_c.x, state_c.y) == "", "compra al Estado a precio fijo")
	check(absf(m0 - gs.money - p) < 1.0 and float(gs.government["treasury"]) > tr0, "se paga %s al tesoro" % Fmt.money(p))
	check(MapSim.owner_of(gs, state_c.x * 400.0, state_c.y * 400.0) == "jugador" and LandSim.player_parcels(gs, state_c.x, state_c.y) == 25, "las 25 parcelas son tuyas: se unen al instante a tu mapa")
	check(ConstructionSim.placement_block_reason(gs, "granja", state_c.x * 400.0 + 30.0, state_c.y * 400.0 + 30.0) != "Terreno del gobierno: cómpralo primero (Construir → Comprar terreno)", "se puede construir ahí")
	MunicipalSim.region(gs, zid)["policy"]["regulation"] = "alta"
	var other := Vector2i(999, 999)
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			if other.x == 999 and g.zone_index(cx, cy) == zid and str(LandSim.owner_info(gs, cx, cy)["owner"]) == "estado" and maxi(absi(cx), absi(cy)) >= 4:
				other = Vector2i(cx, cy)
	if other.x != 999:
		check(LandSim.buy_block_reason(gs, other.x, other.y, "fijo").begins_with("Regulación alta"), "con regulación alta solo por licitación")
		var price := LandSim.remaining_price(gs, other.x, other.y)
		check(LandSim.start_tender(gs, other.x, other.y, price * 1.5) == "", "puja en la licitación (%s)" % Fmt.money(price * 1.5))
		TimeManager.advance_days(int(LandSim.cfg().get("tender_days", 10)) + 1)
		check(str(LandSim.owner_info(gs, other.x, other.y)["owner"]) == "jugador", "gana la licitación con una buena puja")
	# Particular: oferta que rechaza y oferta que acepta.
	var a: Vector2i = npc_cs[1]
	var pa := LandSim.remaining_price(gs, a.x, a.y)
	var m1: float = gs.money
	check(LandSim.buy_block_reason(gs, a.x, a.y, "fijo") != "", "a un particular no se le compra a precio fijo")
	check(LandSim.make_offer(gs, a.x, a.y, pa * 0.5) == "" and gs.money < m1, "oferta baja enviada (el dinero queda en garantía)")
	TimeManager.advance_days(6)
	check(str(LandSim.owner_info(gs, a.x, a.y)["owner"]) == "npc" and absf(gs.money - m1) < 1.0 * pa, "el particular rechaza la oferta baja y devuelve el dinero")
	var b: Vector2i = npc_cs[2]
	var pb := LandSim.remaining_price(gs, b.x, b.y)
	check(LandSim.make_offer(gs, b.x, b.y, pb * 1.3) == "", "oferta generosa enviada")
	check(str(LandSim.owner_info(gs, b.x, b.y)["owner"]) == "npc", "aún no responde")
	TimeManager.advance_days(6)
	check(str(LandSim.owner_info(gs, b.x, b.y)["owner"]) == "jugador" and gs.map["land_offers"].is_empty(), "el particular acepta la oferta: el territorio es tuyo")
	check(ConstructionSim.zone_block_reason(gs, a.x * 5 + 2, a.y * 5 + 2).begins_with("Terreno privado") or ConstructionSim.zone_block_reason(gs, a.x * 5 + 2, a.y * 5 + 2) != "", "una parcela de particular no se compra al gobierno")
	# Precio que fluctúa y libre comercio de NPC.
	var c2: Vector2i = npc_cs[0]
	var p0 := LandSim.chunk_price(gs, c2.x, c2.y)
	var changed := false
	var sales0: int = gs.map["land_sales"].size()
	for i in range(4):
		LandSim.monthly(gs)
		if absf(LandSim.chunk_price(gs, c2.x, c2.y) - p0) > 1.0:
			changed = true
	check(changed, "el precio fluctúa cada mes (%s → %s)" % [Fmt.money(p0), Fmt.money(LandSim.chunk_price(gs, c2.x, c2.y))])
	check(gs.map["land_sales"].size() > sales0, "los NPC compran y venden tierra (%d ventas registradas)" % gs.map["land_sales"].size())


func _test_roads_outside() -> void:
	print("-- Carreteras fuera del pueblo --")
	GameState.new_game({"map_type": "interior", "seed": 1234, "difficulty": "facil"})
	var gs = GameState
	gs.money = 1e6
	var g := MapSim.gen(gs)
	# Tramo por tierra del Estado explorada, fuera del chunk del pueblo.
	var a := Vector2(520, 20)
	var b := Vector2(700, 60)
	for k in range(60):
		a = Vector2(230.0 + (k % 6) * 90.0, -300.0 + (k / 6) * 70.0)
		b = a + Vector2(150, 30)
		var dry := true
		for i in range(11):
			var q := a.lerp(b, i / 10.0)
			if g.height(q.x, q.y) < g.water_level + 0.8:
				dry = false
		if dry and absf(a.x) > 210.0:
			break
	var owner_a := MapSim.owner_of(gs, a.x, a.y)
	check(owner_a == "estado" and MapSim.public_way_ok(gs, a.x, a.y), "tierra del Estado explorada junto al pueblo")
	var plan := TransitSim.road_plan(gs, PackedVector2Array([a, b]), "barro")
	check(str(plan["reason"]) == "", "se traza una carretera fuera del chunk del pueblo (%s)" % (plan["reason"] if str(plan["reason"]) != "" else Fmt.money(float(plan["cost"]["total"]))))
	check(TransitSim._inside_map(gs, Vector2(1500, 0)) and not TransitSim._inside_map(gs, Vector2(1e6, 0)), "TransitSim usa los límites del país")
	check(TransitSim.build_road(gs, PackedVector2Array([a, b]), "barro") == "", "carretera construida fuera del pueblo")
	# Por la niebla no.
	var far := _unrevealed_chunk(gs, 14)
	var fp := Vector2(far) * 400.0
	check(str(TransitSim.road_plan(gs, PackedVector2Array([fp, fp + Vector2(60, 0)]), "barro")["reason"]) != "", "no se trazan carreteras en territorio sin explorar")
	check(absf(WaterSim.height_at(gs, 900.0, 40.0) - g.height(900.0, 40.0)) < 0.01, "WaterSim conoce el relieve fuera del pueblo")


func _test_real_countries() -> void:
	print("-- Países reales (mapa mundial) --")
	var ids := MapSim.real_country_ids()
	check(ids.size() >= 20 and ids.has("COL") and ids.has("CHL") and ids.has("SAU"), "%d países reales jugables" % ids.size())
	var w: Dictionary = WorldData.world()
	check((w.get("countries", []) as Array).size() > 150, "mapa mundial con %d países (Natural Earth)" % (w.get("countries", []) as Array).size())
	check(FileAccess.file_exists("res://data/world/ATRIBUCION.md"), "atribución y licencia de los datos")
	var col := MapSim.country_def("COL")
	check(str(col.get("label", "")) == "Colombia" and (col.get("real_resources", []) as Array).has("esmeraldas") and str(col.get("currency", {}).get("name", "")).contains("Peso"), "perfil de Colombia: esmeraldas, café, carbón y petróleo; peso colombiano")
	check((MapSim.country_def("CHL").get("real_resources", []) as Array).has("cobre") and (MapSim.country_def("SAU").get("real_resources", []) as Array).has("petróleo"), "Chile: cobre · Arabia Saudita: petróleo")
	var g := CountryGen.new().init("interior", 3, "COL")
	check(g.real and g.size >= 40 and g.size <= 80, "Colombia a escala: %d chunks por lado (1 chunk ≈ %.1f km)" % [g.size, g.km_per_chunk])
	var ury := CountryGen.new().init("interior", 3, "URY")
	var bra := CountryGen.new().init("interior", 3, "BRA")
	check(ury.size < g.size and bra.size >= g.size, "tamaño proporcional con límites (Uruguay %d < Colombia %d ≤ Brasil %d)" % [ury.size, g.size, bra.size])
	var inside := 0
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			if g.in_country_chunk(cx, cy):
				inside += 1
	check(inside > g.size * g.size / 5 and inside < g.size * g.size * 9 / 10, "la frontera real recorta el país (%d de %d chunks)" % [inside, g.size * g.size])
	var names := []
	for z in g.zones:
		if str(z.get("real_name", "")) != "":
			names.append(str(z["real_name"]))
	check(names.has("Medellín") and names.has("Cali"), "municipios con nombres reales (%s…)" % ", ".join(PackedStringArray(names.slice(0, 6))))
	# Relieve real: la cordillera es más alta que los Llanos; el Caribe está al norte y es mar.
	var hmax := -100.0
	var sea := 0
	for p in g.places:
		if str(p["name"]) in ["Bogota", "Manizales", "Pasto"]:
			hmax = maxf(hmax, g.real_elevation(float(p["x"]), float(p["z"])))
	for i in range(20):
		var x := g.x_min + (i + 0.5) * (g.x_max - g.x_min) / 20.0
		if g.height(x, g.x_min + 200.0) < g.water_level:
			sea += 1
	check(hmax > 1500.0, "los Andes son altos (hasta %d m reales bajo las ciudades andinas)" % int(hmax))
	var hist := {}
	for j in range(30):
		for i in range(30):
			var x := g.x_min + (i + 0.5) * (g.x_max - g.x_min) / 30.0
			var z := g.x_min + (j + 0.5) * (g.x_max - g.x_min) / 30.0
			if g.in_country(x, z):
				var b := g.biome_at(x, z)
				hist[b] = int(hist.get(b, 0)) + 1
	check(hist.size() >= 4 and hist.has("montana"), "variedad de biomas por latitud y altura reales %s" % hist)
	check(g.height(0, 0) > g.water_level, "el pueblo está en tierra")
	# Una partida en un país real: el chunk central sigue siendo el terreno de siempre.
	GameState.new_game({"map_type": "interior", "seed": 4321, "country_id": "COL"})
	var old := OldTerrain.new("interior", 4321)
	var t := Terrain.new()
	t.generate("interior", 4321)
	var err := 0.0
	for j in range(0, Terrain.RES + 1, 9):
		for i in range(0, Terrain.RES + 1, 9):
			err = maxf(err, absf(t.heights[j * (Terrain.RES + 1) + i] - old.height_fn(-200.0 + i * 2.5, -200.0 + j * 2.5)))
	check(err < 1e-4, "Colombia: el chunk central es idéntico al terreno viejo (error %.6f)" % err)
	t.free()
	var towns: Array = GameState.trade.get("towns", [])
	var real_names := {}
	for pl in MapSim.gen(GameState).places:
		real_names[str(pl["name"])] = true
	check(not towns.is_empty() and MapSim.town_zone(GameState, str(towns[0]["id"])) > 0 and real_names.has(str(towns[0]["name"])), "los pueblos de comercio son pueblos reales (%s)" % (towns[0]["name"] if not towns.is_empty() else "-"))


func _test_chunk_timing() -> void:
	print("-- Tiempo de construcción de chunks --")
	GameState.new_game({"map_type": "interior", "seed": 1234, "country_id": "andoria"})
	var t := Terrain.new()
	add_child(t)
	t.generate("interior", 1234)
	t.build_mesh()
	var labels := ["alta (80×80, 5 m)", "media (40×40, 10 m)", "lejana: tesela 4×4 chunks (20×20, 80 m)"]
	for lod in [Terrain.LOD_HIGH, Terrain.LOD_MID, Terrain.LOD_FAR]:
		var t0 := Time.get_ticks_usec()
		var reps := 3 if lod != Terrain.LOD_MID else 10
		var trees := 0
		for k in range(reps):
			var r: Dictionary = t._chunk_arrays(Vector2i(3 + k * (4 if lod == Terrain.LOD_FAR else 1), -2), lod, {}, [])
			trees += int(r.get("tree_n", 0))
		var calc := (Time.get_ticks_usec() - t0) / 1000.0 / reps
		var up := t.build_chunk_now(Vector2i(-4, 3), lod)
		print("    chunk %s: cálculo %.1f ms (en hilo), total con subida %.1f ms, ~%d árboles" % [labels[lod], calc, up, trees / reps])
		check(calc < 400.0, "chunk %s se calcula en menos de 400 ms" % labels[lod])
	var t1 := Time.get_ticks_usec()
	t._build_town_mesh()
	print("    chunk del pueblo (160×160, 2,5 m): %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	# Un país real completo: cuánto cuesta la capa lejana entera (en hilos, 3 a la vez).
	GameState.new_game({"map_type": "interior", "seed": 1234, "country_id": "COL"})
	var tc := Terrain.new()
	add_child(tc)
	tc.generate("interior", 1234)
	var tt := Time.get_ticks_usec()
	var r2: Dictionary = tc._tile_arrays(Vector2i(5, 5), {})
	var one := (Time.get_ticks_usec() - tt) / 1000.0
	var ntiles := ceili(float(tc.gen.size + 4) / Terrain.TILE)
	print("    Colombia %d×%d chunks: tesela lejana %.1f ms → %d teselas ≈ %.1f s de CPU (≈ %.1f s con 3 hilos)" % [tc.gen.size, tc.gen.size, one, ntiles * ntiles, one * ntiles * ntiles / 1000.0, one * ntiles * ntiles / 3000.0])
	check((r2["verts"] as PackedVector3Array).size() > 0 and one < 400.0, "tesela lejana de un país real en menos de 400 ms")
	tc.queue_free()
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
	var fc := _frontier_chunk(GameState)
	mm.clicked(Vector2(fc) * 400.0, true)
	await get_tree().process_frame
	check(mm.selected == fc, "clic en el minimapa selecciona el territorio")
	mm._send_expedition()
	check(GameState.map["expeditions"].size() == 1, "expedición desde el minimapa grande")
	# Mapa ampliado: capa de propiedad y compra de un territorio del Estado.
	mm.set_owner_layer(true)
	await get_tree().process_frame
	check(mm.owner_texture != null and mm.show_owner, "capa de propiedad en el mapa ampliado")
	mm._select(Vector2i(2, 1))
	var own0 := LandSim.player_parcels(GameState, 2, 1)
	mm._buy_fixed()
	check(LandSim.player_parcels(GameState, 2, 1) == 25 and own0 < 25, "botón Comprar: el territorio (2, 1) es tuyo")
	check(t.overlay.house_count() > 50, "cascos urbanos de los pueblos NPC (%d casas en instancias)" % t.overlay.house_count())
	check(t.tiles.size() > 0 and t.far_material != null, "capa lejana en teselas con velo translúcido (%d teselas)" % t.tiles.size())
	mm.set_expanded(false)
	cr.view_town()
	for i in range(60):
		await get_tree().process_frame
	check(cr.distance < 200.0, "volver al pueblo")
	world.queue_free()
	await get_tree().process_frame
