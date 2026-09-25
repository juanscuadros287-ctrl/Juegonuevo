extends Node
## Estado completo y serializable de la partida.
## La lógica vive en scripts/sim/ (PopulationSim, WeatherSim, BusinessSim,
## ConstructionSim, MarketSim, PlayerSim).

const SAVE_VERSION := 7
const MAP_SIZE := 400.0
const ZONE_GRID := 5
const START_ZONE := [2, 2]
const TOWN_RADIUS := 24.0
const MAX_LOG := 300
const MAX_HISTORY := 12 * 400

var running := false
var settings: Dictionary = {}
var money: float = 0.0
var citizens: Dictionary = {}          # id (int) -> Citizen
var next_citizen_id: int = 1
var buildings: Array = []              # Array[Dictionary]
var next_building_id: int = 1
var player_id: int = -1
## Datos propios del jugador: relaciones, planificación familiar, médico, finanzas personales.
var player: Dictionary = {}
var techs: Array = []                  # tecnologías investigadas (Fase 4)
var research: Dictionary = {}          # época, proyecto actual, progreso, cola, modificadores
var government: Dictionary = {}        # régimen, políticas, tesoro, misiones, licitaciones
var problems: Dictionary = {}          # crimen, contaminación, cobertura de servicios, eventos
var logistics: Dictionary = {}         # Fase 6: almacén, yacimientos, transporte, rutas
var trade: Dictionary = {}             # Fase 7: pueblos, conexiones, comercio exterior
var tourism: Dictionary = {}           # Fase 8: turismo y publicidad
var market: Dictionary = {}            # Libre mercado: empresas NPC, contratos, planes del gobierno
var realestate: Dictionary = {}        # Bienes raíces: demanda de vivienda y contadores (RealEstateSim)
var economy: Dictionary = {}           # nivel de precios, inflación, oferta/demanda por bien
var map: Dictionary = {}               # Fase 9A: país por chunks, revelado y expediciones (MapSim)
var transit: Dictionary = {}           # Transporte: carreteras por puntos, buses, paraderos, parqueaderos (TransitSim)
var utilities: Dictionary = {}         # Redes: tramos eléctricos y de agua, acometidas, tarifas y facturas (GridSim/WaterSim)
var loans: Array = []                  # préstamos (banco externo ↔ jugador, tu banco ↔ ciudadanos)
var next_loan_id: int = 1
var weather: Dictionary = {}
var season: String = ""
var unlocked_zones: Array = []         # Array de [x, y]
var graveyard: Dictionary = {}         # id -> "Nombre (motivo en año)"
var history: Array = []                # registro mensual para gráficas
var month_counters: Dictionary = {}
var notifications_log: Array = []
var rng := RandomNumberGenerator.new()

var collecting_report := false
var suppress_notifications := false
var _report: Dictionary = {}
var _building_index: Dictionary = {}   # id -> Dictionary (caché, no se guarda)


func diff() -> Dictionary:
	return GameData.difficulty(str(settings.get("difficulty", "normal")))


func today() -> int:
	return TimeManager.day_index()


## Nivel general de precios (inflación acumulada).
func price_level() -> float:
	return float(economy.get("price_level", 1.0))


## Multiplicador de precios: dificultad × inflación. Úsalo para todo costo nominal.
func price_mult() -> float:
	return float(diff().get("price_mult", 1.0)) * price_level()


# --- Partida nueva ----------------------------------------------------------

func default_settings() -> Dictionary:
	var towns: Array = GameData.game.get("town_names", ["San Rafael"])
	return {
		"town_name": towns[randi() % towns.size()],
		"player_name": "Sebastián",
		"player_surname": "Cuadros",
		"player_gender": "M",
		"player_age": int(GameData.game.get("player", {}).get("default_age", 25)),
		"difficulty": "normal",
		"map_type": "interior",
		"seed": randi() % 1000000,
	}


func new_game(opts: Dictionary) -> void:
	_clear()
	settings = default_settings()
	settings.merge(opts, true)
	settings["seed"] = int(settings["seed"])
	rng.seed = int(settings["seed"])
	TimeManager.reset()
	money = float(diff().get("start_money", 8000))
	unlocked_zones = [START_ZONE.duplicate()]
	EconomySim.init_state(self)
	TechSim.init_state(self)
	EventsSim.init_state(self)
	WeatherSim.init_weather(self)
	PopulationSim.generate_initial(self, int(diff().get("start_citizens", 30)))
	PlayerSim.create_player(self)
	GovSim.init_state(self)
	_init_expansions()
	running = true
	notify("Bienvenido a %s, %s. Eres el único empresario del pueblo." % [settings["town_name"], player_name()], "info")


