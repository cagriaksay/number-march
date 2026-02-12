shader_type canvas_item;

// Pencil effect: makes text look hand-written with graphite on paper.
// Uses screen-space coordinates so the grain is consistent across all text.

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

// Fractional Brownian Motion for richer texture
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float base_alpha = COLOR.a * tex.a;

	if (base_alpha < 0.01) {
		discard;
	}

	// Use screen-space so grain is world-consistent, not per-glyph
	vec2 px = FRAGCOORD.xy;

	// Layer 1: Fine graphite particles (high freq)
	float particles = hash12(px);

	// Layer 2: Pencil stroke texture using fbm
	float pencil_tex = fbm(px * 0.15);

	// Layer 3: Angled hatching (pencil strokes tend to go in one direction)
	float hatch = value_noise(vec2(
		(px.x + px.y * 0.6) * 0.2,
		(px.y - px.x * 0.3) * 0.08
	));

	// Combine into graphite coverage
	// Real pencil: graphite fills paper grooves unevenly
	float coverage = pencil_tex * 0.5 + hatch * 0.3 + particles * 0.2;

	// Remap to useful range: pencil marks are never perfectly solid
	// but should still be clearly readable
	coverage = smoothstep(0.15, 0.65, coverage);  // 0 to 1
	coverage = 0.5 + coverage * 0.5;              // remap to 0.5 - 1.0

	// Keep original font color, apply graphite coverage to alpha
	COLOR = vec4(COLOR.rgb * tex.rgb, base_alpha * coverage);
}
