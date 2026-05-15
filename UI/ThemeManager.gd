## 主题管理器（单例）
## 统一管理全局颜色调色板、背景图片和字号配置
## 通过 autoload 注册，引擎启动时自动实例化
##
## 颜色来源：theme.ini 的 [preset_*] 段 → active_preset 选择 → _palette（7 色）
## 背景色由 primary_dark 自动衍生，语义色（danger/success 等）写死在代码中
##
## 外部接口：
##   ThemeManager.instance.get_color("primary")
##   ThemeManager.instance.apply_preset("pink")
##   ThemeManager.instance.refresh_all()          # 主题变更后刷新全部
##   ThemeManager.instance.refresh_backgrounds()  # 仅刷新背景（给设置界面）
class_name ThemeManager
extends Node

# ============ 单例 ============

static var instance: ThemeManager

func _init() -> void:
	if instance != null:
		push_error("ThemeManager is a singleton, use ThemeManager.instance instead")
		return

func _ready() -> void:
	instance = self
	add_to_group("singletons")
	load_theme()
	if EventBus.instance:
		EventBus.instance.theme_changed.connect(_on_theme_changed)

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
	GameLogger.instance.warning("Theme color key not found: %s" % key, "ThemeManager")
	return default

func set_color(key: String, value: Color) -> void:
	_palette[key.to_lower()] = value
	GameLogger.instance.info("Theme color changed: %s = %s" % [key, value.to_html(true)], "ThemeManager")
	if EventBus.instance:
		EventBus.instance.theme_changed.emit(_theme_name)

func has_color(key: String) -> bool:
	return _palette.has(key.to_lower())

func get_palette() -> Dictionary:
	return _palette.duplicate()

# ============ 衍生色 ============

func get_panel_bg() -> Color:
	return PANEL_BG

func get_sidebar_bg() -> Color:
	return SIDEBAR_BG

# ============ 预设颜色方案 ============

func get_available_presets() -> PackedStringArray:
	var names: PackedStringArray = []
	for key in _presets:
		names.append(key)
	return names

func apply_preset(preset_name: String) -> void:
	if not _presets.has(preset_name):
		GameLogger.instance.warning("预设不存在: %s，回退到 %s" % [preset_name, DEFAULT_PRESET], "ThemeManager")
		if preset_name != DEFAULT_PRESET and _presets.has(DEFAULT_PRESET):
			apply_preset(DEFAULT_PRESET)
		return

	var p: Dictionary = _presets[preset_name]
	for key in p:
		var val: String = p[key]
		if val.is_valid_html_color():
			_palette[key.to_lower()] = Color(val)

	_theme_name = preset_name
	GameLogger.instance.info("主题预设已应用: %s (%d 色)" % [preset_name, _palette.size()], "ThemeManager")

	if EventBus.instance:
		EventBus.instance.theme_changed.emit(_theme_name)
	save_theme()

func set_palette_colors(pri: Color, pri_light: Color, pri_dark: Color) -> void:
	_palette["primary"] = pri
	_palette["primary_light"] = pri_light
	_palette["primary_dark"] = pri_dark
	_theme_name = "custom"
	GameLogger.instance.info("主题色已自定义设置", "ThemeManager")
	if EventBus.instance:
		EventBus.instance.theme_changed.emit(_theme_name)
	save_theme()

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
	if EventBus.instance:
		EventBus.instance.theme_changed.emit(_theme_name)
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

func reset_to_defaults() -> void:
	_palette.clear()
	_presets.clear()
	_font_sizes.clear()
	_backgrounds.clear()
	ConfigManager.instance.clear_cache()
	load_theme()
	GameLogger.instance.info("主题已重置为默认", "ThemeManager")

# ============ 字号 API ============

func get_font_size(key: String, default: int = 32) -> int:
	if _font_sizes.has(key):
		return _font_sizes[key]
	GameLogger.instance.warning("Font size key not found: %s" % key, "ThemeManager")
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
	GameLogger.instance.info("背景设置已更新: %s" % view_name, "ThemeManager")
	save_theme()
	if EventBus.instance:
		EventBus.instance.theme_changed.emit(_theme_name)

