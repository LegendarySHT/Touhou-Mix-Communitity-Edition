extends VBoxContainer
class_name ProfilePage

## 个人信息详情页：Profile / History / Edit 三页切换
## Profile 页显示资料，Edit 页提供修改功能

## 资料更新成功后通知外部刷新（PlayerInfoContent 监听）
signal profile_updated()

## 头像加载完成后的纹理（供 PlayerInfoContent 同步到 MiniInfo/ProfileView）
signal avatar_loaded(texture: Texture2D)

# ========== PageContent（Profile / History / Edit） ==========
@onready var page_content: TabContainer = $PC/PageContent
@onready var navi_profile_btn: Button = $Navi/Btns/Profile
@onready var navi_history_btn: Button = $Navi/Btns/History
@onready var navi_edit_btn: Button = $Navi/Btns/Edit

# ========== History 页面 List 切换 ==========
@onready var history_list: TabContainer = $PC/PageContent/History/List
@onready var recent_play_btn: Button = $PC/PageContent/History/PC/TopBar/TopBtns/RecentPlay
@onready var best_play_btn: Button = $PC/PageContent/History/PC/TopBar/TopBtns/BestPlay
@onready var most_play_btn: Button = $PC/PageContent/History/PC/TopBar/TopBtns/MostPlay

# ========== Profile 页显示节点 ==========
@onready var profile_name_label: Label = $PC/PageContent/Profile/Main/Header/HBoxContainer/NameLevelVBox/NameLabel
@onready var profile_pp_label: Label = $PC/PageContent/Profile/Main/Header/HBoxContainer/NameLevelVBox/Level/PPLabel
@onready var profile_bio_label: Label = $PC/PageContent/Profile/Data/VBox/Desc/Label
@onready var profile_avatar_rect: TextureRect = $PC/PageContent/Profile/Main/Header/HBoxContainer/AvatarBig/TextureRect

# ========== History 页统计显示节点（TopBar/Grid） ==========
@onready var history_pp_label: Label = $PC/PageContent/History/PC/TopBar/PC/InnerMargin/Grid/pp
@onready var history_s_count: Label = $PC/PageContent/History/PC/TopBar/PC/InnerMargin/Grid/SCount
@onready var history_a_count: Label = $PC/PageContent/History/PC/TopBar/PC/InnerMargin/Grid/ACount
@onready var history_b_count: Label = $PC/PageContent/History/PC/TopBar/PC/InnerMargin/Grid/BCount
@onready var history_c_count: Label = $PC/PageContent/History/PC/TopBar/PC/InnerMargin/Grid/CCount
@onready var history_d_count: Label = $PC/PageContent/History/PC/TopBar/PC/InnerMargin/Grid/DCount
@onready var history_f_count: Label = $PC/PageContent/History/PC/TopBar/PC/InnerMargin/Grid/FCount

# ========== Edit 页输入节点 ==========
@onready var nickname_edit: LineEdit = $PC/PageContent/Edit/HBox/ProfileEdit/Nickname/LineEdit
@onready var desc_edit: LineEdit = $PC/PageContent/Edit/HBox/ProfileEdit/Desc/LineEdit
@onready var old_pwd_edit: LineEdit = $PC/PageContent/Edit/HBox/OtherEdit/Password/LineEdit
@onready var new_pwd_edit: LineEdit = $PC/PageContent/Edit/HBox/OtherEdit/NewPassword/LineEdit
@onready var avatar_preview_rect: TextureRect = $PC/PageContent/Edit/HBox/OtherEdit/AvatorEdit/Border/Avatar
@onready var nickname_confirm_btn: Button = $PC/PageContent/Edit/HBox/ProfileEdit/Nickname/ConfirmBtn
@onready var desc_confirm_btn: Button = $PC/PageContent/Edit/HBox/ProfileEdit/Desc/ConfirmBtn
@onready var pwd_confirm_btn: Button = $PC/PageContent/Edit/HBox/OtherEdit/NewPassword/ConfirmBtn
@onready var upload_avatar_btn: Button = $PC/PageContent/Edit/HBox/OtherEdit/AvatorEdit/UploadBtn

