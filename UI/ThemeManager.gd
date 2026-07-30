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
	if EvtBus:
		EvtBus.theme_changed.connect(_on_theme_changed)
	# 监听 UI 状态变化，触发主背景交叉淡入淡出
	if UiStatMGR:
		UiStatMGR.state_changed.connect(_on_state_changed_for_bg)
	# 延迟初始化主背景节点引用，确保 /root/Main 已就绪
	call_deferred("_init_main_bg_nodes")

# ============ 配置路径 ============

const DEFAULT_THEME_PATH := "res://Resources/Config/theme.ini"
const DEFAULT_PRESET := "blue"

static var USER_THEME_PATH: String:
	get: return PathHelper.get_files_dir() + "theme.ini"

# ============ 内部状态 ============

var _palette: Dictionary = {}
var _font_sizes: Dictionary = {}
var _backgrounds: Dictionary = {}
var _presets: Dictionary = {}
var _theme_name: String = "default"
var _loaded: bool = false

# 背景图片纹理缓存（file_name → Texture2D），避免主题切换时重复 Image.load_from_file 同步阻塞
var _bg_image_cache: Dictionary = {}

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
	save_theme()
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
	save_theme()
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
	# PlayView 的 cover 模式由 PlayView 自己在切回 PLAY_VIEW 时通过 _apply_play_background 处理
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
				var tex := load_background_image(img_path)
				if tex:
					texture_rect.texture = tex
					texture_rect.modulate = Color.WHITE
					var stretch: String = _backgrounds.get(prefix + "image_stretch", "cover")
					texture_rect.stretch_mode = _parse_stretch_mode(stretch)
					return
			_apply_gradient(texture_rect, prefix)
		_:
			_apply_gradient(texture_rect, prefix)

func load_background_image(file_name: String) -> Texture2D:
	if file_name.is_empty():
		return null
	# 缓存命中检查（同时校验纹理是否仍有效，避免引用已释放资源）
	if _bg_image_cache.has(file_name):
		var cached = _bg_image_cache[file_name]
		if is_instance_valid(cached):
			return cached
		_bg_image_cache.erase(file_name)
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

## 修改按钮已有 StyleBoxFlat 的颜色属性（不新建 StyleBox，保留 tscn 预设的圆角/边框等配置）
## fancy_focus: true=同时修改 focus 的 shadow_color (Album/Song)
func _modify_button_colors(btn: Button, pri_light: Color, fancy_focus: bool) -> void:
	var sb := btn.get_theme_stylebox("pressed")
	if sb is StyleBoxFlat:
		sb.bg_color = Color(pri_light.r, pri_light.g, pri_light.b, 0.25)

	sb = btn.get_theme_stylebox("hover")
	if sb is StyleBoxFlat:
		sb.bg_color = Color(pri_light.r, pri_light.g, pri_light.b, 0.15)

	if fancy_focus:
		sb = btn.get_theme_stylebox("focus")
		if sb is StyleBoxFlat:
			sb.shadow_color = Color(pri_light.r, pri_light.g, pri_light.b, 0.6)

		# 边框颜色
		for state in ["normal", "hover", "pressed"]:
			sb = btn.get_theme_stylebox(state)
			if sb is StyleBoxFlat:
				sb.border_color = pri_light
				sb.shadow_color = Color(pri_light.r, pri_light.g, pri_light.b, 0.4)

## 修改 albumNode 的 item_instance 上的共享 StyleBoxFlat
func _style_album_instance(item: Control, pri_light: Color) -> void:
	# AlbumButton — pressed/hover/focus 的颜色
	var btn := item.get_node_or_null("AlbumButton") as Button
	if btn:
		_modify_button_colors(btn, pri_light, true)

	# SongCount — normal StyleBoxFlat.bg_color（共享引用，duplicate 子项自动同步）
	var song_count := item.get_node_or_null("SongCount") as Label
	if song_count:
		var sb := song_count.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = pri_light