func _clear() -> void:
	running = false
	settings = {}
	money = 0.0
	citizens = {}
	next_citizen_id = 1
	buildings = []
	_building_index = {}
	next_building_id = 1
	player_id = -1
	player = {}
	techs = []
	research = {}
	government = {}
	problems = {}
	logistics = {}
	trade = {}
	tourism = {}
	market = {}
	realestate = {}
	map = {}
	economy = {}
	utilities = {}
	transit = {}
	loans = []
	next_loan_id = 1
	weather = {}
	season = ""
	unlocked_zones = []
	graveyard = {}
	history = []
	month_counters = {}
	notifications_log = []
	collecting_report = false
	suppress_notifications = false


## Inicializa (o completa en partidas antiguas) el estado de las fases 6-8.
func _init_expansions() -> void:
	MapSim.init_state(self)   # Fase 9A: país (antes que la región, que usa sus recursos).
	LogisticsSim.init_state(self)
	TradeSim.init_state(self)
	TourismSim.init_state(self)
	FreeMarketSim.init_state(self)
	RealEstateSim.init_state(self)
	GridSim.init_state(self)
	TransitSim.init_state(self)
	MapSim.post_init(self)   # Fase 9B: pueblos de comercio con posición real en municipios.


# --- Simulación diaria -----------------------------------------------------

func simulate_day(new_month: bool, _new_year: bool) -> void:
	if not running:
		return
	WeatherSim.daily(self)
	EventsSim.daily(self)
	MapSim.daily(self)   # Fase 9A: expediciones.
	BusinessSim.produce(self)
	FreeMarketSim.produce(self)   # Libre mercado: producción de las empresas NPC.
	LogisticsSim.daily(self)
	TradeSim.daily(self)
	TransitSim.daily(self)   # Transporte: trazados a otros pueblos, buses, pasajes y parqueaderos.
	TourismSim.daily(self)
	RealEstateSim.daily(self)   # Bienes raíces: pago por etapas / pausa de obras.
	ConstructionSim.daily(self)
	MineSim.daily(self)   # Minas: obras de frentes, mantenimiento y cierre al agotarse.
	GridSim.daily(self)   # Redes: tormentas, reparaciones y acometidas (antes del reparto eléctrico).
	MarketSim.begin_day(self)
	WaterSim.daily(self)
	PopulationSim.daily(self)
	BusinessSim.end_day(self)
	FreeMarketSim.daily(self)     # Empresas NPC, contratos y planes del gobierno.
	TechSim.end_day(self)
	PlayerSim.daily(self)
	if new_month and running:
		RealEstateSim.monthly(self)   # Bienes raíces: unidades, preventas, arriendo y venta.
		GridSim.monthly(self)   # Redes: facturas de luz y agua, mantenimiento, inquilinos sin servicios.
		MarketSim.monthly_housing(self)
		BankSim.monthly(self)
		EducationSim.monthly(self)
		BusinessSim.monthly(self)
		GovSim.monthly(self)
		MapSim.monthly(self)   # Fase 9B: precios de la tierra, comercio NPC de tierras, alcaldes y misiones regionales.
		FreeMarketSim.monthly(self)
		EventsSim.monthly(self)
		LogisticsSim.monthly(self)
		TradeSim.monthly(self)
		TransitSim.monthly(self)
		TourismSim.monthly(self)
		AdvertisingSim.monthly(self)
		EconomySim.monthly(self)
		PlayerSim.monthly(self)
		_record_month()


func _record_month() -> void:
	history.append({
		"day": today(),
		"population": citizens.size(),
		"money": money,
		"happiness": avg_happiness(),
		"health": avg_health(),
		"births": int(month_counters.get("births", 0)),
		"deaths": int(month_counters.get("deaths", 0)),
		"immigrants": int(month_counters.get("immigrants", 0)),
		"income": float(month_counters.get("income", 0.0)),
		"expenses": float(month_counters.get("expenses", 0.0)),
		"net_worth": EconomySim.net_worth(self),
		"debt": EconomySim.player_debt(self),
		"loans_granted": EconomySim.loans_granted(self),
		"price_level": price_level(),
		"inflation": EconomySim.annual_inflation(self),
		"unemployment": EconomySim.unemployment(self),
		"interest_paid": float(month_counters.get("interest_paid", 0.0)),
		"interest_earned": float(month_counters.get("interest_earned", 0.0)),
		"taxes_paid": float(month_counters.get("taxes_paid", 0.0)),
		"subsidies": float(month_counters.get("subsidies", 0.0)),
		"crime": float(problems.get("crime", 0.0)),
		"pollution": float(problems.get("pollution", 0.0)),
	})
	if history.size() > MAX_HISTORY:
		history.pop_front()
	month_counters = {}