# ========== 主题色引用节点（每个共享 StyleBox 取一个代表节点） ==========
@onready var _info_panel: PanelContainer = $PC/PageContent/Profile/Main/PC/Displayer/Info
@onready var _header_panel: PanelContainer = $PC/PageContent/Profile/Main/Header
@onready var _play_panel: PanelContainer = $PC/PageContent/Profile/Data/VBox/Play
@onready var _rank_total: PanelContainer = $PC/PageContent/Profile/Data/VBox/Desc/Rank/RankTotal
@onready var _navi_panel: PanelContainer = $Navi
@onready var _history_pc: PanelContainer = $PC/PageContent/History/PC
@onready var _edit_confirm_btn: Button = $PC/PageContent/Edit/HBox/ProfileEdit/Nickname/ConfirmBtn

# PageContent tab 索引
const TAB_PROFILE := 0
const TAB_HISTORY := 1
const TAB_EDIT := 2
# History/List tab 索引
const LIST_RECENT := 0
const LIST_BEST := 1
const LIST_MOST := 2

## 操作进行中（防止重复点击）
var _busy: bool = false
## 头像 FileDialog（运行时创建）
var _avatar_file_dialog: FileDialog = null
## 头像图片 HTTP 加载请求（避免重复加载）
var _avatar_load_token: int = 0

func _ready() -> void:
	navi_profile_btn.pressed.connect(_on_navi_profile_pressed)
	navi_history_btn.pressed.connect(_on_navi_history_pressed)
	navi_edit_btn.pressed.connect(_on_navi_edit_pressed)
	recent_play_btn.pressed.connect(_on_recent_play_pressed)
	best_play_btn.pressed.connect(_on_best_play_pressed)
	most_play_btn.pressed.connect(_on_most_play_pressed)
	_sync_navi_selection(page_content.current_tab)
	_sync_topbtn_z_index(recent_play_btn)
	# 密码输入框设为密文
	old_pwd_edit.secret = true
	new_pwd_edit.secret = true
	if ThemeMGR:
		ThemeMGR.register_theme_applier(self)
		apply_theme()

func _exit_tree() -> void:
	if ThemeMGR:
		ThemeMGR.unregister_theme_applier(self)

# ========== 主题色应用 ==========

## 规则：亮蓝 bg → primary_light，暗蓝 bg → primary_dark，中等蓝 bg → primary
## 暗蓝边框 → primary_dark.darkened()，亮蓝边框 → primary_light
## 近黑 bg 保持不动，只替换蓝色边框
func apply_theme() -> void:
	var pl := ThemeMGR.get_color("primary_light")
	var p := ThemeMGR.get_color("primary")
	var pd := ThemeMGR.get_color("primary_dark")
	var pd_darker := pd.darkened(0.2)

	# Profile 页面面板
	_set_panel(_info_panel, pl, pd_darker)      # Info: 亮蓝 bg, 暗蓝 border
	_set_panel(_header_panel, pd, pl)            # Header: 暗蓝 bg, 亮蓝 border
	_set_panel(_play_panel, pd, pl)              # Play + Desc Label（共享）: 暗蓝 bg, 亮蓝 border
	_set_panel(_rank_total, pl, pd_darker)       # RankTotal: 亮蓝 bg, 暗蓝 border
	# Navi 面板
	_set_panel(_navi_panel, pl, pd_darker)       # Navi: 亮蓝 bg, 暗蓝 border
	# History 顶部面板（近黑 bg 保持，只改暗蓝边框）
	_set_panel_border(_history_pc, pd_darker)
	# Navi 按钮（normal/pressed/hover/focus 共享 StyleBox，改 navi_profile_btn 即同步全部）
	# pressed 与 InfoPanelBtn 按下态同色（primary_dark），视觉上融入 PlayerInfo 面板背景
	_set_btn(navi_profile_btn, "normal", pl, pd_darker)
	_set_btn(navi_profile_btn, "pressed", pd, pd_darker)
	_set_btn(navi_profile_btn, "hover", p, pd_darker)
	_set_btn(navi_profile_btn, "focus", p, pd_darker)
	# History TopBtns（近黑 bg 保持，只改蓝色边框）
	_set_btn_border(recent_play_btn, "pressed", pl)
	_set_btn_border(recent_play_btn, "hover", pl)
	# MostPlay hover 用单独 StyleBox（665dv，近黑 bg），只改边框
	_set_btn_border(most_play_btn, "hover", pl)
	# Edit 页面 ConfirmBtn / UploadBtn（共享 StyleBox）
	_set_btn(_edit_confirm_btn, "normal", pl, pl)
	_set_btn(_edit_confirm_btn, "pressed", pd, pl)
	_set_btn(_edit_confirm_btn, "hover", p, pl)

