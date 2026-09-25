class_name CycleIndicator
extends Button
## Indicador del ciclo económico de tu país para la barra superior: fase (color) y riesgo según los
## indicadores adelantados. El tooltip muestra las señales. Al pulsarlo abre Economía mundial.
## Uso en el HUD:  var ci := CycleIndicator.new(); row.add_child(ci); ci.pressed.connect(...)

var _t := 0.0


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("font_size", 14)
	refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 1.0:
		_t = 0.0
		refresh()


func refresh() -> void:
	var gs := GameState
	if not GlobalEconSim.ready(gs) or GlobalEconSim.home(gs).is_empty():
		text = ""
		visible = false
		return
	visible = true
	var st := GlobalEconSim.home(gs)
	var phase := str(st["phase"])
	var c: Array = GlobalEconSim.phase_def(phase).get("color", [0.8, 0.8, 0.8])
	var col := Color(float(c[0]), float(c[1]), float(c[2]))
	var r := GlobalEconSim.risk(gs, GlobalEconSim.home_id(gs))
	text = "%s%s" % [GlobalEconSim.bar_text(gs), "  ⚠" if r >= 40.0 and phase != "crisis" else ""]
	add_theme_color_override("font_color", col)
	add_theme_color_override("font_hover_color", col.lightened(0.2))
	var sig := GlobalEconSim.signals(gs, GlobalEconSim.home_id(gs))
	var tip := "Ciclo económico de %s: %s. Riesgo según indicadores: %d/100." % [GlobalEconSim.country_label(GlobalEconSim.home_id(gs)), GlobalEconSim.phase_label(phase), int(r)]
	for s in sig:
		tip += "\n• " + str(s)
	tip += "\nClic: Economía mundial (ciclos, monedas, bolsa y seguros)."
	tooltip_text = tip
