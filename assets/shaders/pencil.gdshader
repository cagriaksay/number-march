shader_type canvas_item;

// Pencil graphite shader: realistic pencil-on-paper look.
// Graphite fills paper grooves unevenly, has directional strokes,
// fine grain particles, and subtle warm/cool color shifts.

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

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < octaves; i++) {
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

	vec2 px = FRAGCOORD.xy;

	// ── Paper grain: rough paper surface — graphite only fills the peaks ──
	// Multiple frequencies of grain for realistic paper tooth
	float grain_fine = hash12(px);
	float grain_med = hash12(px * 0.5 + 7.3);
	float paper_grain = grain_fine * 0.6 + grain_med * 0.4;

	// ── Graphite texture: uneven pressure across the stroke ──
	float graphite = fbm(px * 0.12, 5);

	// ── Directional hatching: visible pencil stroke direction ──
	float angle1 = (px.x * 0.7 + px.y) * 0.18;
	float angle2 = (px.x * 0.3 - px.y * 0.8) * 0.12;
	float hatch1 = value_noise(vec2(angle1, px.y * 0.05));
	float hatch2 = value_noise(vec2(angle2, px.x * 0.07));
	float hatching = hatch1 * 0.6 + hatch2 * 0.4;

	// ── Pixel-level grain: individual graphite particles ──
	float pixel_grain = hash12(px * 1.0 + 3.7);
	// Some pixels are just bare paper (graphite didn't stick)
	float dropout = step(0.88, pixel_grain);  // ~12% of pixels drop out

	// ── Graphite sheen: rare bright flecks ──
	float flecks = hash12(px * 0.8);
	float sparkle = smoothstep(0.80, 0.86, flecks);

	// ── Combine: paper grain dominates for that grainy look ──
	float coverage = paper_grain * 0.45 + graphite * 0.25 + hatching * 0.30;

	// Harsh smoothstep for more contrast between filled/unfilled paper grooves
	coverage = smoothstep(0.08, 0.55, coverage);

	// Apply dropouts and sparkle
	coverage = coverage * (1.0 - dropout * 0.6) * (1.0 - sparkle * 0.4);

	// Map to final alpha: wider range = grainier appearance
	float final_alpha = 0.3 + coverage * 0.65;

	// ── Color warmth: graphite isn't pure black, it shifts slightly warm ──
	vec3 base_color = COLOR.rgb * tex.rgb;
	float warmth = value_noise(px * 0.08) * 0.08;
	// Shift toward warm gray slightly (pencil graphite has a slight brown/warm tint)
	base_color = mix(base_color, base_color * vec3(1.04, 1.01, 0.96), warmth);

	COLOR = vec4(base_color, base_alpha * final_alpha);
}
