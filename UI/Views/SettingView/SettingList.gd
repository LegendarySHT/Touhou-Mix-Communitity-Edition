extends BaseScrollList
class_name SettingList

var item_separator: String = "res://UI/Views/SettingView/Seperator.tscn"
var setting_items: Dictionary = {}  # 存储所有设置项，键为id，值为SettingItem
var pending_config_updates: Dictionary = {}  # 待提交配置，键为 "section::key"

# 设置项分组数据
var setting_groups = [
	{
		"name": "常规设置",
		"settings": [
			{
				"id": "display_debug_info",
				"name_en": "Display Debug Info",
				"name_zh": "显示调试信息",
				"description": "在游玩界面实时显示FPS、渲染和内存状态",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
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
				"id": "audio_buffer_frames",
				"name_en": "Audio Buffer Size",
				"name_zh": "音频缓冲区大小",
				"description": "调整音频解码缓冲区帧数，较小的值可降低延迟但可能导致电流声，较大的值更稳定但延迟更高",
				"type": "TYPE_OPTION",
				"default_value": "2",
				"options": [
					{"text_en": "256 (最低延迟)", "text_zh": "256 (最低延迟)"},
					{"text_en": "512 (低延迟)", "text_zh": "512 (低延迟)"},
					{"text_en": "1024 (平衡)", "text_zh": "1024 (平衡)"},
					{"text_en": "2048 (最高稳定)", "text_zh": "2048 (最高稳定)"}
				]
			},
			{
				"id": "max_polyphony",
				"name_en": "Max Polyphony",
				"name_zh": "最大复音数",
				"description": "设置同时发声的最大音符数，较高的值音质更好但占用更多CPU资源，建议值：32/64/96/128",
				"type": "TYPE_LINE_EDIT",
				"default_value": "96",
				"unit": "音符"
			},
			{
				"id": "default_midi_volume",
				"name_en": "Default MIDI Volume",
				"name_zh": "默认MIDI音量",
				"description": "设置加载新MIDI时的默认MIDI音量，范围0-100",
				"type": "TYPE_LINE_EDIT",
				"default_value": "50",
				"unit": "%"
			},
			{
				"id": "default_vocal_volume",
				"name_en": "Default Vocal Volume",
				"name_zh": "默认人声音量",
				"description": "设置加载新MIDI时的默认人声音量，范围0-100",
				"type": "TYPE_LINE_EDIT",
				"default_value": "50",
				"unit": "%"
			},
		{
			"id": "audio_sync_threshold",
			"name_en": "Audio Sync Threshold",
			"name_zh": "音频不同步阈值",
			"description": "MIDI与人声进度差值超过此阈值时自动对齐，范围50-500毫秒",
			"type": "TYPE_LINE_EDIT",
			"default_value": "200",
			"unit": "ms"
		},
		{
			"id": "soundfont_select",
			"name_en": "Sound Font",
			"name_zh": "音源选择",
			"description": "选择MIDI播放时使用的SoundFont音源文件。",
			"type": "TYPE_OPTION",
			"default_value": "GeneralUser-GS.sf2",
			"options": [],
			"dynamic_options": true
		},
		{
			"id": "midi_backend",
			"name_en": "MIDI Backend",
			"name_zh": "MIDI合成器",
			"description": "选择MIDI合成器后端以进行音质对比。",
			"type": "TYPE_OPTION",
			"default_value": "0",
			"options": [
				{"text_en": "Addon (GDScript)", "text_zh": "插件合成器", "value": "addons"},
				{"text_en": "MeltySynth (C#)", "text_zh": "MeltySynth", "value": "meltysynth"}
			]
		},

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
					{"text_en": "None", "text_zh": "无"},
					{"text_en": "Block", "text_zh": "方块"}
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
					{"text_en": "None", "text_zh": "无"},
					{"text_en": "Block", "text_zh": "方块"}
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
					{"text_en": "None", "text_zh": "无"},
					{"text_en": "Block", "text_zh": "方块"}
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
					{"text_en": "None", "text_zh": "无"},
					{"text_en": "Block", "text_zh": "方块"}
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
				"description": "手指从抬起到任意位置按下的最短时间（会限制上下音符之间的横向距离）",
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
			},
			{
				"id": "note_fall_time",
				"name_en": "Note Fall Time",
				"name_zh": "音符下落时间",
				"description": "设置音符从屏幕顶端生成到落到判定线的时间，决定了音符下落速度的快慢，越小越快",
				"type": "TYPE_LINE_EDIT",
				"default_value": "1",
				"unit": "s",
				"min_value": 0.2,
				"max_value": 5.0,
				"step": 0.1
			},
			{
				"id": "note_fall_mode",
				"name_en": "Note Fall Mode",
				"name_zh": "音符下落模式",
				"description": "选择音符的下落速度模式：匀速、加速下落或自定义",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Uniform", "text_zh": "匀速"},
					{"text_en": "Accelerate", "text_zh": "加速下落"},
					{"text_en": "Custom", "text_zh": "自定义"}
				]
			},
			{
				"id": "note_fall_speed_after_judge_multiplier",
				"name_en": "Note Fall Speed Multiplier After Judge Line",
				"name_zh": "音符过判定线后的下落速度倍率",
				"description": "设置音符过判定线后的下落速度相对于判定线前的倍率（1.0表示相同）",
				"type": "TYPE_LINE_EDIT",
				"default_value": "1.0",
				"unit": "x",
				"min_value": 0.1,
				"max_value": 5.0,
				"step": 0.1
			},
			{
				"id": "note_fall_easing_before_func",
				"name_en": "Note Fall Easing (Before Judge) - Function",
				"name_zh": "音符下落缓动（判定线前）- 函数",
				"description": "选择音符在判定线前的缓动函数类型",
				"type": "TYPE_OPTION",
				"default_value": "LINEAR",
				"is_custom_easing": true,
				"easing_type": "func"
			},
			{
				"id": "note_fall_easing_before_phase",
				"name_en": "Note Fall Easing (Before Judge) - Phase",
				"name_zh": "音符下落缓动（判定线前）- 相位",
				"description": "选择音符在判定线前的缓动相位",
				"type": "TYPE_OPTION",
				"default_value": "IN",
				"is_custom_easing": true,
				"easing_type": "phase"
			},
			{
				"id": "note_fall_easing_after_func",
				"name_en": "Note Fall Easing (After Judge) - Function",
				"name_zh": "音符下落缓动（判定线后）- 函数",
				"description": "选择音符在判定线后的缓动函数类型",
				"type": "TYPE_OPTION",
				"default_value": "LINEAR",
				"is_custom_easing": true,
				"easing_type": "func"
			},
			{
				"id": "note_fall_easing_after_phase",
				"name_en": "Note Fall Easing (After Judge) - Phase",
				"name_zh": "音符下落缓动（判定线后）- 相位",
				"description": "选择音符在判定线后的缓动相位",
				"type": "TYPE_OPTION",
				"default_value": "IN",
				"is_custom_easing": true,
				"easing_type": "phase"
			}
		]
	},
	{
		"name": "外观设置",
		"settings": [
			{
				"id": "theme_preset",
				"name_en": "Theme Preset",
				"name_zh": "主题色配置",
				"description": "选择界面主题配色方案",
				"type": "TYPE_OPTION",
				"default_value": "",
				"dynamic_options": true
			},
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
				"name_en": "Note Skin",
				"name_zh": "音符外观设定",
				"description": "直接选择已导入的或内置的音符皮肤的名称即可更换皮肤",
				"type": "TYPE_OPTION",
				"default_value": "旧版2 [内置]",
				"options": [],
				"dynamic_options": true
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
				"id": "play_background_mode",
				"name_en": "Play Background Mode",
				"name_zh": "游玩背景类型",
				"description": "选择游玩界面背景来源：曲包封面、用户图片或纯色。",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Cover", "text_zh": "封面"},
					{"text_en": "Image", "text_zh": "图片"},
					{"text_en": "Solid", "text_zh": "纯色"}
				]
			},
			{
				"id": "play_background_cover_blur",
				"name_en": "Cover Blur",
				"name_zh": "封面模糊程度",
				"description": "仅封面模式生效。0.0 表示不模糊，1.0 表示最强模糊。",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.35"
			},
			{
				"id": "play_background_size_mode",
				"name_en": "Play Background Size Mode",
				"name_zh": "游玩背景尺寸模式",
				"description": "封面/图片模式生效。覆盖会等比填满，拉伸会按屏幕比例拉伸。",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Cover", "text_zh": "覆盖"},
					{"text_en": "Stretch", "text_zh": "拉伸"}
				]
			},
			{
				"id": "play_background_image_file",
				"name_en": "Play Background Image",
				"name_zh": "游玩背景图片",
				"description": "仅图片模式生效。图片列表来自用户目录 BackgroundImage。",
				"type": "TYPE_OPTION",
				"default_value": "",
				"options": [],
				"dynamic_options": true
			},
			{
				"id": "play_background_color",
				"name_en": "Play Background Color",
				"name_zh": "游玩背景颜色",
				"description": "仅纯色模式生效。用于设置游玩背景纯色。",
				"type": "TYPE_COLOR",
				"edit_alpha": true,
				"default_value": "#10121AFF"
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
				"id": "note_glow_intensity",
				"name_en": "Note Glow Intensity",
				"name_zh": "音符发光强度",
				"description": "控制音符周围的发光效果强度，[0, 2]",
				"type": "TYPE_LINE_EDIT",
				"default_value": "0.5",
				"range": [0.0, 2.0, 0.1]
			},
			{
				"id": "note_glow_size",
				"name_en": "Note Glow Size",
				"name_zh": "音符发光范围",
				"description": "控制音符发光效果的范围大小，[0, 30]",
				"type": "TYPE_LINE_EDIT",
				"default_value": "5.0",
				"range": [1.0, 12.0, 1.0]
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
				"id": "background_image_flash_color",
				"name_en": "Background Image Flash Color",
				"name_zh": "背景闪光颜色",
				"description": "修改打击音符时背景发光的颜色",
				"type": "TYPE_COLOR",
				"edit_alpha": true,
				"default_value": "#FFFFFF00"
			},
			{
				"id": "background_dim_color",
				"name_en": "Background Dim Color",
				"name_zh": "背景遮罩颜色",
				"description": "背景遮罩的颜色，与背景遮罩透明度配合使用来降低背景亮度",
				"type": "TYPE_COLOR",
				"edit_alpha": true,
				"default_value": "#000000FF"
			},
			{
				"id": "beam_width_mode",
				"name_en": "Beam Width Mode",
				"name_zh": "轨道光效宽度模式",
				"description": "控制轨道光效的宽度依据：跟随音符宽度会在音符宽度基础上增加边距，跟随轨道间距会填满轨道间隔",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Note Width", "text_zh": "跟随音符宽度"},
					{"text_en": "Lane Spacing", "text_zh": "跟随轨道间距"}
				]
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
			},
			{
				"id": "hdr_2d",
				"name_en": "HDR 2D Rendering",
				"name_zh": "HDR 2D渲染",
				"description": "开启后画面可呈现更丰富的高动态范围特效，但会带来庞大的性能开销",
				"type": "TYPE_OPTION",
				"default_value": "0",
				"options": [
					{"text_en": "Off", "text_zh": "关闭"},
					{"text_en": "On", "text_zh": "开启"}
				]
			},
			{
				"id": "lane_effect_quality",
				"name_en": "Lane Effect Quality",
				"name_zh": "轨道光效质量",
				"description": "控制轨道光效的渲染策略。推荐使用Shader模式以降低Tween和GPU混合开销；Discard模式会更激进地裁剪弱贡献像素。",
				"type": "TYPE_OPTION",
				"default_value": "1",
				"options": [
					{"text_en": "Legacy", "text_zh": "传统"},
					{"text_en": "Shader", "text_zh": "Shader"},
					{"text_en": "Shader + Discard", "text_zh": "Shader + 剔除"}
				]
			}
		]
	}
]

