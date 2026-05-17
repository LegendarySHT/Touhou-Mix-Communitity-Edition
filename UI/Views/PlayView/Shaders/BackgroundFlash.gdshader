shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	COLOR = mix(COLOR, flash_color, flash_progress);
}