## 修改 songNode 的 item_instance
func _style_song_instance(item: Control, pri_light: Color) -> void:
	# HBoxC/SongCount — normal StyleBoxFlat.bg_color（共享引用，duplicate 子项自动同步）
	var song_count := item.get_node_or_null("HBoxC/SongCount") as Label
	if song_count:
		var sb := song_count.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = pri_light

	# SongButton
	var btn := item.get_node_or_null("SongButton") as Button
	if btn:
		_modify_button_colors(btn, pri_light, true)

## 修改 sortedMidiNode 的 item_instance
func _style_sorted_midi_instance(item: Control, pri_light: Color) -> void:
	# Panel/Border
	var border := item.get_node_or_null("Panel/Border") as PanelContainer
	if border:
		var sb := border.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.border_color = pri_light

	# Panel/Button（简洁焦点，不修改 shadow）
	var btn := item.get_node_or_null("Panel/Button") as Button
	if btn:
		_modify_button_colors(btn, pri_light, false)


## 统一设置按钮三种状态的 bg_color（通过 Theme 的 StyleBoxFlat 引用）
## normal -> base_color, hover -> base_color.lightened(0.15), pressed -> base_color.darkened(0.25)
func _theme_button_set_color(theme: Theme, base_color: Color, type: String = "Button") -> void:
	theme.get_stylebox("normal", type).bg_color = base_color
	theme.get_stylebox("hover", type).bg_color = base_color.lightened(0.15)
	theme.get_stylebox("pressed", type).bg_color = base_color.darkened(0.25)
	theme.get_stylebox("focus", type).bg_color = base_color.lightened(0.1)
	theme.get_stylebox("disabled", type).bg_color = base_color.darkened(0.6)

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

# ============ 商店视图主题 ============

## 对 MidiStore.tscn 的静态组件应用主题色
func _apply_store_theme(main: Node) -> void:
	var store := main.get_node_or_null("Store")
	if not store:
		return

	# TopBar — 垂直渐变 primary → primary_dark
	var topbar := store.get_node_or_null("TopBar") as Panel
	if topbar:
		var sb := topbar.get_theme_stylebox("panel")
		if sb is StyleBoxTexture:
			var tex := sb.texture as GradientTexture2D
			if tex and tex.gradient:
				var g := tex.gradient
				g.set_color(0, get_color("primary"))
				g.set_color(1, get_color("primary_dark"))

	# TopBar/C/Search/Base — 四点 vertex_colors，基于 primary 做细微调整
	var search_base := store.get_node_or_null("TopBar/C/Search/Base") as Polygon2D
	if search_base:
		var p := get_color("primary")
		var pd := get_color("primary_dark")
		search_base.vertex_colors = PackedColorArray([
			p.lightened(0.1),   # 左上 — 稍亮
			p,                   # 左下 — 基准 primary
			pd,                  # 右下 — primary_dark
			p.lightened(0.2),   # 右上 — 左侧偏亮，产生水平过渡
		])

	# Bottom/Previ + Next — primary_dark 基调
	for btn_name in ["Previ", "Next"]:
		var btn := store.get_node_or_null("Bottom/" + btn_name) as Button
		_style_button_set_bg_color(btn, get_color("primary_dark"))

	# Bottom/Indicate — 页码标签背景 primary_light
	var indicate := store.get_node_or_null("Bottom/Indicate") as Label
	if indicate:
		var sb := indicate.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = get_color("primary_light")

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

	# PlayBtn — 中间按钮比两边亮
	var play_btn := info_ui.get_node_or_null("LeftArea/MainBtn/PlayBtn") as Button
	_style_button_set_bg_color(play_btn, pl)

	# RedirectButtons/Button
	var redirect_btn := info_ui.get_node_or_null("LeftArea/RedirectButtons/Button") as Button
	_style_button_set_bg_color(redirect_btn, p)

	# OptionPanel 背景 (和按钮按下状态同色)
	var option_panel := info_ui.get_node_or_null("OptionPanel") as PanelContainer
	_style_panel_set_bg_color(option_panel, p.darkened(0.25))

## 对 MidiView 的独立节点应用主题色
func _apply_midi_theme(main: Node) -> void:
	var info_ui := main.get_node_or_null("skew/C/MidiView")
	if not info_ui:
		return
	_style_midi_individual_nodes(info_ui)


# ============ 结算界面主题 ============

