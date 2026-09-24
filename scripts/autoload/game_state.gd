extends Node
## Estado completo y serializable de la partida.
## La lógica de simulación vive en scripts/sim/ (PopulationSim, WeatherSim).

const SAVE_VERSION := 1
const MAP_SIZE := 400.0
const ZONE_GRID := 5
const START_ZONE := [2, 2]
const TOWN_RADIUS := 24.0
const MAX_LOG := 200
const MAX_HISTORY := 12 * 400

var running := false
var settings: Dictionary = {}
var money: float = 0.0
var citizens: Dictionary = {}          # id (int) -> Citizen
var next_citizen_id: int = 1
var buildings: Array = []              # Array[Dictionary]
var next_building_id: int = 1
var player: Dictionary = {}
var weather: Dictionary = {}
var season: String = ""
var unlocked_zones: Array = []         # Array de [x, y]
var graveyard: Dictionary = {}         # id -> "Nombre (año)" de ciudadanos fallecidos/emigrados
var history: Array = []                # registro mensual para gráficas
var month_counters: Dictionary = {}
var notifications_log: Array = []
var rng := RandomNumberGenerator.new()

var collecting_report := false
var suppress_notifications := false
var _report: Dictionary = {}


func diff() -> Dictionary:
	return GameData.difficulty(str(settings.get("difficulty", "normal")))


func today() -> int:
	return TimeManager.day_index()


# --- Partida nueva ----------------------------------------------------------

func default_settings() -> Dictionary:
	var towns: Array = GameData.game.get("town_names", ["San Rafael"])
	return {
		"town_name": towns[randi() % towns.size()],
		"player_name": "Sebastián",
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
	var start_age := int(GameData.game.get("player_start_age", 25))
	player = {
		"name": str(settings["player_name"]),
		"birth_day": today() - start_age * TimeManager.DAYS_PER_YEAR - rng.randi_range(0, 364),
		"health": 100.0,
		"alive": true,
	}
	WeatherSim.init_weather(self)
	PopulationSim.generate_initial(self, int(diff().get("start_citizens", 30)))
	running = true
	notify("Bienvenido a %s. Eres el único empresario del pueblo." % settings["town_name"], "info")


func _clear() -> void:
	running = false
	settings = {}
	money = 0.0
	citizens = {}
	next_citizen_id = 1
	buildings = []
	next_building_id = 1
	player = {}
	weather = {}
	season = ""
	unlocked_zones = []
	graveyard = {}
	history = []
	month_counters = {}
	notifications_log = []
	collecting_report = false
	suppress_notifications = false


# --- Simulación diaria -----------------------------------------------------

func simulate_day(new_month: bool, _new_year: bool) -> void:
	if not running:
		return
	WeatherSim.daily(self)
	PopulationSim.daily(self)
	_player_daily()
	if new_month:
		_record_month()


func _player_daily() -> void:
	if not player.get("alive", false):
		return
	var age := player_age()
	var p := PopulationSim.daily_death_probability(age, float(player.get("health", 100.0)), false)
	if rng.randf() < p:
		player["alive"] = false
		running = false
		notify("Has muerto a los %d años. Fin de la partida." % age, "jugador")
		EventBus.player_died.emit()


func player_age() -> int:
	@warning_ignore("integer_division")
	return (today() - int(player.get("birth_day", 0))) / TimeManager.DAYS_PER_YEAR


func _record_month() -> void:
	history.append({
		"day": today(),
		"population": citizens.size(),
		"money": money,
		"happiness": avg_happiness(),
		"health": avg_health(),
		"births": int(month_counters.get("births", 0)),
		"deaths": int(month_counters.get("deaths", 0)),
	})
	if history.size() > MAX_HISTORY:
		history.pop_front()
	month_counters = {}


func count(key: String, n: int = 1) -> void:
	month_counters[key] = int(month_counters.get(key, 0)) + n
	if collecting_report:
		var c: Dictionary = _report["counters"]
		c[key] = int(c.get(key, 0)) + n


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


func get_building(id: int) -> Dictionary:
	for b in buildings:
		if int(b["id"]) == id:
			return b
	return {}


func residents_of(building_id: int) -> Array:
	var out := []
	for c in citizens.values():
		if c.home_id == building_id:
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


# --- Notificaciones y reportes ----------------------------------------------

## Categorías: info, nacimiento, muerte, salud, boda, emigracion, clima, importante, jugador.
func notify(text: String, category := "info") -> void:
	var entry := {"text": text, "category": category, "date": TimeManager.date_string(false)}
	notifications_log.append(entry)
	if notifications_log.size() > MAX_LOG:
		notifications_log.pop_front()
	if collecting_report and category in ["importante", "jugador", "emigracion"]:
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
	r["player_alive"] = player.get("alive", false)
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
		"player": player,
		"weather": weather,
		"season": season,
		"unlocked_zones": unlocked_zones,
		"graveyard": gy,
		"history": history,
		"month_counters": month_counters,
		"notifications_log": notifications_log,
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
		var bd: Dictionary = b
		bd["id"] = int(bd["id"])
		buildings.append(bd)
	next_building_id = int(d.get("next_building_id", 1))
	player = d.get("player", {})
	player["birth_day"] = int(player.get("birth_day", 0))
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
	running = bool(player.get("alive", true))
