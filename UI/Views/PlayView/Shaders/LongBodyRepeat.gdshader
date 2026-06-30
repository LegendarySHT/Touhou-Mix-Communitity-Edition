shader_type canvas_item;
render_mode unshaded;

// 垂直方向重复次数 = 节点高度(像素) / 贴图原始高度(像素)
// 水平方向 UV 保持 0-1（拉伸填充整个节点宽度），垂直方向按贴图原始高度重复
uniform float v_repeat = 1.0;

void fragment() {
	vec2 uv = vec2(UV.x, fract(UV.y * v_repeat));
	COLOR = texture(TEXTURE, uv);
}
