extends Node
## Reloj del juego. Velocidades: 0 pausa, 1 tiempo real (1 s = 1 s, como en Los Sims),
## 2 = x1 (1 s = 1 h), 3 = x2 (1 s = 1 día), 4 = x3 (1 s = 1 semana).
## x4 es un salto de años con simulación resumida (start_jump).

const SPEED_REALTIME := 1
const MAX_SPEED := 4
const SPEED_LABELS := ["II", "Real", "x1", "x2", "x3"]
const HOURS_PER_SECOND := [0.0, 1.0 / 3600.0, 1.0, 24.0, 168.0]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTH_NAMES := ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
		"agosto", "septiembre", "octubre", "noviembre", "diciembre"]
const DAYS_PER_YEAR := 365
const JUMP_FRAME_BUDGET_USEC := 12000

## Horas transcurridas desde el 1 de enero del año inicial a las 00:00.
var total_hours: int = 0
var hour_fraction: float = 0.0
var speed: int = 0
var last_speed: int = 1
var jumping := false
var _jump_days_left := 0
var _jump_days_total := 1


func start_year() -> int:
	return int(GameData.game.get("start_year", 1700))


func reset() -> void:
	var month := int(GameData.game.get("start_month", 3))
	var day := int(GameData.game.get("start_day", 1))
	var doy := 0
	for m in range(month - 1):
		doy += MONTH_DAYS[m]
	doy += day - 1
	total_hours = doy * 24 + int(GameData.game.get("start_hour", 6))
	hour_fraction = 0.0
	speed = 0
	last_speed = 1
	jumping = false


# --- Consultas de fecha ---------------------------------------------------

@warning_ignore("integer_division")
func day_index() -> int:
	return total_hours / 24


func hour() -> int:
	return total_hours % 24


func hours_per_second() -> float:
	var h: float = HOURS_PER_SECOND[speed]
	if speed == SPEED_REALTIME:
		h *= float(GameData.game.get("realtime_game_seconds_per_second", 1.0))
	return h


## Hora con fracción (iluminación y relojes a velocidades lentas).
func hour_float() -> float:
	return float(hour()) + hour_fraction


@warning_ignore("integer_division")
func year() -> int:
	return start_year() + day_index() / DAYS_PER_YEAR


func day_of_year() -> int:
	return day_index() % DAYS_PER_YEAR


## Devuelve [mes (1-12), día (1-31)].
func month_day() -> Array:
	var doy := day_of_year()
	for m in range(12):
		if doy < MONTH_DAYS[m]:
			return [m + 1, doy + 1]
		doy -= MONTH_DAYS[m]
	return [12, 31]


func month() -> int:
	return month_day()[0]


func date_string(with_hour := true) -> String:
	var md := month_day()
	var s := "%d de %s de %d" % [md[1], MONTH_NAMES[md[0] - 1], year()]
	if with_hour:
		var minutes := int(hour_fraction * 60.0) if speed <= 2 else 0
		s += "  %02d:%02d" % [hour(), minutes]
		if speed == SPEED_REALTIME:
			s += ":%02d" % (int(hour_fraction * 3600.0) % 60)
	return s


static func date_from_day(day: int, base_year: int) -> String:
	@warning_ignore("integer_division")
	var y := base_year + day / DAYS_PER_YEAR
	var doy := day % DAYS_PER_YEAR
	var m := 0
	while m < 11 and doy >= MONTH_DAYS[m]:
		doy -= MONTH_DAYS[m]
		m += 1
	return "%d de %s de %d" % [doy + 1, MONTH_NAMES[m], y]


# --- Control de velocidad --------------------------------------------------

func set_speed(s: int) -> void:
	if jumping:
		return
	speed = clampi(s, 0, MAX_SPEED)
	if speed > 0:
		last_speed = speed
	EventBus.speed_changed.emit(speed)


func toggle_pause() -> void:
	set_speed(last_speed if speed == 0 else 0)


func _process(delta: float) -> void:
	if not GameState.running:
		return
	if jumping:
		_process_jump()
		return
	if speed == 0:
		return
	hour_fraction += delta * hours_per_second()
	var steps := 0
	while hour_fraction >= 1.0 and GameState.running:
		hour_fraction -= 1.0
		_advance_hour()
		steps += 1
		if steps > 400:
			hour_fraction = 0.0
			break


func _advance_hour() -> void:
	total_hours += 1
	var h := hour()
	if h == 0:
		_run_day()
	EventBus.hour_passed.emit(h)


func _run_day() -> void:
	var doy := day_of_year()
	var new_month: bool = month_day()[1] == 1
	GameState.simulate_day(new_month, doy == 0)
	EventBus.day_passed.emit()
	if doy == 0 and not jumping:
		EventBus.year_passed.emit(year())


## Avanza días de forma inmediata (tests y herramientas).
func advance_days(days: int) -> void:
	for i in range(days):
		if not GameState.running:
			return
		total_hours += 24
		_run_day()


# --- Salto de años (x4) ----------------------------------------------------

func start_jump(years: int) -> void:
	if jumping or not GameState.running:
		return
	speed = 0
	jumping = true
	_jump_days_total = maxi(1, years * DAYS_PER_YEAR)
	_jump_days_left = _jump_days_total
	GameState.begin_report(years)
	EventBus.jump_started.emit(years)


func _process_jump() -> void:
	var t0 := Time.get_ticks_usec()
	while _jump_days_left > 0 and GameState.running and Time.get_ticks_usec() - t0 < JUMP_FRAME_BUDGET_USEC:
		total_hours += 24
		_run_day()
		_jump_days_left -= 1
	EventBus.jump_progress.emit(1.0 - float(_jump_days_left) / float(_jump_days_total))
	if _jump_days_left <= 0 or not GameState.running:
		jumping = false
		var report := GameState.end_report()
		speed = 0
		EventBus.speed_changed.emit(0)
		EventBus.jump_finished.emit(report)


# --- Guardado ------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"total_hours": total_hours, "hour_fraction": hour_fraction, "last_speed": last_speed}


func load_dict(d: Dictionary) -> void:
	total_hours = int(d.get("total_hours", 0))
	hour_fraction = float(d.get("hour_fraction", 0.0))
	last_speed = int(d.get("last_speed", 1))
	speed = 0
	jumping = false
