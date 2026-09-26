shader_type spatial;
render_mode cull_disabled;
// Vegetación y rocas con color por instancia/vértice (docs/GRAFICOS.md).
// Balanceo con el viento barato: solo se mueven los vértices altos de las piezas verdes
// (copas, hojas, pasto); troncos marrones y rocas grises quedan quietos.
// Sombreado plano con normales de derivadas de pantalla (low-poly limpio).

uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
uniform vec2 wind_dir = vec2(0.8, 0.6);

varying float sway_w;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float green = clamp((COLOR.g - max(COLOR.r, COLOR.b)) * 6.0, 0.0, 1.0);
	float hgt = max(wp.y - origin.y, 0.0);
	float phase = dot(origin.xz, vec2(0.13, 0.17));
	float s = sin(TIME * wind_speed + phase) * 0.7 + sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.3;
	vec2 off = wind_dir * s * wind_strength * hgt * 0.35 * green;
	// Desplazamiento en espacio del mundo convertido al espacio local del modelo.
	float sc2 = max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 0.0001);
	vec3 local_off = (vec4(off.x, 0.0, off.y, 0.0) * MODEL_MATRIX).xyz / sc2;
	VERTEX += local_off;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VERTEX) > 0.0) {
		n = -n;
	}
	NORMAL = n;
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	BACKLIGHT = COLOR.rgb * 0.25;
}
