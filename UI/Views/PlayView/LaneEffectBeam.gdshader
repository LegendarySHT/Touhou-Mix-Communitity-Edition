shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 lane_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float beam_alpha = 1.0;
uniform float trigger_time = -1000.0;
uniform float current_time = 0.0;
uniform float inv_fade_duration = 2.5;
uniform float discard_threshold = 0.02;
uniform float beam_width = 100.0;
uniform float beam_height = 720.0;
uniform float center_inset = 20.0;
uniform float light_height = 3.0;

void fragment() {
	float elapsed = max(0.0, current_time - trigger_time);
	float decay = clamp(1.0 - elapsed * inv_fade_duration, 0.0, 1.0);

	vec2 size = vec2(max(beam_width, 1.0), max(beam_height, 1.0));
	vec2 px = UV * size;
	float x = px.x;

	float edge_soft = max(1.0, size.x * 0.045);
	float left_edge = smoothstep(0.0, edge_soft, x);
	float right_edge = smoothstep(0.0, edge_soft, size.x - x);
	float outer_x = min(left_edge, right_edge);

	float inset = clamp(center_inset, 0.0, size.x * 0.49);
	float center_soft = max(1.0, size.x * 0.06);
	float center_mask = smoothstep(inset, inset + center_soft, x) * (1.0 - smoothstep(size.x - inset - center_soft, size.x - inset, x));

	float outer_y = mix(0.055, 0.235, UV.y);
	float center_y = mix(0.467, 0.800, UV.y);
	float highlight_h = clamp(light_height / size.y, 0.0, 1.0);
	float highlight = smoothstep(1.0 - highlight_h, 1.0, UV.y);

	float lane_strength = beam_alpha * decay;
	float alpha = lane_strength * max(outer_x * outer_y, center_mask * center_y);
	alpha = max(alpha, lane_strength * highlight * 0.9);

	if (alpha < discard_threshold || decay <= 0.0) {
		discard;
	}

	vec3 color = mix(vec3(1.0), lane_color.rgb, center_mask);
	color += vec3(0.15) * highlight;
	COLOR = vec4(color, alpha);
}