extends Node2D

## NoteBatchDrawer 的光效子层
## 使用加色混合（BLEND_MODE_ADD）绘制 glow 纹理
## 直接读父节点 NoteBatchDrawer 的字段，避免数据同步开销

var _drawer: NoteBatchDrawer = null

func _draw() -> void:
	if _drawer == null:
		return
	var glow_tex = _drawer._glow_tex
	if glow_tex == null:
		return
	var notes = _drawer._notes
	if notes.is_empty():
		return

	var view_h = _drawer._viewport_height
	var top_limit = -_drawer._cull_margin_top
	var bottom_limit = view_h + _drawer._cull_margin_bottom
	var note_width = _drawer._note_width
	var glow_intensity = _drawer._glow_intensity

	for note in notes:
		if note.is_judged or note.is_removed:
			continue
		var cy = note.cached_center_y
		var half_h = note.cached_half_height
		if cy + half_h < top_limit or cy - half_h > bottom_limit:
			continue
		var is_slide = note.type == FlowNote.NoteType.Slide
		var color = _drawer._slide_color if is_slide else _drawer._block_color
		# 方形光效矩形：取音符宽高较大值 × 2，避免方形纹理被非均匀拉伸
		# 原 ColorRect anchors -1..2 在非方形音符上会导致光效横向拉伸
		var note_height = half_h * 2.0
		var glow_size = maxf(note_width, note_height) * 2.0
		var rect = Rect2(note.cached_center_x - glow_size * 0.5, cy - glow_size * 0.5, glow_size, glow_size)
		draw_texture_rect(glow_tex, rect, false, color * glow_intensity)
