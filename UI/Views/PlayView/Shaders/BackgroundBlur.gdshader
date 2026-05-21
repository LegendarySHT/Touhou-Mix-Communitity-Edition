shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float lod_base = blur_strength * 7.0;
	vec2 step = TEXTURE_PIXEL_SIZE * blur_strength * 12.0;
	const float ga = 2.399963;

	vec4 accum = vec4(0.0);
	float total_w = 0.0;

	for (int i = 0; i < 16; i++) {
		float r = sqrt((float(i) + 0.5) / 16.0);
		float a = float(i) * ga;
		vec2 off = vec2(cos(a), sin(a)) * r * step;
		float w = exp(-r * 4.0);
		accum += textureLod(TEXTURE, UV + off, lod_base) * w;
		total_w += w;
	}

	COLOR = accum / total_w;
}
