shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float glow_size : hint_range(1.0, 30.0) = 15.0;
uniform float glow_stretch = 0.7;
uniform vec2 note_uv_center = vec2(0.5, 0.5);
uniform vec2 note_uv_half = vec2(0.1667, 0.1667);

void fragment() {
	vec2 note_coord = (UV - note_uv_center) / note_uv_half;
	float dist = length(note_coord / vec2(glow_stretch, 1.0));
	// 与 GlowLayer 烘焙一致：高斯径向衰减 exp(-(dist/σ)²)，σ 由 glow_size 映射
	float sigma = 0.6 + glow_size * (1.5 - 0.6) / 30.0;
	// Long 贡献为 glow²（glow 同时进 RGB 和 alpha），peak 取 sqrt(0.45)≈0.67 使有效峰值与 GlowLayer 一致
	float glow = 0.67 * exp(-(dist * dist) / (sigma * sigma));
	// 强度只进 alpha 通道：加色混合按 src.rgb * src.a 计算，RGB/alpha 都乘强度会平方
	// 有效贡献 = glow_color.rgb * glow * intensity（线性），与 GlowLayer 的光效一致
	COLOR = vec4(glow_color.rgb * glow, glow_color.a * glow * glow_intensity);
}