func _apply_score_theme(main: Node) -> void:
	var score := main.get_node_or_null("ScoreView")
	if not score:
		return

	# LevelingProgress — 透明 primary_dark
	var leveling := score.get_node_or_null("LevelingProgress") as Panel
	if leveling:
		var sb := leveling.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var a = sb.bg_color.a
			var pd := get_color("primary_dark")
			sb.bg_color = Color(pd.r, pd.g, pd.b, a)

	# Btns — 透明 primary_light
	var btns := score.get_node_or_null("Btns") as Panel
	if btns:
		var sb := btns.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var a = sb.bg_color.a
			var pl := get_color("primary_light")
			sb.bg_color = Color(pl.r, pl.g, pl.b, a)


func _apply_track_theme(main: Node) -> void:
	var track_view := main.get_node_or_null("skew/C/TrackView") as Control
	if not track_view:
		return

	var p := get_color("primary")
	var pl := get_color("primary_light")

	# TotalView / VolumeView panel -> primary (shares StyleBoxFlat_31lmn)
	var total_view := track_view.get_node_or_null("MC/VBox/TotalView") as Panel
	if total_view:
		var sb := total_view.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = p

	# noteTotal panel -> primary_light
	var note_total := track_view.get_node_or_null("MC/VBox/TotalView/MC/VBoxC/flowArea/noteTotal") as Panel
	if note_total:
		var sb := note_total.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = pl

	# VocalEnableBtn button states
	var vocal_btn := track_view.get_node_or_null("MC/VBox/VolumeView/HBoxC/VBoxC2/VocalEnableBtn") as Button
	if vocal_btn:
		var sb_n := vocal_btn.get_theme_stylebox("normal")
		if sb_n is StyleBoxFlat:
			sb_n.bg_color = p
		var sb_h := vocal_btn.get_theme_stylebox("hover")
		if sb_h is StyleBoxFlat:
			sb_h.bg_color = p.lightened(0.15)
		var sb_p := vocal_btn.get_theme_stylebox("pressed")
		if sb_p is StyleBoxFlat:
			sb_p.bg_color = DANGER_COLOR
		var sb_hp := vocal_btn.get_theme_stylebox("hover_pressed")
		if sb_hp is StyleBoxFlat:
			sb_hp.bg_color = DANGER_COLOR.lightened(0.2)

	GLogger.debug("TrackView theme applied", "ThemeManager")


func _apply_play_theme(main: Node) -> void:
	var play_view := main.get_node_or_null("PlayView") as Control
	if not play_view:
		return

	var menu := play_view.get_node_or_null("Layer/CenterBackGround/Menu") as HBoxContainer
	if not menu or not menu.theme:
		return

	var theme := menu.theme
	var p := get_color("primary")

	_theme_button_set_color(theme, p)

	# Add shadow effects to the base button styles
	var normal := theme.get_stylebox("normal", "Button")
	if normal is StyleBoxFlat:
		normal.shadow_color = Color(p.r, p.g, p.b, 0.3)
		normal.shadow_size = 8

	var hover := theme.get_stylebox("hover", "Button")
	if hover is StyleBoxFlat:
		var hc := p.lightened(0.15)
		hover.shadow_color = Color(hc.r, hc.g, hc.b, 0.35)
		hover.shadow_size = 12

	# Continue button: brighter than the others
	var continue_btn := menu.get_node_or_null("continue") as Button
	if continue_btn:
		var sb_n := continue_btn.get_theme_stylebox("normal")
		if sb_n is StyleBoxFlat:
			sb_n.bg_color = p.lightened(0.15)
		var sb_h := continue_btn.get_theme_stylebox("hover")
		if sb_h is StyleBoxFlat:
			sb_h.bg_color = p.lightened(0.30)

	# Quit button: danger color on pressed
	var quit_btn := menu.get_node_or_null("quit") as Button
	if quit_btn:
		var sb_p := quit_btn.get_theme_stylebox("pressed")
		if sb_p is StyleBoxFlat:
			sb_p.bg_color = DANGER_COLOR

	GLogger.debug("PlayView theme applied", "ThemeManager")


