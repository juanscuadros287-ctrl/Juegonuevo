class_name GraphicsSettings
extends RefCounted
## Calidad gráfica (Baja / Media / Alta), guardada en user://graficos.cfg (docs/GRAFICOS.md).
##
## API para la interfaz:
##   GraphicsSettings.level()            -> int   nivel actual (LOW, MEDIUM, HIGH)
##   GraphicsSettings.apply(nivel)               guarda el nivel y lo aplica al instante a la escena
##   GraphicsSettings.make_selector()    -> Control  fila "Calidad gráfica: [Baja|Media|Alta]" lista para
##                                               añadir a un menú de opciones (solo usa apply()).
##   GraphicsSettings.profile()          -> Dictionary  valores efectivos del nivel (sombras, ssao, glow…)
##
## Quien dibuje algo afectado por la calidad entra al grupo GROUP e implementa
## apply_graphics(profile: Dictionary). En Compatibility (OpenGL) SSAO/glow/SSR no existen: se
## ignoran y se usan equivalentes baratos (ver SkyRig).

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const LABELS := ["Baja", "Media", "Alta"]
const GROUP := "graphics_listeners"
const PATH := "user://graficos.cfg"

static var _level := -1


static func is_forward_plus() -> bool:
	# En Compatibility (OpenGL) no hay RenderingDevice; Forward+ y Mobile sí (Metal/Vulkan).
	return RenderingServer.get_rendering_device() != null


static func level() -> int:
	if _level < 0:
		var cfg := ConfigFile.new()
		var def := HIGH if is_forward_plus() else MEDIUM
		if cfg.load(PATH) == OK:
			_level = clampi(int(cfg.get_value("graficos", "calidad", def)), LOW, HIGH)
		else:
			_level = def
	return _level


## Guarda y aplica el nivel a todo lo que esté en el grupo GROUP.
static func apply(new_level: int) -> void:
	_level = clampi(new_level, LOW, HIGH)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("graficos", "calidad", _level)
	cfg.save(PATH)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.call_group(GROUP, "apply_graphics", profile())


## Valores efectivos del nivel actual. Las distancias son de dibujo (visibility range) en metros.
static func profile(lv := -1) -> Dictionary:
	var l := level() if lv < 0 else lv
	var fp := is_forward_plus()
	var p := {
		"level": l,
		"forward_plus": fp,
		"shadows": l >= MEDIUM,
		"shadow_distance": [0.0, 160.0, 260.0][l],
		"shadow_atlas": [1024, 2048, 4096][l],
		"soft_shadows": [0, 1, 2][l],
		"ssao": fp and l >= HIGH,
		"glow": fp and l >= MEDIUM,
		"fog_depth": fp and l >= MEDIUM,
		"msaa": [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][l] if fp else [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X][l],
		"fxaa": l == LOW,
		"building_range": [260.0, 480.0, 900.0][l],
		"detail_range": [60.0, 110.0, 180.0][l],
		"tree_range": [240.0, 420.0, 800.0][l],
		"grass": l >= MEDIUM,
		"grass_range": [0.0, 55.0, 85.0][l],
		"lamp_lights": fp and l >= HIGH,
	}
	return p


## Selector compacto para un menú de opciones. Solo llama a apply().
static func make_selector() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lab := Label.new()
	lab.text = "Calidad gráfica"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lab)
	var ob := OptionButton.new()
	for i in range(LABELS.size()):
		ob.add_item(LABELS[i], i)
	ob.selected = level()
	ob.tooltip_text = "Baja: sin sombras ni efectos, menos distancia de dibujo.\nMedia: sombras suaves y brillo.\nAlta: sombras finas, oclusión ambiental (SSAO) y más distancia."
	ob.item_selected.connect(func(i: int): apply(i))
	row.add_child(ob)
	return row
