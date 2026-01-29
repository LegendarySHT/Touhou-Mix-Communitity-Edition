extends BaseScrollList
class_name SettingList

var item_separator: String = "res://UI/Views/SettingView/Seperator.tscn"
var setting_items: Dictionary = {}  # 存储所有设置项，键为id，值为SettingItem

# 设置项分组数据
var setting_groups = [
	{
		"name": "常规设置",
		"settings": [
			{
				"id": "online_mode",
				"name_en": "Online Mode",
				"name_zh": "线上模式",
				"description": "选择no后，需要网络的功能不会运作",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "language",
				"name_en": "Language",
				"name_zh": "语言",
				"description": "选择游戏界面的语言",
				"type": "TYPE_OPTION",
				"default_value": "1",
				"options": [
					{"text_en": "English", "text_zh": "英文"},
					{"text_en": "Chinese", "text_zh": "中文"}
				]
			},
			{
				"id": "server_address",
				"name_en": "Server Address",
				"name_zh": "服务器地址",
				"description": "输入服务器的地址",
				"type": "TYPE_LINE_EDIT",
				"default_value": "thmix.org",
			},
			{
				"id": "reload_builtin_resources",
				"name_en": "Reload Built-in Resources",
				"name_zh": "重置内置资源",
				"description": "选择后，内置的资源将重新加载",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			}
		]
	},
	{
		"name": "播放设置",
		"settings": [
			{
				"id": "performing_mode",
				"name_en": "Performing Mode",
				"name_zh": "弹奏模式",
				"description": "选择no后，即使不去点击下落的音符，选择了的音轨也会正常发声",
				"type": "TYPE_OPTION",
				"default_value": "1",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "play_ready_animation",
				"name_en": "Play Ready Animation",
				"name_zh": "播放准备动画",
				"description": "关闭后，音乐开始前不会有准备动画",
				"type": "TYPE_OPTION",
				"default_value": "1",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "playback_speed_scaling",
				"name_en": "Playback Speed Scaling",
				"name_zh": "播放速度设定",
				"description": "调整音乐的播放倍率，数值越大速度越快",
				"type": "TYPE_LINE_EDIT",
				"default_value": "1.0",
				"unit": "x"
			},
			{
				"id": "vibrate_on_touch",
				"name_en": "Vibrate on Touch",
				"name_zh": "触摸震动反馈",
				"description": "选择是否在点击音符时使设备震动",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "vibration_duration",
				"name_en": "Vibration Duration",
				"name_zh": "震动持续时间",
				"description": "设置点击音符时震动的持续时间，单位：毫秒",
				"type": "TYPE_LINE_EDIT",
				"default_value": "50",
				"unit": "ms"
			},
			{
				"id": "use_system_stopwatch",
				"name_en": "Use System Stopwatch",
				"name_zh": "使用系统时钟",
				"description": "通过使用系统时钟(硬件时钟)来提高精度，如果游戏内音频时而提前时而延后可以启用",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "soundfont_select",
				"name_en": "Sound Font",
				"name_zh": "音源选择",
				"description": "选择MIDI播放时使用的音源文件。user://files/Soundfont/中的音源会覆盖内置版本",
				"type": "TYPE_OPTION",
				"default_value": "GeneralUser-GS.sf2",
				"options": [],
				"dynamic_options": true
			}
		]
	},
	{
		"name": "轨道设置",
		"settings": [
			{
				"id": "lane_count",
				"name_en": "Lane Count",
				"name_zh": "下落轨道数量",
				"description": "设置音符的下落轨道数，数值过高可能会提升出现重叠的音符的概率",
				"type": "TYPE_LINE_EDIT",
				"default_value": "12",
				"unit": "lanes"
			},
			{
				"id": "keyboard_mode",
				"name_en": "Keyboard Mode",
				"name_zh": "鍵盤模式",
				"description": "用键盘来玩THMIX，打开后判定线上会显示所设置的键位名称",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "keyboard_mode_keys",
				"name_en": "Keyboard Mode Keys",
				"name_zh": "键盘键位设置",
				"description": "设置用于点击的键盘按键，不同内容间的英文逗号分隔",
				"type": "TYPE_LINE_EDIT",
				"default_value": "A,S,D,F,J,K,L,;"
			},
			{
				"id": "flash_alpha",
				"name_en": "Flash Alpha",
				"name_zh": "光柱不透明度",
				"description": "修改光柱的不透明度，有效范围为[0, 1]",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.8"
			},
			{
				"id": "perfect_spark_preset",
				"name_en": "Perfect Spark Preset",
				"name_zh": "Perfect特效设定",
				"description": "点击选框或左右两旁的按钮更改按键特效的样式",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Default", "text_zh": "默认"},
					{"text_en": "Simple", "text_zh": "简单"}
				]
			},
			{
				"id": "perfect_spark_scaling",
				"name_en": "Perfect Spark Scaling",
				"name_zh": "Perfect特效大小",
				"description": "调整按键特效的半径",
				"type": "TYPE_LINE_EDIT",
				"default_value": "50",
				"unit": "px"
			},
			{
				"id": "great_spark_preset",
				"name_en": "Great Spark Preset",
				"name_zh": "Great特效设定",
				"description": "同【Perfect特效设定】",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Default", "text_zh": "默认"},
					{"text_en": "Simple", "text_zh": "简单"}
				]
			},
			{
				"id": "great_spark_scaling",
				"name_en": "Great Spark Scaling",
				"name_zh": "Great特效大小",
				"description": "调整按键特效的半径",
				"type": "TYPE_LINE_EDIT",
				"default_value": "50",
				"unit": "px"
			},
			{
				"id": "good_spark_preset",
				"name_en": "Good Spark Preset",
				"name_zh": "Good特效设定",
				"description": "同【Perfect特效设定】",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Default", "text_zh": "默认"},
					{"text_en": "Simple", "text_zh": "简单"}
				]
			},
			{
				"id": "good_spark_scaling",
				"name_en": "Good Spark Scaling",
				"name_zh": "Good特效大小",
				"description": "调整按键特效的半径",
				"type": "TYPE_LINE_EDIT",
				"default_value": "50",
				"unit": "px"
			},
			{
				"id": "bad_spark_preset",
				"name_en": "Bad Spark Preset",
				"name_zh": "Bad特效设定",
				"description": "同【Perfect特效设定】",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Default", "text_zh": "默认"},
					{"text_en": "Simple", "text_zh": "简单"}
				]
			},
			{
				"id": "bad_spark_scaling",
				"name_en": "Bad Spark Scaling",
				"name_zh": "Bad特效大小",
				"description": "调整按键特效的半径",
				"type": "TYPE_LINE_EDIT",
				"default_value": "1.0",
				"unit": "px"
			}
		]
	},
	{
		"name": "判定设置",
		"settings": [
			{
				"id": "touch_judging_criteria",
				"name_en": "Touch Judging Criteria",
				"name_zh": "判定方式",
				"description": "使音符的判定范围变为半径为【音符判定宽度】所设定的数值的圆，手指在以外区域的点击不会生效",
				"type": "TYPE_OPTION",
				"default_value": "3",
				"options": [
					{"text_en": "Nearest", "text_zh": "最临近"},
					{"text_en": "Best Timing", "text_zh": "最佳时机"},
					{"text_en": "Nearest from Judge Line", "text_zh": "距判定线最近"},
					{"text_en": "Best Timing (First In, First Out)", "text_zh": "最佳时机(先现先判)"}
				]
			},
			{
				"id": "check_instant_blocks_when_finger_up",
				"name_en": "Check Instant Blocks When Finger Up",
				"name_zh": "抬手时判定滑块",
				"description": "若启用该项，在抬起手指时，处于判定范围内的滑块会进行判定",
				"type": "TYPE_OPTION",
				"default_value": "1",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "only_perfect_instant_blocks_before_judge",
				"name_en": "Only Perfect Instant Blocks Before Judge",
				"name_zh": "仅判定完美滑块",
				"description": "若打开此项，在滑块落至完美判定区间的范围前无法被判定，即使主动点击",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "judge_line_position",
				"name_en": "Judge Line Position",
				"name_zh": "判定线高度",
				"description": "调整判定线距离屏幕底部的距离",
				"type": "TYPE_LINE_EDIT",
				"default_value": "200",
				"unit": "px"
			},
			{
				"id": "block_judging_width",
				"name_en": "Block Judging Width",
				"name_zh": "音符判定宽度",
				"description": "调整音符的判定范围的宽度，不影响判定范围的高度",
				"type": "TYPE_LINE_EDIT",
				"default_value": "100",
				"unit": "px"
			},
			{
				"id": "min_block_spacing",
				"name_en": "Min Block Spacing",
				"name_zh": "最小横向音符间距",
				"description": "控制音符间的水平最小距离，数值太大会导致没有音符下落",
				"type": "TYPE_LINE_EDIT",
				"default_value": "50",
				"unit": "px"
			},
			{
				"id": "canvas_horizontal_padding",
				"name_en": "Canvas Horizontal Padding",
				"name_zh": "安全区域宽度设定",
				"description": "控制生成的音符与屏幕左右其中一边的最小距离，会影响音符生成位置",
				"type": "TYPE_LINE_EDIT",
				"default_value": "100",
				"unit": "px"
			},
			{
				"id": "judge_time_offset",
				"name_en": "Judge Time Offset",
				"name_zh": "按键判定延迟偏移",
				"description": "调整判定提前或延后的时间，不会使音符提前或延后生成",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0",
				"unit": "ms"
			},
			{
				"id": "perfect_time",
				"name_en": "Perfect Time",
				"name_zh": "Perfect判定范围",
				"description": "控制perfect评分的判定时间范围",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.05",
				"unit": "ms"
			},
			{
				"id": "great_time",
				"name_en": "Great Time",
				"name_zh": "Great判定范围",
				"description": "控制great评分的判定时间范围",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.1",
				"unit": "ms"
			},
			{
				"id": "good_time",
				"name_en": "Good Time",
				"name_zh": "Good判定范围",
				"description": "控制good评分的判定时间范围",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.15",
				"unit": "ms"
			},
			{
				"id": "bad_time",
				"name_en": "Bad Time",
				"name_zh": "Bad判定范围",
				"description": "控制bad评分的判定时间范围",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.2",
				"unit": "ms"
			}
		]
	},
	{
		"name": "生成设置",
		"settings": [
			{
				"id": "instant_block_max_time",
				"name_en": "Instant Block Max Time",
				"name_zh": "生成滑块最大时间",
				"description": "控制滑块的生成时间，使长度低于此时间的Note变成滑块",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.5",
				"unit": "s"
			},
			{
				"id": "short_block_max_time",
				"name_en": "Short Block Max Time",
				"name_zh": "生成短块最大时间",
				"description": "使低于此时间，高于滑块生成时间的音符变为点块",
				"type": "TYPE_LINE_EDIT",
				"default_value": "1.0",
				"unit": "s"
			},
			{
				"id": "max_simultaneous_blocks",
				"name_en": "Max Simultaneous Blocks",
				"name_zh": "最大并排下落音符",
				"description": "控制同时下落的音符的最大数量",
				"type": "TYPE_LINE_EDIT",
				"default_value": "3"
			},
			{
				"id": "min_tap_interval",
				"name_en": "Min Tap Interval",
				"name_zh": "连点最小时间间隔",
				"description": "使一个点块后跟着的与其间隔时间低于此时间的所有点块变成滑块",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.2",
				"unit": "s"
			},
			{
				"id": "min_touch_cooldown_time",
				"name_en": "Min Touch Cooldown Time",
				"name_zh": "最小点击冷却时间",
				"description": "在一段纵连之中，如果上下相邻的音符之间的间隔时间超过最小点击冷却时间",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.2",
				"unit": "s"
			},
			{
				"id": "max_touch_move_speed",
				"name_en": "Max Touch Move Speed",
				"name_zh": "手指最大移动速度",
				"description": "使各个相邻的音符之间的水平距离在设置的数值所推算出来的距离之间",
				"type": "TYPE_LINE_EDIT",
				"default_value": "500",
				"unit": "px/s"
			},
			{
				"id": "max_block_coalesce_time",
				"name_en": "Max Block Coalesce Time",
				"name_zh": "每个批次最大时间",
				"description": "控制每组下落的音符的时间间隔",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.5",
				"unit": "s"
			}
		]
	},
	{
		"name": "外观设置",
		"settings": [
			{
				"id": "randomize_block_color",
				"name_en": "Randomize Block Color",
				"name_zh": "随机音符顏色",
				"description": "随机设置下落音符的颜色。由于光柱特效的颜色与音符的颜色相同，所以当玩家使用自定义皮肤时该设置项相当于随机设置光柱特效的颜色",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "sync_color_across_block_type",
				"name_en": "Sync Color Across Block Type",
				"name_zh": "统一音符颜色",
				"description": "使点块、滑块和长条的颜色统一，同时也会统一光柱特效的颜色，但打开此项后音符颜色无法随机",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "instant_block_color",
				"name_en": "Instant Block Color",
				"name_zh": "更改滑块颜色",
				"description": "通过输入RGB颜色编码或颜色的英文名字来改变滑块及其光柱特效颜色",
				"type": "TYPE_COLOR",
				"default_value": "#FF6B6B"
			},
			{
				"id": "short_block_color",
				"name_en": "Short Block Color",
				"name_zh": "更改点块颜色",
				"description": "通过输入RGB颜色编码或颜色的英文名字来改变点块及其光柱特效颜色",
				"type": "TYPE_COLOR",
				"default_value": "#4ECDC4"
			},
			{
				"id": "long_block_color",
				"name_en": "Long Block Color",
				"name_zh": "更改长条颜色",
				"description": "通过输入RGB颜色编码或颜色的英文名字来改变长条及其光柱特效颜色",
				"type": "TYPE_COLOR",
				"default_value": "#45B7D1"
			},
			{
				"id": "custom_block_skin_texture_filter_mode",
				"name_en": "Custom Block Skin Texture Filter Mode",
				"name_zh": "皮肤纹理过滤模式",
				"description": "更改对音符皮肤的渲染方式",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Nearest", "text_zh": "Nearest"},
					{"text_en": "Bilinear", "text_zh": "Bilinear"}
				]
			},
			{
				"id": "block_skin_preset",
				"name_en": "Block Skin Preset",
				"name_zh": "音符外观设定",
				"description": "直接选择已导入的或内置的音符皮肤的名称即可更换皮肤",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Default", "text_zh": "默认"},
					{"text_en": "Simple", "text_zh": "简单"}
				]
			},
			{
				"id": "cache_time",
				"name_en": "Cache Time",
				"name_zh": "音符下落速度",
				"description": "调整音符在判定线以上范围的下落速度，数值越小速度越快",
				"type": "TYPE_LINE_EDIT",
				"default_value": "2.0",
				"unit": "x"
			},
			{
				"id": "cache_easing_type",
				"name_en": "Cache Easing Type",
				"name_zh": "音符下落模式",
				"description": "设置音符在判定线以上范围的下落方式",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Linear", "text_zh": "线性"},
					{"text_en": "In", "text_zh": "缓入"},
					{"text_en": "Out", "text_zh": "缓出"},
					{"text_en": "InOut", "text_zh": "缓入缓出"}
				]
			},
			{
				"id": "grace_time",
				"name_en": "Grace Time",
				"name_zh": "音符过判定线后的下落速度",
				"description": "同本栏第2项，但调整的是音符过判定线后的下落速度",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.5",
				"unit": "x"
			},
			{
				"id": "grace_easing_type",
				"name_en": "Grace Easing Type",
				"name_zh": "音符过判定线后的下落模式",
				"description": "同本栏第3项，但影响的是音符过判定线后的下落方式",
				"type": "TYPE_OPTION",
				"default_value": "2",
				"options": [
					{"text_en": "Linear", "text_zh": "线性"},
					{"text_en": "In", "text_zh": "缓入"},
					{"text_en": "Out", "text_zh": "缓出"},
					{"text_en": "InOut", "text_zh": "缓入缓出"}
				]
			},
			{
				"id": "custom_background_image_size_mode",
				"name_en": "Custom Background Image Size Mode",
				"name_zh": "背景尺寸模式",
				"description": "更改背景图片适配屏幕的方式",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Cover", "text_zh": "覆盖"},
					{"text_en": "Fit", "text_zh": "适应"}
				]
			},
			{
				"id": "block_size",
				"name_en": "Block Size",
				"name_zh": "音符尺寸大小",
				"description": "调整音符的显示宽度，音符判定区域大小不受其影响",
				"type": "TYPE_LINE_EDIT",
				"default_value": "150",
				"unit": "px"
			},
			{
				"id": "background_image_preset",
				"name_en": "Background Image Preset",
				"name_zh": "背景图像设定",
				"description": "设置打歌过程中的背景图像",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "None", "text_zh": "无"},
					{"text_en": "Default", "text_zh": "默认"}
				]
			},
			{
				"id": "background_image_color",
				"name_en": "Background Image Color",
				"name_zh": "背景图像颜色",
				"description": "设置叠在背景上的纯色图层的颜色和透明度",
				"type": "TYPE_COLOR",
				"edit_alpha": true,
				"default_value": "#FFFFFFFF"
			},
			{
				"id": "background_image_flash_color",
				"name_en": "Background Image Flash Color",
				"name_zh": "背景闪光颜色",
				"description": "修改打击音符时背景发光的颜色",
				"type": "TYPE_COLOR",
				"edit_alpha": true,
				"default_value": "#FFFFFF00"
			},
			{
				"id": "background_dim_alpha",
				"name_en": "Background Dim Alpha",
				"name_zh": "背景最低亮度",
				"description": "背景的不透明度会随着准度的变化而变化，准度越高不透明度越高",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.5"
			},
			{
				"id": "judge_line_thickness",
				"name_en": "Judge Line Thickness",
				"name_zh": "判定线粗细",
				"description": "调整判定线厚度，不影响判定，只影响外观",
				"type": "TYPE_LINE_EDIT",
				"default_value": "2",
				"unit": "px"
			},
			{
				"id": "generate_short_connect",
				"name_en": "Generate Short Connect",
				"name_zh": "是否连接所有并排的点块",
				"description": "选择是否生成连接线，连接并排下落的点块、滑块和长条",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "generate_instant_connect",
				"name_en": "Generate Instant Connect",
				"name_zh": "是否连接上下相邻的滑块",
				"description": "选择是否生成连接线，连接同一下落轨道内的时间差在设定范围内的数的音符",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "instant_connect_max_time",
				"name_en": "Instant Connect Max Time",
				"name_zh": "被连接音符的最大时间差",
				"description": "设置被连接音符之间的最大时间间隔",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.5",
				"unit": "s"
			}
		]
	}
]

