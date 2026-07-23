## 设置项分组静态数据
## 从 SettingList.gd 外移，纯数据无逻辑
class_name SettingGroupsData
extends RefCounted

static func get_setting_groups() -> Array:
	return [
	{
		"name": "常规设置",
		"settings": [
			{
				"id": "album_sort_method",
				"name_en": "Album Sort Method",
				"name_zh": "专辑排序方式",
				"description": "选择专辑列表的默认排序方式",
				"type": "TYPE_OPTION",
				"default_value": "creation_time",
				"options": [
					{"text_en": "By Creation Time", "text_zh": "按创建时间"},
					{"text_en": "By Download Time", "text_zh": "按下载时间"}
				],
				"option_values": ["creation_time", "download_time"]
			},
			{
				"id": "album_sort_direction",
				"name_en": "Album Sort Direction",
				"name_zh": "专辑排序方向",
				"description": "选择专辑列表的正序或倒序排列",
				"type": "TYPE_OPTION",
				"default_value": "asc",
				"options": [
					{"text_en": "Oldest First", "text_zh": "从旧到新"},
					{"text_en": "Newest First", "text_zh": "从新到旧"}
				],
				"option_values": ["asc", "desc"]
			},
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
			"description": "MIDI与人声进度差值超过此阈值时自动对齐",
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
				"description": "设置判定宽度占音符宽度的倍数。例如：设置为1.0表示判定宽度等于音符宽度，设置为2.0表示判定宽度为音符宽度的2倍。",
				"type": "TYPE_LINE_EDIT",
				"default_value": "1.0",
				"unit": "倍音符宽度"
			},
			{
				"id": "min_block_spacing",
				"name_en": "Min Block Spacing",
				"name_zh": "最小横向音符间距",
				"description": "控制并排音符间的最小轨道间隔。值为1时，任意两个并排音符的轨道号差必须大于1（至少相隔一个空轨道）。数值太大会导致没有音符下落",
				"type": "TYPE_LINE_EDIT",
				"default_value": "1",
				"unit": "轨道"
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
				"description": "设置可游玩区域容纳的音符数量，数值越大音符越小。例如：设置为6.5表示可游玩区域宽度正好为6.5个音符宽度。",
				"type": "TYPE_LINE_EDIT",
				"default_value": "6.5",
				"unit": "个音符"
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
