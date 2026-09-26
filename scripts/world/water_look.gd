class_name WaterLook
extends RefCounted
## Material del agua (shaders/water.gdshader). Se engancha desde world.gd con una línea después de
## terrain.make_water(): no modifica terrain.gd, solo reemplaza el material del plano de agua.
## Hornea un mapa de alturas del terreno alrededor del pueblo para el color por profundidad y la
## espuma de la orilla (el resto del país usa una profundidad media).

const RES := 192
const EXTENT := 480.0


static func apply(t: Terrain) -> void:
	if t == null or t.water == null:
		return
	var img := Image.create(RES, RES, false, Image.FORMAT_RF)
	var x0 := -EXTENT * 0.5
	var step := EXTENT / RES
	for j in range(RES):
		for i in range(RES):
			img.set_pixel(i, j, Color(t.height_at(x0 + (i + 0.5) * step, x0 + (j + 0.5) * step), 0, 0))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("height_tex", ImageTexture.create_from_image(img))
	m.set_shader_parameter("height_rect", Vector4(x0, x0, EXTENT, EXTENT))
	m.set_shader_parameter("water_level", t.water_level)
	t.water.material_override = m