func _ready() -> void:
	work_state = UIStateManager.UIState.SETTINGS_VIEW
	super._ready()
	get_v_scroll_bar().value_changed.connect(func (_v):
		var btns = get_parent().get_parent().short_cut_btn.get_children()
		var tBtn: Button = btns[_get_current_para_sepa_idx()]
		# await get_tree().process_frame
		if tBtn.get_parent().has_meta("snaping"):
			return
		
		if tBtn and not tBtn.button_pressed:
			for b in btns:
				b.set_block_signals(true)
				b.call_deferred("set_block_signals", false)
			tBtn.button_pressed = true
			# for b in btns:
			# 	b.set_block_signals(false)
	)

# 传入配置字典加载界面
func load_settings(setting: Dictionary = {}):
	# 清空现有项目
	clear_items()
	setting_items.clear()
	pending_config_updates.clear()
	
	# 遍历所有分组
	for group in setting_groups:
		# 添加分隔符
		_add_separator()
		
		# 添加该组的所有设置项
		for setting_data in group.settings:
			var init_value = setting.get(setting_data.id) if setting.get(setting_data.id) else ""
			add_setting_item(setting_data, init_value)

	# 初始化依赖可见性
	_refresh_play_background_visibility()

var separators = []
func _add_separator():
	# 加载并添加分隔符
	var separator_scene = load(item_separator)
	if separator_scene:
		var separator = separator_scene.instantiate()
		container.add_child(separator)

		separators.append(separator)
		separator = separator_scene.instantiate()
		container.add_child(separator)

