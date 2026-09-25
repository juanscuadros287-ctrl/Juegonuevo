shader_type spatial;
// Área de un yacimiento (MiningVisuals): tinte del suelo con vetas (oro, hierro, carbón…) o
// manchas (petróleo, gas), borde irregular (12 radios, igual que MineSim.radius_at) y un
// contorno que se ilumina al colocar una mina o un frente.
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

uniform vec3 ore_color = vec3(0.6, 0.3, 0.2);
uniform vec3 soil_color = vec3(0.42, 0.35, 0.27);
uniform vec2 center = vec2(0.0);
uniform float radius = 20.0;
uniform float shape[12];
uniform int pattern = 0;          // 0 = vetas, 1 = manchas
uniform float highlight = 0.0;    // 0..1 contorno brillante
uniform vec3 highlight_color = vec3(0.3, 1.0, 0.4);
uniform float seed = 0.0;
uniform float depleted = 0.0;     // 0..1: reserva gastada (el tinte se apaga)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 d = wpos.xz - center;
	float ang = atan(d.y, d.x);
	float t = mod(ang + 6.2831853, 6.2831853) / 6.2831853 * 12.0;
	int i0 = int(floor(t)) % 12;
	int i1 = (i0 + 1) % 12;
	float f = smoothstep(0.0, 1.0, fract(t));
	float r = radius * mix(shape[i0], shape[i1], f);
	float dist = length(d) / r;
	if (dist > 1.0) {
		discard;
	}
	vec2 p = wpos.xz + vec2(seed * 7.3, seed * 3.1);
	float n = vnoise(p * 0.12) + 0.5 * vnoise(p * 0.37);
	float mask = 0.0;
	if (pattern == 0) {
		// Vetas: bandas sinuosas con dos direcciones.
		float v1 = abs(sin(dot(p, vec2(0.62, 0.78)) * 0.42 + n * 3.4));
		float v2 = abs(sin(dot(p, vec2(-0.8, 0.6)) * 0.27 + n * 2.6 + 1.7));
		mask = max(1.0 - smoothstep(0.08, 0.32, v1), 0.8 * (1.0 - smoothstep(0.05, 0.18, v2)));
	} else {
		// Manchas: charcos oscuros irregulares.
		float m = n * 0.62 + vnoise(p * 0.8) * 0.38;
		mask = smoothstep(0.58, 0.66, m);
	}
	float speck = step(0.93, hash(floor(p * 1.6)));
	vec3 soil = soil_color * (0.85 + 0.3 * vnoise(p * 0.9));
	vec3 col = mix(soil, ore_color, clamp(mask + speck * 0.6, 0.0, 1.0));
	col = mix(col, soil_color, depleted * 0.6);
	float edge = 1.0 - smoothstep(0.82, 1.0, dist);
	float ring = smoothstep(0.9, 0.97, dist) * (1.0 - smoothstep(0.97, 1.0, dist));
	col = mix(col, highlight_color, ring * highlight);
	ALBEDO = col;
	ALPHA = clamp(edge * mix(0.82, 0.97, mask) + ring * highlight * 0.9, 0.0, 1.0);
	ROUGHNESS = 0.95;
}