func apply_background(texture_rect: TextureRect, view_name: String) -> void:
	if texture_rect == null:
		return

	var prefix := "bg_" + view_name + "_"
	var bg_type: String = _backgrounds.get(prefix + "type", "gradient")

	match bg_type:
		"solid":
			var color_str: String = _backgrounds.get(prefix + "solid_color", "#0D1020")
			texture_rect.texture = null
			texture_rect.modulate = Color(color_str) if color_str.is_valid_html_color() else Color("#0D1020")
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
	var full_path := PathHelper.get_background_dir().path_join(file_name)
	if not FileAccess.file_exists(full_path):
		return null
	var img := Image.load_from_file(full_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

# ============ 样式工具方法 ============

func style_panel(node: Control, color_key: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = get_color(color_key)
	node.add_theme_stylebox_override("panel", sb)
	GameLogger.instance.debug("style_panel: %s ← %s" % [node.name, color_key], "ThemeManager")

func style_diag_gradient(node: TextureRect, from_key: String, to_key: String) -> void:
	var gradient := Gradient.new()
	gradient.add_point(0.0, get_color(from_key))
	gradient.add_point(1.0, get_color(to_key))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 64
	tex.fill_from = Vector2(0, 1)
	tex.fill_to = Vector2(1, 0)
	node.texture = tex
	GameLogger.instance.debug("style_diag_gradient: %s ← %s→%s" % [node.name, from_key, to_key], "ThemeManager")

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

## 修改 albumNode 的 item_instance 上的共享 StyleBoxFlat 和 self_modulate
func _style_album_instance(item: Control, pri_light: Color) -> void:
	# PN/Border — border_color + shadow_color
	var border := item.get_node_or_null("PN/Border") as PanelContainer
	if border:
		var sb := border.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.border_color = pri_light
			sb.shadow_color = Color(pri_light.r, pri_light.g, pri_light.b, 0.57)

	# PN/AlbumButton — pressed/hover/focus 的颜色
	var btn := item.get_node_or_null("PN/AlbumButton") as Button
	if btn:
		_modify_button_colors(btn, pri_light, true)

	# PN/CountBase — self_modulate 是属性非共享资源，设在 item_instance 上让 duplicate() 自动带过去
	var count_base := item.get_node_or_null("PN/CountBase") as TextureRect
	if count_base:
		count_base.self_modulate = pri_light

## 修改 songNode 的 item_instance
func _style_song_instance(item: Control, pri_light: Color) -> void:
	# PC/Border
	var border := item.get_node_or_null("PC/Border") as PanelContainer
	if border:
		var sb := border.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.border_color = pri_light

	# PC/HBoxC/CountBase — bg_color
	var count_base := item.get_node_or_null("PC/HBoxC/CountBase") as PanelContainer
	if count_base:
		var sb := count_base.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = pri_light

	# PC/SongButton
	var btn := item.get_node_or_null("PC/SongButton") as Button
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


# ============ 商店视图主题 ============

## 修改 Previ / Next 按钮的已有 StyleBoxFlat 颜色（保留 tscn 的 skew/border/shadow 配置）
func _style_store_nav_button(btn: Button) -> void:
	var base := get_color("primary_dark")

	var normal := btn.get_theme_stylebox("normal")
	if normal is StyleBoxFlat:
		normal.bg_color = base

	var pressed := btn.get_theme_stylebox("pressed")
	if pressed is StyleBoxFlat:
		pressed.bg_color = base.darkened(0.2)

	var hover := btn.get_theme_stylebox("hover")
	if hover is StyleBoxFlat:
		hover.bg_color = base.lightened(0.15)

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
	var previ := store.get_node_or_null("Bottom/Previ") as Button
	if previ:
		_style_store_nav_button(previ)

	var next_btn := store.get_node_or_null("Bottom/Next") as Button
	if next_btn:
		_style_store_nav_button(next_btn)


	# Bottom/Indicate — 页码标签背景 primary_light
	var indicate := store.get_node_or_null("Bottom/Indicate") as Label
	if indicate:
		var sb := indicate.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.bg_color = get_color("primary_light")

# ============ 设置视图主题 ============

## 修改 ShortCut 按钮内联 Theme 中的 StyleBoxFlat（normal/hover/pressed 的 bg_color）
func _style_shortcut_theme(theme: Theme) -> void:
	var p := get_color("primary")
	var pl := get_color("primary_light")
	var pd := get_color("primary_dark")

	var normal := theme.get_stylebox("normal", "Button")
	if normal is StyleBoxFlat:
		normal.bg_color = p

	var hover := theme.get_stylebox("hover", "Button")
	if hover is StyleBoxFlat:
		hover.bg_color = pl

	var pressed := theme.get_stylebox("pressed", "Button")
	if pressed is StyleBoxFlat:
		pressed.bg_color = pd

## 修改 SettingList 内联 Theme 中 Button 状态和 PopupMenu hover 的 StyleBoxFlat
func _style_setting_list_theme(theme: Theme) -> void:
	var p := get_color("primary")
	var pl := get_color("primary_light")
	var pd := get_color("primary_dark")

	# Button 状态
	var normal := theme.get_stylebox("normal", "Button")
	if normal is StyleBoxFlat:
		normal.bg_color = p

	var hover := theme.get_stylebox("hover", "Button")
	if hover is StyleBoxFlat:
		hover.bg_color = pl

	var pressed := theme.get_stylebox("pressed", "Button")
	if pressed is StyleBoxFlat:
		pressed.bg_color = pd

	# PopupMenu hover
	var popup_hover := theme.get_stylebox("hover", "PopupMenu")
	if popup_hover is StyleBoxFlat:
		popup_hover.bg_color = p

## 对 SettingView 的 ShortCut 和 SettingList 内联 Theme 应用主题色
func _apply_setting_theme(main: Node) -> void:
	var setting := main.get_node_or_null("skew/C/SettingView")
	if not setting:
		return

	# HBoxC/ShortCut — 内联 Theme_07r5k
	var shortcut := setting.get_node_or_null("HBoxC/ShortCut") as VBoxContainer
	if shortcut and shortcut.theme:
		_style_shortcut_theme(shortcut.theme)

	# HBoxC/SettingList — 内联 Theme_ys6ou
	var setting_list := setting.get_node_or_null("HBoxC/SettingList") as ScrollContainer
	if setting_list and setting_list.theme:
		_style_setting_list_theme(setting_list.theme)

# ============ MidiView 主题 ============

## 修改 InfoUI 根 Theme (Theme_5hcss) 中的 Button/OptionButton/PopupMenu/TabContainer 样式
func _style_info_ui_theme(theme: Theme) -> void:
	var p := get_color("primary")
	var pl := get_color("primary_light")
	var pd := get_color("primary_dark")

	# Button
	var btn_normal := theme.get_stylebox("normal", "Button")
	if btn_normal is StyleBoxFlat:
		btn_normal.bg_color = p
	var btn_hover := theme.get_stylebox("hover", "Button")
	if btn_hover is StyleBoxFlat:
		btn_hover.bg_color = pl
	var btn_pressed := theme.get_stylebox("pressed", "Button")
	if btn_pressed is StyleBoxFlat:
		btn_pressed.bg_color = pd

	# OptionButton
	var opt_normal := theme.get_stylebox("normal", "OptionButton")
	if opt_normal is StyleBoxFlat:
		opt_normal.bg_color = p
	var opt_hover := theme.get_stylebox("hover", "OptionButton")
	if opt_hover is StyleBoxFlat:
		opt_hover.bg_color = pl
	var opt_pressed := theme.get_stylebox("pressed", "OptionButton")
	if opt_pressed is StyleBoxFlat:
		opt_pressed.bg_color = pd

	# PopupMenu hover
	var popup_hover := theme.get_stylebox("hover", "PopupMenu")
	if popup_hover is StyleBoxFlat:
		popup_hover.bg_color = p

	# TabContainer
	var tab_panel := theme.get_stylebox("panel", "TabContainer")
	if tab_panel is StyleBoxFlat:
		tab_panel.bg_color = pd
	var tab_unselected := theme.get_stylebox("tab_unselected", "TabContainer")
	if tab_unselected is StyleBoxFlat:
		tab_unselected.bg_color = p
	var tab_selected := theme.get_stylebox("tab_selected", "TabContainer")
	if tab_selected is StyleBoxFlat:
		tab_selected.bg_color = pd

## 修改 TabBtn 子 Theme (Theme_n3ivs) 中的 Button 样式
func _style_tab_btn_theme(theme: Theme) -> void:
	var p := get_color("primary")
	var pl := get_color("primary_light")
	var pd := get_color("primary_dark")

	var normal := theme.get_stylebox("normal", "Button")
	if normal is StyleBoxFlat:
		normal.bg_color = p
	var hover := theme.get_stylebox("hover", "Button")
	if hover is StyleBoxFlat:
		hover.bg_color = pl
	var pressed := theme.get_stylebox("pressed", "Button")
	if pressed is StyleBoxFlat:
		pressed.bg_color = pd

## 修改 MidiView 中通过 theme_override_styles 单独设置的节点样式
func _style_midi_individual_nodes(info_ui: Node) -> void:
	var p := get_color("primary")
	var pl := get_color("primary_light")
	var pd := get_color("primary_dark")

	# InfoWindow 边框
	var info_window := info_ui.get_node_or_null("LeftArea/InfoWindow") as PanelContainer
	if info_window:
		var sb := info_window.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.border_color = pl

	# Fold 面板（与 Center 共享同一 StyleBoxFlat_5h6qm）
	var fold := info_ui.get_node_or_null("LeftArea/InfoWindow/HBoxC/Left/Fold") as Panel
	if fold:
		var sb := fold.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = pl

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
	if play_btn:
		var sb_n := play_btn.get_theme_stylebox("normal")
		if sb_n is StyleBoxFlat:
			sb_n.bg_color = pl
		var sb_h := play_btn.get_theme_stylebox("hover")
		if sb_h is StyleBoxFlat:
			sb_h.bg_color = pl.lightened(0.15)
		var sb_p := play_btn.get_theme_stylebox("pressed")
		if sb_p is StyleBoxFlat:
			sb_p.bg_color = pd

	# RedirectButtons/Button
	var redirect_btn := info_ui.get_node_or_null("LeftArea/RedirectButtons/Button") as Button
	if redirect_btn:
		var sb_n := redirect_btn.get_theme_stylebox("normal")
		if sb_n is StyleBoxFlat:
			sb_n.bg_color = p
		var sb_h := redirect_btn.get_theme_stylebox("hover")
		if sb_h is StyleBoxFlat:
			sb_h.bg_color = pl
		var sb_p := redirect_btn.get_theme_stylebox("pressed")
		if sb_p is StyleBoxFlat:
			sb_p.bg_color = pd

	# OptionPanel 背景
	var option_panel := info_ui.get_node_or_null("RightArea/OptionPanel") as PanelContainer
	if option_panel:
		var sb := option_panel.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb.bg_color = pd

## 对 MidiView (InfoUI) 的所有组件应用主题色
func _apply_midi_theme(main: Node) -> void:
	var info_ui := main.get_node_or_null("skew/C/InfoUI")
	if not info_ui:
		return

	# 根 Theme (Theme_5hcss) — Button/OptionButton/PopupMenu/TabContainer
	if info_ui.theme:
		_style_info_ui_theme(info_ui.theme)

	# TabBtn 子 Theme (Theme_n3ivs) — Rank/Mode/Comment 按钮
	var tab_btn := info_ui.get_node_or_null("RightArea/OptionPanel/VBoxC/TabBtn") as HBoxContainer
	if tab_btn and tab_btn.theme:
		_style_tab_btn_theme(tab_btn.theme)

	# 单节点 theme_override_styles
	_style_midi_individual_nodes(info_ui)


# ============ DelView 主题 ============


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


## 对 DelView 的静态部分应用主题色（侧边栏、内容面板、按钮颜色）
## 由 DelView._ready() 和 theme_changed 信号触发
func _apply_delview_theme(main: Node) -> void:
	var delview := main.get_node_or_null("skew/C/SettingView/DelView")
	if not delview:
		return
	var sidebar := delview.get_node_or_null("SideBar")
	var content := delview.get_node_or_null("Content")
	var close_btn := delview.get_node_or_null("SideBar/CloseBtn")

	# 侧边栏背景
	if sidebar:
		style_panel(sidebar, "")  # 会用固定色处理——见下方 override
		var sb := StyleBoxFlat.new()
		sb.bg_color = SIDEBAR_BG
		sidebar.add_theme_stylebox_override("panel", sb)

	# 内容面板
	if content:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = PANEL_BG
		panel_style.corner_radius_top_right = 12
		panel_style.corner_radius_bottom_right = 12
		panel_style.content_margin_left = 24
		panel_style.content_margin_right = 24
		panel_style.content_margin_top = 16
		panel_style.content_margin_bottom = 16
		content.add_theme_stylebox_override("panel", panel_style)

	# 侧边栏 Tab 按钮（从 delview 的 _tab_buttons 获取）
	var tab_btns: Array = delview.get("_tab_buttons")
	for btn in tab_btns:
		if btn is Button:
			style_delview_sidebar_tab(btn, (btn as Button).button_pressed)

	if close_btn:
		close_btn.add_theme_font_size_override("font_size", get_font_size("small", 22))
		close_btn.add_theme_color_override("font_color", get_color("text_secondary"))
		close_btn.add_theme_color_override("font_hover_color", get_color("text_primary"))

	GameLogger.instance.debug("DelView theme applied", "ThemeManager")

## 单个侧边栏 Tab 按钮样式
func style_delview_sidebar_tab(btn: Button, is_active: bool) -> void:
	var normal_bg := get_color("primary") if is_active else CARD_BG
	var hover_bg := get_color("primary_light") if is_active else PANEL_BG
	var pressed_bg := get_color("primary_dark")

	var normal := StyleBoxFlat.new()
	normal.bg_color = normal_bg
	normal.corner_radius_top_left = 8
	normal.corner_radius_bottom_left = 8
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = hover_bg
	hover.corner_radius_top_left = 8
	hover.corner_radius_bottom_left = 8
	hover.content_margin_left = 16
	hover.content_margin_right = 16
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = pressed_bg
	pressed.corner_radius_top_left = 8
	pressed.corner_radius_bottom_left = 8
	pressed.content_margin_left = 16
	pressed.content_margin_right = 16
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_font_size_override("font_size", get_font_size("medium", 32))
	btn.add_theme_color_override("font_color", Color.WHITE if is_active else get_color("text_primary"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

## 操作按钮（全选、取消全选、恢复默认）
func style_delview_action_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = get_color("primary")
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = get_color("primary").lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = get_color("primary").darkened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_font_size_override("font_size", get_font_size("body", 28))
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

## 删除按钮（CARD_BG 底，红色字）
func style_delview_delete_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = CARD_BG
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = CARD_BG.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = CARD_BG.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_font_size_override("font_size", get_font_size("body", 28))
	btn.add_theme_color_override("font_color", DANGER_COLOR)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

## 次要文本标签（文件体积、来源等提示信息）
func style_delview_info_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", get_font_size("small", 22))
	label.add_theme_color_override("font_color", get_color("text_secondary"))

func style_delview_body_size(node: Control) -> void:
	node.add_theme_font_size_override("font_size", get_font_size("body", 28))

func style_delview_large_size(node: Control) -> void:
	node.add_theme_font_size_override("font_size", get_font_size("large", 40))

# ============ 全局刷新 ============

## 主题变更后调用：重建 Theme 资源 + 主界面组件 + 所有背景
func refresh_all() -> void:
	var main := get_node_or_null("/root/Main")
	if not main:
		return

	main.theme = create_theme_resource()
	_apply_main_theme(main)
	_apply_delview_theme(main)
	_apply_all_backgrounds(main)
	_apply_list_theme(main)
	_apply_store_theme(main)
	_apply_setting_theme(main)
	_apply_midi_theme(main)
	_apply_score_theme(main)
	GameLogger.instance.info("主题刷新完成: %s" % _theme_name, "ThemeManager")

func _on_theme_changed(preset_name: String) -> void:
	# 如果信号携带的预设名在配置中存在且与当前不同，应用它
	if _presets.has(preset_name) and preset_name != _theme_name:
		var p: Dictionary = _presets[preset_name]
		for key in p:
			var val: String = p[key]
			if val.is_valid_html_color():
				_palette[key.to_lower()] = Color(val)
		_theme_name = preset_name
		GameLogger.instance.info("主题预设已应用: %s (%d 色)" % [preset_name, _palette.size()], "ThemeManager")
	save_theme()
	refresh_all()

## 仅刷新背景（设置界面修改背景配置后调用）
func refresh_backgrounds() -> void:
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	_apply_all_backgrounds(main)
	GameLogger.instance.info("背景刷新完成", "ThemeManager")

# ============ 内部：主界面组件主题 ============

func _apply_main_theme(main: Node) -> void:
	# LT_Btn — 蓝 (primary)
	var lt := main.get_node_or_null("LT_Btn")
	if lt:
		style_panel(lt, "primary")

	# RB_Btn — 淡蓝 (primary_light)
	var rb := main.get_node_or_null("RB_Btn")
	if rb:
		style_panel(rb, "primary_light")

	# ShortCutMenu 面板 — 蓝 (primary)
	var sc_panel := main.get_node_or_null("skew/C/ShortCutMenu/Panel")
	if sc_panel:
		style_panel(sc_panel, "primary")

	# 覆盖 ShortCutMenu Btns 的内联 Theme，使用根 Theme 的 Button 样式
	var btns := main.get_node_or_null("skew/C/ShortCutMenu/Btns")
	if btns:
		btns.theme = main.theme

	# PlayerInfo 面板 — 暗色 (primary_dark.darkened)
	var info_panel := main.get_node_or_null("PlayerInfo/Info/Panel")
	if info_panel:
		style_panel(info_panel, "primary_dark")

## 修改三个列表容器的 item_instance 共享 StyleBoxFlat，并刷新已有项的非共享属性
func _apply_list_theme(main: Node) -> void:
	var pri_light := get_color("primary_light")

	# AlbumList — 修改 item_instance 共享样式 + 刷新已有项 self_modulate
	var album_view := main.get_node_or_null("skew/C/AlbumList") as BaseScrollList
	if album_view and album_view.item_instance:
		_style_album_instance(album_view.item_instance, pri_light)
		if album_view.has_method("refresh_item_colors"):
			album_view.refresh_item_colors()

	# SongList — 修改 item_instance 共享样式（全部在 StyleBox 中，无需逐项刷新）
	var song_view := main.get_node_or_null("skew/C/SongList") as BaseScrollList
	if song_view and song_view.item_instance:
		_style_song_instance(song_view.item_instance, pri_light)

	# SortedMidisList — 修改 item_instance 共享样式
	var sorted_view := main.get_node_or_null("skew/C/SortedMidisList") as BaseScrollList
	if sorted_view and sorted_view.item_instance:
		_style_sorted_midi_instance(sorted_view.item_instance, pri_light)


# ============ 内部：背景批量应用 ============

func _apply_all_backgrounds(main: Node) -> void:
	# 各视图背景 → TextureRect 节点路径映射
	var bg_map := {
		"main": "Background",
		"score": "ScoreView/BackGround",
		"store": "Store/Background",
		"play": "PlayView/Background",
	}

	for view_name in bg_map:
		var rect := main.get_node_or_null(bg_map[view_name])
		if rect:
			apply_background(rect, view_name)

func get_theme_name() -> String:
	return _theme_name

func is_loaded() -> bool:
	return _loaded

# ============ Theme 资源生成 ============

func create_theme_resource() -> Theme:
	var thm := Theme.new()
	var default_font_size := get_font_size("body", 28)

	# Button — 基于 primary 色，hover 变亮、pressed 变暗
	var normal_bg := get_color("primary", Color("#2E8BF0"))

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = normal_bg
	btn_normal.corner_radius_top_left = 6
	btn_normal.corner_radius_top_right = 6
	btn_normal.corner_radius_bottom_left = 6
	btn_normal.corner_radius_bottom_right = 6
	btn_normal.content_margin_left = 14
	btn_normal.content_margin_right = 14
	btn_normal.content_margin_top = 6
	btn_normal.content_margin_bottom = 6
	thm.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = normal_bg.lightened(0.15)
	thm.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = normal_bg.darkened(0.25)
	thm.set_stylebox("pressed", "Button", btn_pressed)

	var btn_focus := btn_normal.duplicate() as StyleBoxFlat
	btn_focus.bg_color = normal_bg.lightened(0.1)
	thm.set_stylebox("focus", "Button", btn_focus)

	thm.set_color("font_color", "Button", Color.WHITE)
	thm.set_color("font_hover_color", "Button", Color.WHITE)
	thm.set_color("font_pressed_color", "Button", Color.WHITE)
	thm.set_color("font_focus_color", "Button", Color.WHITE)
	thm.set_color("font_disabled_color", "Button", get_color("text_dim"))
	thm.set_color("icon_normal_color", "Button", Color.WHITE)
	thm.set_color("icon_hover_color", "Button", Color.WHITE)
	thm.set_color("icon_pressed_color", "Button", Color.WHITE)
	thm.set_font_size("font_size", "Button", default_font_size)

	# --- Label ---
	thm.set_color("font_color", "Label", get_color("text_primary"))
	thm.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.5))
	thm.set_font_size("font_size", "Label", default_font_size)

	# --- LineEdit ---
	thm.set_color("font_color", "LineEdit", get_color("text_primary"))
	thm.set_color("font_placeholder_color", "LineEdit", get_color("text_dim"))
	thm.set_color("selection_color", "LineEdit", get_color("primary"))
	thm.set_color("caret_color", "LineEdit", get_color("text_primary"))
	thm.set_font_size("font_size", "LineEdit", default_font_size)

	# --- CheckBox ---
	thm.set_color("font_color", "CheckBox", get_color("text_primary"))
	thm.set_font_size("font_size", "CheckBox", default_font_size)

	# --- OptionButton ---
	thm.set_color("font_color", "OptionButton", get_color("text_primary"))
	thm.set_color("font_hover_color", "OptionButton", Color.WHITE)
	thm.set_color("font_pressed_color", "OptionButton", Color.WHITE)
	thm.set_font_size("font_size", "OptionButton", default_font_size)

	# --- PopupMenu ---
	thm.set_color("font_color", "PopupMenu", get_color("text_primary"))
	thm.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	thm.set_font_size("font_size", "PopupMenu", default_font_size)

	# --- ProgressBar ---
	thm.set_color("font_color", "ProgressBar", get_color("text_primary"))

	# --- Panel / PanelContainer 默认背景 ---
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = PANEL_BG
	panel_bg.corner_radius_top_left = 8
	panel_bg.corner_radius_top_right = 8
	panel_bg.corner_radius_bottom_left = 8
	panel_bg.corner_radius_bottom_right = 8
	thm.set_stylebox("panel", "Panel", panel_bg)
	thm.set_stylebox("panel", "PanelContainer", panel_bg)

	GameLogger.instance.debug("Theme resource created (primary=%s)" % normal_bg.to_html(), "ThemeManager")
	return thm

# ============ 内部方法 ============

func _parse_theme_config(cfg: Dictionary) -> void:
	for section in cfg:
		if section is String and (section as String).begins_with("preset_"):
			var name: String = (section as String).replace("preset_", "")
			_presets[name] = cfg[section].duplicate()

	GameLogger.instance.info("加载了 %d 个主题预设" % _presets.size(), "ThemeManager")

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
	gradient.add_point(0.0, top_color)
	gradient.add_point(1.0, bottom_color)

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

func _parse_stretch_mode(mode: String) -> TextureRect.StretchMode:
	match mode:
		"scale": return TextureRect.STRETCH_SCALE
		"tile": return TextureRect.STRETCH_TILE
		"cover": return TextureRect.STRETCH_KEEP_ASPECT_COVERED
		"center": return TextureRect.STRETCH_KEEP_CENTERED
		"keep": return TextureRect.STRETCH_KEEP
	return TextureRect.STRETCH_KEEP_ASPECT_COVERED
