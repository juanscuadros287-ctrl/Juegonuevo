shader_type spatial;
render_mode cull_back;
// Material único de edificios y modelos de MeshLib (docs/GRAFICOS.md).
// COLOR.rgb = color base (con la variación de tono de cada edificio ya aplicada).
// UV2.x = tipo de material: 0 liso, 1 estuco/adobe, 2 ladrillo, 3 madera, 4 piedra, 5 teja,
//         6 paja, 7 concreto, 8 metal, 9 vidrio, 10 emisivo (farol), 11 postigo de madera.
// UV2.y = azar por pieza (ventanas encendidas de noche, vetas).
// Sombreado plano: la normal sale de las derivadas de pantalla (low-poly limpio y consistente).
// Los patrones son procedurales y sin texturas, baratos en un M1 y en OpenGL.
// Pulido (docs/GRAFICOS.md §10): los patrones van en ESPACIO DEL OBJETO (no del mundo): no se deslizan
// sobre vehículos y personas en movimiento, y en un edificio girado los ladrillos siguen la pared (la
// coordenada horizontal es la tangente real de la cara, sin estirarse a 45°). Juntas y hiladas con
// antialias analítico (fwidth) en lugar de step(): sin dientes ni parpadeo al mover la cámara.

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float detail_fade_start = 70.0;
uniform float detail_fade_end = 140.0;
uniform vec3 window_light = vec3(1.0, 0.72, 0.38);

varying vec3 opos;
varying vec3 onrm;
varying flat vec2 mdata;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	mdata = UV2;
}

// Coordenadas 2D sobre la cara según la normal dominante (u horizontal, v vertical).
vec2 face_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y > 0.7) {
		return p.xz;
	}
	// Tangente horizontal de la cara: el patrón no se estira en paredes que no miran a un eje.
	vec2 t = normalize(vec2(-n.z, n.x) + vec2(1e-5, 0.0));
	return vec2(dot(p.xz, t), p.y);
}

