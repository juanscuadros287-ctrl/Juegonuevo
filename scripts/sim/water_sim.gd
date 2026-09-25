class_name WaterSim
extends RefCounted
## Agua del pueblo (docs/REDES.md), en tres etapas:
## 1. Pozos comunitarios (por defecto, gratis): quien no compra agua la saca del pozo (autoabastecimiento
##    con calidad self_supply del bien "agua"). Cada pozo abastece ~people_per_well personas (la plaza
##    tiene wells_base; se pueden construir más "Pozo comunitario"). Con más gente que pozos el agua
##    escasea: baja la calidad y suben las enfermedades.
## 2. Venta de agua: el Aguatero (en cualquier sitio) o la Toma de río (solo a menos de fresh_water_reach
##    m de un río o lago) venden el bien "agua" en el mercado y la reparten a pie o en carreta.
## 3. Planta de agua ("water_plant") + tuberías subterráneas por tramos (GridSim, capa "water", desde
##    Potabilización): las casas conectadas (con acometida) toman el agua de la planta de su red y pagan
##    una factura mensual (tarifa × precio de mercado) a esa empresa. Mejora la salud (piped_disease)
##    y la calidad de la vivienda; las viviendas de nivel alto la exigen (GridSim.home_missing).
## Estado: gs.utilities["well"] y las facturas en gs.utilities["bills"]["water"].

const GOOD := "agua"

static var _heights := PackedFloat32Array()
static var _terrain_key := ""
static var _water_level := 0.0
static var _half := 200.0
static var _cell := 2.5
static var _plants_key := ""
static var _plants := {}        # red -> Array de ids de plantas de agua


static func cfg() -> Dictionary:
	return GridSim.water_cfg()


static func is_water_plant(def: Dictionary) -> bool:
	return bool(def.get("water_plant", false))


static func pipes_active(gs) -> bool:
	return gs.has_tech(str(GridSim.kind_def("tuberia").get("tech", "potabilizacion")))


static func _well(gs) -> Dictionary:
	var st := GridSim.state(gs)
	if not (st["well"] as Dictionary).has("factor"):
		st["well"] = {"factor": 1.0, "users": 0.0, "users_prev": 0.0, "day": -1}
	return st["well"]


# --- Pozos comunitarios --------------------------------------------------------------------------

## Personas que pueden abastecer los pozos gratuitos del pueblo.
static func well_capacity(gs) -> float:
	var cap := float(cfg().get("wells_base", 1)) * float(cfg().get("people_per_well", 80.0))
	for b in gs.buildings:
		if b["status"] == "activo":
			cap += float(gs.level_def(b).get("well_capacity", 0.0))
	return cap


static func well_count(gs) -> int:
	var n := int(cfg().get("wells_base", 1))
	for b in gs.buildings:
		if b["status"] == "activo" and float(gs.level_def(b).get("well_capacity", 0.0)) > 0.0:
			n += 1
	return n


## 0–1: qué tanto alcanzan los pozos para quienes los usan (1 = sobra agua).
static func well_factor(gs) -> float:
	return clampf(float(_well(gs).get("factor", 1.0)), 0.0, 1.0)


## Multiplicador de la calidad del autoabastecimiento de agua (pozo): baja si escasea.
static func well_mult(gs) -> float:
	var lo := float(cfg().get("well_min_quality", 0.55))
	return lo + (1.0 - lo) * well_factor(gs)


static func record_well_use(gs, qty: float) -> void:
	var w := _well(gs)
	w["users"] = float(w.get("users", 0.0)) + qty


static func daily(gs) -> void:
	var w := _well(gs)
	var today: int = gs.today()
	if int(w.get("day", -1)) == today:
		return
	w["day"] = today
	# Uso de ayer (en personas-día de agua) contra la capacidad de los pozos.
	var used := float(w.get("users", 0.0))
	w["users_prev"] = used
	w["users"] = 0.0
	w["factor"] = clampf(well_capacity(gs) / maxf(1.0, used), 0.0, 1.0) if used > 0.0 else 1.0
	var m: Dictionary = GridSim.state(gs)["month"]
	m["well_days"] = float(m.get("well_days", 0.0)) + 1.0
	m["well_factor_sum"] = float(m.get("well_factor_sum", 0.0)) + float(w["factor"])


## Enfermedad: agua por tubería protege; agua de pozo escasa enferma más.
static func disease_mult(gs, c) -> float:
	var home: Dictionary = gs.get_building(c.home_id)
	if home_piped(gs, home):
		return float(cfg().get("piped_disease", 0.8))
	var f := well_factor(gs)
	if f >= 1.0:
		return 1.0
	return 1.0 + (1.0 - f) * float(cfg().get("scarcity_disease", 0.5))


# --- Tubería y planta de agua --------------------------------------------------------------------

