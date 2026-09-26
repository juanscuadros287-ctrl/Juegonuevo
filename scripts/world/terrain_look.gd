class_name TerrainLook
extends RefCounted
## Gradación de color del terreno sin tocar terrain.gd (docs/GRAFICOS.md): cambia el shader de los
## materiales ya creados por Terrain (pueblo y chunks) por copias con la gradación de
## shaders/terrain_grade.gdshaderinc. Los parámetros (estación, nieve, niebla) se conservan porque
## los uniformes se llaman igual. Enganche: una línea en world.gd después de terrain.start_country().
## Si la Fase 9B cambia terrain.gdshader o terrain_chunk.gdshader, hay que llevar el cambio a las
## copias *_plus (o quitar el enganche).


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
