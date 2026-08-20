## 主题管理器（单例）
## 统一管理全局颜色调色板、背景图片和字号配置
## 通过 autoload 注册，引擎启动时自动实例化
##
## 颜色来源：theme.ini 的 [preset_*] 段 → active_preset 选择 → _palette（7 色）
## 背景色由 primary_dark 自动衍生，语义色（danger/success 等）写死在代码中
##
## 外部接口：
##   ThemeMGR.get_color("primary")
##   ThemeMGR.apply_preset("pink")
##   ThemeMGR.refresh_theme_only()   # 主题变更后刷新主题色（不刷新背景）
##   ThemeMGR.refresh_backgrounds()  # 仅刷新背景（给设置界面）
class_name ThemeManager
extends Node

func _ready() -> void:
	add_to_group("singletons")
	load_theme()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SECONDS
	_save_timer.timeout.connect(_flush_scheduled_save)
	add_child(_save_timer)
	if EvtBus:
		EvtBus.theme_changed.connect(_on_theme_changed)
	# 监听 UI 状态变化，触发主背景交叉淡入淡出
	if UiStatMGR:
		UiStatMGR.state_changed.connect(_on_state_changed_for_bg)
	# 延迟初始化主背景节点引用，确保 PathRegistry.MAIN 已就绪
	call_deferred("_init_main_bg_nodes")

# ============ 配置路径 ============

const DEFAULT_THEME_PATH := "res://Resources/Config/theme.ini"
const DEFAULT_PRESET := "blue"

# 共享按钮 Theme 资源（几何参数收在 .tres，颜色由本管理器按主题统一刷新）
const SHARED_LIST_BTN_THEME_PATH := "res://UI/Theme/BtnTheme/ListBtn-ColorBorder.tres"
const SHARED_R12_BTN_THEME_PATH := "res://UI/Theme/BtnTheme/R12NoBorder.tres"

static var USER_THEME_PATH: String:
	get: return PathHelper.get_files_dir() + "theme.ini"

# ============ 内部状态 ============

var _palette: Dictionary = {}
var _font_sizes: Dictionary = {}
var _backgrounds: Dictionary = {}
var _presets: Dictionary = {}
var _theme_name: String = "default"
var _loaded: bool = false

# 背景图片纹理缓存（file_name → Texture2D），避免主题切换时重复读盘
var _bg_image_cache: Dictionary = {}

# 主题保存防抖（颜色选择器拖动等高频回调只落盘一次）
var _save_timer: Timer = null
var _save_pending: bool = false
const SAVE_DEBOUNCE_SECONDS := 0.25

# 背景图异步加载（TMX-037）：缓存未命中时由后台线程读盘，避免主线程同步 IO 卡顿
var _bg_load_thread: Thread = null
var _bg_pending_rects: Dictionary = {}   # file_name -> Array[{rect, stretch}]
var _bg_load_queue: Array[String] = []

# 固定色 — 不从预设中读取
const PANEL_BG := Color("#161A2E")       # 面板背景
const SIDEBAR_BG := Color("#080C16")     # 侧边栏最深背景
const CARD_BG := Color("#1E2A40")        # 卡片/按钮次级背景
const DANGER_COLOR := Color("#FF5555")   # 删除/危险操作
const SUCCESS_COLOR := Color("#55DD88")  # 成功/确认
const WARNING_COLOR := Color("#FFCC44")  # 警告
const INFO_COLOR := Color("#55AAFF")     # 信息提示

# ============ 颜色 API ============

func get_color(key: String, default: Color = Color.WHITE) -> Color:
	var k := key.to_lower()
	if _palette.has(k):
		return _palette[k]
	GLogger.warning("Theme color key not found: %s" % key, "ThemeManager")
	return default

func set_color(key: String, value: Color) -> void:
	# 注意：此方法会立即同步落盘 + 触发完整主题刷新（含 4 帧分帧），
	# 不适合连接到颜色选择器拖动等高频回调（每帧调用会堆叠 I/O 与 refresh 协程）。
	_palette[key.to_lower()] = value
	GLogger.info("Theme color changed: %s = %s" % [key, value.to_html(true)], "ThemeManager")
	_schedule_save_theme()
	refresh_theme_only()
	if EvtBus:
		EvtBus.theme_changed.emit(_theme_name)

# ============ 预设颜色方案 ============

func get_available_presets() -> PackedStringArray:
	var names: PackedStringArray = []
	for key in _presets:
		names.append(key)
	return names

