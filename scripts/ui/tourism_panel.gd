class_name TourismPanel
extends VBoxContainer
## Panel "Turismo y publicidad" (esqueleto de integración; lo completa su fase).

signal closed
signal message(text: String, category: String)

var hud: Hud
var body: VBoxContainer


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Turismo y publicidad", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func refresh() -> void:
	UIKit.clear(body)
	body.add_child(UIKit.label("En construcción.", 14, UIKit.TEXT_DIM))
