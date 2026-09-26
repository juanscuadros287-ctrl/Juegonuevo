shader_type spatial;
#include "res://shaders/terrain_grade.gdshaderinc"
// Copia de terrain.gdshader + gradación (docs/GRAFICOS.md). Terreno low-poly con color por vértice. COLOR.a marca la hierba,
// que se tiñe según la estación (y se cubre de nieve en invierno).

uniform vec3 season_tint = vec3(1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 tg_wpos;

void vertex() {
	tg_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float grass = COLOR.a;
	c = mix(c, c * season_tint, grass);
	c = mix(c, vec3(0.92, 0.94, 0.97) * max(max(COLOR.r, COLOR.g), 0.45) * 1.6, grass * snow_amount);
	ALBEDO = terrain_grade(c, grass, tg_wpos, length(VERTEX));
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
