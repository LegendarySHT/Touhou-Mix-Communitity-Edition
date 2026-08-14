class_name GlowLayer
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

# _draw 遍历用：复用常量，避免每帧分配 [Block, Slide] 数组字面量
const _BLOCK_SLIDE_TYPES: Array = [FlowNote.NoteType.Block, FlowNote.NoteType.Slide]

var _drawer: NoteBatchDrawer = null

func _draw() -> void:
	if _drawer == null:
		return
	var glow_tex = _drawer._glow_tex
	if glow_tex == null:
		return
	var buckets = _drawer._note_buckets
	if buckets == null or buckets.is_empty():
		return

	var view_h = _drawer._viewport_height
	var top_limit = -_drawer._cull_margin_top
	var bottom_limit = view_h + _drawer._cull_margin_bottom
	var note_width = _drawer._note_width
	var glow_intensity = _drawer._glow_intensity

	# 只跳过已移除音符：Long 被按住时 is_judged=true 但仍需显示光效
	# 分桶遍历：Block/Slide 一遍 + Long 一遍（绘制逻辑与单数组模型一致，仅遍历结构变化）

	# Block/Slide：每音符一个与音符尺寸一致的方形光效
	for type_key in _BLOCK_SLIDE_TYPES:
		var type_bucket: Dictionary = buckets[type_key]  # set_notes_source 后三级键必存在
		for color_key in type_bucket:
			# 同色桶共用同一 modulate（桶键即音符颜色），逐音符构造 Color 是纯浪费
			var glow_modulate := Color(color_key.r, color_key.g, color_key.b, color_key.a * glow_intensity)
			for note in type_bucket[color_key]:
				if note.is_removed:
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
				draw_texture_rect(glow_tex, rect, false, glow_modulate)

	# Long：头尾各一个与 Block/Slide 相同的方形光效（直接复用现有 glow 纹理）
	# 旧 NoteGlow shader 因尺寸设置问题需横向拉伸补偿，此处统一为方块光效
	# 手写头/尾两段（原 for part in [[..],[..]] 每 Long 每帧分配 2 个数组字面量）
	var long_bucket: Dictionary = buckets[FlowNote.NoteType.Long]
	for color_key in long_bucket:
		var glow_modulate := Color(color_key.r, color_key.g, color_key.b, color_key.a * glow_intensity)
		for note in long_bucket[color_key]:
			if note.is_removed:
				continue
			var cx : float = note.cached_center_x
			# head 光效
			var head_cy: float = note.cached_head_center_y
			var head_half: float = note.cached_head_half_height
			if head_cy + head_half >= top_limit and head_cy - head_half <= bottom_limit:
				var head_glow := maxf(note_width, head_half * 2.0) * GLOW_QUAD_SCALE
				draw_texture_rect(glow_tex, Rect2(cx - head_glow * 0.5, head_cy - head_glow * 0.5, head_glow, head_glow), false, glow_modulate)
			# tail 光效
			var tail_cy: float = note.cached_tail_center_y
			var tail_half: float = note.cached_tail_half_height
			if tail_cy + tail_half >= top_limit and tail_cy - tail_half <= bottom_limit:
				var tail_glow := maxf(note_width, tail_half * 2.0) * GLOW_QUAD_SCALE
				draw_texture_rect(glow_tex, Rect2(cx - tail_glow * 0.5, tail_cy - tail_glow * 0.5, tail_glow, tail_glow), false, glow_modulate)
