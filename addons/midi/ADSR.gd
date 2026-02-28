##
## AudioStreamPlayer with ADSR + Linked by あるる（きのもと 結衣） @arlez80
##
## MIT License
##

class_name AudioStreamPlayerADSR

extends AudioStreamPlayer

## 先頭空白秒数
const gap_second:float = 1024.0 / 44100.0
## ステレオバス名（左）
const stereo_bus_name_left:String = "arlez80_GMP_CHANNEL_BUS%d_L"
## ステレオバス名（右）
const stereo_bus_name_right:String = "arlez80_GMP_CHANNEL_BUS%d_R"

## 発音チャンネル
var channel_number:int = -1
## 発音キーナンバー
var key_number:int = -1
## 發音軌道インデックス（轨道级音量控制用）
var track_index:int = 0
## 轨道级音量倍数（由MidiPlayer在Note On时设置，保证后续不会被覆盖）
var track_volume_multiplier:float = 1.0
## Hold 1
var hold:bool = false
## リリース中？
var releasing:bool = false
## リリース要求
var request_release:bool = false
## リリース開始ズラし
var request_release_second:float = 0.0
## 楽器情報
var instrument:Bank.Instrument = null

## ベロシティ
var velocity:int = 0
## ピッチベンド
var pitch_bend:float = 0.0
## ピッチベンド幅
var pitch_bend_sensitivity:float = 12.0
## モジュレーション
var modulation:float = 0.0
## モジュレーション幅
var modulation_sensitivity:float = 0.5
## ベースピッチ
var base_pitch:float = 0.0

## ADSRタイマー
var timer:float = 0.0
## 使用時間
var using_timer:float = 0.0
## リンク先の音色
@onready var linked:AudioStreamPlayer = $Linked
## リンク先ベースピッチ
var linked_base_pitch:float = 0.0

## 同時発音数
var polyphony_count:float = 1.0

## Android安全：预缓存立体声总线 StringName（避免每次 note_play 动态格式化字符串）
var _cached_stereo_bus_left: Array[StringName] = []
var _cached_stereo_bus_right: Array[StringName] = []

## 現在のADSRボリューム
var current_volume_db:float = 0.0
## 自動リリースモード？
var auto_release_mode:bool = false

## 強制アップデート
var force_update:bool = false

## LinkedSampleを使用中
var is_check_using_linked:bool
## ステレオサンプル（左右分離が必要か）
var is_stereo_sample:bool = false

## ADSステート
@onready var ads_state:Array[Bank.VolumeState] = [
	Bank.VolumeState.new( 0.0, 0.0 ),
	Bank.VolumeState.new( 0.2, -80.0 )
	# { "time": 0.2, "jump_to": 0.0 },	# not implemented
]
## Rステート
@onready var release_state:Array[Bank.VolumeState] = [
	Bank.VolumeState.new( 0.0, 0.0 ),
	Bank.VolumeState.new( 0.01, -80.0 )
	# { "time": 0.2, "jump_to": 0.0 },	# not implemented
]

## 準備
func _ready( ) -> void:
	self.stop( )
	# 预缓存所有 16 个通道的立体声总线名称
	for i in range( 16 ):
		_cached_stereo_bus_left.append( StringName( stereo_bus_name_left % i ) )
		_cached_stereo_bus_right.append( StringName( stereo_bus_name_right % i ) )

## Linkedサウンドを使用しているか？
## @return	使用している場合true
func _check_using_linked( ) -> bool:
	return self.instrument != null and 2 <= len( self.instrument.array_stream )

## 楽器を変更
## @param	_instrument	楽器
## 注意：此方法应在 AudioServer.lock() 保护下调用（通常由 MidiPlayer._process 提供外层锁）
func set_instrument( _instrument:Bank.Instrument ) -> void:
	if self.instrument == _instrument:
		return

	self.instrument = _instrument
	self.base_pitch = _instrument.array_base_pitch[0]
	self.ads_state = _instrument.ads_state
	self.release_state = _instrument.release_state
	self.is_stereo_sample = _instrument.is_stereo_sample

	self.is_check_using_linked = self._check_using_linked( )
	self.stream = _instrument.array_stream[0]
	if self.is_check_using_linked:
		self.linked_base_pitch = _instrument.array_base_pitch[1]
		self.linked.stream = _instrument.array_stream[1]

