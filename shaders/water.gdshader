shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Agua de ríos, lagos y mar (docs/GRAFICOS.md). Sin textura de profundidad (funciona igual en
// Forward+ y en Compatibility): la profundidad sale de un mapa de alturas del terreno horneado
// alrededor del pueblo (height_tex). Color por profundidad, brillo con fresnel, ondas suaves en la
// normal y espuma animada en la orilla.

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 height_rect = vec4(-200.0, -200.0, 400.0, 400.0);   // x0, z0, ancho, alto
uniform float water_level = 0.0;
uniform float far_depth = 4.0;
uniform vec3 shallow_color : source_color = vec3(0.22, 0.58, 0.6);
uniform vec3 deep_color : source_color = vec3(0.05, 0.2, 0.36);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
uniform float wave_scale = 0.18;
// Mapa v2: rejilla real del país (A = altura/batimetría real en m, B = fracción de tierra) para el
// color por profundidad en todo el país (plataforma turquesa, mar profundo azul oscuro).
uniform sampler2D geo_tex : filter_linear, repeat_disable;
uniform bool has_geo = false;
uniform vec4 geo_rect = vec4(0.0, 0.0, 1.0, 1.0);

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

float waves(vec2 p, float t) {
	return vnoise(p * 0.35 + vec2(t * 0.25, t * 0.12)) * 0.6 + vnoise(p * 0.9 - vec2(t * 0.18, -t * 0.3)) * 0.4;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - height_rect.xy) / height_rect.zw;
	float depth = far_depth;
	float real_d = -1.0;
	float coast = 0.0;
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		depth = max(water_level - texture(height_tex, uv).r, 0.0);
	} else if (has_geo) {
		vec2 guv = (wpos.xz - geo_rect.xy) / geo_rect.zw;
		if (guv.x > 0.0 && guv.y > 0.0 && guv.x < 1.0 && guv.y < 1.0) {
			vec4 g = texture(geo_tex, guv);
			real_d = g.a < 0.0 ? -g.a : 25.0;   // lagos y ríos (altura positiva): poco profundos
			coast = smoothstep(0.05, 0.6, g.b);
		} else {
			real_d = 3000.0;
		}
	}
	float dist = length(VERTEX);
	float t = TIME;
	// Ondas: normal perturbada por dos capas de ruido (se aplanan a lo lejos).
	float e = 0.35;
	float h0 = waves(wpos.xz, t);
	float hx = waves(wpos.xz + vec2(e, 0.0), t);
	float hz = waves(wpos.xz + vec2(0.0, e), t);
	float calm = 1.0 - smoothstep(60.0, 260.0, dist);
	vec3 wn = normalize(vec3((h0 - hx) * wave_scale * 6.0 * calm, 1.0, (h0 - hz) * wave_scale * 6.0 * calm));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float d01 = clamp(depth / 3.0, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, d01));
	if (real_d >= 0.0) {
		// Profundidad real: orilla y plataforma turquesa → talud → océano profundo.
		float k = clamp(sqrt(real_d / 3500.0), 0.0, 1.0);
		vec3 shelf = mix(vec3(0.17, 0.42, 0.44), vec3(0.09, 0.27, 0.38), smoothstep(0.0, 0.25, k));
		col = mix(shelf, vec3(0.03, 0.1, 0.2), smoothstep(0.2, 0.85, k));
		col = mix(col, vec3(0.3, 0.55, 0.52), coast * 0.4);
		d01 = max(smoothstep(0.0, 0.3, k), 0.35);
	}
	// Espuma en la orilla: bandas que avanzan y se deshacen con ruido.
	float shore = 1.0 - smoothstep(0.0, 0.55, depth);
	float bands = smoothstep(0.55, 0.9, sin(depth * 14.0 - t * 1.8) * 0.5 + 0.5) * (1.0 - smoothstep(0.1, 0.6, depth));
	float foam = clamp(shore * 0.75 + bands * 0.5, 0.0, 1.0) * smoothstep(0.35, 0.65, vnoise(wpos.xz * 1.8 + t * 0.3) + shore * 0.4);
	foam *= 1.0 - smoothstep(80.0, 180.0, dist);
	col = mix(col, foam_color, foam);
	float fres = pow(1.0 - clamp(dot(normalize(-VERTEX), NORMAL), 0.0, 1.0), 4.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(mix(0.55, 0.92, d01) + fres * 0.3 + foam, 0.0, 1.0);
}