## 对 DelView 的静态部分应用主题色（侧边栏、内容面板、按钮颜色）
## 由 DelView._ready() 和 theme_changed 信号触发
func _apply_delview_theme(main: Node) -> void:
	var delview := main.get_node_or_null("skew/C/SettingView/DelView")
	if not delview:
		return
	var sidebar: VBoxContainer = delview.get_node_or_null("SideBar")
	if sidebar:
		_theme_button_set_color(sidebar.theme, get_color("primary"))
		var pressed := sidebar.theme.get_stylebox("pressed", "Button")
		if pressed:
			pressed.bg_color = get_color("primary_dark").darkened(0.5)

	var top_panel: PanelContainer = delview.get_node_or_null("Content/PC")
	if top_panel:
		var sb := top_panel.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = get_color("primary_dark")

	GLogger.debug("DelView theme applied", "ThemeManager")

# ============ 弹出窗口主题 ============

## 对 PopupWindow 的静态部分应用主题色
## 由 refresh_theme_only() 触发
func _apply_popup_window_theme(main: Node) -> void:
	var popup := main.get_node_or_null("PopupWindow")
	if not popup:
		return

	# DelayAdjust/Button — primary 色调
	var delay_btn := popup.delay_btn as Button
	_style_button_set_bg_color(delay_btn, get_color("primary"))

	# KBModeAdjust/AddBtn — primary 色调（静态按钮）
	var kb_add_btn := popup.get_node_or_null("TabC/KBModeAdjust/KeySequence/VFlowC/AddBtn") as Button
	if kb_add_btn:
		_style_button_set_bg_color(kb_add_btn, get_color("primary"))

	# KBModeAdjust 中动态创建的 KeySequenceItem — 委托给 KBModeAdjust.apply_button_theme
	# （_rebuild_items 重建时也会调用此方法，确保新 item 即时应用主题色）
	var kb_mode_adjust := popup.get_node_or_null("TabC/KBModeAdjust") as KBModeAdjust
	if kb_mode_adjust:
		kb_mode_adjust.apply_button_theme(get_color("primary"))

	GLogger.debug("PopupWindow theme applied", "ThemeManager")

# ============ 设置视图主题 ============

## 对 SettingView 中所有 TYPE_BUTTON 设置项应用主题色
## 由 refresh_theme_only() 触发
func _apply_setting_view_theme(main: Node) -> void:
	var setting_view := main.get_node_or_null("skew/C/SettingView")
	if not setting_view:
		return
	var setting_list := setting_view.get_node_or_null("HBoxC/SettingList") as SettingList
	if not setting_list:
		return
	setting_list.apply_button_theme(get_color("primary"))

	# ShortCut 导航按钮（Btn1-6）：focus 样式 = pressed + 白边
	# 这些按钮没有 theme_override_styles，使用全局 Theme 的 Button 样式（focus 默认是 lightened(0.1)，与 pressed 差异大）
	# 直接修改全局 Theme 的 focus StyleBox 会污染所有按钮，因此给每个按钮单独加 theme_override_styles
	var shortcut_btn := setting_view.get_node_or_null("HBoxC/ShortCut")
	if shortcut_btn:
		var pressed_color := get_color("primary").darkened(0.25)
		for b in shortcut_btn.get_children():
			if b is Button:
				_apply_shortcut_focus_style(b, pressed_color)
	GLogger.debug("SettingView theme applied", "ThemeManager")

## 给 ShortCut 按钮设置 focus 样式：复制 pressed 样式 + 白色边框
## 通过 theme_override_styles/focus 独立覆盖，不影响其他按钮和共享 Theme 资源
func _apply_shortcut_focus_style(btn: Button, pressed_color: Color) -> void:
	# 取当前 pressed 样式做副本（可能是全局 Theme 的引用，必须 duplicate 才能独立修改）
	var sb := btn.get_theme_stylebox("pressed")
	if sb is StyleBoxFlat:
		var dup := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
		dup.bg_color = pressed_color
		dup.border_color = Color.WHITE
		dup.border_width_left = 4
		dup.border_width_right = 4
		dup.border_width_top = 4
		dup.border_width_bottom = 4
		btn.add_theme_stylebox_override("focus", dup)