func _get_current_para_sepa_idx():
	var lower: int = separators.filter(func (s):
		if s.global_position.y >= -s.size.y/2:
			return true
		return false
	).size()
	lower = clampi(lower+1, 1, separators.size())
	return separators.size() - lower

func _process(delta: float) -> void:
	super._process(delta)

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
			if setting_data.get("dynamic_options", false) and setting_data.get("options", []).is_empty():
				# 动态options为空，先设置空列表，等SettingView调用update_soundfont_options()更新
				option_texts = ["Loading..."]
			elif setting_data.get("is_custom_easing", false):
				# 自定义缓动选项，从EasingMapper动态生成
				var easing_type = setting_data.get("easing_type", "func")  # "func" or "phase"
				var easing_options = []
				
				if easing_type == "func":
					easing_options = EasingMapper.get_func_options()
				elif easing_type == "phase":
					easing_options = EasingMapper.get_phase_options()
				
				# 提取显示名称
				for easing_opt in easing_options:
					option_texts.append(easing_opt.display_name)
			else:
				# 静态options，正常处理
				for option in setting_data.options:
					var option_text = option["text_%s" % language] if language in ["en", "zh"] else option.text_en
					option_texts.append(option_text)
			
			# 设置选项，并选中初始值对应的索引
			var default_index = 0
			if setting_data.get("is_custom_easing", false) and initial_value is String:
				var easing_type = setting_data.get("easing_type", "func")
				var easing_options = []
				if easing_type == "func":
					easing_options = EasingMapper.get_func_options()
				elif easing_type == "phase":
					easing_options = EasingMapper.get_phase_options()

				for i in range(easing_options.size()):
					if easing_options[i].name.to_upper() == initial_value.to_upper():
						default_index = i
						break
			elif initial_value is String and initial_value.is_valid_int():
				default_index = int(initial_value)
			elif initial_value is String:
				var matched_index = -1
				for i in range(setting_data.get("options", []).size()):
					var option_data = setting_data.get("options", [])[i]
					if option_data.has("value") and str(option_data["value"]).to_lower() == initial_value.to_lower():
						matched_index = i
						break
				if matched_index >= 0:
					default_index = matched_index
				else:
					var idx = option_texts.find(initial_value)
					default_index = idx if idx >= 0 else 0
			
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

	# 主题预设 — 直接交给 ThemeManager
	if id == "theme_preset":
		if ThemeManager.instance:
			var presets := ThemeManager.instance.get_available_presets()
			if value >= 0 and value < presets.size():
				ThemeManager.instance.apply_preset(presets[value])
		return

	# 从SettingsMapper中查找该设置项对应的section和key
	if id in SettingsMapper.mappings:
		var setting_info = SettingsMapper.mappings[id]
		var section = setting_info.get("section", "")
		var key = setting_info.get("key", "")
		var value_type = setting_info.get("value_type", "string")
		
		if not section.is_empty() and not key.is_empty():
			# 根据配置类型转换值（确保类型匹配）
			var converted_value = value
			
			# 特殊处理：midi_backend 需要将索引转换为实际值
			if id == "midi_backend" and value is int:
				# 0 -> "addons", 1 -> "meltysynth"
				converted_value = "addons" if value == 0 else "meltysynth"
				print("[SettingList] Converting midi_backend index %d to '%s'" % [value, converted_value])
			elif id == "play_background_mode" and value is int:
				converted_value = value
				_refresh_play_background_visibility()
			# 特殊处理：note_fall_mode 需要控制自定义缓动选项的可见性
			elif id == "note_fall_mode" and value is int:
				set_note_fall_mode_and_show_custom_options(value)
				converted_value = value
			# 特殊处理：soundfont_select 需要将索引转换为文件名
			elif id == "soundfont_select" and value is int:
				var display_text = get_option_text(id, value)
				# 去掉 [内置] 标签和 .sf2 扩展名
				var actual_name = display_text.split(" [")[0] if " [" in display_text else display_text
				if actual_name.ends_with(".sf2"):
					actual_name = actual_name.get_basename()
				converted_value = actual_name
				print("[SettingList] Converting soundfont_select index %d to '%s'" % [value, converted_value])
			# 特殊处理：block_skin_preset 需要将索引转换为皮肤名称（保留 [内置] 标记）
			elif id == "block_skin_preset" and value is int:
				var display_text = get_option_text(id, value)
				converted_value = display_text
				print("[SettingList] Converting block_skin_preset index %d to '%s'" % [value, converted_value])
			elif id == "play_background_image_file" and value is int:
				converted_value = get_option_text(id, value)
				print("[SettingList] Converting play_background_image_file index %d to '%s'" % [value, converted_value])
			else:
				match value_type:
					"int":
						converted_value = int(value) if value is not int else value
					"float":
						converted_value = float(value) if value is not float else value
					"bool":
						# 布尔值可能来自int或字符串
						if value is int:
							converted_value = value != 0
						elif value is String:
							converted_value = value.to_lower() in ["1", "true", "yes"]
						else:
							converted_value = bool(value)
					"string":
						converted_value = str(value)
					"color":
						# 颜色保持为Color类型，先校验格式避免编辑过程中的报错
						if value is Color:
							converted_value = value
						elif str(value).is_valid_html_color():
							converted_value = Color(str(value))
						else:
							return  # 颜色值不完整时静默跳过，等待用户输入完成

			# 改为延迟提交：先缓存变更，退出SettingView时统一应用
			var update_id = "%s::%s" % [section, key]
			pending_config_updates[update_id] = {
				"section": section,
				"key": key,
				"value": converted_value
			}
			print("[SettingList] Deferred config update: [%s] %s = %s (type: %s)" % [section, key, str(converted_value), value_type])