func apply_preset(preset_name: String) -> void:
	if not _presets.has(preset_name):
		GLogger.warning("预设不存在: %s，回退到 %s" % [preset_name, DEFAULT_PRESET], "ThemeManager")
		if preset_name != DEFAULT_PRESET and _presets.has(DEFAULT_PRESET):
			apply_preset(DEFAULT_PRESET)
		return

	var p: Dictionary = _presets[preset_name]
	for key in p:
		var val: String = p[key]
		if val.is_valid_html_color():
			_palette[key.to_lower()] = Color(val)

	_theme_name = preset_name
	GLogger.info("主题预设已应用: %s (%d 色)" % [preset_name, _palette.size()], "ThemeManager")

	# apply_preset 自身负责 save + refresh；emit theme_changed 仅通知外部监听者
	# _on_theme_changed 收到信号时 _theme_name 已等于 preset_name，会跳过 re-apply 并跳过重复 save/refresh
	save_theme()
	refresh_theme_only()
	if EvtBus:
		EvtBus.theme_changed.emit(_theme_name)

func set_palette_colors(pri: Color, pri_light: Color, pri_dark: Color) -> void:
	_palette["primary"] = pri
	_palette["primary_light"] = pri_light
	_palette["primary_dark"] = pri_dark
	_theme_name = "custom"
	GLogger.info("主题色已自定义设置", "ThemeManager")
	_schedule_save_theme()
	refresh_theme_only()
	if EvtBus:
		EvtBus.theme_changed.emit(_theme_name)

# ============ 主题加载/保存 ============

func load_theme(file_path: String = "") -> bool:
	_palette.clear()
	_presets.clear()
	_font_sizes.clear()
	_backgrounds.clear()

	var default_cfg := ConfigManager.instance.load_config(DEFAULT_THEME_PATH)
	if default_cfg.is_empty():
		push_error("ThemeManager: 默认主题配置加载失败: " + DEFAULT_THEME_PATH)
		return false

	var user_path := file_path if not file_path.is_empty() else USER_THEME_PATH
	var user_cfg: Dictionary = {}
	if FileAccess.file_exists(user_path):
		user_cfg = ConfigManager.instance.load_config(user_path)

	var merged := ConfigManager.instance.merge_with_defaults(user_cfg, default_cfg)
	_parse_theme_config(merged)

	var active: String = _get_str(merged, "Theme", "active_preset", DEFAULT_PRESET)
	apply_preset(active)

	_loaded = true
	if EvtBus:
		EvtBus.theme_changed.emit(_theme_name)
	return true

func save_theme(file_path: String = "") -> bool:
	var user_path := file_path if not file_path.is_empty() else USER_THEME_PATH
	var cfg: Dictionary = {}

	cfg["Theme"] = {"version": "1.0.0", "active_preset": _theme_name}
	cfg["preset_" + _theme_name] = {}
	for key in _palette:
		cfg["preset_" + _theme_name][key] = (_palette[key] as Color).to_html(true)

	for p_name in _presets:
		if p_name != _theme_name:
			cfg["preset_" + p_name] = _presets[p_name].duplicate()

	cfg["backgrounds"] = {}
	for key in _backgrounds:
		cfg["backgrounds"][key] = str(_backgrounds[key])

	cfg["font_sizes"] = {}
	for key in _font_sizes:
		cfg["font_sizes"][key] = str(_font_sizes[key])

	return ConfigManager.instance.save_config(user_path, cfg)

# ============ 字号 API ============

func get_font_size(key: String, default: int = 32) -> int:
	if _font_sizes.has(key):
		return _font_sizes[key]
	GLogger.warning("Font size key not found: %s" % key, "ThemeManager")
	return default

# ============ 背景管理 ============

func get_view_background(view_name: String) -> Dictionary:
	var bg: Dictionary = {}
	var prefix := "bg_" + view_name + "_"
	for key in _backgrounds:
		if key.begins_with(prefix):
			bg[key.substr(prefix.length())] = _backgrounds[key]
	return bg

func set_view_background(view_name: String, config: Dictionary) -> void:
	var prefix := "bg_" + view_name + "_"
	for key in config:
		_backgrounds[prefix + key] = config[key]
	GLogger.info("背景设置已更新: %s" % view_name, "ThemeManager")
	save_theme()
	# 仅刷新背景（不 emit theme_changed，避免触发 refresh_theme_only 完整主题刷新导致卡顿）
	refresh_backgrounds()

