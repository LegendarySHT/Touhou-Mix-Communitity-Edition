shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float glow_size : hint_range(1.0, 30.0) = 15.0;
uniform float glow_falloff : hint_range(0.5, 3.0) = 1.2;
uniform float glow_stretch = 0.7;
uniform vec2 note_uv_center = vec2(0.5, 0.5);
uniform vec2 note_uv_half = vec2(0.1667, 0.1667);

void fragment() {
	vec2 note_coord = (UV - note_uv_center) / note_uv_half;
	float dist = length(note_coord / vec2(glow_stretch, 1.0));
	float max_dist = 1.0 + glow_size * 0.2;
	float t = clamp(dist / max_dist, 0.0, 1.0);
	float inner = 1.0 - smoothstep(0.0, 1.0, t);
	float outer = exp(-dist * dist * glow_falloff);
	float glow = glow_intensity * mix(outer, inner, 0.65);
	COLOR = glow_color * glow;
}