func apply_pending_config_updates() -> int:
	var emitted_count = 0
	if pending_config_updates.is_empty():
		return emitted_count

	if EventBus.instance == null:
		push_warning("[SettingList] EventBus is null, skip applying pending config updates")
		pending_config_updates.clear()
		return emitted_count

	for update_key in pending_config_updates.keys():
		var update = pending_config_updates[update_key]
		if update is Dictionary:
			var section = update.get("section", "")
			var key = update.get("key", "")
			if section.is_empty() or key.is_empty():
				continue
			EventBus.instance.config_changed.emit(key, section, update.get("value", null))
			emitted_count += 1

	pending_config_updates.clear()
	return emitted_count

func has_pending_changes() -> bool:
	return not pending_config_updates.is_empty()



func _refresh_play_background_visibility() -> void:
	var mode_index = 0
	if setting_items.has("play_background_mode"):
		var mode_item = setting_items["play_background_mode"]
		if mode_item:
			mode_index = int(mode_item.get_value())

	var show_cover_only = mode_index == 0
	var show_image_only = mode_index == 1
	var show_color_only = mode_index == 2
	var show_size_mode = mode_index == 0 or mode_index == 1

	var visibility_rules = {
		"play_background_cover_blur": show_cover_only,
		"play_background_image_file": show_image_only,
		"play_background_color": show_color_only,
		"play_background_size_mode": show_size_mode
	}

	for setting_id in visibility_rules.keys():
		if setting_items.has(setting_id):
			var item = setting_items[setting_id]
			if item:
				var _is_visible = visibility_rules[setting_id]
				item.visible = _is_visible
				if item.value_node:
					item.value_node.visible = _is_visible



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

