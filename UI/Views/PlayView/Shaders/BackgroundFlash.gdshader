shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_progress : hint_range(0.0, 1.0) = 0.0;
uniform float flash_radius : hint_range(0.3, 1.5) = 0.85;

void fragment() {
	float dist = length(UV - vec2(0.5, 0.5));
	float radial = 1.0 - smoothstep(flash_radius * 0.35, flash_radius, dist);
	float progress = flash_progress * radial;
	COLOR = mix(COLOR, flash_color, progress);
}
