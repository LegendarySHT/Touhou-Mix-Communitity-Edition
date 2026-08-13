## 非键盘模式全局随机音符调色板生成器
## 规则：short=点块、instant=滑块、long=长条的色相两两环距 >= 30°；
## 饱和度 0.8~1.0，亮度 0.9~1.0；unified=true 时三种类型共用同一颜色。
class_name NoteColorPalette
extends RefCounted

static func generate(unified: bool) -> Dictionary:
	var saturation := randf_range(0.8, 1.0)
	var value := randf_range(0.9, 1.0)
	if unified:
		var hue := randf()
		var color := Color.from_hsv(hue, saturation, value)
		return {"short": color, "instant": color, "long": color}

	var h0 := randf() * 360.0
	var h1 := h0 + 30.0 + randf() * 150.0
	var h2 := h1 + 30.0 + randf() * (300.0 - (h1 - h0))
	return {
		"short": Color.from_hsv(fposmod(h0, 360.0) / 360.0, saturation, value),
		"instant": Color.from_hsv(fposmod(h1, 360.0) / 360.0, saturation, value),
		"long": Color.from_hsv(fposmod(h2, 360.0) / 360.0, saturation, value),
	}