func apply_background(texture_rect: TextureRect, view_name: String) -> void:
	if texture_rect == null:
		return

	var prefix := "bg_" + view_name + "_"
	var bg_type: String = _backgrounds.get(prefix + "type", "gradient")

	match bg_type:
		"cover":
			# 封面模式由 PlayView 自己处理（需要曲包封面 + 模糊烘焙）
			# ThemeManager 不实际应用，仅作为配置占位，让 PlayView 完全接管
			return
		"solid":
			var color_str: String = _backgrounds.get(prefix + "solid_color", "#0D1020")
			var solid_color := Color(color_str) if color_str.is_valid_html_color() else Color("#0D1020")
			texture_rect.texture = _create_solid_gradient_texture(solid_color)
			texture_rect.modulate = Color.WHITE
		"image":
			var img_path: String = _backgrounds.get(prefix + "image_path", "")
			if not img_path.is_empty():
				var tex := get_cached_background_image(img_path)
				if tex:
					texture_rect.texture = tex
					texture_rect.modulate = Color.WHITE
					var stretch: String = _backgrounds.get(prefix + "image_stretch", "cover")
					texture_rect.stretch_mode = _parse_stretch_mode(stretch)
					return
				# 缓存未命中：先应用渐变占位，再异步加载背景图（避免主线程同步 IO 卡顿）
				_apply_gradient(texture_rect, prefix)
				_request_background_image_load(img_path, texture_rect, _parse_stretch_mode(_backgrounds.get(prefix + "image_stretch", "cover")))
				return
			_apply_gradient(texture_rect, prefix)
		_:
			_apply_gradient(texture_rect, prefix)

## 获取已缓存的背景图（不触发磁盘 IO）；未缓存返回 null
func get_cached_background_image(file_name: String) -> Texture2D:
	if file_name.is_empty():
		return null
	# 缓存命中检查（同时校验纹理是否仍有效，避免引用已释放资源）
	if _bg_image_cache.has(file_name):
		var cached = _bg_image_cache[file_name]
		if is_instance_valid(cached):
			return cached
		_bg_image_cache.erase(file_name)
	return null

## 同步加载背景图（读盘 + 缓存）。仅限用户触发的单图预览（如 ImageAdjust 弹窗），
## 批量应用背景请走 apply_background（缓存命中立即、未命中走异步加载）。
func load_background_image(file_name: String) -> Texture2D:
	var cached := get_cached_background_image(file_name)
	if cached:
		return cached
	var full_path := PathHelper.get_background_dir().path_join(file_name)
	if not FileAccess.file_exists(full_path):
		return null
	var img := Image.load_from_file(full_path)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	if tex:
		_bg_image_cache[file_name] = tex
	return tex

## 请求异步加载背景图：命中缓存立即应用；否则入队由后台线程读盘（TMX-037）
func _request_background_image_load(file_name: String, rect: TextureRect, stretch: int) -> void:
	if file_name.is_empty() or not is_instance_valid(rect):
		return
	var cached := get_cached_background_image(file_name)
	if cached:
		rect.texture = cached
		rect.modulate = Color.WHITE
		rect.stretch_mode = stretch as TextureRect.StretchMode
		return
	if not _bg_pending_rects.has(file_name):
		_bg_pending_rects[file_name] = []
		_bg_load_queue.append(file_name)
	var rects: Array = _bg_pending_rects[file_name]
	rects.append({"rect": rect, "stretch": stretch})
	_bg_pending_rects[file_name] = rects
	_start_bg_load_if_idle()

func _start_bg_load_if_idle() -> void:
	if _bg_load_thread != null or _bg_load_queue.is_empty():
		return
	var file_name: String = _bg_load_queue[0]
	_bg_load_queue.pop_front()
	_bg_load_thread = Thread.new()
	_bg_load_thread.start(_bg_image_load_worker.bind(file_name))

## 后台线程：读取图片文件（纯文件 IO，不在主线程执行）
func _bg_image_load_worker(file_name: String) -> void:
	var full_path := PathHelper.get_background_dir().path_join(file_name)
	var img: Image = null
	if FileAccess.file_exists(full_path):
		img = Image.load_from_file(full_path)
	# call_deferred 跨线程投递到主线程是安全的
	call_deferred("_on_bg_image_loaded", file_name, img)

## 主线程：把后台加载的图片应用到所有等待中的 TextureRect
func _on_bg_image_loaded(file_name: String, img: Image) -> void:
	if _bg_load_thread:
		_bg_load_thread.wait_to_finish()
		_bg_load_thread = null
	var tex: Texture2D = null
	if img:
		tex = ImageTexture.create_from_image(img)
		if tex:
			_bg_image_cache[file_name] = tex
	var rects: Array = _bg_pending_rects.get(file_name, [])
	_bg_pending_rects.erase(file_name)
	for entry in rects:
		var rect: TextureRect = entry.get("rect")
		if is_instance_valid(rect):
			if tex:
				rect.texture = tex
				rect.modulate = Color.WHITE
				rect.stretch_mode = entry.get("stretch", rect.stretch_mode)
			# 加载失败：保持渐变占位（apply_background 已应用）
	_start_bg_load_if_idle()

func _exit_tree() -> void:
	_flush_scheduled_save()
	if _bg_load_thread:
		_bg_load_thread.wait_to_finish()
		_bg_load_thread = null

