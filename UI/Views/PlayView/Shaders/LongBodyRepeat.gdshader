shader_type canvas_item;
render_mode unshaded;

// 垂直方向重复次数 = 节点高度(像素) / 贴图原始高度(像素)
// 水平方向 UV 保持 0-1（拉伸填充整个节点宽度），垂直方向按贴图原始高度重复
uniform float v_repeat = 1.0;

// Godot 4.7 中 canvas_item shader 不再自动对 fragment 输出应用 modulate 链。
// vertex() 中 COLOR 内置变量包含完整的 modulate * self_modulate * 父节点链，
// 通过 varying 传到 fragment() 显式乘回，恢复对 body/core 的着色效果。
varying vec4 modulate_chain;

void vertex() {
	modulate_chain = COLOR;
}

void fragment() {
	vec2 uv = vec2(UV.x, fract(UV.y * v_repeat));
	COLOR = texture(TEXTURE, uv) * modulate_chain;
}