// 1 dentro de una junta de ancho `w` (en fracción de celda) al inicio de la celda, con borde suave.
float joint_aa(float f, float w, float fw) {
	float e = max(fw, 1e-4);
	return 1.0 - smoothstep(w - e, w + e, f);
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VERTEX) > 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 base = COLOR.rgb;
	float kind = floor(mdata.x + 0.5);
	float rnd = mdata.y;
	float dist = length(VERTEX);
	// Los patrones se desvanecen con la distancia (evita moiré y parpadeo).
	float detail = 1.0 - smoothstep(detail_fade_start, detail_fade_end, dist);
	vec3 on = normalize(onrm);
	vec2 uv = face_uv(opos, on);
	float shade = 1.0;
	float rough = 0.88;
	float metal = 0.0;
	float spec = 0.35;
	vec3 emit = vec3(0.0);
	if (kind == 1.0) {
		// Estuco / adobe: manchas suaves.
		shade = 0.94 + 0.08 * vnoise(uv * 1.3) + 0.04 * vnoise(uv * 6.0);
	} else if (kind == 2.0) {
		// Ladrillo: hiladas de 0,22 m y juntas de mortero.
		vec2 b = uv / vec2(0.46, 0.22);
		vec2 fwb = fwidth(uv) / vec2(0.46, 0.22);
		b.x += 0.5 * mod(floor(b.y), 2.0);
		vec2 f = fract(b);
		float mortar = joint_aa(f.y, 0.1, fwb.y) + joint_aa(f.x, 0.05, fwb.x);
		mortar *= 1.0 - smoothstep(0.25, 0.5, max(fwb.x, fwb.y));   // de lejos, sin moiré
		float tone = 0.9 + 0.18 * hash21(floor(b));
		shade = mix(tone, 1.25, clamp(mortar, 0.0, 1.0) * 0.6);
	} else if (kind == 3.0) {
		// Madera: tablas horizontales de 0,28 m con vetas.
		float row = floor(uv.y / 0.28);
		float f = fract(uv.y / 0.28);
		shade = 0.86 + 0.16 * hash21(vec2(row, rnd * 17.0)) + 0.05 * vnoise(vec2(uv.x * 3.0, row * 7.0));
		shade *= mix(0.72, 1.0, smoothstep(0.0, 0.08 + fwidth(uv.y / 0.28), f));
	} else if (kind == 4.0) {
		// Piedra: bloques irregulares.
		vec2 b = uv / vec2(0.7, 0.4);
		vec2 fwb = fwidth(uv) / vec2(0.7, 0.4);
		b.x += 0.37 * mod(floor(b.y), 3.0);
		vec2 f = fract(b);
		float joint = (joint_aa(f.y, 0.08, fwb.y) + joint_aa(f.x, 0.05, fwb.x)) * (1.0 - smoothstep(0.25, 0.5, max(fwb.x, fwb.y)));
		shade = mix(0.82 + 0.26 * hash21(floor(b)), 0.62, clamp(joint, 0.0, 1.0));
		shade *= 0.95 + 0.1 * vnoise(uv * 4.0);
	} else if (kind == 5.0) {
		// Teja: hileras onduladas a lo largo de la pendiente.
		float row = floor(opos.y / 0.24);
		float f = fract(opos.y / 0.24);
		float along = (abs(on.x) > abs(on.z)) ? opos.z : opos.x;
		float wave = 0.5 + 0.5 * sin(along * 20.0);
		shade = (0.84 + 0.12 * wave + 0.08 * hash21(vec2(row, floor(along * 3.2)))) * mix(0.7, 1.0, smoothstep(0.0, 0.2, f));
	} else if (kind == 6.0) {
		// Paja: fibras.
		float along = (abs(on.x) > abs(on.z)) ? opos.z : opos.x;
		shade = 0.84 + 0.2 * vnoise(vec2(along * 14.0, opos.y * 1.5)) + 0.06 * vnoise(vec2(along * 40.0, opos.y * 3.0)) * detail;
		shade *= mix(0.78, 1.0, smoothstep(0.0, 0.25, fract(opos.y / 0.45)));
	} else if (kind == 7.0) {
		// Concreto: paneles grandes.
		vec2 f = fract(uv / vec2(3.0, 1.5));
		vec2 fwc = fwidth(uv) / vec2(3.0, 1.5);
		float joint = joint_aa(f.y, 0.02, fwc.y) + joint_aa(f.x, 0.01, fwc.x);
		shade = (0.93 + 0.07 * vnoise(uv * 2.0)) * mix(1.0, 0.8, clamp(joint, 0.0, 1.0));
	} else if (kind == 8.0) {
		// Metal corrugado.
		// Corrugado: la onda se apaga cuando su período baja de ~3 píxeles (sin moiré).
		shade = 0.88 + 0.12 * sin(uv.x * 30.0) * (1.0 - smoothstep(0.08, 0.2, fwidth(uv.x)));
		rough = 0.45;
		metal = 0.35;
		spec = 0.6;
	} else if (kind == 9.0) {
		// Vidrio: brillante; de noche algunas ventanas se encienden (según el azar de la pieza).
		rough = 0.12;
		metal = 0.25;
		spec = 0.8;
		float lit = step(0.35, fract(rnd * 7.31 + floor(opos.y / 2.6) * 0.37 + floor((opos.x + opos.z) / 2.2) * 0.23));
		emit = window_light * lit * night * 1.6;
		base = mix(base, base * 0.35, night * lit);
	} else if (kind == 11.0) {
		// Postigo de madera: tablas verticales; de noche, luz cálida entre las rendijas.
		float f = fract((uv.x + uv.y * 0.001) / 0.16);
		shade = (0.85 + 0.15 * hash21(vec2(floor(uv.x / 0.16), rnd * 9.0))) * mix(0.6, 1.0, smoothstep(0.0, 0.15, f));
		float lit = step(0.3, fract(rnd * 5.17 + 0.2));
		emit = window_light * lit * night * mix(1.6, 0.45, smoothstep(0.0, 0.2, f));
	} else if (kind == 10.0) {
		rough = 0.5;
		emit = base * (0.25 + night * 3.0);
	}
	shade = mix(1.0, shade, detail);
	ALBEDO = base * shade;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
