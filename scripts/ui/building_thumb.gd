class_name BuildingThumb
extends SubViewportContainer
## Miniatura 3D de un edificio (Mis empresas, docs/MIS_EMPRESAS.md), hermana de VehicleThumb: un SubViewport con
## mundo propio, luz, el modelo del edificio tal como se ve en el mapa (nivel, vivienda y módulos) sobre un
## pedazo de suelo y una cámara que lo encuadra según su tamaño.
##   - make(b, tamaño, girar): visor en vivo (ficha). Se actualiza solo mientras está visible.
##   - request(host, b, tamaño, TextureRect): foto fija para las listas. Se renderiza UNA vez en un visor
##     temporal (de a uno por cuadro), se copia a una ImageTexture y se guarda en caché por modelo; el visor
##     se libera. Con el renderizador de prueba (headless) no hay imagen y queda el marcador de color.

var b_id := -1
var spin := true
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D

static var _cache := {}      # clave de modelo -> Texture2D
static var _waiting := {}    # clave -> [TextureRect]


# --- Modelo -------------------------------------------------------------------------------------------

## Piezas del modelo como en world.gd: vivienda por nivel/tier o el modelo del nivel, más los módulos.
static func parts_for(b: Dictionary) -> Array:
	var gs := GameState
	var parts: Array = Housing.exterior_parts(b) if Housing.is_home(b) else gs.level_def(b).get("model", [])
	if b.get("modules", null) is Dictionary and not (b["modules"] as Dictionary).is_empty():
		parts = parts + MeshLib.module_parts(parts, {"almacen": ModulesSim.level(b, "almacen"), "parqueadero": ModulesSim.level(b, "parqueadero")})
	return parts


static func key_for(b: Dictionary, size: Vector2i) -> String:
	return "%s|%d|%s|%s|%d|%dx%d" % [str(b.get("type", "")), int(b.get("level", 1)), str(b.get("tier", "")), str(b.get("modules", {})),
		int(b.get("id", 0)) % 5, size.x, size.y]


## Color de marcador (primer color del modelo) mientras no hay foto.
static func swatch_color(b: Dictionary) -> Color:
	var parts := parts_for(b)
	return MeshLib.arr_color(parts[0].get("c") if not parts.is_empty() else null, Color(0.45, 0.47, 0.52))


# --- Visor en vivo ------------------------------------------------------------------------------------

static func make(b: Dictionary, size := Vector2i(300, 190), rotate := true) -> BuildingThumb:
	var t := BuildingThumb.new()
	t.spin = rotate
	t.custom_minimum_size = Vector2(size)
	t.stretch = true
	t._vp = _make_viewport(size, SubViewport.UPDATE_WHEN_VISIBLE)
	t.add_child(t._vp)
	t.set_building(b)
	return t


func set_building(b: Dictionary) -> void:
	b_id = int(b.get("id", -1))
	var r := _fill(_vp, b)
	_pivot = r[0]
	_cam = r[1]


func _process(delta: float) -> void:
	if spin and _pivot and is_visible_in_tree():
		_pivot.rotation.y += delta * 0.35


static func _make_viewport(size: Vector2i, mode: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = size
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = mode
	return vp


## Arma la escena del visor: entorno, sol, suelo, el edificio y la cámara. Devuelve [pivote, cámara].
static func _fill(vp: SubViewport, b: Dictionary) -> Array:
	for c in vp.get_children():
		c.queue_free()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.8, 0.88)
	e.ambient_light_energy = 0.75
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.light_energy = 1.25
	vp.add_child(sun)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var parts := parts_for(b)
	var ext := MeshLib.model_half_extent(parts)
	var h := MeshLib.model_height(parts)
	var ground_r := maxf(ext.x, ext.y) * 1.25 + 0.6
	var ground := MeshLib.mesh_node(MeshLib.cylinder(ground_r, ground_r, 0.12, 20), MeshLib.mat(Color(0.42, 0.55, 0.32)), Vector3(0, -0.06, 0))
	pivot.add_child(ground)
	var model := MeshLib.build_model(parts, float(Housing.tier_def(b).get("tint", 1.0)) if Housing.is_home(b) else 1.0, null, int(b.get("id", 0)) % 5)
	for c in model.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 0.0   # En la miniatura siempre el detalle.
			(c as GeometryInstance3D).visibility_range_begin = 0.0
	pivot.add_child(model)
	pivot.rotation.y = deg_to_rad(-30.0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var center := Vector3(0, h * 0.4, 0)
	var r := maxf(Vector3(maxf(ext.x, ext.y) * 1.15, h * 0.55, maxf(ext.x, ext.y) * 1.15).length(), 1.2)
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 0.82
	var dir := Vector3(0, 0.62, 1.0).normalized()
	var eye := center + dir * dist
	cam.transform = Transform3D(Basis.looking_at(center - eye, Vector3.UP), eye)
	return [pivot, cam]


# --- Fotos fijas en caché -----------------------------------------------------------------------------

## Pide la foto del edificio para `target` (TextureRect). Si está en caché se asigna al instante.
static func request(host: Node, b: Dictionary, size: Vector2i, target: TextureRect) -> void:
	var key := key_for(b, size)
	if _cache.has(key):
		target.texture = _cache[key]
		return
	var list: Array = _waiting.get(key, [])
	list.append(target)
	if _waiting.has(key):
		return
	_waiting[key] = list
	var r := _renderer(host)
	if r != null:
		r.queue.append([key, b.duplicate(), size])


static func cached(b: Dictionary, size: Vector2i) -> Texture2D:
	return _cache.get(key_for(b, size), null)


static func clear_cache() -> void:
	_cache.clear()
	_waiting.clear()


static func _renderer(host: Node) -> Renderer:
	if host == null or not host.is_inside_tree():
		return null
	var n := host.get_node_or_null("BuildingThumbRenderer")
	if n == null:
		n = Renderer.new()
		n.name = "BuildingThumbRenderer"
		host.add_child(n)
	return n as Renderer


static func _deliver(key: String, tex: Texture2D) -> void:
	if tex != null:
		_cache[key] = tex
	for t in _waiting.get(key, []):
		if is_instance_valid(t) and tex != null:
			(t as TextureRect).texture = tex
	_waiting.erase(key)


## Renderiza las fotos pendientes de a una: arma el visor, espera a que se dibuje, copia la imagen y lo libera.
class Renderer extends Node:
	var queue: Array = []
	var _busy := false

	func _process(_delta: float) -> void:
		if _busy or queue.is_empty():
			return
		_busy = true
		var job: Array = queue.pop_front()
		_render(job)

	func _render(job: Array) -> void:
		var key := str(job[0])
		var size: Vector2i = job[2]
		var vp := BuildingThumb._make_viewport(size, SubViewport.UPDATE_ONCE)
		add_child(vp)
		BuildingThumb._fill(vp, job[1])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var tex: Texture2D = null
		if is_instance_valid(vp):
			var vt := vp.get_texture()
			var img: Image = vt.get_image() if vt != null else null
			if img != null and not img.is_empty() and img.get_width() > 1:
				tex = ImageTexture.create_from_image(img)
			vp.queue_free()
		BuildingThumb._deliver(key, tex)
		_busy = false
