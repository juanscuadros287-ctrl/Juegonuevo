class_name PlayerPanel
extends VBoxContainer
## "Mi Personaje": salud, familia, hogar, heredero, relaciones y acciones personales.

signal closed
signal message(text: String, category: String)

var hud: Hud
var info: RichTextLabel
var actions: VBoxContainer


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Mi Personaje", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	info = UIKit.rich()
	info.meta_clicked.connect(hud.on_meta_clicked)
	sb["box"].add_child(info)
	actions = VBoxContainer.new()
	sb["box"].add_child(actions)


func refresh() -> void:
	var p := GameState.player_citizen()
	if p == null:
		info.text = "Sin personaje."
		return
	var today := GameState.today()
	var s := "[font_size=20][color=#edc259]%s[/color][/font_size]\n" % p.full_name()
	s += "%s · %d años\n" % ["Mujer" if p.gender == "F" else "Hombre", p.age_years(today)]
	s += "Salud: %s%s · Felicidad: %s\n" % [hud.bar(p.health), "  [color=#e88](enfermo/a)[/color]" if p.sick else "", hud.bar(p.happiness)]
	s += "Dinero: %s\n" % Fmt.money(GameState.money)
	var home := PlayerSim.player_home(GameState)
	s += "Hogar: %s\n\n" % ("Sin hogar" if home.is_empty() else "%s (%s)" % [GameState.building_label(home), Housing.tier_label(str(home.get("tier", "normal")))])
	s += "[b]Familia[/b]\n"
	s += "Cónyuge: %s\n" % (hud.link(p.spouse_id) if p.spouse_id >= 0 else "—")
	var kids := PlayerSim.heir_candidates(GameState)
	s += "Hijos: %s\n" % (", ".join(kids.map(func(k): return "%s (%d)" % [hud.link(k.id), k.age_years(today)])) if not kids.is_empty() else "—")
	var heir := int(GameState.player.get("heir_id", -1))
	s += "Heredero: %s\n" % (hud.link(heir) if GameState.citizens.has(heir) else ("el hijo(a) mayor" if not kids.is_empty() else "[color=#e66]ninguno: si mueres, termina la partida[/color]"))
	s += "Planificación familiar: %s\n\n" % ("buscando hijos" if bool(GameState.player.get("family_planning", true)) else "no desean hijos")
	var rel: Dictionary = GameState.player.get("relations", {})
	var known := rel.keys()
	known.sort_custom(func(a, b): return float(rel[a]) > float(rel[b]))
	s += "[b]Personas que conoces[/b]\n"
	var n := 0
	for k in known:
		var id := int(k)
		if GameState.citizens.has(id) and n < 15:
			s += "• %s — %s\n" % [hud.link(id), PlayerSim.relation_label(GameState, GameState.citizens[id])]
			n += 1
	if n == 0:
		s += "[color=#999]Haz clic en personas del pueblo para conocerlas.[/color]\n"
	info.text = s
	_rebuild_actions(p, kids)


func _rebuild_actions(p: Citizen, kids: Array) -> void:
	UIKit.clear(actions)
	var home := PlayerSim.player_home(GameState)
	if not home.is_empty():
		actions.add_child(UIKit.button("Ver mi casa por dentro", func(): EventBus.interior_requested.emit(int(home["id"]))))
	if p.spouse_id >= 0:
		actions.add_child(UIKit.button("Buscar un bebé con mi pareja", func(): _do(PlayerSim.try_child(GameState))))
	var fp := CheckBox.new()
	fp.text = "Queremos tener hijos"
	fp.button_pressed = bool(GameState.player.get("family_planning", true))
	fp.toggled.connect(func(on): GameState.player["family_planning"] = on)
	actions.add_child(fp)
	actions.add_child(UIKit.button("Adoptar un bebé de otro pueblo (%s)" % Fmt.money(float(PlayerSim.cfg().get("adopt_baby_fee", 400)) * GameState.price_mult()), func(): _do(PlayerSim.adopt_baby(GameState))))
	actions.add_child(UIKit.button("Ir al médico (%s)" % Fmt.money(float(PlayerSim.cfg().get("doctor_fee", 30)) * GameState.price_mult()), func(): _do(PlayerSim.visit_doctor(GameState))))
	if not kids.is_empty():
		var row := HBoxContainer.new()
		row.add_child(UIKit.label("Elegir heredero:"))
		var opt := OptionButton.new()
		for k in kids:
			opt.add_item(k.full_name())
			opt.set_item_metadata(opt.item_count - 1, k.id)
		opt.item_selected.connect(func(i): GameState.player["heir_id"] = int(opt.get_item_metadata(i)); refresh())
		for i in range(opt.item_count):
			if int(opt.get_item_metadata(i)) == int(GameState.player.get("heir_id", -1)):
				opt.select(i)
		row.add_child(opt)
		actions.add_child(row)
	actions.add_child(UIKit.button("Ir a mi personaje (cámara)", func():
		var world := hud.get_parent()
		if world.has_method("focus_citizen"):
			world.focus_citizen(GameState.player_id)))


func _do(text: String) -> void:
	message.emit(text, "familia")
	refresh()