static func home_piped(gs, b: Dictionary) -> bool:
	if b.is_empty() or not pipes_active(gs):
		return false
	if not GridSim.connected(gs, b, GridSim.WATER):
		return false
	return GridSim.has_source(gs, GridSim.WATER, GridSim.net_of(gs, b, GridSim.WATER))


## Plantas de agua activas por red de tuberías (memo por día y versión).
static func plants_by_net(gs) -> Dictionary:
	var st := GridSim.state(gs)
	var key := "%d|%d|%d|%d" % [gs.today(), int(st.get("version", 0)), gs.buildings.size(), Engine.get_process_frames()]
	if key == _plants_key:
		return _plants
	_plants_key = key
	_plants = {}
	for b in gs.buildings:
		if b["status"] != "activo" or not gs.owned_by_player(b) or not is_water_plant(gs.building_def(b)):
			continue
		var n := GridSim.net_of(gs, b, GridSim.WATER)
		if n < 0:
			continue
		if not _plants.has(n):
			_plants[n] = []
		_plants[n].append(int(b["id"]))
	return _plants


## Precio por unidad que se factura a las casas conectadas.
static func pipe_price(gs) -> float:
	return EconomySim.market_price(gs, GOOD) * GridSim.tariff(gs, GridSim.WATER)


## Agua por tubería (llamado desde MarketSim.purchase para el bien "agua"). Si la casa del que paga
## está conectada a una red con planta y hay existencias, toma el agua de la planta y la anota en la
## factura del mes. Devuelve {} para seguir con el mercado/pozo.
static func piped_purchase(gs, payers: Array, qty: float) -> Dictionary:
	if payers.is_empty() or qty <= 0.0 or not pipes_active(gs):
		return {}
	var head = payers[0]
	var home: Dictionary = gs.get_building(head.home_id)
	if home.is_empty() or not GridSim.connected(gs, home, GridSim.WATER):
		return {}
	var st := GridSim.state(gs)
	if st["cut"][GridSim.WATER].has(str(head.id)):
		return {}
	var n := GridSim.net_of(gs, home, GridSim.WATER)
	var ids: Array = plants_by_net(gs).get(n, [])
	if ids.is_empty():
		return {}
	var stock := 0.0
	for pid in ids:
		stock += float(gs.get_building(int(pid))["inventory"].get(GOOD, 0.0))
	if stock < qty:
		return {}
	var left := qty
	var quality := 0.0
	var units: Dictionary = st["plant_units"][GridSim.WATER]
	for pid in ids:
		if left <= 0.0:
			break
		var p: Dictionary = gs.get_building(int(pid))
		var inv: Dictionary = p["inventory"]
		var take := minf(left, float(inv.get(GOOD, 0.0)))
		if take <= 0.0:
			continue
		inv[GOOD] = float(inv[GOOD]) - take
		left -= take
		units[str(int(pid))] = float(units.get(str(int(pid)), 0.0)) + take
		quality += float(gs.level_def(p).get("quality", 1.0)) * take / qty
	if not gs.is_player(head.id):
		var key := str(head.id)
		var bill: Dictionary = st["bills"][GridSim.WATER].get(key, {"own": 0.0, "grid": 0.0, "units": 0.0})
		bill["own"] = float(bill["own"]) + qty * pipe_price(gs)
		bill["units"] = float(bill["units"]) + qty
		st["bills"][GridSim.WATER][key] = bill
	var m: Dictionary = st["month"]
	m["piped_units"] = float(m.get("piped_units", 0.0)) + qty
	EconomySim.record_purchase(gs, GOOD, qty, qty, 0.0, 0.0, 0.0, 0.0)
	return {"ok": true, "quality": 1.0, "bonus": (quality - 1.0) + float(cfg().get("piped_bonus", 0.6))}


# --- Ríos y tomas de agua ------------------------------------------------------------------------

## Alturas del mapa (sin malla) para saber dónde hay agua dulce. Se calculan una vez por semilla y
## se guarda solo la cuadrícula (el nodo Terrain se libera).
static func _heights_for(gs) -> void:
	var key := "%s|%d" % [str(gs.settings.get("map_type", "interior")), int(gs.settings.get("seed", 0))]
	if key == _terrain_key and not _heights.is_empty():
		return
	var t := Terrain.new()
	t.generate(str(gs.settings.get("map_type", "interior")), int(gs.settings.get("seed", 0)))
	_heights = t.heights.duplicate()
	_water_level = t.water_level
	_half = t.half
	_cell = t.cell
	t.free()
	_terrain_key = key