func add_counter(key: String, amount: float) -> void:
	month_counters[key] = float(month_counters.get(key, 0.0)) + amount


func count(key: String, n: int = 1) -> void:
	month_counters[key] = int(month_counters.get(key, 0)) + n
	if collecting_report:
		var c: Dictionary = _report["counters"]
		c[key] = int(c.get(key, 0)) + n


## Movimiento de dinero del jugador. Positivo = ingreso, negativo = gasto.
func add_money(amount: float) -> void:
	money += amount
	var key := "income" if amount >= 0.0 else "expenses"
	month_counters[key] = float(month_counters.get(key, 0.0)) + absf(amount)
	if collecting_report:
		var c: Dictionary = _report["counters"]
		c[key] = float(c.get(key, 0.0)) + absf(amount)


# --- Jugador --------------------------------------------------------------------

func player_citizen() -> Citizen:
	return citizens.get(player_id)


func is_player(id: int) -> bool:
	return id == player_id and id >= 0


func player_name() -> String:
	var p := player_citizen()
	return p.full_name() if p != null else str(settings.get("player_name", ""))


func player_age() -> int:
	var p := player_citizen()
	return p.age_years(today()) if p != null else 0


# --- Estadísticas ------------------------------------------------------------

func avg_happiness() -> float:
	if citizens.is_empty():
		return 0.0
	var total := 0.0
	for c in citizens.values():
		total += c.happiness
	return total / citizens.size()


func avg_health() -> float:
	if citizens.is_empty():
		return 0.0
	var total := 0.0
	for c in citizens.values():
		total += c.health
	return total / citizens.size()


# --- Edificios ------------------------------------------------------------------

func get_building(id: int) -> Dictionary:
	if _building_index.size() != buildings.size():
		_reindex()
	return _building_index.get(id, {})


func _reindex() -> void:
	_building_index = {}
	for b in buildings:
		_building_index[int(b["id"])] = b


func add_building(b: Dictionary) -> void:
	buildings.append(b)
	_building_index[int(b["id"])] = b


func remove_building(id: int) -> void:
	for i in range(buildings.size()):
		if int(buildings[i]["id"]) == id:
			buildings.remove_at(i)
			break
	_building_index.erase(id)


func building_def(b: Dictionary) -> Dictionary:
	return GameData.building_def(str(b.get("type", "")))


## Huella actual del edificio según su nivel.
func footprint_of(b: Dictionary) -> float:
	return GameData.footprint(str(b.get("type", "")), int(b.get("level", 1)))


func level_def(b: Dictionary) -> Dictionary:
	return GameData.level_def(str(b.get("type", "")), int(b.get("level", 1)))


func building_label(b: Dictionary) -> String:
	var n := str(b.get("name", ""))
	return n if n != "" else str(level_def(b).get("label", b.get("type", "")))


func building_capacity(b: Dictionary) -> int:
	return GameData.capacity(str(b.get("type", "")), int(b.get("level", 1)), str(b.get("tier", "normal")))


func is_active(b: Dictionary) -> bool:
	return str(b.get("status", "activo")) == "activo"


func owned_by_player(b: Dictionary) -> bool:
	return str(b.get("owner", "")) == "jugador"


func player_buildings(category := "") -> Array:
	var out := []
	for b in buildings:
		if owned_by_player(b) and (category == "" or str(building_def(b).get("category", "")) == category):
			out.append(b)
	return out


func residents_of(building_id: int) -> Array:
	var out := []
	for c in citizens.values():
		if c.home_id == building_id:
			out.append(c)
	return out


func employees_of(building_id: int) -> Array:
	var out := []
	for c in citizens.values():
		if c.job_id == building_id:
			out.append(c)
	return out


func person_name(id: int) -> String:
	if citizens.has(id):
		return citizens[id].full_name()
	return str(graveyard.get(id, "Desconocido"))


func is_zone_unlocked(zx: int, zy: int) -> bool:
	for z in unlocked_zones:
		if int(z[0]) == zx and int(z[1]) == zy:
			return true
	return false


func has_tech(id: String) -> bool:
	return id == "" or techs.has(id)


func era() -> int:
	return int(research.get("era", 1))


# --- Notificaciones y reportes ----------------------------------------------

## Categorías: info, nacimiento, muerte, salud, boda, emigracion, clima,
## importante, jugador, negocio, construccion, familia.
func notify(text: String, category := "info") -> void:
	var entry := {"text": text, "category": category, "date": TimeManager.date_string(false)}
	notifications_log.append(entry)
	if notifications_log.size() > MAX_LOG:
		notifications_log.pop_front()
	if collecting_report and category in ["importante", "jugador", "emigracion", "familia", "construccion"]:
		var notes: Array = _report["notes"]
		if notes.size() < 40:
			notes.append(entry)
	if not suppress_notifications:
		EventBus.notification_posted.emit(entry)