## 计划一次延迟落盘（高频调用合并为最后一次变更后 0.25s 写一次）
func _schedule_save_theme() -> void:
	_save_pending = true
	if _save_timer:
		_save_timer.start()

func _flush_scheduled_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	if not save_theme():
		GLogger.error("Theme save failed after debounce", "ThemeManager")

## 清除背景图片缓存（删除背景文件后调用，避免缓存指向已删除的文件）
## 传空字符串清空全部缓存，否则只清除指定 file_name
func invalidate_background_cache(file_name: String = "") -> void:
	if file_name.is_empty():
		_bg_image_cache.clear()
	else:
		_bg_image_cache.erase(file_name)

# ============ 样式工具方法 ============

## 修改节点已有 StyleBoxFlat 的 bg_color（不新建 StyleBox，保留 tscn 预设的圆角/边框/阴影等配置）
func _modify_panel_color(node: Control, color_key: String) -> void:
	var sb := node.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.bg_color = get_color(color_key)
		sb.border_color = get_color(color_key).lightened(0.3)

# ============ 列表项样式 ============

## 修改 albumNode 列表项上的 SongCount 圆形标签背景色
## （按钮四态已由共享 theme ListBtn-ColorBorder.tres 统一处理，不再逐实例改色）
func _style_album_instance(item: Control, pri_light: Color) -> void:
	var song_count := item.get_node_or_null("SongCount") as Label
	if song_count:
		var sb := song_count.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = pri_light

## 修改 songNode 列表项上的 SongCount 圆形标签背景色
func _style_song_instance(item: Control, pri_light: Color) -> void:
	var song_count := item.get_node_or_null("HBoxC/SongCount") as Label
	if song_count:
		var sb := song_count.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = pri_light


## 统一设置按钮三种状态的 bg_color（通过 Theme 的 StyleBoxFlat 引用）
## normal -> base_color, hover -> base_color.lightened(0.15), pressed -> base_color.darkened(0.25)
func _theme_button_set_color(theme: Theme, base_color: Color, type: String = "Button") -> void:
	theme.get_stylebox("normal", type).bg_color = base_color
	theme.get_stylebox("hover", type).bg_color = base_color.lightened(0.15)
	theme.get_stylebox("pressed", type).bg_color = base_color.darkened(0.25)
	theme.get_stylebox("focus", type).bg_color = base_color.lightened(0.1)
	theme.get_stylebox("disabled", type).bg_color = base_color.darkened(0.6)

# ============ 共享按钮 Theme（几何 .tres，颜色随主题） ============

## 刷新共享按钮 Theme 资源的四态颜色。
## 几何参数（圆角/边框宽度/边距）收在 UI/Theme/BtnTheme/*.tres 里，颜色在此按当前主题统一写入。
## 资源按 uid 单例缓存，改一次即同步所有引用场景（含 duplicate 的列表项）。
func _refresh_shared_btn_themes() -> void:
	# ListBtn-ColorBorder — 列表项按钮（album/song/sorted 共用）：与专辑节点同款（边框 pri_light + 半透明底 + focus 阴影）
	var list_theme := load(SHARED_LIST_BTN_THEME_PATH) as Theme
	if list_theme:
		_style_shared_list_btn_theme(list_theme)
	# R12NoBorder — 圆角12 无边框按钮（PopupWindow/KeySequenceItem/MidiView/PlayView/ValueButton 共用）：与主 Theme 按钮同款（primary 三阶）
	var r12_theme := load(SHARED_R12_BTN_THEME_PATH) as Theme
	if r12_theme:
		_style_shared_flat_btn_theme(r12_theme)

## 列表项按钮 Theme 四态颜色（fancy_focus 风格：normal 边框 pri_light + 半透明底 + focus 阴影）
func _style_shared_list_btn_theme(theme: Theme) -> void:
	var pl := get_color("primary_light")
	# pressed/hover — 半透明底色
	var sb := theme.get_stylebox("pressed", "Button")
	if sb is StyleBoxFlat:
		sb.bg_color = Color(pl.r, pl.g, pl.b, 0.25)
	sb = theme.get_stylebox("hover", "Button")
	if sb is StyleBoxFlat:
		sb.bg_color = Color(pl.r, pl.g, pl.b, 0.15)
	# focus — 阴影高亮
	sb = theme.get_stylebox("focus", "Button")
	if sb is StyleBoxFlat:
		sb.shadow_color = Color(pl.r, pl.g, pl.b, 0.6)
	# normal — 蓝色边框只加给 normal（与 tscn 原始设计一致）；hover/pressed 保持默认边框色
	sb = theme.get_stylebox("normal", "Button")
	if sb is StyleBoxFlat:
		sb.border_color = pl
		sb.shadow_color = Color(pl.r, pl.g, pl.b, 0.4)
	for state in ["hover", "pressed"]:
		sb = theme.get_stylebox(state, "Button")
		if sb is StyleBoxFlat:
			sb.shadow_color = Color(pl.r, pl.g, pl.b, 0.4)