## Altura del terreno (misma interpolación que Terrain.height_at).
static func height_at(gs, x: float, z: float) -> float:
	_heights_for(gs)
	if absf(x) > _half or absf(z) > _half:
		return MapSim.height_at(x, z, gs)   # Fase 9B: fuera del pueblo, el relieve del país.
	var res := Terrain.RES
	var fx := clampf((x + _half) / _cell, 0.0, res - 0.001)
	var fz := clampf((z + _half) / _cell, 0.0, res - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var w := res + 1
	return lerpf(lerpf(_heights[j * w + i], _heights[j * w + i + 1], tx), lerpf(_heights[(j + 1) * w + i], _heights[(j + 1) * w + i + 1], tx), tz)


## ¿Hay río o lago (agua dulce) a menos de `radius` m de (x, z)? En la costa el agua es de mar.
static func fresh_water_near(gs, x: float, z: float, radius := -1.0) -> bool:
	if radius < 0.0:
		radius = float(cfg().get("fresh_water_reach", 25.0))
	if not (cfg().get("fresh_water_maps", ["rio"]) as Array).has(str(gs.settings.get("map_type", ""))):
		return false
	_heights_for(gs)
	var step := 3.0
	var r := step
	while r <= radius + 0.01:
		var n := maxi(8, int(TAU * r / step))
		for i in range(n):
			var a := TAU * i / n
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if MapSim.in_country(gs, px, pz) and height_at(gs, px, pz) < _water_level:
				return true
		r += step
	return false


## ¿Hay agua dulce en alguna parte del mapa? (para avisar en el menú)
static func map_has_fresh_water(gs) -> bool:
	return (cfg().get("fresh_water_maps", ["rio"]) as Array).has(str(gs.settings.get("map_type", "")))


## Motivo de ubicación para la toma de río ("" si se puede).
static func placement_block_reason(gs, type_id: String, x: float, z: float) -> String:
	var def := GameData.building_def(type_id)
	if not bool(def.get("near_fresh_water", false)):
		return ""
	if not map_has_fresh_water(gs):
		return "Solo en mapas con río o lagos de agua dulce"
	if not fresh_water_near(gs, x, z):
		return "Debe estar a menos de %d m de un río o lago" % int(cfg().get("fresh_water_reach", 25.0))
	return ""


# --- Interfaz ------------------------------------------------------------------------------------

static func status_text(gs, b: Dictionary) -> String:
	if is_water_plant(gs.building_def(b)):
		var n := GridSim.net_of(gs, b, GridSim.WATER)
		if n < 0:
			return "[color=#e66]planta sin tubería[/color] — tiende tubería hasta las casas (Servicios públicos)"
		var homes := 0
		for h in gs.buildings:
			if Housing.is_home(h) and GridSim.connected(gs, h, GridSim.WATER) and GridSim.net_of(gs, h, GridSim.WATER) == n:
				homes += 1
		return "[color=#6c6]red de tuberías %d[/color] · %d casas conectadas" % [n, homes]
	if home_piped(gs, b):
		return "[color=#6c6]tubería[/color] (red %d, factura mensual)" % GridSim.net_of(gs, b, GridSim.WATER)
	var t := ""
	var n := GridSim.net_of(gs, b, GridSim.WATER) if pipes_active(gs) else -1
	if n >= 0 and not GridSim.connected(gs, b, GridSim.WATER):
		t = "[color=#e9b949]tubería cerca, falta la acometida (%s)[/color] · " % Fmt.money(GridSim.hookup_cost(gs, b, GridSim.WATER))
	elif n >= 0:
		t = "[color=#e9b949]tubería sin planta de agua[/color] · "
	t += "pozo comunitario (%d%% de abasto)" % int(round(well_factor(gs) * 100.0))
	if GridSim.home_missing(gs, b).has(GridSim.WATER):
		t += " · [color=#e66]este nivel exige tubería[/color]"
	return t


static func summary(gs) -> Dictionary:
	var st := GridSim.state(gs)
	var lm: Dictionary = st.get("last_month", {})
	var plants := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and is_water_plant(gs.building_def(b)):
			plants.append(b)
	var nets := {}
	for n in plants_by_net(gs):
		nets[n] = {"plants": (plants_by_net(gs)[n] as Array).size(), "homes": 0, "production": 0.0}
		for pid in plants_by_net(gs)[n]:
			nets[n]["production"] = float(nets[n]["production"]) + BusinessSim.expected_output(gs, gs.get_building(int(pid)))
	for h in gs.buildings:
		if Housing.is_home(h) and GridSim.connected(gs, h, GridSim.WATER):
			var n := GridSim.net_of(gs, h, GridSim.WATER)
			if nets.has(n):
				nets[n]["homes"] = int(nets[n]["homes"]) + 1
	var sellers := 0
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["status"] == "activo" and str(gs.building_def(b).get("product", "")) == GOOD and not is_water_plant(gs.building_def(b)):
			sellers += 1
	return {
		"wells": well_count(gs), "well_capacity": well_capacity(gs), "well_users": float(_well(gs).get("users_prev", 0.0)),
		"well_factor": well_factor(gs), "plants": plants.size(), "nets": nets, "sellers": sellers,
		"pipes": pipes_active(gs), "price": pipe_price(gs), "piped_units": float(lm.get("piped_units", 0.0)),
		"fresh_water": map_has_fresh_water(gs),
	}
