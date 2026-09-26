class_name PollutionVisuals
extends Node3D
## Capa visual de la contaminación (docs/TRABAJO_MUNDO.md): columnas de humo gris sobre los edificios
## que contaminan, proporcionales a su emisión (menos con filtros; nada en renovables). Las bocanadas
## suben y se desvanecen. world.gd llama setup(world) al iniciar. Se puede ocultar con `visible`.

const MAX_PUFFS := 6
const RISE := 1.6

var world: Node3D
var _timer := 0.0
var _sources: Array = []      # [{pos: Vector3, puffs: Array[MeshInstance3D], rate: float}]
var _mat: StandardMaterial3D
var _mesh: SphereMesh


func setup(p_world: Node3D) -> void:
	world = p_world
	name = "PollutionVisuals"
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.35, 0.34, 0.33, 0.45)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh = SphereMesh.new()
	_mesh.radius = 1.0
	_mesh.height = 2.0
	_mesh.radial_segments = 8
	_mesh.rings = 4
	_rebuild()


func _height(x: float, z: float) -> float:
	var t = world.get("terrain") if world else null
	if t != null and t.has_method("height_at"):
		return float(t.height_at(x, z))
	return 0.0


func _rebuild() -> void:
	for s in _sources:
		for p in s["puffs"]:
			p.queue_free()
	_sources = []
	if not GameState.running:
		return
	for b in GameState.buildings:
		var e := PollutionSim.emission(GameState, b)
		if e <= 0.05:
			continue
		var x := float(b.get("x", 0.0))
		var z := float(b.get("z", 0.0))
		var top := _height(x, z) + 5.0 + GameState.footprint_of(b) * 0.4
		var n := clampi(int(ceil(e)), 1, MAX_PUFFS)
		var puffs := []
		for i in range(n):
			var m := MeshInstance3D.new()
			m.mesh = _mesh
			m.material_override = _mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(m)
			puffs.append(m)
		_sources.append({"pos": Vector3(x, top, z), "puffs": puffs, "rate": 0.25 + e * 0.05, "phase": randf()})


func _process(delta: float) -> void:
	if world == null:
		return
	_timer += delta
	if _timer >= 3.0:
		_timer = 0.0
		_rebuild()
	var t := Time.get_ticks_msec() / 1000.0
	for s in _sources:
		var n: int = s["puffs"].size()
		for i in range(n):
			var m: MeshInstance3D = s["puffs"][i]
			var k := fposmod(t * float(s["rate"]) + float(s["phase"]) + float(i) / n, 1.0)
			m.position = s["pos"] + Vector3(k * 2.5, k * RISE * n + 0.5, k * 0.8)
			m.scale = Vector3.ONE * (0.6 + k * 1.6)
			m.visible = k < 0.95