## 圆角12 无边框按钮 Theme 四态颜色（primary 三阶，与主 Theme 按钮逻辑一致）
func _style_shared_flat_btn_theme(theme: Theme) -> void:
	var base := get_color("primary")
	var states := ["normal", "hover", "pressed", "focus"]
	var colors := {
		"normal": base,
		"hover": base.lightened(0.15),
		"pressed": base.darkened(0.25),
		"focus": base.lightened(0.1),
	}
	for state in states:
		var sb := theme.get_stylebox(state, "Button")
		if sb is StyleBoxFlat:
			sb.bg_color = colors[state]

func _style_panel_set_bg_color(panel: Control, color: Color) -> void:
	if not panel:
		return
	var sb := panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.bg_color = color
		sb.border_color = color.lightened(0.3)

## 修改 Previ / Next 按钮的已有 StyleBoxFlat 颜色（保留 tscn 的 skew/border/shadow 配置）
func _style_button_set_bg_color(btn: Button, color: Color) -> void:
	if not btn:
		return
	btn.get_theme_stylebox("normal").bg_color = color
	btn.get_theme_stylebox("pressed").bg_color = color.darkened(0.25)
	btn.get_theme_stylebox("hover").bg_color = color.lightened(0.15)

# ============ MidiView 主题 ============

## 修改 MidiView 中通过 theme_override_styles 单独设置的节点样式
func _style_midi_individual_nodes(info_ui: Node) -> void:
	var p := get_color("primary")
	var pl := get_color("primary_light")
	var pd := get_color("primary_dark")

	# InfoWindow 边框
	var info_window := info_ui.get_node_or_null("LeftArea/InfoWindow") as PanelContainer
	_style_panel_set_bg_color(info_window, pd)

	# Fold 面板（与 Center 共享同一 StyleBoxFlat_5h6qm）
	var fold := info_ui.get_node_or_null("LeftArea/InfoWindow/HBoxC/Left/Fold") as Panel
	_style_panel_set_bg_color(fold, pl)

	# Fold/Btn — 只改 pressed（normal 透明，hover 暗色遮罩保留）
	var fold_btn := info_ui.get_node_or_null("LeftArea/InfoWindow/HBoxC/Left/Fold/Btn") as Button
	if fold_btn:
		var sb := fold_btn.get_theme_stylebox("pressed")
		if sb is StyleBoxFlat:
			sb.bg_color = pd

	# Description 背景
	var desc := info_ui.get_node_or_null("LeftArea/InfoWindow/HBoxC/Description") as RichTextLabel
	if desc:
		var sb := desc.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = Color(p.r, p.g, p.b, 0.5)
			sb.border_color = Color(pd.r, pd.g, pd.b, 0.4)

	# PlayBtn — 中间按钮比两边亮（内联 stylebox，不走共享 theme）
	var play_btn := info_ui.get_node_or_null("LeftArea/MainBtn/PlayBtn") as Button
	_style_button_set_bg_color(play_btn, pl)

	# DetailData 的 PC1 面板（亮色，取 TrackViewBtn Normal 色=primary，比 primary_light 深）/ PC2 面板（暗色）
	var pc1 := info_ui.get_node_or_null("LeftArea/DetailData/PC1") as PanelContainer
	if pc1:
		var pc1_color := get_color("primary")
		var tv_btn := info_ui.get_node_or_null("LeftArea/MainBtn/TrackViewBtn") as Button
		if tv_btn:
			var tv_sb := tv_btn.get_theme_stylebox("normal")
			if tv_sb is StyleBoxFlat:
				pc1_color = tv_sb.bg_color
		_style_panel_set_bg_color(pc1, pc1_color)
	var pc2 := info_ui.get_node_or_null("LeftArea/DetailData/PC2") as PanelContainer
	_style_panel_set_bg_color(pc2, pd)

	# OptionPanel 背景 (和按钮按下状态同色)
	var option_panel := info_ui.get_node_or_null("OptionPanel") as PanelContainer
	_style_panel_set_bg_color(option_panel, p.darkened(0.25))

# ============ 全局刷新 ============

## 主题应用者注册表：视图/组件在 _ready 时注册，refresh_theme_only 遍历调用其 apply_theme()
## 懒加载视图实例化后自动注册，不再依赖 ThemeManager 主动按路径查找节点，从根本上解决懒加载时序问题
var _theme_appliers: Array[Node] = []

## 注册主题应用者（视图/组件 _ready 时调用，并自调一次 apply_theme() 完成首次着色）
func register_theme_applier(node: Node) -> void:
	if node and not _theme_appliers.has(node):
		_theme_appliers.append(node)

