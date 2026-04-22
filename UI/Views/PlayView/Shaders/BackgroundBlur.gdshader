shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 screen_texel = SCREEN_PIXEL_SIZE;
	vec2 texture_size = 1.0 / max(texel, vec2(0.000001));
	vec2 screen_size = 1.0 / max(screen_texel, vec2(0.000001));
	float upscale = max(screen_size.x / texture_size.x, screen_size.y / texture_size.y);
	float upscale_factor = clamp((upscale - 1.0) / 3.0, 0.0, 1.0);
	float strength = clamp(blur_strength, 0.0, 1.0);
	float lod_main = mix(0.0, 9.5, pow(strength, 1.05)) * mix(1.0, 1.25, upscale_factor);
	float lod_near = lod_main * 0.55;
	float lod_far = lod_main * 1.25;
	vec2 lod_step = mix(texel, screen_texel, upscale_factor) * mix(0.0, 2.4, pow(strength, 1.1));

	vec4 accum = vec4(0.0);
	float weight = 0.0;

	float base_w = mix(0.70, 0.06, strength);
	accum += textureLod(TEXTURE, UV, lod_near) * base_w;
	weight += base_w;

	float ring_w = mix(0.035, 0.095, strength);
	accum += textureLod(TEXTURE, UV + vec2(1.0, 0.0) * lod_step, lod_main) * ring_w;
	accum += textureLod(TEXTURE, UV + vec2(-1.0, 0.0) * lod_step, lod_main) * ring_w;
	accum += textureLod(TEXTURE, UV + vec2(0.0, 1.0) * lod_step, lod_main) * ring_w;
	accum += textureLod(TEXTURE, UV + vec2(0.0, -1.0) * lod_step, lod_main) * ring_w;
	weight += ring_w * 4.0;

	float diag_w = mix(0.020, 0.070, strength);
	accum += textureLod(TEXTURE, UV + vec2(0.70710678, 0.70710678) * lod_step, lod_main + 0.6) * diag_w;
	accum += textureLod(TEXTURE, UV + vec2(-0.70710678, 0.70710678) * lod_step, lod_main + 0.6) * diag_w;
	accum += textureLod(TEXTURE, UV + vec2(0.70710678, -0.70710678) * lod_step, lod_main + 0.6) * diag_w;
	accum += textureLod(TEXTURE, UV + vec2(-0.70710678, -0.70710678) * lod_step, lod_main + 0.6) * diag_w;
	weight += diag_w * 4.0;

	float far_w = mix(0.0, 0.040, strength);
	vec2 far_step = lod_step * 1.9;
	accum += textureLod(TEXTURE, UV + vec2(0.92387953, 0.38268343) * far_step, lod_far) * far_w;
	accum += textureLod(TEXTURE, UV + vec2(-0.38268343, 0.92387953) * far_step, lod_far) * far_w;
	accum += textureLod(TEXTURE, UV + vec2(-0.92387953, -0.38268343) * far_step, lod_far) * far_w;
	accum += textureLod(TEXTURE, UV + vec2(0.38268343, -0.92387953) * far_step, lod_far) * far_w;
	weight += far_w * 4.0;

	COLOR = accum / max(weight, 0.0001);
}
