## 收藏夹列表项
## 支持两种交互模式：
## - BROWSE: AlbumView 中点击列表项，跳转到 SortedMidiView 浏览收藏夹内容
## - MANAGE: MidiView 弹窗中点击列表项，切换当前 MIDI 的收藏状态
extends HBoxContainer

class_name FavorListItem

enum Mode { BROWSE, MANAGE }

## 列表项点击（BROWSE 模式）
signal favor_item_clicked(fav_id: String)
## 当前 MIDI 收藏状态切换（MANAGE 模式）
signal favor_midi_toggled(fav_id: String)
## 请求重命名收藏夹
signal favor_item_renamed(fav_id: String, new_name: String)
## 请求删除收藏夹
signal favor_item_deleted(fav_id: String)

var mode: Mode = Mode.BROWSE
var favorite_id: String = ""
var current_midi: MidiData = null

@onready var cover: TextureRect = $Cover
@onready var name_label: Label = $Detail/NameBox/name
@onready var name_box: Control = $Detail/NameBox
@onready var midi_count_label: Label = $Detail/midiCount
@onready var name_edit: LineEdit = $Detail/nameEdit
@onready var action_icon_wrap: Control = $Cover/ActionIconWrap
@onready var action_icon: TextureRect = $Cover/ActionIconWrap/ActionIcon
@onready var manage_btns: HBoxContainer = $ManageBtns
@onready var delete_btn: TextureButton = $ManageBtns/DeleteBtn

const ICON_ADD := "res://Resources/icon/add.png"
const ICON_DELETE := "res://Resources/icon/minus.png"

# 文字滚动动画相关
var _scroll_tween: Tween = null
var _name_full_text: String = ""


func _ready() -> void:
	# 连接管理按钮信号
	delete_btn.pressed.connect(_on_delete_pressed)
	# 点击名称区域进入重命名模式
	name_label.gui_input.connect(_on_name_label_gui_input)
	# 连接 LineEdit 信号
	name_edit.text_submitted.connect(_on_rename_submitted)
	name_edit.focus_exited.connect(_on_rename_focus_exited)


## 点击名称区域：进入重命名模式
func _on_name_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_enter_rename_mode()


## 内置 gui_input：点击列表项主体（非按钮区域）触发主操作
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 编辑模式下不响应点击
		if name_edit.visible:
			return
		if mode == Mode.BROWSE:
			favor_item_clicked.emit(favorite_id)
		else:
			favor_midi_toggled.emit(favorite_id)


## 初始化列表项
func setup(fav: FavoriteListData, p_mode: Mode, p_midi: MidiData = null) -> void:
	favorite_id = fav.id
	mode = p_mode
	current_midi = p_midi
	# 需要等节点准备好
	if not is_node_ready():
		await ready
	_name_full_text = fav.name
	name_label.text = fav.name
	midi_count_label.text = "%d midis" % fav.midi_ids.size()
	# 封面：最近添加的 midi（midi_ids 末尾）
	_load_cover(fav)
	# 模式切换
	_apply_mode()
	# 启动文字滚动动画（如果文字过长）
	call_deferred("_setup_name_scroll")


func _load_cover(fav: FavoriteListData) -> void:
	if fav.midi_ids.is_empty():
		cover.texture = null
		return
	var last_midi_id: String = fav.midi_ids.back()
	var midi := DataMGR.get_midi_by_id(last_midi_id)
	if midi:
		cover.texture = FileSystemManager.instance.get_cover_by_midiData(midi)
	else:
		cover.texture = null


func _apply_mode() -> void:
	var show_action := (mode == Mode.MANAGE) and current_midi != null
	# 整个 Wrap（含黑色背景）在 BROWSE 模式下隐藏
	action_icon_wrap.visible = show_action
	if show_action:
		var in_fav := FavoriteManager.instance.is_midi_in_favorite(favorite_id, current_midi)
		action_icon.texture = load(ICON_DELETE if in_fav else ICON_ADD)
		# tscn 中 ActionIcon 默认 visible=false，需显式开启
		action_icon.visible = true


# ========== 文字滚动动画 ==========

## 检测文字是否超出 Label 显示区域，若超出则启动来回滚动
## 同步计算，避免 await 造成刷新时闪烁
func _setup_name_scroll() -> void:
	# 清理旧动画
	if _scroll_tween:
		_scroll_tween.kill()
		_scroll_tween = null
	# 重置位置
	name_label.position = Vector2.ZERO
	# 获取 box 宽度：优先用已布局的 size，未布局时用 Detail 最小宽度 230 作为 fallback
	var box_width := name_box.size.x
	if box_width <= 10:
		box_width = 230
	var box_height := name_box.size.y
	if box_height <= 10:
		box_height = 50
	# 检测文字宽度
	var text_width := name_label.get_theme_font("font").get_string_size(
		_name_full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")
	).x
	# 设置 Label 尺寸：高度填满 NameBox，宽度取文字宽度和 NameBox 宽度的较大值
	name_label.size = Vector2(max(text_width, box_width), box_height)
	if text_width <= box_width:
		# 文字未超出：居中显示，无需滚动
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	# 文字超出：左对齐 + 来回滚动
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var max_offset := text_width - box_width
	_scroll_tween = create_tween().set_loops()
	_scroll_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# 向右滚动到末端，再回到开头，中间停留
	_scroll_tween.tween_property(name_label, "position:x", -max_offset, 3.0)
	_scroll_tween.tween_interval(1.0)
	_scroll_tween.tween_property(name_label, "position:x", 0, 3.0)
	_scroll_tween.tween_interval(1.0)


# ========== 重命名交互 ==========

func _enter_rename_mode() -> void:
	# 暂停滚动动画
	if _scroll_tween:
		_scroll_tween.kill()
		_scroll_tween = null
	name_label.position.x = 0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.text = _name_full_text
	name_label.visible = false
	name_edit.visible = true
	name_edit.grab_focus()
	name_edit.select_all()


func _on_rename_submitted(_new_name: String) -> void:
	_confirm_rename()


func _on_rename_focus_exited() -> void:
	_confirm_rename()


func _confirm_rename() -> void:
	if not name_edit.visible:
		return
	var new_name := name_edit.text.strip_edges()
	name_edit.visible = false
	name_label.visible = true
	if not new_name.is_empty() and new_name != _name_full_text:
		favor_item_renamed.emit(favorite_id, new_name)
	else:
		# 恢复显示并重启滚动
		_name_full_text = name_label.text
		_setup_name_scroll()


# ========== 删除交互 ==========

func _on_delete_pressed() -> void:
	favor_item_deleted.emit(favorite_id)