## 设置面板 bg + border
func _set_panel(node: Control, bg: Color, border: Color) -> void:
	if not node:
		return
	var sb := node.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.bg_color = bg
		sb.border_color = border

## 仅设置面板 border（保留原 bg）
func _set_panel_border(node: Control, border: Color) -> void:
	if not node:
		return
	var sb := node.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.border_color = border

## 设置按钮某状态的 bg + border
func _set_btn(btn: Button, state: String, bg: Color, border: Color) -> void:
	if not btn:
		return
	var sb := btn.get_theme_stylebox(state)
	if sb is StyleBoxFlat:
		sb.bg_color = bg
		sb.border_color = border

## 仅设置按钮某状态的 border（保留原 bg 和 border alpha）
func _set_btn_border(btn: Button, state: String, border: Color) -> void:
	if not btn:
		return
	var sb := btn.get_theme_stylebox(state)
	if sb is StyleBoxFlat:
		var a = sb.border_color.a
		sb.border_color = Color(border.r, border.g, border.b, a)

# ========== Navi → PageContent 切换 ==========

func _on_navi_profile_pressed() -> void:
	page_content.current_tab = TAB_PROFILE

func _on_navi_history_pressed() -> void:
	page_content.current_tab = TAB_HISTORY

func _on_navi_edit_pressed() -> void:
	page_content.current_tab = TAB_EDIT

func _sync_navi_selection(tab_idx: int) -> void:
	navi_profile_btn.button_pressed = (tab_idx == TAB_PROFILE)
	navi_history_btn.button_pressed = (tab_idx == TAB_HISTORY)
	navi_edit_btn.button_pressed = (tab_idx == TAB_EDIT)

# ========== History TopBar → List 切换 + z_index ==========

func _on_recent_play_pressed() -> void:
	_switch_history_list(LIST_RECENT, recent_play_btn)

func _on_best_play_pressed() -> void:
	_switch_history_list(LIST_BEST, best_play_btn)

func _on_most_play_pressed() -> void:
	_switch_history_list(LIST_MOST, most_play_btn)

## 切换 History/List 的 tab，并把激活按钮 z_index 抬到 1，其余压回 0
## 避免相邻按钮 stylebox 超边界部分被遮挡
func _switch_history_list(tab_idx: int, active_btn: Button) -> void:
	if tab_idx < history_list.get_tab_count():
		history_list.current_tab = tab_idx
	_sync_topbtn_z_index(active_btn)

func _sync_topbtn_z_index(active_btn: Button) -> void:
	recent_play_btn.z_index = 1 if recent_play_btn == active_btn else 0
	best_play_btn.z_index = 1 if best_play_btn == active_btn else 0
	most_play_btn.z_index = 1 if most_play_btn == active_btn else 0

# ========== 资料显示（由 PlayerInfoContent 调用） ==========

