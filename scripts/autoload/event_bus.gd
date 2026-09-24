extends Node
## Bus global de señales. Desacopla simulación, mundo 3D e interfaz.

signal notification_posted(entry: Dictionary)
signal citizen_born(id: int)
signal citizen_removed(id: int, reason: String)
signal citizens_moved
signal hour_passed(hour: int)
signal day_passed
signal year_passed(year: int)
signal season_changed(season_id: String)
signal weather_changed
signal speed_changed(speed: int)
signal jump_started(years: int)
signal jump_progress(ratio: float)
signal jump_finished(report: Dictionary)
signal citizen_selected(id: int)
signal building_selected(id: int)
signal player_died
signal building_changed(id: int)
signal building_removed(id: int)
signal zones_changed
signal player_changed
signal build_mode_requested(type_id: String, tier: String)
signal zone_mode_requested
signal interior_requested(building_id: int)
signal interior_closed