func _ready() -> void:
	work_state = UIStateManager.UIState.SETTINGS_VIEW
	super._ready()

# 传入配置字典加载界面
func load_settings(setting: Dictionary = {}):
	# 清空现有项目
	clear_items()
	setting_items.clear()
	
	# 遍历所有分组
	for group in setting_groups:
		# 添加分隔符
		_add_separator()
		
		# 添加该组的所有设置项
		for setting_data in group.settings:
			var init_value = setting.get(setting_data.id) if setting.get(setting_data.id) else ""
			add_setting_item(setting_data, init_value)

func _add_separator():
	# 加载并添加分隔符
	var separator_scene = load(item_separator)
	if separator_scene:
		var separator = separator_scene.instantiate()
		container.add_child(separator)
		separator = separator_scene.instantiate()
		container.add_child(separator)

func add_setting_item(setting_data: Dictionary, init_value: String = ""):
	# 创建设置项
	var setting_item: SettingItem = create_and_add_item(setting_data.id, "SettingItem")
	
	# 解析值类型
	var value_type: SettingItem.ValueType = SettingItem.ValueType.TYPE_LINE_EDIT
	match setting_data.type:
		"TYPE_OPTION":
			value_type = SettingItem.ValueType.TYPE_OPTION
		"TYPE_COLOR":
			value_type = SettingItem.ValueType.TYPE_COLOR
		"TYPE_LINE_EDIT":
			value_type = SettingItem.ValueType.TYPE_LINE_EDIT
	
	# 设置界面语言（这里假设使用中文，可以根据需要调整）
	var language = "zh"  # 可以改为从全局设置获取
	var display_name = setting_data["name_%s" % language] if language in ["en", "zh"] else setting_data.name_en
	var description = setting_data.description
	
	# 设置初始值（从保存的数据或默认值）
	var initial_value = init_value if init_value else setting_data.default_value
	
	# 调用setup_item方法
	setting_item.setup_item(
		setting_data.id,
		display_name,
		description,
		value_type,
		initial_value
	)
	
	# 如果是指令类型的设置项，设置选项
	match value_type:
		SettingItem.ValueType.TYPE_OPTION:
			var option_texts = []
			
			# 检查是否为动态options（由SettingView在runtime填充）
			if setting_data.get("dynamic_options", false) and setting_data.options.is_empty():
				# 动态options为空，先设置空列表，等SettingView调用update_soundfont_options()更新
				option_texts = ["Loading..."]
			else:
				# 静态options，正常处理
				for option in setting_data.options:
					var option_text = option["text_%s" % language] if language in ["en", "zh"] else option.text_en
					option_texts.append(option_text)
			
			# 设置选项，并选中初始值对应的索引
			var default_index = 0
			if initial_value is String and initial_value.is_valid_int():
				default_index = int(initial_value)
			elif initial_value is String and not option_texts.has(initial_value):
				# 初始值不在选项列表中，使用第一个选项
				default_index = 0
			elif initial_value is String:
				# 初始值在选项列表中，查找其索引
				default_index = option_texts.find(initial_value)
			
			setting_item.set_options(option_texts, default_index)
	
		# 如果是颜色类型的设置项，设置颜色选择器选项
		SettingItem.ValueType.TYPE_COLOR:
			var enable_alpha = setting_data.get("edit_alpha", false)
			setting_item.set_color_picker_options(enable_alpha, false, false)
			
			# 设置初始颜色值
			if initial_value is String:
				if initial_value.is_valid_html_color():
					setting_item.set_value(Color(initial_value))
		SettingItem.ValueType.TYPE_LINE_EDIT:
			if setting_data.get("unit"):
				setting_item.set_line_edit_properties("", false, setting_data.unit)

	# 连接值改变信号
	setting_item.connect("value_changed", Callable(self, "_on_setting_value_changed"))
	
	# 存储到字典中
	setting_items[setting_data.id] = setting_item

