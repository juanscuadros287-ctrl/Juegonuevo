class_name WeatherSim
extends RefCounted
## Estaciones y clima diario. Afectan agricultura (ingresos), salud y felicidad.


static func season_for_month(m: int) -> String:
	var seasons: Dictionary = GameData.weather.get("seasons", {})
	for id in seasons:
		for sm in seasons[id].get("months", []):
			if int(sm) == m:
				return id
	return "primavera"


static func season_data(gs) -> Dictionary:
	return GameData.weather.get("seasons", {}).get(gs.season, {})


static func weather_data(gs) -> Dictionary:
	return GameData.weather.get("types", {}).get(str(gs.weather.get("type", "despejado")), {})


static func init_weather(gs) -> void:
	gs.season = season_for_month(TimeManager.month())
	gs.weather = {"type": "despejado", "temp": 15.0}
	_roll(gs, true)


static func daily(gs) -> void:
	var s := season_for_month(TimeManager.month())
	if s != gs.season:
		gs.season = s
		gs.notify("Comienza la estación: %s." % str(season_data(gs).get("label", s)), "clima")
		EventBus.season_changed.emit(s)
	_roll(gs, false)


static func _roll(gs, force: bool) -> void:
	var s := season_data(gs)
	var table: Dictionary = s.get("weather", {"despejado": 1.0})
	var old := str(gs.weather.get("type", "despejado"))
	var new_type := old
	var persistence := float(GameData.weather.get("persistence", 0.6))
	if force or not table.has(old) or gs.rng.randf() > persistence:
		new_type = _weighted_pick(gs.rng, table)
	var temp_range: Array = s.get("temp", [10, 20])
	gs.weather = {"type": new_type, "temp": roundf(gs.rng.randf_range(float(temp_range[0]), float(temp_range[1])))}
	if new_type != old:
		if new_type in ["tormenta", "calor", "helada"]:
			gs.notify("Clima: %s." % str(weather_data(gs).get("label", new_type)), "clima")
		EventBus.weather_changed.emit()


static func _weighted_pick(rng: RandomNumberGenerator, table: Dictionary) -> String:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var r := rng.randf() * total
	for k in table:
		r -= float(table[k])
		if r <= 0.0:
			return k
	return table.keys()[0]
