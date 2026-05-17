shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float glow_size : hint_range(1.0, 30.0) = 15.0;

void fragment() {
	float dist = length(UV - 0.5) * 2.0;
	float radial = exp(-dist * dist / max(glow_size * 0.003, 0.0001));
	COLOR = glow_color * radial * glow_intensity;
}