## 注销主题应用者（视图/组件 _exit_tree 时调用，防止 refresh 时访问已释放节点）
func unregister_theme_applier(node: Node) -> void:
	_theme_appliers.erase(node)

## 刷新主题色（不刷新背景）
## 仅刷新调色板、Theme 资源，并广播通知所有已注册应用者各自更新内部样式；
## 不调用 _apply_all_backgrounds，因为背景与主题色独立，切换主题不应触发背景重新加载（避免 Image.load_from_file 同步阻塞）。
## 若需要刷新背景，调用 refresh_backgrounds()。
##
## 注意：本函数是协程（含 await get_tree().process_frame），但调用方无需 await：
## - 主题色挨个帧更新在视觉上可接受；
## - 真正的痛点是 godot 内部对 StyleBox/Theme 的批量重绘卡顿，分帧是把卡顿摊到多帧而非消除。
## - 短时间内连续调用会并发执行多个协程，但 _palette 已是终态值，每帧的阶段幂等。
func refresh_theme_only() -> void:
	var main := get_node_or_null(PathRegistry.MAIN)
	if not main:
		return

	# 第一阶段：全局 Theme 资源（触发大面积重绘，单独一帧）
	# 注意：切换主题色不再清空背景缓存，背景与主题色独立（避免 Image.load_from_file 同步阻塞）
	_refresh_theme_colors(main.theme)
	# 共享按钮 Theme（几何 .tres，颜色随主题）—— 资源单例，改一次即同步所有引用场景
	_refresh_shared_btn_themes()
	var skew_part: Control = main.get_node_or_null("skew/C")
	if skew_part and skew_part.theme != main.theme:
		skew_part.theme = main.theme  # 让子节点继承更新后的 Theme （因为skew会导致子节点不继承theme）
	await get_tree().process_frame

	# 第二阶段：广播通知所有已注册应用者各自更新内部样式
	# 视图/组件在 _ready 时 register_theme_applier(self) 并自调 apply_theme() 完成首次着色；
	# 懒加载视图实例化后自动注册，不再有"启动阶段查找节点落空"的问题。
	var i := _theme_appliers.size() - 1
	while i >= 0:
		var applier = _theme_appliers[i]
		if is_instance_valid(applier) and applier.has_method("apply_theme"):
			applier.apply_theme()
		else:
			_theme_appliers.remove_at(i)
		i -= 1
	GLogger.info("主题刷新完成: %s" % _theme_name, "ThemeManager")

func _on_theme_changed(preset_name: String) -> void:
	# 如果信号携带的预设名在配置中存在且与当前不同，应用它
	if _presets.has(preset_name) and preset_name != _theme_name:
		var p: Dictionary = _presets[preset_name]
		for key in p:
			var val: String = p[key]
			if val.is_valid_html_color():
				_palette[key.to_lower()] = Color(val)
		_theme_name = preset_name
		GLogger.info("主题预设已应用: %s (%d 色)" % [preset_name, _palette.size()], "ThemeManager")
		# 外部驱动的预设切换：re-apply 后需要 save + refresh
		save_theme()
		refresh_theme_only()
	# 若 _theme_name == preset_name，说明是内部已 emit 的通知，无需重复 save+refresh：
	# - apply_preset / load_theme 自身已完成 save+refresh_theme_only 后再 emit
	# - set_color / set_palette_colors 同理（_theme_name 保持不变或改为 "custom"，
	#   但 emit 时 preset_name 等于 _theme_name，故也走此跳过分支）
	# 此处跳过避免了双重 save/refresh 导致的卡顿

## 仅刷新背景（设置界面修改背景配置后调用）
func refresh_backgrounds() -> void:
	var main := get_node_or_null(PathRegistry.MAIN)
	if not main:
		return
	_apply_all_backgrounds(main)
	GLogger.info("背景刷新完成", "ThemeManager")

# ============ 内部：背景批量应用 ============

func _apply_all_backgrounds(main: Node) -> void:
	# 独立背景节点（score/store/play 有自己的 Background 子节点）
	# main/midi/track/setting 共享主场景的 Background / Background2，由 _switch_main_bg 切换
	var bg_map := {
		"score": "ScoreView/BackGround",
		"store": "Store/Background",
		"play": "PlayView/Background",
	}

	for view_name in bg_map:
		var rect := main.get_node_or_null(bg_map[view_name])
		if rect:
			apply_background(rect, view_name)

	# 主背景节点：应用当前 view_name 的背景（首次或主题刷新时）
	if _active_bg and not _current_main_bg_view.is_empty():
		apply_background(_active_bg, _current_main_bg_view)

func get_theme_name() -> String:
	return _theme_name

func is_loaded() -> bool:
	return _loaded

