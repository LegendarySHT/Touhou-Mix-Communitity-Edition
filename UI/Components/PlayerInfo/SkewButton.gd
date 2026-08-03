extends Button
class_name SkewButton

## 带 skew 倾斜点击判定的 Button
## StyleBoxFlat.skew 只改变绘制形状，不改变 Control 的矩形点击区域，
## 导致倾斜后视觉边缘点不到 / 矩形空白处也能点。
## 本类重写 _has_point()，让点击区域与倾斜后的平行四边形一致，
## Button 的 hover/pressed 反馈会自动基于此判定工作。
##
## skew_x 语义与 StyleBoxFlat.skew.x 一致：
##   > 0：顶部往右偏（右侧向下倾斜的平行四边形）
##   < 0：顶部往左偏
##   = 0：退化为矩形判定

@export var skew_x: float = 0.0

## _has_point 的 point 是相对控件左上角的局部坐标（矩形 [0,w]×[0,h]）
## Godot 源码 StyleBoxFlat::draw_rounded_rectangle 中 skew 变换为：
##   x_skew = -skew.x * (y - style_rect_center.y)
##   x' = x + x_skew = x - skew.x * (y - h/2)
## 所以 skew.x > 0 时：顶部往右偏，底部往左偏（从右上往左下倾斜的平行四边形）
## 变换后顶点：顶部左(skew*h/2,0) 顶部右(w+skew*h/2,0)
##             底部左(-skew*h/2,h) 底部右(w-skew*h/2,h)
## 在 y=py 处，x 范围为 [skew_x*(h/2-py), w + skew_x*(h/2-py)]
##
## 重写 _has_point 会完全替代默认矩形检查，矩形外的点也会被传入判定，
## 因此凸出矩形外的部分也能返回 true 被点击。
func _has_point(point: Vector2) -> bool:
	var w := size.x
	var h := size.y
	if h <= 0.0 or w <= 0.0:
		return false
	# y 方向有界：超出 [0, h] 的点不在平行四边形内
	if point.y < 0.0 or point.y > h:
		return false
	var offset := skew_x * (h * 0.5 - point.y)
	return point.x >= offset and point.x <= w + offset