# 获取指定选项型设置的显示文本
func get_option_text(setting_id: String, index: int) -> String:
	if not setting_items.has(setting_id):
		return ""
	var setting_item = setting_items[setting_id]
	if setting_item == null:
		return ""
	if not setting_item.value_node or not (setting_item.value_node is OptionButton):
		return ""
	var option_btn: OptionButton = setting_item.value_node
	if index < 0 or index >= option_btn.item_count:
		return ""
	return option_btn.get_item_text(index)

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
func update_soundfont_options(soundfont_list: Array, current_selection: String = "") -> void:
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



## 更新theme_preset的选项（由SettingView调用）
func update_theme_preset_options() -> void:
	if not ThemeManager.instance:
		return
	var item = setting_items.get("theme_preset")
	if not item:
		return

	var presets := ThemeManager.instance.get_available_presets()
	var texts: Array[String] = []
	for p in presets:
		texts.append(p)

	var current := ThemeManager.instance.get_theme_name()
	var idx = max(0, presets.find(current))
	item.set_options(texts, idx)

func update_background_image_options(image_files: Array, current_selection: String = "") -> void:
	if not setting_items.has("play_background_image_file"):
		return

	var setting_item = setting_items["play_background_image_file"]
	if setting_item == null:
		return

	if image_files.is_empty():
		setting_item.set_options([""], 0)
		return

	setting_item.set_options(image_files, 0)

	if not current_selection.is_empty():
		var target_index = image_files.find(current_selection)
		if target_index >= 0:
			setting_item.set_value(target_index)


