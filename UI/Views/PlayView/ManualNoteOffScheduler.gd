class_name ManualNoteOffScheduler
extends RefCounted

## 手动触发音符的 NoteOff 调度器
## 演奏模式点击/判定音符时由 FlowArea 触发 note_on，NoteOff 由播放位置驱动触发
## （而非墙钟 Timer），避免：
## 1) 提前点击时 NoteOff 被"点击后 duration_ms"锚定而提前发出（音符没响够就停）
## 2) 暂停菜单打开时墙钟 Timer 照走，把正在响的音符掐断
## 3) 同键快速连打时旧音的 NoteOff 把新音掐断（MeltySynth NoteOff 会结束该键全部 voice）
## 本类无场景树依赖，纯数据 + 播放器调用，可由 FlowArea 持有并逐帧驱动。

## 待触发的手动 NoteOff（驱动源为播放位置，而非墙钟 Timer）
## 每项: {abs_end_ms, track, channel, pitch, velocity, gen}
var _pending_manual_offs: Array = []
## 待触发 NoteOff 的最小绝对结束时刻：绝大多数帧 t < min 直接跳过扫描（O(n)→O(1)）
var _pending_manual_offs_min_end: float = INF
## "track:channel:pitch" -> 单调递增代数，用于判定某次 NoteOff 是否已被更新的音符取代
var _manual_note_off_gens: Dictionary = {}


## 从 GameSequence 触发 MIDI 音符（演奏模式；game_seq 是 KeySequenceManager.GameSequence 对象）
func trigger_from_sequence(game_seq: Object) -> void:
	if not game_seq or game_seq.original_notes.is_empty():
		return

	var midi_player = MidiPlaybackManager.instance.midi_player
	if not midi_player:
		return

	# 触发原始notes中的所有MIDI音符
	for note in game_seq.original_notes:
		if note is MidiParser.NoteEvent:
			var track_idx := int(note.track_index)

			# 触发note_on（即时，保证点击反馈）
			if midi_player.has_method("trigger_note_on"):
				midi_player.call("trigger_note_on", note.pitch, note.velocity, note.channel, track_idx)
			elif midi_player.has_method("note_on"):
				midi_player.note_on(note.channel, note.pitch, note.velocity)

			# NoteOff 锚定到音符的绝对结束时刻（原曲 NoteOff 位于 note_start + duration）。
			# 乐器音色由 sustain/release 包络决定，只有在该绝对时刻发出 NoteOff，
			# 音色才与原曲一致；按"点击后 duration_ms"调度会把提前点击的音符提前掐断。
			var abs_end_ms := float(game_seq.start_time_ms + game_seq.duration_ms)
			var gen := _bump_note_off_gen(track_idx, note.channel, note.pitch)
			_pending_manual_offs.append({
				"abs_end_ms": abs_end_ms,
				"track": track_idx,
				"channel": note.channel,
				"pitch": note.pitch,
				"velocity": note.velocity,
				"gen": gen,
			})
			if abs_end_ms < _pending_manual_offs_min_end:
				_pending_manual_offs_min_end = abs_end_ms


## 每帧由 FlowArea 调用，按播放位置触发到期的手动 NoteOff
## force=true 时全部触发（游戏结束/清场时释放残留音符）
func process(time_ms: float, force: bool = false) -> void:
	if _pending_manual_offs.is_empty():
		return
	# 绝大多数帧没有 NoteOff 到期，直接跳过整轮扫描（最小到期时刻缓存）
	if not force and _pending_manual_offs_min_end > time_ms:
		return
	var midi_player = MidiPlaybackManager.instance.midi_player
	var remaining: Array = []
	var new_min := INF
	for entry in _pending_manual_offs:
		if force or time_ms >= entry["abs_end_ms"]:
			# 代数守卫：同键已触发更新的音符则跳过本次 NoteOff（旧音交给新音一起结束）
			if _is_note_off_gen_current(entry["track"], entry["channel"], entry["pitch"], entry["gen"]):
				if midi_player and is_instance_valid(midi_player):
					if midi_player.has_method("trigger_note_off"):
						midi_player.call("trigger_note_off", entry["pitch"], entry["velocity"], entry["channel"], entry["track"])
					elif midi_player.has_method("note_off"):
						midi_player.note_off(entry["channel"], entry["pitch"])
		else:
			remaining.append(entry)
			if entry["abs_end_ms"] < new_min:
				new_min = entry["abs_end_ms"]
	_pending_manual_offs = remaining
	_pending_manual_offs_min_end = new_min


## 清空待触发队列（新一局 / 清场时调用）
func reset() -> void:
	_pending_manual_offs.clear()
	_pending_manual_offs_min_end = INF
	_manual_note_off_gens.clear()


## 递增某键的 NoteOff 代数，返回新代数（使旧的待触发 NoteOff 失效）
func _bump_note_off_gen(track_index: int, channel: int, pitch: int) -> int:
	var key := "%d:%d:%d" % [track_index, channel, pitch]
	var gen: int = int(_manual_note_off_gens.get(key, 0)) + 1
	_manual_note_off_gens[key] = gen
	return gen


## 校验某次 NoteOff 的代数是否仍是最新（未被更新的同键音符取代）
func _is_note_off_gen_current(track_index: int, channel: int, pitch: int, gen: int) -> bool:
	var key := "%d:%d:%d" % [track_index, channel, pitch]
	return int(_manual_note_off_gens.get(key, 0)) == gen
