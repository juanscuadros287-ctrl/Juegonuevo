shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;
// Carreteras, caminos, balasto y rieles (docs/GRAFICOS.md). Patrones procedurales sin texturas:
// kind 0 = tierra con huellas, 1 = empedrado, 2 = asfalto con líneas, 3 = balasto (grava),
// 4 = acero de riel, 5 = tablero de madera (puentes).
// UV.x = 0..1 a lo ancho, UV.y = metros a lo largo. Los patrones "de superficie" usan coordenadas
// del mundo: dos tramos que se cruzan dibujan exactamente lo mismo (intersecciones sin parpadeo).
// El vértice se acerca un poco a la cámara (sesgo de profundidad) para no pelear con el terreno.

uniform int kind = 0;
uniform vec3 base_color : source_color = vec3(0.5, 0.4, 0.3);
uniform float depth_bias = 0.04;
uniform float detail_fade = 120.0;

varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(VERTEX);
	VERTEX -= VERTEX / max(d, 0.001) * min(depth_bias + d * 0.0022, 4.0);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(VERTEX);
	float detail = 1.0 - smoothstep(detail_fade * 0.5, detail_fade, dist);
	vec2 w = wpos.xz;
	float u = UV.x;
	float along = UV.y;
	vec3 c = base_color;
	float rough = 0.95;
	float metal = 0.0;
	float edge = smoothstep(0.0, 0.1, u) * smoothstep(1.0, 0.9, u);
	if (kind == 0) {
		// Tierra apisonada: manchas, huellas de ruedas y bordes con pasto.
		float n = vnoise(w * 1.6) * 0.6 + vnoise(w * 5.0) * 0.4;
		float ruts = exp(-pow((u - 0.3) / 0.06, 2.0)) + exp(-pow((u - 0.7) / 0.06, 2.0));
		c *= 0.86 + 0.24 * n;
		c *= 1.0 - 0.2 * ruts * detail;
		c = mix(vec3(0.3, 0.42, 0.2) * (0.85 + 0.3 * n), c, smoothstep(0.0, 0.16, min(u, 1.0 - u) + (n - 0.5) * 0.12));
	} else if (kind == 1) {
		// Empedrado: piedras en hileras desfasadas, juntas oscuras y bordillo.
		vec2 p = w / 0.3;
		p.x += 0.5 * mod(floor(p.y), 2.0);
		vec2 f = fract(p) - 0.5;
		float stone = hash21(floor(p));
		float joint = smoothstep(0.38, 0.5, max(abs(f.x), abs(f.y)));
		c *= (0.88 + 0.2 * stone) * mix(1.0, 0.72, joint * detail);
		c *= 0.94 + 0.12 * vnoise(w * 0.4);
		float curb = 1.0 - step(0.06, u) * step(u, 0.94);
		c = mix(c, base_color * 0.82, curb);
		rough = 0.85;
	} else if (kind == 2) {
		// Asfalto: grano fino, bordes blancos y línea central amarilla discontinua.
		float n = vnoise(w * 3.0) * 0.5 + vnoise(w * 11.0) * 0.5;
		c *= 0.88 + 0.2 * n;
		float side = step(0.055, u) * step(u, 0.095) + step(0.905, u) * step(u, 0.945);
		float center = step(abs(u - 0.5), 0.022) * step(fract(along / 4.0), 0.55);
		c = mix(c, vec3(0.92, 0.92, 0.88), side * 0.9);
		c = mix(c, vec3(0.95, 0.78, 0.25), center * 0.95);
		float shoulder = 1.0 - step(0.03, u) * step(u, 0.97);
		c = mix(c, base_color * 1.4, shoulder);
		rough = 0.8;
	} else if (kind == 3) {
		// Balasto: grava.
		float g = hash21(floor(w / 0.12)) * 0.6 + vnoise(w * 2.5) * 0.4;
		c *= 0.75 + 0.45 * g;
	} else if (kind == 4) {
		c = base_color;
		rough = 0.35;
		metal = 0.7;
	} else if (kind == 5) {
		// Tablones de madera cruzados.
		float plank = fract(along / 0.35);
		c *= (0.82 + 0.25 * hash21(vec2(floor(along / 0.35), 3.0))) * mix(0.65, 1.0, smoothstep(0.0, 0.12, plank));
		rough = 0.9;
	}
	c = mix(base_color, c, 0.35 + 0.65 * detail);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.3;
}