# ============ 全局刷新 ============

## 刷新主题色（不刷新背景）
## 仅应用调色板、Theme 资源、各视图/弹窗的 StyleBox 与 self_modulate；
## 不调用 _apply_all_backgrounds，因为背景与主题色独立，切换主题不应触发背景重新加载（避免 Image.load_from_file 同步阻塞）。
## 若需要刷新背景，调用 refresh_backgrounds()。
##
## 注意：本函数是协程（含 await get_tree().process_frame），但调用方无需 await：
## - 主题色挨个帧更新在视觉上可接受；
## - 真正的痛点是 godot 内部对 StyleBox/Theme 的批量重绘卡顿，分帧是把卡顿摊到多帧而非消除。
## - 短时间内连续调用会并发执行多个协程，但 _palette 已是终态值，每帧的阶段幂等。
func refresh_theme_only() -> void:
	var main := get_node_or_null("/root/Main")
	if not main:
		return

	# 第一阶段：全局 Theme 资源 + 主框架主题（最可能触发大面积重绘，单独一帧）
	# 注意：切换主题色不再清空背景缓存，背景与主题色独立（避免 Image.load_from_file 同步阻塞）
	_refresh_theme_colors(main.theme)
	var skew_part: Control = main.get_node_or_null("skew/C")
	if skew_part.theme != main.theme:
		skew_part.theme = main.theme  # 让子节点继承更新后的 Theme （因为skew会导致子节点不继承theme）
	_apply_main_theme(main)
	_apply_delview_theme(main)
	await get_tree().process_frame

	# 第二阶段：列表主题（含 item_instance 的 StyleBoxFlat 修改，子项自动同步）
	_apply_list_theme(main)
	_apply_store_theme(main)
	await get_tree().process_frame

	# 第三阶段：各视图主题
	_apply_midi_theme(main)
	_apply_score_theme(main)
	_apply_track_theme(main)
	_apply_play_theme(main)
	await get_tree().process_frame

	# 第四阶段：弹窗与设置页主题
	_apply_popup_window_theme(main)
	_apply_setting_view_theme(main)
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
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	_apply_all_backgrounds(main)
	GLogger.info("背景刷新完成", "ThemeManager")

# ============ 内部：主界面组件主题 ============

func _apply_main_theme(main: Node) -> void:
	# LT_Btn — 蓝 (primary)
	var lt := main.get_node_or_null("LT_Btn")
	if lt:
		_modify_panel_color(lt, "primary")

	# RB_Btn — 淡蓝 (primary_light)
	var rb := main.get_node_or_null("RB_Btn")
	if rb:
		_modify_panel_color(rb, "primary_light")

	# ShortCutMenu 面板 — 蓝 (primary)
	var sc_panel := main.get_node_or_null("skew/C/ShortCutMenu/Panel")
	if sc_panel:
		_modify_panel_color(sc_panel, "primary")

	# PlayerInfo 面板 — 暗色 (primary_dark.darkened)
	var info_panel := main.get_node_or_null("PlayerInfo/Info/Panel")
	if info_panel:
		_modify_panel_color(info_panel, "primary_dark")

## 修改三个列表容器的 item_instance 共享 StyleBoxFlat（duplicate 子项自动同步，无需逐项刷新）
func _apply_list_theme(main: Node) -> void:
	var pri_light := get_color("primary_light")

	# AlbumList
	var album_view := main.get_node_or_null("skew/C/AlbumList") as BaseScrollList
	if album_view and album_view.item_instance:
		_style_album_instance(album_view.item_instance, pri_light)

	# SongList
	var song_view := main.get_node_or_null("skew/C/SongList") as BaseScrollList
	if song_view and song_view.item_instance:
		_style_song_instance(song_view.item_instance, pri_light)

	# SortedMidisList
	var sorted_view := main.get_node_or_null("skew/C/SortedMidisList") as BaseScrollList
	if sorted_view and sorted_view.item_instance:
		_style_sorted_midi_instance(sorted_view.item_instance, pri_light)


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
	var main := get_node_or_null("/root/Main")
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
	_bg_switch_tween = create_tween()
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
