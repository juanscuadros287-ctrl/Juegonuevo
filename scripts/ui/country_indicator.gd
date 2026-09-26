class_name CountryIndicator
extends Button
## Fase 10: indicador de la barra superior con el país donde está el personaje (o el viaje en curso) y,
## si la cámara muestra otro país, "vista remota". Al pulsarlo abre Mis países / mapa mundial.
## Cuando el personaje llega de un viaje emite `view_change` (el HUD cambia la cámara a ese país).

signal view_change(iso: String)

var _t := 0.0


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	icon = UIIcons.tex("globe", 16)
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size.x = 150
	add_theme_font_size_override("font_size", 14)
	refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	refresh()
	var gs := GameState
	if CountriesSim.ready(gs) and str(gs.countries.get("pending_view", "")) != "" and not TimeManager.jumping:
		var iso := str(gs.countries["pending_view"])
		gs.countries["pending_view"] = ""
		if iso != CountriesSim.active_id(gs):
			view_change.emit(iso)


func refresh() -> void:
	var gs := GameState
	if not CountriesSim.ready(gs):
		text = ""
		return
	var loc := CountriesSim.location(gs)
	var act := CountriesSim.active_id(gs)
	var col := UIKit.ACCENT
	if TravelSim.traveling(gs):
		var t: Dictionary = gs.countries["travel"]
		text = "De viaje a %s (%d d)" % [CountriesSim.country_label(str(t["to"])), TravelSim.days_left(gs)]
		col = UIKit.ACCENT_2
	else:
		text = "En %s" % CountriesSim.country_label(loc)
	if act != loc:
		text += " · viendo %s%s" % [CountriesSim.country_label(act), "" if ManagerSim.has_manager(gs, act) else " (remoto)"]
		col = Color(0.95, 0.7, 0.4)
	add_theme_color_override("font_color", col)
	var n := CountriesSim.presence_ids(gs).size()
	tooltip_text = "País donde está tu personaje. Presencia en %d país%s. Clic: mapa mundial y Mis países." % [n, "" if n == 1 else "es"]