## 从 PlayerInfoContent 传入玩家数据，更新 Profile 页显示
func update_display(data: Dictionary) -> void:
	var display_name_raw = data.get("display_name", "")
	var display_name := str(display_name_raw) if display_name_raw != null else ""
	if display_name.is_empty() or display_name == "<null>":
		var name_raw = data.get("name", "Anonymous Player")
		display_name = str(name_raw) if name_raw != null else "Anonymous Player"
	profile_name_label.text = display_name
	profile_pp_label.text = "%.2f pp" % float(data.get("pp", 0.0))
	var bio_raw = data.get("bio", "")
	var bio := str(bio_raw) if bio_raw != null else ""
	profile_bio_label.text = bio if not bio.is_empty() and bio != "<null>" else "还没有填写简介..."
	# 同步 History 页统计：总 pp + 各评级数量
	history_pp_label.text = "%.2f pp" % float(data.get("pp", 0.0))
	var grades = data.get("grades", {})
	if grades == null:
		grades = {}
	history_s_count.text = str(int(grades.get("S", 0)))
	history_a_count.text = str(int(grades.get("A", 0)))
	history_b_count.text = str(int(grades.get("B", 0)))
	history_c_count.text = str(int(grades.get("C", 0)))
	history_d_count.text = str(int(grades.get("D", 0)))
	history_f_count.text = str(int(grades.get("F", 0)))
	# 同步 Edit 页输入框为当前值
	nickname_edit.text = display_name
	desc_edit.text = bio
	# 加载头像
	var avatar_url = data.get("avatar_url", "")
	if avatar_url == null:
		avatar_url = ""
	_load_avatar_async(str(avatar_url))

