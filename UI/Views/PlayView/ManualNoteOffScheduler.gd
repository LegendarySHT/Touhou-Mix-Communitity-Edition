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

	# 【TEMP DIAG】首触卡顿定位（验证后移除）
	var _diag_t0 := Time.get_ticks_usec()

	var midi_player = MidiPlaybackManager.instance.midi_player
	if not midi_player:
		return

	# 收集 original notes 的触发数据 + 登记 NoteOff 调度
	var events: Array = []
	for note in game_seq.original_notes:
		if note is MidiParser.NoteEvent:
			var track_idx := int(note.track_index)

			events.append({
				"pitch": int(note.pitch),
				"velocity": int(note.velocity),
				"channel": int(note.channel),
				"track_index": track_idx,
			})

			# NoteOff 锚定到音符的绝对结束时刻（原曲 NoteOff 位于 note_start + duration）。
			# 乐器音色由 sustain/release 包络决定，只有在该绝对时刻发出 NoteOff，
			# 音色才与原曲一致；按"点击后 duration_ms"调度会把提前点击的音符提前掐断。
			var abs_end_ms := float(game_seq.start_time_ms + game_seq.duration_ms)
			var gen := _bump_note_off_gen(track_idx, int(note.channel), int(note.pitch))
			_pending_manual_offs.append({
				"abs_end_ms": abs_end_ms,
				"track": track_idx,
				"channel": int(note.channel),
				"pitch": int(note.pitch),
				"velocity": int(note.velocity),
				"gen": gen,
			})
			if abs_end_ms < _pending_manual_offs_min_end:
				_pending_manual_offs_min_end = abs_end_ms

	if events.is_empty():
		return

	# 批量触发（单次跨语言调用，替代逐音符 call 的 N 次开销；旧后端回退逐音符）
	if midi_player.has_method("trigger_notes_on"):
		midi_player.trigger_notes_on(events)
	else:
		for entry in events:
			if midi_player.has_method("trigger_note_on"):
				midi_player.call("trigger_note_on", entry["pitch"], entry["velocity"], entry["channel"], entry["track_index"])
			elif midi_player.has_method("note_on"):
				midi_player.note_on(entry["channel"], entry["pitch"], entry["velocity"])

	# 【TEMP DIAG】首触卡顿定位（验证后移除）
	_diag_trigger_count += 1
	if _diag_trigger_count <= 5:
		GLogger.info("[TapDiag] trigger_from_sequence#%d notes=%d 耗时 %.2fms" % [_diag_trigger_count, events.size(), (Time.get_ticks_usec() - _diag_t0) / 1000.0], "ManualNoteOffScheduler")

## 【TEMP DIAG】首触卡顿定位（验证后移除）
var _diag_trigger_count: int = 0


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
