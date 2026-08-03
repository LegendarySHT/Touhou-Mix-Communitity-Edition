shader_type canvas_item;
// 黄金角螺旋盘形散景模糊（gather，一次性烘焙成静态纹理）
//
// 设计要点：
// - 软边盘权重：中心平坦、边缘 smoothstep 过渡，无硬边、无环状伪影
// - 亮度加权：高光采样贡献放大（~1.5x），小亮点被摊成散景碟形
// - 黄金角螺旋均匀覆盖圆盘：256 采样在半径 ~24px 内采样间隙 <1.5px，不产生采样结构
// - 不依赖 mipmap LOD（那是原版"水彩糊"观感的来源）
uniform float blur_strength : hint_range(0.0, 1.0) = 0.35;
uniform float max_radius : hint_range(1.0, 64.0) = 40.0; // 烘焙分辨率下的最大纹素半径
uniform float saturation : hint_range(0.5, 2.0) = 1.15; // 模糊后饱和度恢复，抵消洗白感

const int SAMPLES = 256;
const float GOLDEN_ANGLE = 2.399963229728653;

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	float radius = max(1.0, blur_strength * max_radius);

	vec4 accum = vec4(0.0);
	float total = 0.0;

	for (int i = 0; i < SAMPLES; i++) {
		float fi = float(i) + 0.5;
		// sqrt 让螺旋点密度在圆盘内均匀（而不是中心密边缘疏）
		float r = sqrt(fi / float(SAMPLES)) * radius;
		float a = float(i) * GOLDEN_ANGLE;
		vec2 off = vec2(cos(a), sin(a)) * (r * texel);
		vec4 c = texture(TEXTURE, UV + off);
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		// 软边盘：半径 <0.55R 权重平坦，0.55R~R 平滑衰减到 0
		float w = 1.0 - smoothstep(radius * 0.55, radius, r);
		// 亮度加权：暗色贡献 0.8、亮色 1.2，高光轻微摊成散景碟。
		// 系数不宜过大（过高 → 洗白/凹凸毛玻璃感）
		accum += c * (w * (0.8 + l * 0.4));
		total += w * (0.8 + l * 0.4);
	}

	// 中心补一点原始细节，避免整体糊成纯色块（保留明暗轮廓）
	float cw = 1.0 + radius * 0.08;
	accum += texture(TEXTURE, UV) * cw;
	total += cw;

	COLOR = accum / total;

	// 模糊会让颜色平均化（降饱和 → 洗白感），做饱和度恢复抵消
	float l_out = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(vec3(l_out), COLOR.rgb, saturation);
}
