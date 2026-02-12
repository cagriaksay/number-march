shader_type canvas_item;

// Pencil graphite shader: lightweight version for mobile.
// Keeps the pencil-on-paper aesthetic but with much less per-pixel work.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x),
		f.y
	);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float base_alpha = COLOR.a * tex.a;

	if (base_alpha < 0.01) {
		discard;
	}

	vec2 px = FRAGCOORD.xy;

	// ── Paper grain: single-frequency noise for paper tooth ──
	float grain = hash12(px) * 0.6 + hash12(px * 0.5 + 7.3) * 0.4;

	// ── Graphite texture: single noise layer (was 5-octave fbm) ──
	float graphite = value_noise(px * 0.12);

	// ── Directional hatching: one direction only ──
	float angle = (px.x * 0.7 + px.y) * 0.18;
	float hatching = value_noise(vec2(angle, px.y * 0.05));

	// ── Pixel dropout: some pixels are bare paper ──
	float dropout = step(0.88, hash12(px + 3.7));

	// ── Combine ──
	float coverage = grain * 0.4 + graphite * 0.3 + hatching * 0.3;
	coverage = smoothstep(0.08, 0.55, coverage);
	coverage *= (1.0 - dropout * 0.5);

	float final_alpha = 0.35 + coverage * 0.6;

	// ── Slight warm tint ──
	vec3 base_color = COLOR.rgb * tex.rgb;
	base_color *= vec3(1.02, 1.005, 0.98);

	COLOR = vec4(base_color, base_alpha * final_alpha);
}
