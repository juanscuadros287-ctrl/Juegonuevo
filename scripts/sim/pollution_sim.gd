class_name PollutionSim
extends RefCounted
## Contaminación local (sección D.13, docs/TRABAJO_MUNDO.md).
##
## - Emisión de un edificio = "pollution" de su nivel × actividad (empleados / puestos) × (1 − filtros).
##   Las centrales eólica, solar e hidroeléctrica no contaminan (no declaran "pollution").
## - Se acumula por fuente cada mes (acc = acc × keep + emisión) y llega a las casas a menos de `radius`
##   metros (cae lineal con la distancia): exposición por vivienda.
## - Los vecinos expuestos enferman más (PopulationSim._health) y están menos felices (_happiness).
## - Multas: GovSim cobra env_fine × emisión (según el gobierno y la época) salvo con la licencia
##   ambiental del lobby (PoliticsSim.has_license). La contaminación global de EventsSim también usa la
##   emisión (con filtros).
## - Filtros y depuradoras: mejora comprable por negocio (tecnología, costo y mantenimiento mensual).
## Estado: GameState.world_events["pollution"] y b["filters"] (nivel de filtros, 0 = sin filtros).


static func cfg() -> Dictionary:
	return LaborSim.cfg().get("pollution", {})


static func st(gs) -> Dictionary:
	if not gs.world_events.has("pollution"):
		gs.world_events["pollution"] = {}
	return gs.world_events["pollution"]


static func init_state(gs) -> void:
	var s := st(gs)
	for k in ["acc", "exposure"]:
		if not s.has(k) or not (s[k] is Dictionary):
			s[k] = {}
	s["fines_last"] = float(s.get("fines_last", 0.0))
	s["filters_upkeep_last"] = float(s.get("filters_upkeep_last", 0.0))


# --- Emisión ---------------------------------------------------------------------------------------------

static func base_pollution(gs, b: Dictionary) -> float:
	return float(gs.level_def(b).get("pollution", 0.0))


static func filter_def(tier: int) -> Dictionary:
	return cfg().get("filters", {}).get(str(tier), {})


static func filter_reduction(b: Dictionary) -> float:
	var t := int(b.get("filters", 0))
	return float(filter_def(t).get("reduction", 0.0)) if t > 0 else 0.0


## Fracción de actividad: empleados trabajando / puestos (edificios sin puestos: 1).
static func activity(gs, b: Dictionary, counts := {}) -> float:
	var jobs := int(gs.level_def(b).get("jobs", 0))
	if jobs <= 0:
		return 1.0
	var n := 0
	if counts.is_empty():
		for c in gs.employees_of(int(b["id"])):
			if c.job_kind == "empleo" or c.job_kind == "dueño":
				n += 1
	else:
		n = int(counts.get(int(b["id"]), 0))
	return clampf(float(n) / jobs, 0.0, 1.0)


## Emisión mensual del edificio (con producción y filtros). 0 si no está activo.
static func emission(gs, b: Dictionary, counts := {}) -> float:
	if str(b.get("status", "")) != "activo":
		return 0.0
	var p := base_pollution(gs, b)
	if p <= 0.0:
		return 0.0
	var act := activity(gs, b, counts)
	if gs.building_def(b).get("category", "") != "negocio":
		act = 1.0
	return p * act * (1.0 - filter_reduction(b)) * LaborSim.strike_mult(gs, b)


static func _worker_counts(gs) -> Dictionary:
	var counts := {}
	for c in gs.citizens.values():
		if c.job_id >= 0 and (c.job_kind == "empleo" or c.job_kind == "dueño"):
			counts[c.job_id] = int(counts.get(c.job_id, 0)) + 1
	return counts


## Suma de emisiones (para la contaminación global de EventsSim).
static func total_emission(gs) -> float:
	var counts := _worker_counts(gs)
	var t := 0.0
	for b in gs.buildings:
		t += emission(gs, b, counts)
	return t


# --- Acumulación y exposición ----------------------------------------------------------------------------

static func monthly(gs) -> void:
	var s := st(gs)
	var keep := float(cfg().get("keep", 0.5))
	var counts := _worker_counts(gs)
	var acc: Dictionary = s["acc"]
	var new_acc := {}
	var sources := []
	for b in gs.buildings:
		var key := str(int(b["id"]))
		var e := emission(gs, b, counts)
		var v := float(acc.get(key, 0.0)) * keep + e
		if v > 0.05:
			new_acc[key] = snappedf(v, 0.001)
			sources.append([Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0))), v])
	s["acc"] = new_acc
	_compute_exposure(gs, sources)
	_filters_upkeep(gs)
	var fines := float(gs.government.get("taxes_last", {}).get("multas", 0.0))
	s["fines_last"] = fines
	if fines > 0.0:
		gs.notify("Multa ambiental del gobierno: %s por la contaminación de tus negocios. Los filtros, las renovables o la licencia ambiental la reducen." % Fmt.money(fines), "jugador")


static func _compute_exposure(gs, sources: Array) -> void:
	var r := float(cfg().get("radius", 45.0))
	var exp_map := {}
	if not sources.is_empty():
		for b in gs.buildings:
			if str(gs.building_def(b).get("category", "")) != "vivienda":
				continue
			var p := Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))
			var e := 0.0
			for src in sources:
				var d: float = p.distance_to(src[0])
				if d < r:
					e += float(src[1]) * (1.0 - d / r)
			if e > 0.01:
				exp_map[str(int(b["id"]))] = snappedf(e, 0.001)
	st(gs)["exposure"] = exp_map