func begin_report(years: int) -> void:
	collecting_report = true
	suppress_notifications = true
	_report = {
		"years": years,
		"start_date": TimeManager.date_string(false),
		"start_population": citizens.size(),
		"start_money": money,
		"start_happiness": avg_happiness(),
		"counters": {},
		"notes": [],
	}


func end_report() -> Dictionary:
	collecting_report = false
	suppress_notifications = false
	var r := _report.duplicate(true)
	r["end_date"] = TimeManager.date_string(false)
	r["end_population"] = citizens.size()
	r["end_money"] = money
	r["end_happiness"] = avg_happiness()
	r["player_alive"] = running
	_report = {}
	return r


# --- Serialización ----------------------------------------------------------

func to_dict() -> Dictionary:
	var cit := []
	for c in citizens.values():
		cit.append(c.to_dict())
	var gy := {}
	for k in graveyard:
		gy[str(k)] = graveyard[k]
	return {
		"settings": settings,
		"money": money,
		"citizens": cit,
		"next_citizen_id": next_citizen_id,
		"buildings": buildings,
		"next_building_id": next_building_id,
		"player_id": player_id,
		"player": player,
		"techs": techs,
		"research": research,
		"government": government,
		"problems": problems,
		"logistics": logistics,
		"trade": trade,
		"tourism": tourism,
		"market": market,
		"realestate": realestate,
		"economy": economy,
		"utilities": utilities,
		"map": map,
		"transit": transit,
		"loans": loans,
		"next_loan_id": next_loan_id,
		"weather": weather,
		"season": season,
		"unlocked_zones": unlocked_zones,
		"graveyard": gy,
		"history": history,
		"month_counters": month_counters,
		"notifications_log": notifications_log,
		"running": running,
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
	}


func load_dict(d: Dictionary) -> void:
	_clear()
	settings = d.get("settings", {})
	settings["seed"] = int(settings.get("seed", 0))
	money = float(d.get("money", 0.0))
	for cd in d.get("citizens", []):
		var c := Citizen.from_dict(cd)
		citizens[c.id] = c
	next_citizen_id = int(d.get("next_citizen_id", 1))
	buildings = []
	for b in d.get("buildings", []):
		buildings.append(ConstructionSim.normalize_building(b))
	_reindex()
	next_building_id = int(d.get("next_building_id", 1))
	player = d.get("player", {})
	player_id = int(d.get("player_id", -1))
	techs = d.get("techs", [])
	loans = []
	for l in d.get("loans", []):
		var ld: Dictionary = l
		ld["id"] = int(ld["id"])
		ld["months_paid"] = int(ld.get("months_paid", 0))
		ld["missed"] = int(ld.get("missed", 0))
		ld["term_months"] = int(ld.get("term_months", 12))
		loans.append(ld)
	next_loan_id = int(d.get("next_loan_id", 1))
	weather = d.get("weather", {})
	season = str(d.get("season", ""))
	unlocked_zones = d.get("unlocked_zones", [START_ZONE.duplicate()])
	for k in d.get("graveyard", {}):
		graveyard[int(k)] = d["graveyard"][k]
	history = d.get("history", [])
	month_counters = d.get("month_counters", {})
	notifications_log = d.get("notifications_log", [])
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))
	running = bool(d.get("running", true))
	economy = d.get("economy", {})
	if economy.is_empty():
		EconomySim.init_state(self)
	research = d.get("research", {})
	if research.is_empty():
		TechSim.init_state(self)
	research["era"] = int(research.get("era", 1))
	problems = d.get("problems", {})
	if problems.is_empty():
		EventsSim.init_state(self)
	government = d.get("government", {})
	if government.is_empty():
		GovSim.init_state(self)
	logistics = d.get("logistics", {})
	trade = d.get("trade", {})
	tourism = d.get("tourism", {})
	market = d.get("market", {})
	realestate = d.get("realestate", {})
	utilities = d.get("utilities", {})
	map = d.get("map", {})   # Partida sin mapa (antes de la Fase 9A): MapSim la convierte en país.
	transit = d.get("transit", {})
	_init_expansions()
	if not d.has("utilities"):
		GridSim.migrate(self)   # Partida sin redes: período de gracia si ya había centrales.
	TechSim._recompute_mods(self)
	if player_id < 0:
		# Partida de la Fase 1: el jugador aún no era un ciudadano.
		PlayerSim.migrate_v1_player(self, d.get("player", {}))