## 再生
## @param	from_position	再生位置
## 注意：此方法应在 AudioServer.lock() 保护下调用（通常由 MidiPlayer._process 提供外层锁）
func note_play( from_position:float = 0.0 ) -> void:
	self.releasing = false
	self.request_release = false
	self.timer = 0.0
	self.using_timer = 0.0
	self.pitch_scale = 1.0
	self.linked.pitch_scale = 1.0

	# ステレオサンプルであれば、L/Rバスを分ける
	if self.is_stereo_sample and self.is_check_using_linked and self.channel_number >= 0:
		# Android安全：使用预缓存的 StringName 而不是动态格式化
		self.bus = _cached_stereo_bus_left[self.channel_number]
		self.linked.bus = _cached_stereo_bus_right[self.channel_number]
	else:
		self.linked.bus = self.bus

	self.current_volume_db = self.ads_state[0].volume_db
	self._update_volume( )

	var from_position_skip_silence:float = from_position + Bank.head_silent_second
	var mix_delay:float = clampf( self.gap_second - AudioServer.get_time_to_next_mix( ), 0.0, self.gap_second )
	var own_from_position:float = from_position_skip_silence - mix_delay * pow( 2.0, self.base_pitch )
	super.play( maxf( 0.0, own_from_position ) )
	if self.is_check_using_linked:
		var linked_from_position:float = from_position_skip_silence - mix_delay * pow( 2.0, self.linked_base_pitch )
		self.linked.play( maxf( 0.0, linked_from_position ) )

	self.force_update = true
	self._update_adsr( 0.0 )
	self.force_update = false

## 停止
## 注意：此方法应在 AudioServer.lock() 保护下调用（通常由 MidiPlayer._process 提供外层锁）
func note_stop( ) -> void:
	super.stop( )
	if self.linked != null and is_instance_valid( self.linked ):
		self.linked.stop( )
	self.hold = false

## リリース開始
func start_release( ) -> void:
	self.request_release_second = self.gap_second - maxf( AudioServer.get_time_to_next_mix( ), 0.0 )
	self.request_release = true

## ADSR制御
## @param	delta	前回からの差分秒数 sec
func _update_adsr( delta:float ) -> void:
	if ( not self.playing ) and ( not self.force_update ):
		return

	self.timer += delta
	self.using_timer += delta

	# ADSR選択
	var use_state:Array[Bank.VolumeState] = self.ads_state
	if self.releasing:
		use_state = self.release_state

	var all_states:int = use_state.size( )
	var last_state:int = all_states - 1
	if use_state[last_state].time <= self.timer:
		self.current_volume_db = use_state[last_state].volume_db
		if self.releasing:
			# 使用 note_stop() 代替 self.stop()，确保 linked 播放器也被停止
			self.note_stop( )
		if self.auto_release_mode: self.request_release = true
	else:
		for state_number in range( 1, all_states ):
			var state:Bank.VolumeState = use_state[state_number]
			if self.timer < state.time:
				var pre_state:Bank.VolumeState = use_state[state_number-1]
				var t:float = 1.0 - ( state.time - self.timer ) / ( state.time - pre_state.time )
				if not self.releasing and all_states > 2 and ( state_number == 1 or state_number == 2 ):
					self.current_volume_db = linear_to_db( lerpf( db_to_linear( pre_state.volume_db ), db_to_linear( state.volume_db ), t ) )
				else:
					self.current_volume_db = lerpf( pre_state.volume_db, state.volume_db, t )
				break

	var synthed_pitch_bend:float = self.pitch_bend * self.pitch_bend_sensitivity / 12.0
	var synthed_modulation:float = sin( self.using_timer * 32.0 ) * ( self.modulation * self.modulation_sensitivity / 12.0 )
	self.pitch_scale = pow( 2.0, self.base_pitch + synthed_modulation + synthed_pitch_bend )
	if self.is_check_using_linked:
		self.linked.pitch_scale = pow( 2.0, self.linked_base_pitch + synthed_modulation + synthed_pitch_bend )

	self._update_volume( )

	if self.hold:
		pass
	else:
		if self.request_release and not self.releasing:
			self.request_release_second -= delta
			if self.request_release_second <= 0.0:
				self.releasing = true
				self.current_volume_db = self.release_state[0].volume_db
				self.timer = 0.0

## 音量を更新
func _update_volume( ) -> void:
	var v:float = self.current_volume_db + linear_to_db( float( self.velocity ) / 127.0 )# + self.instrument.volume_db
	
	# 应用轨道级音量衰减（由MidiPlayer设置的track_volume_multiplier）
	v = v + linear_to_db(self.track_volume_multiplier)

	if self.is_check_using_linked:
		v = maxf( -80.0, linear_to_db( db_to_linear( v ) / self.polyphony_count / 2.0 ) )
		self.volume_db = v
		self.linked.volume_db = v
	else:
		v = maxf( -80.0, linear_to_db( db_to_linear( v ) / self.polyphony_count ) )
		self.volume_db = v
