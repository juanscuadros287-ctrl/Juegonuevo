shader_type spatial;
render_mode cull_disabled;
// Fase 9A: chunks del país (malla indexada). La normal plana sale de las derivadas de pantalla,
// así el estilo low-poly se conserva sin duplicar vértices. COLOR.a marca la hierba (estación).
// fog > 0: territorio sin explorar (bruma clara con el relieve tenue).

uniform vec3 season_tint = vec3(1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fog : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fog_color = vec3(0.8, 0.84, 0.9);

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 c = COLOR.rgb;
	float grass = COLOR.a;
	c = mix(c, c * season_tint, grass);
	c = mix(c, vec3(0.92, 0.94, 0.97) * max(max(COLOR.r, COLOR.g), 0.45) * 1.6, grass * snow_amount);
	c = mix(c, fog_color * (0.82 + 0.18 * dot(c, vec3(0.33))), fog);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2 * (1.0 - fog);
}
