extends Node2D

## NoteBatchDrawer 的光效子层
## 使用加色混合（BLEND_MODE_ADD）绘制 glow 纹理
## 直接读父节点 NoteBatchDrawer 的字段，避免数据同步开销

# 光效 quad 相对音符尺寸的倍数（原为 2.0）。
# 随谱面密度线性增长（每个活跃音符每帧一张加色大 quad）。
# 注意取舍：glow 高斯纹理是整体拉伸到 quad 上的，quad 变小光晕在屏幕空间会同步收紧
# ~30%（各 glow_size 下比例一致），并非纯减填充零视觉变化；想视觉完全不变需在
# _bake_glow_texture 里放大 σ 抵消（NoteGlow shader 仅剩 NoteSkinAdjust 皮肤预览使用，运行时 Long 走本层方形光效），此处先做纯缩 quad。
const GLOW_QUAD_SCALE := 1.6

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

	# 只跳过已移除音符：Long 被按住时 is_judged=true 但仍需显示光效
	for note in notes:
		if note.is_removed:
			continue
		var color = note.cached_color
		if note.type == FlowNote.NoteType.Long:
			# Long：头尾各一个与 Block/Slide 相同的方形光效（直接复用现有 glow 纹理）
			# 旧 NoteGlow shader 因尺寸设置问题需横向拉伸补偿，此处统一为方块光效
			for part in [[note.cached_head_center_y, note.cached_head_half_height], [note.cached_tail_center_y, note.cached_tail_half_height]]:
				var cy = part[0]
				var half_h = part[1]
				if cy + half_h < top_limit or cy - half_h > bottom_limit:
					continue
				var part_height = half_h * 2.0
				var part_glow = maxf(note_width, part_height) * GLOW_QUAD_SCALE
				var rect = Rect2(note.cached_center_x - part_glow * 0.5, cy - part_glow * 0.5, part_glow, part_glow)
				var glow_modulate := Color(color.r, color.g, color.b, color.a * glow_intensity)
				draw_texture_rect(glow_tex, rect, false, glow_modulate)
			continue
		var cy = note.cached_center_y
		var half_h = note.cached_half_height
		if cy + half_h < top_limit or cy - half_h > bottom_limit:
			continue
		# 方形光效矩形：取音符宽高较大值 × 2，避免方形纹理被非均匀拉伸
		# 原 ColorRect anchors -1..2 在非方形音符上会导致光效横向拉伸
		var note_height = half_h * 2.0
		var glow_size = maxf(note_width, note_height) * GLOW_QUAD_SCALE
		var rect = Rect2(note.cached_center_x - glow_size * 0.5, cy - glow_size * 0.5, glow_size, glow_size)
		# 强度只乘 alpha 通道：加色混合按 src.rgb * src.a 计算，若 RGB 和 alpha 都乘强度会被平方
		# 有效贡献 = color.rgb * glow * intensity（线性），intensity = 1 时与旧行为完全一致
		var glow_modulate := Color(color.r, color.g, color.b, color.a * glow_intensity)
		draw_texture_rect(glow_tex, rect, false, glow_modulate)
