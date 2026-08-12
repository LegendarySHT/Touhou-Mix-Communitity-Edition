## 场景路径注册表（TMX-018）
## 统一收口 Main.tscn 及其懒加载视图的绝对节点路径。
## 修改 Main.tscn / 懒加载视图的节点结构时，只更新本文件即可；
## 业务代码禁止再硬编码 "/root/Main/..." 之类的绝对路径。
class_name PathRegistry

## Main 根节点
const MAIN := "/root/Main"

## skew 容器（动画位移用）与主容器 C
const SKEW := "/root/Main/skew"
const SKEW_C := "/root/Main/skew/C"
const SKEW_SS := "/root/Main/skew/SS"

## 静态导航按钮
const LT_BTN := "/root/Main/LT_Btn"
const RB_BTN := "/root/Main/RB_Btn"

## 常驻 UI
const PLAYER_INFO := "/root/Main/PlayerInfo"
const PLAYER_INFO_TAB_C := "/root/Main/PlayerInfo/InfoPanelBtn/TabC"
## 旧版结构遗留路径（当前 Main.tscn 无 TopLayer，保留供兼容回退）
const PLAYER_INFO_TAB_C_LEGACY := "/root/Main/TopLayer/PlayerInfo/InfoPanelBtn/TabC"
const POPUP_WINDOW_SHADER := "/root/Main/PopupWindowShader"
const POPUP_WINDOW_IMPORT_TIP := "/root/Main/PopupWindowShader/ImportTip"
const POPUP_WINDOW_IMPORT_PROGRESS := "/root/Main/PopupWindowShader/ImportProgress"

## 常驻列表（skew/C 下）
const ALBUM_LIST := "/root/Main/skew/C/AlbumList"
const SONG_LIST := "/root/Main/skew/C/SongList"
const SORTED_MIDIS_LIST := "/root/Main/skew/C/SortedMidisList"
const SHORTCUT_MENU := "/root/Main/skew/C/ShortCutMenu"
const SHORTCUT_MENU_SEARCH := "/root/Main/skew/C/ShortCutMenu/Btns/Search"
const NO_ITEMS := "/root/Main/skew/C/NoItems"
const RANDOM_SELECT_BTN := "/root/Main/skew/C/RandomSelectBtn"

## 懒加载视图（实例化后存在，读取前请用 get_node_or_null）
const STORE_VIEW := "/root/Main/Store"
const STORE_MIDI_LIST := "/root/Main/Store/StoreMidiList"
const MIDI_VIEW := "/root/Main/skew/C/MidiView"
const MIDI_VIEW_INDICATOR := "/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Right/Center/Indicator"
const MIDI_VIEW_PREVI_BTN := "/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Left/PreviBtn"
const MIDI_VIEW_INFO_BTN := "/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Right/InfoBtn"
const MIDI_VIEW_DETAIL_DATA := "/root/Main/skew/C/MidiView/LeftArea/DetailData"
const MIDI_VIEW_DESCRIPTION := "/root/Main/skew/C/MidiView/LeftArea/InfoWindow/HBoxC/Description"
const TRACK_VIEW := "/root/Main/skew/C/TrackView"
const SETTING_VIEW := "/root/Main/skew/C/SettingView"
const PLAY_VIEW := "/root/Main/PlayView"
const SCORE_VIEW := "/root/Main/ScoreView"
