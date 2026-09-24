class_name WeatherFX
extends Node3D
## Partículas de lluvia/nieve que siguen a la cámara.

var _rain: CPUParticles3D
var _snow: CPUParticles3D


func _ready() -> void:
	_rain = _make(MeshLib.box(Vector3(0.03, 0.7, 0.03)), Color(0.7, 0.75, 0.85), 2500, -45.0)
	_snow = _make(MeshLib.sphere(0.07, 4, 2), Color(1, 1, 1), 1800, -4.0)
	set_fx("")


func _make(mesh: Mesh, color: Color, amount: int, gravity: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = 3.0 if gravity > -10.0 else 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(45, 1, 45)
	p.position = Vector3(0, 28, 0)
	p.direction = Vector3.DOWN
	p.initial_velocity_min = 8.0 if gravity < -10.0 else 1.0
	p.initial_velocity_max = p.initial_velocity_min * 1.3
	p.gravity = Vector3(0.6, gravity, 0.2)
	p.local_coords = false
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m
	add_child(p)
	return p


## fx: "", "rain", "storm" o "snow".
func set_fx(fx: String) -> void:
	_rain.emitting = fx == "rain" or fx == "storm"
	_rain.amount = 4000 if fx == "storm" else 2500
	_snow.emitting = fx == "snow"
	_rain.visible = _rain.emitting
	_snow.visible = _snow.emitting