func _on_setting_value_changed(id: String, value: Variant):
	# 设置项值改变时的处理
	print("Setting '%s' changed to: %s" % [id, value])


func get_all_settings_as_json() -> Dictionary:
	# 返回所有设置项的当前值，格式为 {"设置项ID": "值", ...}
	var result = {}
	
	for setting_id in setting_items.keys():
		var setting_item = setting_items[setting_id]
		if setting_item:
			var value = setting_item.get_value()
			# 将值转换为字符串
			if value is int or value is float:
				result[setting_id] = str(value)
			elif value is Color:
				result[setting_id] = value.to_html()
			else:
				result[setting_id] = str(value)
	
	return result

# 获取特定设置项的值
func get_setting_value(setting_id: String) -> Variant:
	if setting_items.has(setting_id):
		var setting_item = setting_items[setting_id]
		return setting_item.get_value()
	return null

# 设置特定设置项的值
func set_setting_value(setting_id: String, value: Variant) -> bool:
	if setting_items.has(setting_id):
		var setting_item = setting_items[setting_id]
		setting_item.set_value(value)
		return true
	return false

# 重置所有设置为默认值
func reset_to_defaults():
	for setting_id in setting_items:
		# 查找默认值
		for group in setting_groups:
			for setting_data in group.settings:
				if setting_data.id == setting_id:
					var setting_item = setting_items[setting_id]
					if setting_item:
						setting_item.set_value(setting_data.default_value)
					break

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)

## 更新soundfont_select的选项（由SettingView调用）
func update_soundfont_options(soundfont_list: Array[String], current_selection: String = "") -> void:
	"""
	更新soundfont_select的选项列表
	
	Args:
		soundfont_list: 格式为 ["GeneralUser-GS [内置]", "CustomFont", ...]
		current_selection: 当前应该选中的soundfont名称（不带标签）
	"""
	if not setting_items.has("soundfont_select"):
		push_warning("[SettingList] soundfont_select setting item not found")
		return
	
	var setting_item = setting_items["soundfont_select"]
	if setting_item == null:
		push_warning("[SettingList] soundfont_select setting item is null")
		return
	
	# 更新options
	if soundfont_list.is_empty():
		setting_item.set_options(["No Sound Fonts Available"], 0)
		return
	
	setting_item.set_options(soundfont_list, 0)
	
	# 尝试选中current_selection
	if not current_selection.is_empty():
		for i in range(soundfont_list.size()):
			# 处理带标签的情况（e.g., "GeneralUser-GS [内置]"）
			var display_name = soundfont_list[i]
			var font_name = display_name.split(" [")[0]  # 移除 [内置] 标签
			
			if font_name == current_selection or display_name == current_selection:
				setting_item.set_value(i)
				break