# ============ 主背景交叉淡入淡出切换 ============

# 主背景交叉淡入淡出状态
var _active_bg: TextureRect = null       # 当前可见的背景节点（初始为 Background）
var _inactive_bg: TextureRect = null      # 备用背景节点（初始为 Background2）
var _current_main_bg_view: String = "main" # 当前主背景所属的 view_name
var _bg_switch_tween: Tween = null        # 切换补间
const _BG_SWITCH_DURATION := 0.4         # 交叉淡入淡出时长（秒）

## 初始化主背景节点引用（延迟调用确保 Main 就绪）
func _init_main_bg_nodes() -> void:
	var main := get_node_or_null(PathRegistry.MAIN)
	if not main:
		return
	_active_bg = main.get_node_or_null("Background")
	_inactive_bg = main.get_node_or_null("Background2")
	if _active_bg and _inactive_bg:
		_active_bg.modulate.a = 1.0
		_active_bg.visible = true
		_inactive_bg.modulate.a = 0.0
		_inactive_bg.visible = false
		# 应用初始背景（main 组）
		apply_background(_active_bg, "main")
		_current_main_bg_view = "main"

## UIState → 主背景组映射（空字符串表示不切主背景，使用独立节点）
func _get_bg_view_name_for_state(state: int) -> String:
	match state:
		UIStateManager.UIState.ALBUM_VIEW, \
		UIStateManager.UIState.SONG_VIEW, \
		UIStateManager.UIState.SORTED_VIEW:
			return "main"
		UIStateManager.UIState.MIDI_VIEW:
			return "midi"
		UIStateManager.UIState.TRACK_VIEW:
			return "track"
		UIStateManager.UIState.SETTINGS_VIEW:
			return "setting"
		_:
			return ""

## state_changed 回调：触发主背景交叉淡入淡出
func _on_state_changed_for_bg(_old_state: int, new_state: int) -> void:
	var target_view := _get_bg_view_name_for_state(new_state)
	if target_view.is_empty():
		return  # PLAY_VIEW/SCORE_VIEW/STORE_VIEW 等有独立背景节点，不切主背景
	if target_view == _current_main_bg_view:
		return  # 同组内不切换（如 main 组内 AlbumView↔SongView）
	_switch_main_bg(target_view)

## 交叉淡入淡出切换主背景到 target_view
func _switch_main_bg(target_view: String) -> void:
	if not _active_bg or not _inactive_bg:
		return
	# 杀掉正在进行的切换补间，并同步状态（避免补间中途被 kill 时角色未交换导致闪烁）
	if _bg_switch_tween and _bg_switch_tween.is_valid():
		_bg_switch_tween.kill()
		# 补间未完成时，active 仍是当前可见节点，强制对齐状态
		_active_bg.modulate.a = 1.0
		_active_bg.visible = true
		_inactive_bg.modulate.a = 0.0
		_inactive_bg.visible = false
	# 把新背景应用到 inactive 节点
	_inactive_bg.visible = true
	_inactive_bg.modulate.a = 0.0
	apply_background(_inactive_bg, target_view)
	# 交叉淡入淡出（inactive 0→1，active 1→0）
	_bg_switch_tween = AniMGR.create_managed_tween(self)
	_bg_switch_tween.set_parallel(true)
	_bg_switch_tween.tween_property(_inactive_bg, "modulate:a", 1.0, _BG_SWITCH_DURATION)
	_bg_switch_tween.tween_property(_active_bg, "modulate:a", 0.0, _BG_SWITCH_DURATION)
	_bg_switch_tween.chain()
	_bg_switch_tween.tween_callback(func():
		_active_bg.visible = false
		# 交换 active/inactive 角色，下次切换时新背景应用到刚变成 inactive 的节点
		var tmp := _active_bg
		_active_bg = _inactive_bg
		_inactive_bg = tmp
	)
	_current_main_bg_view = target_view

# ============ Theme 颜色刷新 ============

