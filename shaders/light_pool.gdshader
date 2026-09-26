shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
// Charco de luz bajo los faroles (docs/GRAFICOS.md): disco aditivo con caída radial que se enciende
// de noche. Imita la luz del farol sobre el suelo sin luces reales (sirve igual en Compatibility).

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.72, 0.4);

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(VERTEX);
	VERTEX -= VERTEX / max(d, 0.001) * min(0.08 + d * 0.003, 4.0);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float f = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	ALBEDO = light_color * f * night * 0.55;
}