## Recalcula ya (pruebas y paneles): acumulado sin decaer + exposición.
static func refresh_now(gs) -> void:
	var s := st(gs)
	var counts := _worker_counts(gs)
	var sources := []
	for b in gs.buildings:
		var v := maxf(float(s["acc"].get(str(int(b["id"])), 0.0)), emission(gs, b, counts))
		if v > 0.05:
			sources.append([Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0))), v])
	_compute_exposure(gs, sources)


static func exposure_of_home(gs, home_id: int) -> float:
	if home_id < 0:
		return 0.0
	var ex: Dictionary = gs.world_events.get("pollution", {}).get("exposure", {})
	if ex.is_empty():
		return 0.0
	return float(ex.get(str(home_id), 0.0))


## Multiplicador de la probabilidad de enfermar por vivir cerca de fuentes contaminantes.
static func disease_mult(gs, c: Citizen) -> float:
	var e := exposure_of_home(gs, c.home_id)
	if e <= 0.0:
		return 1.0
	return 1.0 + minf(float(cfg().get("max_disease", 0.6)), e * float(cfg().get("disease_per_point", 0.03)))


## Felicidad (negativa) por vivir junto a humo y hollín.
static func happiness_delta(gs, c: Citizen) -> float:
	var e := exposure_of_home(gs, c.home_id)
	if e <= 0.0:
		return 0.0
	return -minf(float(cfg().get("max_unhappy", 6.0)), e * float(cfg().get("unhappy_per_point", 0.35)))


## Multa ambiental mensual del edificio (lo llama GovSim._collect_taxes).
static func fine(gs, b: Dictionary, env_fine: float) -> float:
	if env_fine <= 0.0 or PoliticsSim.has_license(gs, "ambiental"):
		return 0.0
	return emission(gs, b) * env_fine * gs.price_level() * 10.0


# --- Filtros y depuradoras -------------------------------------------------------------------------------

## Mejor nivel de filtros disponible con la tecnología investigada (0 = ninguno).
static func best_tier(gs) -> int:
	var best := 0
	for t in cfg().get("filters", {}):
		if gs.has_tech(str(filter_def(int(t)).get("tech", ""))):
			best = maxi(best, int(t))
	return best


static func filter_cost(gs, b: Dictionary, tier: int) -> float:
	return float(gs.level_def(b).get("cost", 0.0)) * float(filter_def(tier).get("cost_ratio", 0.25)) * gs.price_mult()


static func filter_upkeep(gs, b: Dictionary) -> float:
	var t := int(b.get("filters", 0))
	if t <= 0:
		return 0.0
	return float(gs.level_def(b).get("cost", 0.0)) * float(filter_def(t).get("upkeep_ratio", 0.004)) * gs.price_mult()


static func filter_block_reason(gs, b: Dictionary) -> String:
	if not gs.owned_by_player(b):
		return "No es tuyo."
	if base_pollution(gs, b) <= 0.0:
		return "Este negocio no contamina."
	var tier := best_tier(gs)
	if tier <= 0:
		return "Requiere la tecnología %s." % GameData.tech_label(str(filter_def(1).get("tech", "filtros_industriales")))
	if int(b.get("filters", 0)) >= tier:
		return "Ya tiene los mejores filtros disponibles."
	var cost := filter_cost(gs, b, tier)
	if gs.money < cost:
		return "Necesitas %s." % Fmt.money(cost)
	return ""


## Compra e instala filtros (el equipo se importa: el dinero sale del pueblo).
static func buy_filters(gs, b: Dictionary) -> String:
	var why := filter_block_reason(gs, b)
	if why != "":
		return why
	var tier := best_tier(gs)
	var cost := filter_cost(gs, b, tier)
	BusinessSim.pay(gs, b, cost, "obras")
	b["filters"] = tier
	gs.notify("Instalaste %s en %s por %s: contaminación −%d %%." % [str(filter_def(tier).get("label", "filtros")).to_lower(), gs.building_label(b), Fmt.money(cost), int(round(filter_reduction(b) * 100.0))], "negocio")
	EventBus.building_changed.emit(int(b["id"]))
	return ""


static func _filters_upkeep(gs) -> void:
	var total := 0.0
	for b in gs.buildings:
		if not gs.owned_by_player(b) or int(b.get("filters", 0)) <= 0 or str(b["status"]) == "cerrado":
			continue
		var u := filter_upkeep(gs, b)
		if u > 0.0:
			BusinessSim.pay(gs, b, u, "mantenimiento")
			total += u
	st(gs)["filters_upkeep_last"] = total


## "Contaminación: X (−Y % con filtros)" para el panel del edificio ("" si no contamina).
static func panel_text(gs, b: Dictionary) -> String:
	var base := base_pollution(gs, b)
	if base <= 0.0:
		return ""
	var e := emission(gs, b)
	var red := filter_reduction(b)
	var s := "Contaminación: %.1f" % e
	if red > 0.0:
		s += " (−%d %% con filtros)" % int(round(red * 100.0))
	else:
		s += " (sin filtros)"
	var near := 0
	var acc := float(st(gs).get("acc", {}).get(str(int(b["id"])), 0.0))
	if acc > 0.0:
		s += " · acumulada en la zona %.1f" % acc
	var ex: Dictionary = st(gs).get("exposure", {})
	var r := float(cfg().get("radius", 45.0))
	var p := Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))
	for h in gs.buildings:
		if ex.has(str(int(h["id"]))) and p.distance_to(Vector2(float(h.get("x", 0.0)), float(h.get("z", 0.0)))) < r:
			near += 1
	if near > 0:
		s += " · %d viviendas afectadas" % near
	return s