## 更新 Main 节点上已有 Theme 资源的 StyleBoxFlat 颜色（不新建 Theme）
func _refresh_theme_colors(thm: Theme) -> void:
	var p := get_color("primary")
	var pl := get_color("primary_light")
	var pd := get_color("primary_dark")

	# Button states
	_theme_button_set_color(thm, p)

	# CheckBox hover_pressed：已勾选 + hover 状态。
	# 项目主 Theme 未定义 CheckBox/styles/hover_pressed，会按继承链回退到 default theme 的
	# cbx_empty（空 stylebox），导致已勾选的 CheckBox 鼠标 hover 时背景消失。
	# 这里复制 Button 的 pressed 样式作为 CheckBox 的 hover_pressed，并每次刷新同步颜色。
	if not thm.has_theme_item(Theme.DATA_TYPE_STYLEBOX, "hover_pressed", "CheckBox"):
		var btn_pressed := thm.get_stylebox("pressed", "Button")
		if btn_pressed is StyleBoxFlat:
			thm.set_stylebox("hover_pressed", "CheckBox", (btn_pressed as StyleBoxFlat).duplicate())
	var cb_hp := thm.get_stylebox("hover_pressed", "CheckBox")
	if cb_hp is StyleBoxFlat:
		(cb_hp as StyleBoxFlat).bg_color = p.darkened(0.25)

	thm.set_color("font_disabled_color", "Button", get_color("text_dim"))
	thm.set_color("selection_color", "LineEdit", p)

	# Label
	thm.set_color("font_color", "Label", get_color("text_primary"))

	# PopupMenu hover
	var sb_ph := thm.get_stylebox("hover", "PopupMenu")
	if sb_ph is StyleBoxFlat: sb_ph.bg_color = p

	# ScrollBar grabbers
	var sb_gr := thm.get_stylebox("grabber", "VScrollBar")
	if sb_gr is StyleBoxFlat: sb_gr.bg_color = p
	var sb_gh := thm.get_stylebox("grabber_highlight", "VScrollBar")
	if sb_gh is StyleBoxFlat: sb_gh.bg_color = pl

	# TabContainer
	var sb_tu := thm.get_stylebox("tab_unselected", "TabContainer")
	if sb_tu is StyleBoxFlat: sb_tu.bg_color = p
	var sb_ts := thm.get_stylebox("tab_selected", "TabContainer")
	if sb_ts is StyleBoxFlat: sb_ts.bg_color = pd
	var sb_tp := thm.get_stylebox("panel", "TabContainer")
	if sb_tp is StyleBoxFlat: sb_tp.bg_color = pd

	# Tree
	thm.set_font_size("font_size", "Tree", get_font_size("body", 32))
	thm.set_constant("item_margin", "Tree", 48)
	thm.set_constant("button_margin", "Tree", 10)
	thm.set_constant("h_separation", "Tree", 6)

# ============ 内部方法 ============

func _parse_theme_config(cfg: Dictionary) -> void:
	for section in cfg:
		if section is String and (section as String).begins_with("preset_"):
			var _name: String = (section as String).replace("preset_", "")
			_presets[_name] = cfg[section].duplicate()

	GLogger.info("加载了 %d 个主题预设" % _presets.size(), "ThemeManager")

	if cfg.has("backgrounds"):
		for key in cfg["backgrounds"]:
			_backgrounds[key] = cfg["backgrounds"][key]

	if cfg.has("font_sizes"):
		for key in cfg["font_sizes"]:
			_font_sizes[key] = int(cfg["font_sizes"][key])

func _get_str(cfg: Dictionary, section: String, key: String, default: String) -> String:
	if cfg.has(section) and cfg[section].has(key):
		return cfg[section][key]
	return default

func _apply_gradient(texture_rect: TextureRect, prefix: String) -> void:
	var top_str: String = _backgrounds.get(prefix + "gradient_top", "#0D1020")
	var bottom_str: String = _backgrounds.get(prefix + "gradient_bottom", "#0A0F1E")

	var top_color := Color(top_str) if top_str.is_valid_html_color() else Color("#0D1020")
	var bottom_color := Color(bottom_str) if bottom_str.is_valid_html_color() else Color("#0A0F1E")

	var gradient := Gradient.new()
	# 用 set_color 替换默认黑白点，而非 add_point 追加导致 4 个点
	gradient.set_color(0, top_color)
	gradient.set_color(1, bottom_color)

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 256
	tex.fill_from = Vector2(
		float(_backgrounds.get(prefix + "gradient_from_x", "0.0")),
		float(_backgrounds.get(prefix + "gradient_from_y", "0.0"))
	)
	tex.fill_to = Vector2(
		float(_backgrounds.get(prefix + "gradient_to_x", "0.0")),
		float(_backgrounds.get(prefix + "gradient_to_y", "1.0"))
	)

	texture_rect.texture = tex
	texture_rect.modulate = Color.WHITE

## 创建单色 GradientTexture2D（两个点都设为同色，避免 texture=null 时 modulate 失效）
func _create_solid_gradient_texture(color: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, color)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 4
	return tex

func _parse_stretch_mode(mode: String) -> TextureRect.StretchMode:
	match mode:
		"scale": return TextureRect.STRETCH_SCALE
		"tile": return TextureRect.STRETCH_TILE
		"cover": return TextureRect.STRETCH_KEEP_ASPECT_COVERED
		"fit": return TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		"center": return TextureRect.STRETCH_KEEP_CENTERED
		"keep": return TextureRect.STRETCH_KEEP
	return TextureRect.STRETCH_KEEP_ASPECT_COVERED
