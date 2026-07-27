## 收藏夹列表项
## 支持两种交互模式：
## - BROWSE: AlbumView 中点击列表项，跳转到 SortedMidiView 浏览收藏夹内容
## - MANAGE: MidiView 弹窗中点击列表项，切换当前 MIDI 的收藏状态
extends HBoxContainer

class_name FavorListItem

const TextScrollHelper = preload("res://UI/Components/TextScrollHelper.gd")

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

# 点击 vs 滚动 判定阈值
# 移动距离超过此值视为滚动（非点击），用于避免滚动收藏夹时误触
const TAP_MOVE_THRESHOLD := 15.0

# 文字滚动状态
var _name_scroll_state: TextScrollHelper.State = null
var _name_full_text: String = ""

# 触摸追踪状态：用于区分“点击”与“滚动拖拽”
# 同一时刻只有一个触摸目标，故状态可共享
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_pending: bool = false   # 是否有待释放的触摸
var _touch_on_name: bool = false   # 触摸起点是否在 name Label 上（用于保证按下与释放由同一控件处理）


func _ready() -> void:
	# 连接管理按钮信号
	delete_btn.pressed.connect(_on_delete_pressed)
	# 点击名称区域进入重命名模式
	name_label.gui_input.connect(_on_name_label_gui_input)
	# 拦截删除按钮的触摸事件，防止向上冒泡触发列表项点击
	delete_btn.gui_input.connect(_on_delete_btn_gui_input)
	# 连接 LineEdit 信号
	name_edit.text_submitted.connect(_on_rename_submitted)
	name_edit.focus_exited.connect(_on_rename_focus_exited)

## 点击名称区域：进入重命名模式
## 仅在"按下后未发生明显移动"时才判定为点击，避免滚动误触
## name Label 设为 MOUSE_FILTER_PASS，事件会继续冒泡至 _gui_input，通过 _touch_pending 守卫避免重复处理
func _on_name_label_gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	if event.pressed:
		_touch_start_pos = event.position
		_touch_pending = true
		_touch_on_name = true
	elif _touch_pending and _touch_on_name:
		_touch_pending = false
		if _is_tap(event.position):
			_enter_rename_mode()


## 拦截删除按钮触摸：标记 _touch_pending 以阻止 _gui_input 触发列表项点击
## DeleteBtn 设为 MOUSE_FILTER_PASS，按钮自身的 pressed 信号仍正常工作
func _on_delete_btn_gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	if event.pressed:
		_touch_pending = true
	elif _touch_pending:
		_touch_pending = false


## 内置 gui_input：点击列表项主体（非按钮区域）触发主操作
## 仅在"按下后未发生明显移动"时才判定为点击，避免滚动误触
## FavorListItem 设为 MOUSE_FILTER_PASS，触摸事件会继续冒泡至父级 ScrollContainer 以支持滚动
## 子控件（name Label、DeleteBtn）的 gui_input 先于本函数触发并设置 _touch_pending，通过守卫避免重复处理
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	if event.pressed:
		# 若子控件已认领此触摸（_touch_pending 为 true），跳过以保留其状态
		if _touch_pending:
			return
		_touch_start_pos = event.position
		_touch_pending = true
		_touch_on_name = false
	elif _touch_pending and not _touch_on_name:
		_touch_pending = false
		if _is_tap(event.position):
			# 编辑模式下不响应点击
			if name_edit.visible:
				return
			if mode == Mode.BROWSE:
				favor_item_clicked.emit(favorite_id)
			else:
				favor_midi_toggled.emit(favorite_id)


## 判定触摸释放是否构成有效点击（移动距离小于阈值）
func _is_tap(release_pos: Vector2) -> bool:
	return release_pos.distance_to(_touch_start_pos) <= TAP_MOVE_THRESHOLD


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

## 启动/重算名称滚动动画（委托给 TextScrollHelper）
## 视觉规范：名称始终左对齐（与协作者微调一致）
func _setup_name_scroll() -> void:
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_scroll_state = TextScrollHelper.setup(
		name_label, name_box, _name_full_text, _name_scroll_state
	)


# ========== 重命名交互 ==========

func _enter_rename_mode() -> void:
	# 暂停滚动动画并重置位置
	TextScrollHelper.stop(_name_scroll_state)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.text = _name_full_text
	name_box.visible = false
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
	name_box.visible = true
	if not new_name.is_empty() and new_name != _name_full_text:
		favor_item_renamed.emit(favorite_id, new_name)
	else:
		# 恢复显示并重启滚动
		_name_full_text = name_label.text
		_setup_name_scroll()


# ========== 删除交互 ==========

func _on_delete_pressed() -> void:
	favor_item_deleted.emit(favorite_id)
