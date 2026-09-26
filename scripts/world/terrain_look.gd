class_name TerrainLook
extends RefCounted
## Gradación de color del terreno sin tocar terrain.gd (docs/GRAFICOS.md): cambia el shader de los
## materiales ya creados por Terrain (pueblo y chunks) por copias con la gradación de
## shaders/terrain_grade.gdshaderinc. Los parámetros (estación, nieve, niebla) se conservan porque
## los uniformes se llaman igual. Enganche: una línea en world.gd después de terrain.start_country().
## terrain_chunk_plus.gdshader incluye el mismo cuerpo que terrain_chunk.gdshader
## (terrain_chunk_body.gdshaderinc): ya no hay copia que sincronizar. terrain_plus.gdshader sigue
## siendo copia de terrain.gdshader (malla del pueblo).
## Mapa v2: también pasa la rejilla real del país (geo_tex) al agua para el color por profundidad.


static func apply(t: Terrain) -> void:
	if t == null:
		return
	var town := load("res://shaders/terrain_plus.gdshader") as Shader
	var chunk := load("res://shaders/terrain_chunk_plus.gdshader") as Shader
	if t.material and town:
		t.material.shader = town
	for m in [t.chunk_material, t.fog_material, t.outside_material]:
		if m != null and chunk:
			(m as ShaderMaterial).shader = chunk
	if t.geo_tex != null and t.water != null and t.water.material_override is ShaderMaterial:
		var wm := t.water.material_override as ShaderMaterial
		wm.set_shader_parameter("geo_tex", t.geo_tex)
		wm.set_shader_parameter("has_geo", true)
		wm.set_shader_parameter("geo_rect", Vector4(t.geo_rect.position.x, t.geo_rect.position.y, t.geo_rect.size.x, t.geo_rect.size.y))