## 异步加载头像（从服务端 URL），同时更新 Profile 页和 Edit 页预览
func _load_avatar_async(avatar_url: String) -> void:
	if avatar_url.is_empty():
		return
	if NetManager.instance == null or not NetManager.instance.is_online:
		return
	_avatar_load_token += 1
	var my_token := _avatar_load_token
	var full_url := "%s%s" % [NetManager.instance.server_url, avatar_url]
	var http := HTTPRequest.new()
	add_child(http)
	var req_err := http.request(full_url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if req_err != OK:
		GLogger.warning("Avatar request failed to start: err=%d url=%s" % [req_err, full_url], "ProfilePage")
		http.queue_free()
		return
	var resp = await http.request_completed
	if my_token != _avatar_load_token:
		http.queue_free()
		return
	var result_code = resp[0]
	var response_code = resp[1]
	var response_body = resp[3]
	http.queue_free()
	if result_code != HTTPRequest.RESULT_SUCCESS:
		GLogger.warning("Avatar download failed: result=%d url=%s" % [result_code, full_url], "ProfilePage")
		return
	if response_code != 200:
		GLogger.warning("Avatar HTTP %d: url=%s" % [response_code, full_url], "ProfilePage")
		return
	if not response_body is PackedByteArray or response_body.size() == 0:
		GLogger.warning("Avatar response body empty: url=%s" % full_url, "ProfilePage")
		return
	var image := Image.new()
	var err := OK
	# 根据扩展名选择解码器，避免无关解码器报错
	var ext := full_url.get_extension().to_lower()
	if ext == "jpg" or ext == "jpeg":
		err = image.load_jpg_from_buffer(response_body)
	elif ext == "png":
		err = image.load_png_from_buffer(response_body)
	else:
		# 未知扩展名：尝试两种格式
		err = image.load_png_from_buffer(response_body)
		if err != OK:
			err = image.load_jpg_from_buffer(response_body)
	if err != OK:
		GLogger.warning("Avatar image decode failed (not PNG/JPG): url=%s" % full_url, "ProfilePage")
		return
	var tex := ImageTexture.create_from_image(image)
	profile_avatar_rect.texture = tex
	avatar_preview_rect.texture = tex
	avatar_loaded.emit(tex)
	GLogger.info("Avatar loaded: %s" % full_url, "ProfilePage")

# ========== Edit 页面：资料修改 ==========

## 保存昵称
func _on_save_nickname_btn_pressed() -> void:
	if _busy:
		return
	if AuthManager.instance == null or not AuthManager.instance.is_logged_in:
		return
	var new_name := nickname_edit.text.strip_edges()
	if new_name.is_empty():
		return
	_busy = true
	nickname_confirm_btn.disabled = true
	var result: Dictionary = await AuthManager.instance.update_profile(new_name, null)
	_busy = false
	nickname_confirm_btn.disabled = false
	if result.get("ok", false):
		GLogger.info("Nickname updated: %s" % new_name, "ProfilePage")
		profile_updated.emit()
	else:
		GLogger.warning("Nickname update failed: %s" % str(result.get("error", "")), "ProfilePage")

## 保存简介
func _on_save_desc_btn_pressed() -> void:
	if _busy:
		return
	if AuthManager.instance == null or not AuthManager.instance.is_logged_in:
		return
	var new_bio := desc_edit.text.strip_edges()
	_busy = true
	desc_confirm_btn.disabled = true
	var result: Dictionary = await AuthManager.instance.update_profile(null, new_bio)
	_busy = false
	desc_confirm_btn.disabled = false
	if result.get("ok", false):
		GLogger.info("Bio updated", "ProfilePage")
		profile_updated.emit()
	else:
		GLogger.warning("Bio update failed: %s" % str(result.get("error", "")), "ProfilePage")

## 修改密码
func _on_save_pwd_btn_pressed() -> void:
	if _busy:
		return
	if AuthManager.instance == null or not AuthManager.instance.is_logged_in:
		return
	var old_pwd := old_pwd_edit.text
	var new_pwd := new_pwd_edit.text
	if old_pwd.is_empty() or new_pwd.is_empty():
		return
	if new_pwd.length() < 6:
		new_pwd_edit.text = ""
		return
	_busy = true
	pwd_confirm_btn.disabled = true
	var result: Dictionary = await AuthManager.instance.change_password(old_pwd, new_pwd)
	_busy = false
	pwd_confirm_btn.disabled = false
	if result.get("ok", false):
		GLogger.info("Password changed", "ProfilePage")
		old_pwd_edit.text = ""
		new_pwd_edit.text = ""
	else:
		GLogger.warning("Password change failed: %s" % str(result.get("error", "")), "ProfilePage")
		old_pwd_edit.text = ""

## 上传头像：弹出 FileDialog 选择图片
func _on_upload_avatar_btn_pressed() -> void:
	if _busy:
		return
	if AuthManager.instance == null or not AuthManager.instance.is_logged_in:
		return
	if NetManager.instance == null or not NetManager.instance.is_online:
		return
	if _avatar_file_dialog == null:
		_avatar_file_dialog = FileDialog.new()
		_avatar_file_dialog.use_native_dialog = true
		_avatar_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_avatar_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_avatar_file_dialog.filters = PackedStringArray(["*.png ; PNG Image", "*.jpg ; JPEG Image", "*.jpeg ; JPEG Image"])
		_avatar_file_dialog.title = "选择头像图片"
		add_child(_avatar_file_dialog)
		_avatar_file_dialog.file_selected.connect(_on_avatar_file_selected)
	_avatar_file_dialog.popup_centered_clamped(Vector2i(800, 600))

## FileDialog 选择图片后：读取 + base64 编码 + 上传
func _on_avatar_file_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	_busy = true
	upload_avatar_btn.disabled = true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_busy = false
		upload_avatar_btn.disabled = false
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() == 0:
		_busy = false
		upload_avatar_btn.disabled = false
		return
	# 限制约 2MB
	if bytes.size() > 2 * 1024 * 1024:
		GLogger.warning("Avatar too large (>%d bytes), skipping" % (2 * 1024 * 1024), "ProfilePage")
		_busy = false
		upload_avatar_btn.disabled = false
		return
	var image_base64 := Marshalls.raw_to_base64(bytes)
	# 推断 content type
	var content_type := ""
	var ext := path.get_extension().to_lower()
	if ext == "png":
		content_type = "image/png"
	elif ext == "jpg" or ext == "jpeg":
		content_type = "image/jpeg"
	var result: Dictionary = await AuthManager.instance.upload_avatar(image_base64, content_type)
	_busy = false
	upload_avatar_btn.disabled = false
	if result.get("ok", false):
		GLogger.info("Avatar uploaded", "ProfilePage")
		# 直接从上传响应中提取 avatarUrl 并立即加载头像
		if result.data is Dictionary:
			var av = result.data.get("avatarUrl", "")
			var av_url := str(av) if av != null else ""
			if not av_url.is_empty():
				_load_avatar_async(av_url)
		profile_updated.emit()
	else:
		GLogger.warning("Avatar upload failed: %s" % str(result.get("error", "")), "ProfilePage")