## 更新音符皮肤选项
func update_note_skin_options(skin_list: Array, current_selection: String = "") -> void:
	"""
	更新音符皮肤选择器的选项列表
	
	Args:
		skin_list: 皮肤名称列表
		current_selection: 当前选中的皮肤名称
	"""
	if not setting_items.has("block_skin_preset"):
		push_warning("[SettingList] block_skin_preset setting item not found")
		return
	
	var setting_item = setting_items["block_skin_preset"]
	if setting_item == null:
		return
	
	# 更新选项
	if skin_list.is_empty():
		setting_item.set_options(["旧版2 [内置]"], 0)
		return
	
	setting_item.set_options(skin_list, 0)
	
	# 尝试选中当前选择
	if not current_selection.is_empty():
		var target_index = skin_list.find(current_selection)
		if target_index >= 0:
			setting_item.set_value(target_index)

## 设置下落模式和控制自定义缓动选项的可见性
func set_note_fall_mode_and_show_custom_options(mode: int) -> void:
	"""
	设置下落模式并控制自定义缓动选项的可见性
	
	Args:
		mode: 0=匀速, 1=加速下落, 2=自定义
	"""
	var custom_easing_ids = [
		"note_fall_easing_before_func",
		"note_fall_easing_before_phase",
		"note_fall_easing_after_func",
		"note_fall_easing_after_phase"
	]
	
	for easing_id in custom_easing_ids:
		if setting_items.has(easing_id):
			var setting_item = setting_items[easing_id]
			if setting_item and setting_item.value_node:
				# 当模式为2（自定义）时显示，否则隐藏
				setting_item.visible = (mode == 2)
				if setting_item.value_node:
					setting_item.value_node.visible = (mode == 2)
