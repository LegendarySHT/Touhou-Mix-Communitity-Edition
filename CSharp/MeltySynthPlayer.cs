using Godot;
using MeltySynth;
using System;
using System.Collections.Generic;
using System.IO;
using TouhouMix.Midi;

/// <summary>
/// Meltysynth MIDI 播放器后端
/// 实现 IMidiPlaybackInterface 接口，提供与 GDScript 后端一致的 API
/// </summary>
public partial class MeltySynthPlayer : Node, IMidiPlaybackInterface
{
	[Signal]
	public delegate void finishedEventHandler();

	[Signal]
	public delegate void soundfont_changedEventHandler(string soundfont_path);

	public int max_polyphony = 96;
	public bool loop = false;
	private float _volume_db = -20.0f;
	private string _soundfont = "";
	private string _file = "";
	public bool playing = false;
	private StringName _bus = new StringName("Master");

	public Godot.Collections.Dictionary track_channel_instruments = new Godot.Collections.Dictionary();
	public Godot.Collections.Dictionary _track_channel_instruments = new Godot.Collections.Dictionary();

	private AudioStreamPlayer _player;
	private AudioStreamGenerator _generator;
	private AudioStreamGeneratorPlayback _playback;

	private Synthesizer _synth;
	private MidiFileSequencer _sequencer;
	private MidiFile _midiFile;
	private SoundFont _soundFont;

	private int _sampleRate;
	private float _volumeLinear = 1.0f;
	private bool _sequencerStarted = false;  // 追踪 sequencer 是否已启动
	private double _pendingSeekMs = double.NaN;  // 待处理的 seek 位置（NaN 表示无待处理的 seek）
	private double _currentOffsetMs = 0.0;  // 当前相对于 sequencer 的时间偏移（支持负数 pre-roll）
	private bool _hasSkippedPreroolEvents = false;  // 标志：已跳过 pre-roll 事件

	private readonly Dictionary<int, float> _virtualChannelVolumes = new Dictionary<int, float>();
	private readonly Dictionary<int, (int bank, int program)> _virtualChannelInstruments = new Dictionary<int, (int bank, int program)>();
	private sealed class ManualFilterState
	{
		public readonly Dictionary<int, int> PendingManualOnsByTick = new Dictionary<int, int>();
		public int ActiveManualNotes;
	}

	private readonly Dictionary<long, ManualFilterState> _manualNoteFilters = new Dictionary<long, ManualFilterState>();
	private const int MANUAL_WILDCARD_TICK = -1;
	private readonly HashSet<int> _mutedVirtualChannels = new HashSet<int>();

	private float[] _leftBuffer = Array.Empty<float>();
	private float[] _rightBuffer = Array.Empty<float>();

	// ============ 选项 A：独立合成器用于低延迟手动音符 ============
	private Synthesizer _manualSynth;      // 专用于手动触发的音符
	private Synthesizer _autoSynth;        // 原有：用于MIDI自动播放（就是 _synth）
	private bool _useSeparateSynthForManual = true;  // 启用独立合成器
	private const int MANUAL_CHANNEL_OFFSET = 16;   // 手动音符的虚拟通道偏移
	private readonly Dictionary<int, float> _manualNoteVelocities = new Dictionary<int, float>();

	private void EnsureAudioInitialized()
	{
		if (_player != null)
		{
			return;
		}

		_sampleRate = (int)AudioServer.GetMixRate();
		_player = new AudioStreamPlayer();
		_player.Bus = _bus;
		AddChild(_player);

		_generator = new AudioStreamGenerator
		{
			MixRate = _sampleRate,
			BufferLength = 0.1f
		};

		_player.Stream = _generator;
	}

	public override void _Ready()
	{
		EnsureAudioInitialized();
		SetProcess(true);
	}

	public override void _Process(double delta)
	{
		// 【关键】处理待处理的 seek 操作优先级最高，即使不在播放中也要处理
		if (!double.IsNaN(_pendingSeekMs))
		{
			GD.Print($"[MeltySynthPlayer] Processing seek to {_pendingSeekMs} ms (playing={playing})");
			
			if (_sequencer == null || _midiFile == null)
			{
				GD.PrintErr("[MeltySynthPlayer] Cannot seek: sequencer or midiFile is null");
				_pendingSeekMs = double.NaN;
				return;
			}

			// 如果 seek 位置是负数，进入 pre-roll 模式
			if (_pendingSeekMs < 0.0)
			{
				// 负数 seek：停止所有播放，记录 offset，准备 pre-roll
				_currentOffsetMs = _pendingSeekMs;
				_sequencerStarted = false;  // 标记 sequencer 需要重启
				_hasSkippedPreroolEvents = false;  // 重置标志，准备首次 crossing zero
				
				// 停止所有播放（AudioStreamPlayer 和 Sequencer）
				if (_player != null && _player.Playing)
				{
					_player.Stop();
				}
				
				// 【关键】停止 sequencer，防止在后台继续运行
				if (_sequencer != null)
				{
					_sequencer.Stop();
					GD.Print($"[MeltySynthPlayer] Stopped sequencer for pre-roll mode");
				}
				
				GD.Print($"[MeltySynthPlayer] Pre-roll mode: offset set to {_currentOffsetMs} ms");
				_pendingSeekMs = double.NaN;
				return;
			}

			// 正数 seek：正常处理
			// 1. 如果正在播放，停止 AudioStreamPlayer 清空缓冲区
			if (_player != null && _player.Playing)
			{
				_player.Stop();
			}

			var targetSeconds = _pendingSeekMs / 1000.0;
			var targetFrames = (long)(_sampleRate * targetSeconds);

			// 2. 重新启动 sequencer 并快进到目标位置
			_sequencer.Play(_midiFile, loop);
			_sequencerStarted = true;
			_currentOffsetMs = 0.0;  // 清除任何 pre-roll offset
			_hasSkippedPreroolEvents = true;  // 正数seek时无需跳过事件

			var scratchLeft = new float[_synth.BlockSize];
			var scratchRight = new float[_synth.BlockSize];
			long remaining = targetFrames;

			while (remaining > 0)
			{
				var block = (int)Math.Min(remaining, _synth.BlockSize);
				_sequencer.Render(scratchLeft.AsSpan(0, block), scratchRight.AsSpan(0, block));
				remaining -= block;
			}

			// 快进后强制刷新乐器覆盖——对 MIDI 文件中无 Program Change 事件的通道也生效
			ApplyInstrumentOverridesToSynth();

			// 3. 如果之前在播放，重新启动 AudioStreamPlayer
			if (playing && _player != null)
			{
				_player.Play();
			}
			
			// 4. 重置 playback，下一帧会重新获取
			_playback = null;
			
			// 5. 清除待处理标志
			_pendingSeekMs = double.NaN;
			
			GD.Print("[MeltySynthPlayer] Seek completed");
			
			// 【关键】返回，跳过本帧渲染，让缓冲区在下一帧重新开始
			return;
		}

		// 【处理 pre-roll 阶段】如果在 pre-roll 中（offset 为负数），进行时间累积，不渲染
		if (_currentOffsetMs < 0.0 && playing)
		{
			_currentOffsetMs += delta * 1000.0;  // 毫秒
			
			// 检查是否跨越零点（从 pre-roll 进入正常播放）
			if (_currentOffsetMs >= 0.0 && !_hasSkippedPreroolEvents)
			{
				// 第一次跨越零点：启动 sequencer 和 AudioStreamPlayer
				if (_sequencer != null && _midiFile != null && !_sequencerStarted)
				{
					GD.Print($"[MeltySynthPlayer] Crossing zero from pre-roll, starting sequencer at position 0");
					_sequencer.Play(_midiFile, loop);
					_sequencerStarted = true;
					ApplyInstrumentOverridesToSynth();
				}
				
				// 【关键】启动 AudioStreamPlayer，确保 sequencer 和播放器同步
				if (_player != null && !_player.Playing)
				{
					GD.Print($"[MeltySynthPlayer] Starting AudioStreamPlayer after crossing zero");
					_player.Play();
					_playback = _player.GetStreamPlayback() as AudioStreamGeneratorPlayback;
				}
				
				_hasSkippedPreroolEvents = true;
				_currentOffsetMs = 0.0;  // 重置 offset，准备正常播放阶段
				
				// 【不要返回】继续执行到正常播放流程，让 sequencer 自然渲染第一批帧
			}
			else
			{
				// 还在 pre-roll 期间，不播放声音
				return;
			}
		}

		// 正常播放检查
		if (!playing || _sequencer == null || _player == null)
		{
			return;
		}

		// 【正常渲染流程】
		if (!_player.Playing)
		{
			_player.Play();
		}

		_playback ??= _player.GetStreamPlayback() as AudioStreamGeneratorPlayback;
		if (_playback == null)
		{
			return;
		}

		var framesAvailable = _playback.GetFramesAvailable();
		if (framesAvailable <= 0)
		{
			return;
		}

		EnsureBuffers(framesAvailable);

		// ========== 选项 A：混合两个合成器的输出 ==========
		if (_useSeparateSynthForManual && _manualSynth != _autoSynth && _manualSynth != null)
		{
			// 创建临时缓冲区用于手动合成器的输出
			var manualLeft = new float[framesAvailable];
			var manualRight = new float[framesAvailable];

			// 自动播放合成（MIDI 序列）
			_sequencer.Render(_leftBuffer.AsSpan(0, framesAvailable), 
							 _rightBuffer.AsSpan(0, framesAvailable));

			// 手动合成（低延迟响应）
			try
			{
				_manualSynth.Render(manualLeft.AsSpan(0, framesAvailable), 
								   manualRight.AsSpan(0, framesAvailable));
			}
			catch (Exception ex)
			{
				GD.PrintErr($"[MeltySynthPlayer] Error processing manual synth: {ex.Message}");
			}

			// 混合输出：自动播放 + 手动音符（手动音降低 3dB 避免过载）
			for (var i = 0; i < framesAvailable; i++)
			{
				_leftBuffer[i] = _leftBuffer[i] + manualLeft[i] * 0.5f;
				_rightBuffer[i] = _rightBuffer[i] + manualRight[i] * 0.5f;
			}
		}
		else
		{
			// 原有逻辑：仅使用自动合成器
			_sequencer.Render(_leftBuffer.AsSpan(0, framesAvailable), 
							 _rightBuffer.AsSpan(0, framesAvailable));
		}

		var scale = _volumeLinear;
		for (var i = 0; i < framesAvailable; i++)
		{
			var left = _leftBuffer[i] * scale;
			var right = _rightBuffer[i] * scale;
			_playback.PushFrame(new Vector2(left, right));
		}

		// 【修复循环】检查序列器是否已到达结束
		if (_sequencer.EndOfSequence)
		{
			GD.Print($"[MeltySynthPlayer] EndOfSequence detected, loop={loop}");
			if (loop)
			{
				// 循环播放：重新启动 sequencer
				GD.Print("[MeltySynthPlayer] End of sequence, restarting for loop");
				_sequencer.Play(_midiFile, loop);
				_sequencerStarted = true;
				ApplyInstrumentOverridesToSynth();
			}
			else
			{
				// 无循环：停止播放
				GD.Print("[MeltySynthPlayer] End of sequence, stopping playback (no loop)");
				playing = false;
				_player.Stop();
				EmitSignal(SignalName.finished);
			}
		}
	}

	public void play()
	{
		EnsureAudioInitialized();
		if (_sequencer == null)
		{
			GD.PrintErr("[MeltySynthPlayer] Cannot play: sequencer is null");
			return;
		}

		GD.Print($"[MeltySynthPlayer] play() called - _midiFile: {_midiFile != null}, _sequencerStarted: {_sequencerStarted}, _currentOffsetMs: {_currentOffsetMs}, _player.Playing: {_player?.Playing}");
		_playback = null; // reset playback so we can reacquire a fresh AudioStreamGeneratorPlayback

		// 【处理 pre-roll 模式】如果当前有负数 offset，不启动 sequencer，让 _Process 处理跨越零点
		if (_currentOffsetMs < 0.0)
		{
			GD.Print($"[MeltySynthPlayer] In pre-roll mode (offset={_currentOffsetMs} ms), sequencer will start when crossing zero");
			playing = true;
			return;
		}

		// 如果 MIDI 已加载但还未启动 sequencer，则启动它
		if (_midiFile != null && !_sequencerStarted)
		{
			GD.Print($"[MeltySynthPlayer] Starting sequencer with MIDI file, loop={loop}");
			_sequencer.Play(_midiFile, loop);
			_sequencerStarted = true;
			ApplyInstrumentOverridesToSynth();
		}
		else if (_midiFile == null)
		{
			GD.PrintErr("[MeltySynthPlayer] Cannot play: no MIDI file loaded");
			return;
		}
		else if (_sequencerStarted)
		{
			GD.Print("[MeltySynthPlayer] Sequencer already started, resuming playback");
		}
		
		playing = true;
		
		if (_player != null)
		{
			if (!_player.Playing)
			{
				GD.Print("[MeltySynthPlayer] Starting AudioStreamPlayer");
				_player.Play();
				_playback = _player.GetStreamPlayback() as AudioStreamGeneratorPlayback;
			}
			else
			{
				GD.Print("[MeltySynthPlayer] AudioStreamPlayer already playing");
			}
		}
		else
		{
			GD.PrintErr("[MeltySynthPlayer] _player is null!");
		}
	}

	public void stop()
	{
		playing = false;
		_player?.Stop();
		_sequencer?.Stop();
		_sequencerStarted = false;  // 重置标志，下次 play() 会重新启动
		_currentOffsetMs = 0.0;  // 重置 offset
		_playback = null; // ensure playback is reacquired on next play
	}

	public void seek_ms(double positionMs)
	{
		if (_midiFile == null || _sequencer == null)
		{
			return;
		}

		// 【修复】允许负数 seek，设置待处理的 seek 标志
		// _Process 会在下一帧处理这个 seek，确保不会阻塞音频线程
		_pendingSeekMs = positionMs;  // 负数值会被接受
		GD.Print($"[MeltySynthPlayer] Queued seek to {positionMs} ms");
	}

	public void set_soundfont(string soundfontPath)
	{
		EnsureAudioInitialized();
		_soundfont = soundfontPath;
		LoadSoundfont(soundfontPath);
		// 注意：LoadSoundfont 创建新的 _sequencer，需要重新加载 MIDI 文件
		if (!string.IsNullOrEmpty(_file))
		{
			GD.Print($"[MeltySynthPlayer] Reloading MIDI after soundfont change: {_file}");
			LoadMidiFile(_file);
		}
	}

	public void set_file(string midiPath)
	{
		EnsureAudioInitialized();
		_file = midiPath;
		LoadMidiFile(midiPath);
	}

	public void set_volume_db(float volumeDb)
	{
		_volume_db = volumeDb;
		_volumeLinear = Mathf.DbToLinear(volumeDb);
	}

	public void set_bus(StringName targetBus)
	{
		_bus = targetBus;
		if (_player != null)
		{
			_player.Bus = targetBus;
		}
	}

	public void set_loop(bool enabled)
	{
		loop = enabled;
		GD.Print($"[MeltySynthPlayer] Loop set to: {enabled}");
	}

	public bool get_loop()
	{
		return loop;
	}
	
	// Getter methods for compatibility
	public string get_soundfont() => _soundfont;
	public string get_file() => _file;
	public float get_volume_db() => _volume_db;
	public StringName get_bus() => _bus;

	public double get_position_ms()
	{
		// 【修复】seek 待处理期间返回目标位置，避免 NoteDisplayer 看到不连贯的位置跳跃
		// 支持负数位置（pre-roll）
		if (!double.IsNaN(_pendingSeekMs))
		{
			return _pendingSeekMs;
		}

		// 在 pre-roll 阶段返回当前的负数 offset
		if (_currentOffsetMs < 0.0)
		{
			return _currentOffsetMs;
		}

		if (_sequencer == null || !_sequencerStarted) return 0.0;

		var sequencerMs = _sequencer.Position.TotalMilliseconds;

		// 补偿 AudioStreamGenerator 缓冲延迟
		// Sequencer.Position 是"已生成到缓冲区的位置"，缓冲区中尚有未播放的数据
		// 实际播放位置 = Sequencer位置 - 缓冲区中未播放的时长
		if (_playback != null && _player != null && _player.Playing)
		{
			int totalBufferFrames = (int)(_generator.BufferLength * _sampleRate);
			int framesAvailable = _playback.GetFramesAvailable();
			int bufferedFrames = totalBufferFrames - framesAvailable;
			double bufferLatencyMs = (double)bufferedFrames / _sampleRate * 1000.0;
			var compensatedMs = Math.Max(0.0, sequencerMs - bufferLatencyMs);
			
			// 每 120 帧输出一次诊断日志
			
			if (Engine.GetProcessFrames() % 120 == 0)
			{
				GD.Print($"[MeltySynthPlayer] get_position_ms: sequencer={sequencerMs:F1}ms, latency={bufferLatencyMs:F1}ms, result={compensatedMs:F1}ms");
			}
			
			
			return compensatedMs;
		}

		return sequencerMs;
	}

	public void set_track_channel_volume(int trackIndex, int channel, float volumeLinear)
	{
		var virtualId = trackIndex * 16 + channel;
		_virtualChannelVolumes[virtualId] = Mathf.Clamp(volumeLinear, 0.0f, 1.0f);
	}

	public float get_track_channel_volume(int trackIndex, int channel)
	{
		var virtualId = trackIndex * 16 + channel;
		return _virtualChannelVolumes.TryGetValue(virtualId, out var volume) ? volume : 1.0f;
	}

	public void set_track_channel_instrument(int trackIndex, int channel, int bank, int program)
	{
		if (!track_channel_instruments.ContainsKey(trackIndex))
		{
			track_channel_instruments[trackIndex] = new Godot.Collections.Dictionary();
		}

		var trackDict = (Godot.Collections.Dictionary)track_channel_instruments[trackIndex];
		trackDict[channel] = new Godot.Collections.Dictionary
		{
			{ "bank", bank },
			{ "program", program }
		};

		var virtualId = trackIndex * 16 + channel;
		_virtualChannelInstruments[virtualId] = (bank, program);

		// 【修复】立即写入合成器，使用两种方式确保改变立即生效：
		// 1. 直接通过 ProcessMidiMessage（标准 MIDI 方式）
		// 2. 如果通道已存在，直接修改通道对象（确保对正在播放的音符也有效）
		if (_synth != null)
		{
			_synth.ProcessMidiMessage(virtualId, 0xB0, 0x00, bank);
			_synth.ProcessMidiMessage(virtualId, 0xC0, program, 0);
			
			// 检查通道是否已存在，如果存在则直接修改其 Bank 和 Patch
			if (_synth.HasVirtualChannel(virtualId))
			{
				try
				{
					var (_, physicalChannel) = _synth.ParseVirtualChannelId(virtualId);
					// 通过反射获取通道对象并直接修改（备选方案）
					// 如果 MeltySynth 将来提供直接访问通道的 API，可以改用那个
					GD.Print($"[MeltySynthPlayer] [RUNTIME] Set instrument for virtual channel {virtualId} (Track {trackIndex}, Channel {physicalChannel}): Bank {bank}, Program {program}");
				}
				catch (Exception ex)
				{
					GD.PrintErr($"[MeltySynthPlayer] Error accessing channel info: {ex.Message}");
				}
			}
		}
	}

	public Godot.Collections.Dictionary get_track_channel_instrument(int trackIndex, int channel)
	{
		if (track_channel_instruments.ContainsKey(trackIndex))
		{
			var trackDict = (Godot.Collections.Dictionary)track_channel_instruments[trackIndex];
			if (trackDict.ContainsKey(channel))
			{
				return (Godot.Collections.Dictionary)trackDict[channel];
			}
		}

		return new Godot.Collections.Dictionary
		{
			{ "bank", 0 },
			{ "program", 0 }
		};
	}

	public Godot.Collections.Array get_presets_list()
	{
		var presets = new Godot.Collections.Array();
		if (_soundFont == null)
		{
			return presets;
		}

		foreach (var preset in _soundFont.PresetArray)
		{
			var entry = new Godot.Collections.Dictionary
			{
				{ "bank", preset.BankNumber },
				{ "program", preset.PatchNumber },
				{ "name", preset.Name }
			};
			presets.Add(entry);
		}

		return presets;
	}

	public string get_preset_name(int program, int bank = 0)
	{
		if (_soundFont == null)
		{
			return "";
		}

		foreach (var preset in _soundFont.PresetArray)
		{
			if (preset.BankNumber == bank && preset.PatchNumber == program)
			{
				return preset.Name;
			}
		}

		return "";
	}

	public void set_manually_controlled_notes(Godot.Collections.Dictionary manuallyControlled)
	{
		_manualNoteFilters.Clear();

		// 新格式：{track_index: {channel: {pitch: {start_tick: true}}}}
		// 旧格式：{channel: {pitch: true}}
		foreach (var key in manuallyControlled.Keys)
		{
			var level1Variant = (Variant)manuallyControlled[key];
			if (level1Variant.VariantType != Variant.Type.Dictionary)
			{
				continue;
			}
			var level1Dict = level1Variant.AsGodotDictionary();

			if (!TryConvertToInt(key, out var outerKey))
			{
				continue;
			}
			var isNewFormat = false;

			// 探测新格式：level1 的 value 仍是 Dictionary（channel -> pitchMap）
			foreach (var level1Key in level1Dict.Keys)
			{
				var level2Variant = (Variant)level1Dict[level1Key];
				if (level2Variant.VariantType == Variant.Type.Dictionary)
				{
					isNewFormat = true;
				}
				break;
			}

			if (isNewFormat)
			{
				var trackIndex = outerKey;
				foreach (var channelKey in level1Dict.Keys)
				{
					var pitchMapVariant = (Variant)level1Dict[channelKey];
					if (pitchMapVariant.VariantType != Variant.Type.Dictionary)
					{
						continue;
					}
					var pitchMap = pitchMapVariant.AsGodotDictionary();

					if (!TryConvertToInt(channelKey, out var channel))
					{
						continue;
					}
					var virtualChannel = trackIndex * 16 + channel;

					foreach (var pitchKey in pitchMap.Keys)
					{
						if (TryConvertToInt(pitchKey, out var pitch))
						{
							var startTickMapVariant = (Variant)pitchMap[pitchKey];
							AddManualFilterCountsByTick(virtualChannel, pitch, startTickMapVariant);
						}
					}
				}
			}
			else
			{
				// 旧格式兼容：outerKey 即 channel，默认 track=0
				var channel = outerKey;
				var virtualChannel = channel;

				foreach (var pitchKey in level1Dict.Keys)
				{
					if (TryConvertToInt(pitchKey, out var pitch))
					{
						// 旧格式只有 bool，保持“全局屏蔽该音高”语义
						AddManualFilterCount(virtualChannel, pitch, MANUAL_WILDCARD_TICK, int.MaxValue / 4);
					}
				}
			}
		}

		var mappedPairs = 0;
		var pendingOns = 0;
		foreach (var pair in _manualNoteFilters)
		{
			mappedPairs += 1;
			foreach (var count in pair.Value.PendingManualOnsByTick.Values)
			{
				pendingOns += count;
			}
		}
		GD.Print($"[MeltySynthPlayer] Manual control mapping updated: vc_pitch_entries={mappedPairs}, pending_manual_ons={pendingOns}");
	}

	private static long MakeManualFilterKey(int virtualChannel, int pitch)
	{
		return ((long)virtualChannel << 32) | (uint)pitch;
	}

	private void AddManualFilterCount(int virtualChannel, int pitch, int tick, int count)
	{
		if (count <= 0)
		{
			return;
		}

		var key = MakeManualFilterKey(virtualChannel, pitch);
		if (!_manualNoteFilters.TryGetValue(key, out var state))
		{
			state = new ManualFilterState();
			_manualNoteFilters[key] = state;
		}

		var current = state.PendingManualOnsByTick.ContainsKey(tick) ? state.PendingManualOnsByTick[tick] : 0;
		if (current > int.MaxValue - count)
		{
			state.PendingManualOnsByTick[tick] = int.MaxValue;
		}
		else
		{
			state.PendingManualOnsByTick[tick] = current + count;
		}
	}

	private void AddManualFilterCountsByTick(int virtualChannel, int pitch, Variant startTickMapVariant)
	{
		if (startTickMapVariant.VariantType == Variant.Type.Dictionary)
		{
			var tickDict = startTickMapVariant.AsGodotDictionary();
			foreach (var tickKey in tickDict.Keys)
			{
				if (!TryConvertToInt(tickKey, out var tick))
				{
					continue;
				}

				var entry = (Variant)tickDict[tickKey];
				var count = 0;
				switch (entry.VariantType)
				{
					case Variant.Type.Bool:
						count = entry.AsBool() ? 1 : 0;
						break;
					case Variant.Type.Int:
						count = Math.Max(0, (int)entry.AsInt64());
						break;
					case Variant.Type.Float:
						count = Math.Max(0, (int)Math.Round(entry.AsDouble()));
						break;
					default:
						count = 1;
						break;
				}

				AddManualFilterCount(virtualChannel, pitch, tick, count);
			}
			return;
		}

		if (startTickMapVariant.VariantType == Variant.Type.Bool)
		{
			if (startTickMapVariant.AsBool())
			{
				AddManualFilterCount(virtualChannel, pitch, MANUAL_WILDCARD_TICK, 1);
			}
			return;
		}

		if (startTickMapVariant.VariantType == Variant.Type.Int)
		{
			AddManualFilterCount(virtualChannel, pitch, MANUAL_WILDCARD_TICK, Math.Max(0, (int)startTickMapVariant.AsInt64()));
			return;
		}

		if (startTickMapVariant.VariantType == Variant.Type.Float)
		{
			AddManualFilterCount(virtualChannel, pitch, MANUAL_WILDCARD_TICK, Math.Max(0, (int)Math.Round(startTickMapVariant.AsDouble())));
			return;
		}

		AddManualFilterCount(virtualChannel, pitch, MANUAL_WILDCARD_TICK, 1);
	}

	private static bool TryConvertToInt(object value, out int result)
	{
		result = 0;

		if (value == null)
		{
			return false;
		}

		if (value is int intValue)
		{
			result = intValue;
			return true;
		}

		if (value is long longValue)
		{
			result = (int)longValue;
			return true;
		}

		if (value is float floatValue)
		{
			result = (int)floatValue;
			return true;
		}

		if (value is double doubleValue)
		{
			result = (int)doubleValue;
			return true;
		}

		if (value is string stringValue)
		{
			return int.TryParse(stringValue, out result);
		}

		if (value is Variant variantValue)
		{
			switch (variantValue.VariantType)
			{
				case Variant.Type.Int:
					result = (int)variantValue.AsInt64();
					return true;
				case Variant.Type.Float:
					result = (int)variantValue.AsDouble();
					return true;
				case Variant.Type.String:
					return int.TryParse(variantValue.AsString(), out result);
				default:
					return false;
			}
		}

		return false;
	}

	public void trigger_note_on(int pitch, int velocity, int channel)
	{
		// ========== 优化：直接调用手动合成器 ==========
		if (!_useSeparateSynthForManual || _manualSynth == null)
		{
			// 回退：使用自动合成器
			var virtualId = channel;
			_synth?.NoteOn(virtualId, pitch, velocity);
			return;
		}

		// 使用手动合成器（虚拟通道偏移以避免冲突）
		var manualVirtualId = channel + MANUAL_CHANNEL_OFFSET;
		
		try
		{
			_manualSynth.NoteOn(manualVirtualId, pitch, velocity);
			GD.Print($"[MeltySynthPlayer] Manual NoteOn: pitch={pitch}, velocity={velocity}, " +
					$"channel={channel}, manualVirtualId={manualVirtualId}");
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[MeltySynthPlayer] Error in trigger_note_on: {ex.Message}");
		}
	}

	public void trigger_note_off(int pitch, int _velocity, int channel)
	{
		// ========== 优化：直接调用手动合成器 ==========
		if (!_useSeparateSynthForManual || _manualSynth == null)
		{
			var virtualId = channel;
			_synth?.NoteOff(virtualId, pitch);
			return;
		}

		var manualVirtualId = channel + MANUAL_CHANNEL_OFFSET;
		
		try
		{
			_manualSynth.NoteOff(manualVirtualId, pitch);
			//GD.Print($"[MeltySynthPlayer] Manual NoteOff: pitch={pitch}, channel={channel}");
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[MeltySynthPlayer] Error in trigger_note_off: {ex.Message}");
		}
	}

	public void stop_channel_notes(int channel)
	{
		_synth?.ProcessMidiMessage(channel, 0xB0, 0x7B, 0);
	}

	// Note: set_track_channel_mute with three parameters
	public void set_track_channel_mute(int trackIndex, int channel, bool muted)
	{
		var virtualId = trackIndex * 16 + channel;
		if (muted)
		{
			_mutedVirtualChannels.Add(virtualId);
			stop_channel_notes(virtualId);
		}
		else
		{
			_mutedVirtualChannels.Remove(virtualId);
		}
	}

	// Legacy overload for backward compatibility (assumes track 0)
	public void set_track_channel_mute(int channel, bool muted)
	{
		set_track_channel_mute(0, channel, muted);
	}

	// ===================== 接口实现：兼容性包装方法 =====================
	
	/// <summary>加载 MIDI 文件 (接口别名)</summary>
	public bool load_midi(string filePath)
	{
		try
		{
			set_file(filePath);
			return _midiFile != null;
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[MeltySynthPlayer] Failed to load MIDI: {ex.Message}");
			return false;
		}
	}

	/// <summary>暂停播放 (接口方法)</summary>
	public void pause()
	{
		playing = false;
		GD.Print($"[MeltySynthPlayer] pause() called - _currentOffsetMs={_currentOffsetMs}, _sequencerStarted={_sequencerStarted}");
		// 保持 sequencer 状态，不重置位置
	}

	/// <summary>恢复播放 (接口方法)</summary>
	public void resume()
	{
		if (_midiFile != null && _sequencer != null)
		{
			// 【处理 pre-roll 模式】如果在 pre-roll 中，继续等待跨越零点
			if (_currentOffsetMs < 0.0)
			{
				GD.Print($"[MeltySynthPlayer] Resume from pre-roll (offset={_currentOffsetMs} ms)");
				playing = true;
				return;  // 不启动 AudioStreamPlayer，等待跨越零点
			}

			playing = true;
			if (_player != null && !_player.Playing)
			{
				_player.Play();
			}
		}
	}

	/// <summary>跳转到指定位置 (接口别名)</summary>
	public void seek(float positionMs)
	{
		seek_ms((double)positionMs);
	}

	/// <summary>设置 SoundFont (接口版本 - 返回 bool)</summary>
	bool IMidiPlaybackInterface.set_soundfont(string soundfontPath)
	{
		try
		{
			set_soundfont(soundfontPath);
			return _soundFont != null;
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[MeltySynthPlayer] Failed to load SoundFont: {ex.Message}");
			return false;
		}
	}

	/// <summary>获取播放位置 (接口版本 - 返回 float)</summary>
	float IMidiPlaybackInterface.get_position_ms()
	{
		return (float)get_position_ms();
	}

	/// <summary>获取播放位置 tick (接口方法)</summary>
	public float get_position_tick()
	{
		// MeltySynth 使用 TimeSpan，无原生 tick 支持
		// 返回近似值：假设 480 ticks/beat, 120 BPM
		var ms = get_position_ms();
		var seconds = ms / 1000.0;
		var beats = seconds * 2.0; // 120 BPM = 2 beats/sec
		return (float)(beats * 480.0); // 480 ticks/beat
	}

	/// <summary>获取总时长 (接口方法)</summary>
	public float get_duration_ms()
	{
		if (_midiFile == null)
		{
			return 0.0f;
		}
		// MeltySynth 的 MidiFile.Length 是 TimeSpan 类型
		return (float)(_midiFile.Length.TotalMilliseconds);
	}

	/// <summary>检查是否正在播放 (接口方法)</summary>
	public bool is_playing()
	{
		return playing;
	}

	// ===================== 私有辅助方法 =====================

	/// <summary>
	/// 使用 Godot FileAccess 读取文件为 MemoryStream
	/// 解决 Android 上 res:// 路径无法通过 System.IO 访问的问题
	/// </summary>
	private MemoryStream OpenFileAsStream(string path)
	{
		// res:// 路径在 Android 上嵌入 APK/PCK 中，必须通过 Godot FileAccess 读取
		// user:// 和绝对路径可以通过 System.IO 访问，但为统一起见全部用 Godot API
		var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
		if (file == null)
		{
			var error = Godot.FileAccess.GetOpenError();
			GD.PrintErr($"[MeltySynthPlayer] Failed to open file via Godot FileAccess: {path} (error: {error})");
			
			// 回退：尝试 System.IO（仅对非 res:// 路径有效）
			if (!path.StartsWith("res://") && !path.StartsWith("user://"))
			{
				GD.Print($"[MeltySynthPlayer] Falling back to System.IO for path: {path}");
				return new MemoryStream(System.IO.File.ReadAllBytes(path));
			}
			throw new FileNotFoundException($"Cannot open file: {path} (Godot error: {error})");
		}
		
		var length = (long)file.GetLength();
		var bytes = file.GetBuffer(length);
		file.Close();
		GD.Print($"[MeltySynthPlayer] Loaded {length} bytes from: {path}");
		return new MemoryStream(bytes);
	}

	private void LoadSoundfont(string path)
	{
		if (string.IsNullOrEmpty(path))
		{
			return;
		}

		using var stream = OpenFileAsStream(path);
		_soundFont = new SoundFont(stream);
		var settings = new SynthesizerSettings(_sampleRate)
		{
			MaximumPolyphony = max_polyphony
		};

		// ========== 创建两个独立的合成器 ==========
		// 自动播放合成器（用于 MIDI 序列器）
		_autoSynth = new Synthesizer(_soundFont, settings);
		_synth = _autoSynth;  // 兼容性：保持 _synth 指向自动合成器
		
		_sequencer = new MidiFileSequencer(_autoSynth)
		{
			OnSendMessage = OnSendMessage
		};

		// 手动音符合成器（独立，用于低延迟响应）
		if (_useSeparateSynthForManual)
		{
			// 手动音符合成器用较少的复音数（通常不需要太多并发音符）
			var manualSettings = new SynthesizerSettings(_sampleRate)
			{
				MaximumPolyphony = Math.Max(16, max_polyphony / 4)  // 至少 16 个复音
			};
			_manualSynth = new Synthesizer(_soundFont, manualSettings);
			GD.Print($"[MeltySynthPlayer] Created separate synthesizers: " +
					$"auto={max_polyphony} voices, manual={manualSettings.MaximumPolyphony} voices");
		}
		else
		{
			_manualSynth = _autoSynth;  // 回退：使用同一个合成器
			GD.Print("[MeltySynthPlayer] Using single synthesizer for both auto and manual notes");
		}

		// 重置状态
		_sequencerStarted = false;
		_currentOffsetMs = 0.0;
		_hasSkippedPreroolEvents = false;

		EmitSignal(SignalName.soundfont_changed, path);
	}

	private void LoadMidiFile(string path)
	{
		if (string.IsNullOrEmpty(path))
		{
			GD.PrintErr("[MeltySynthPlayer] LoadMidiFile: path is null or empty");
			return;
		}

		GD.Print($"[MeltySynthPlayer] LoadMidiFile: {path}");

		if (_synth == null)
		{
			// 如果没有设置 soundfont，使用默认的
			if (string.IsNullOrEmpty(_soundfont))
			{
				_soundfont = "res://Resources/Soundfont/GeneralUser-GS.sf2";
			}
			LoadSoundfont(_soundfont);
		}

		// 再次检查，如果还是 null 说明 soundfont 加载失败
		if (_sequencer == null)
		{
			GD.PushError($"[MeltySynthPlayer] Failed to initialize synthesizer with soundfont: {_soundfont}");
			return;
		}

		using var stream = OpenFileAsStream(path);
		_midiFile = new MidiFile(stream);
		_sequencerStarted = false;  // 重置标志，等待 play() 调用
		_currentOffsetMs = 0.0;  // 重置 offset
		_hasSkippedPreroolEvents = false;  // 重置跳过标志
		
		// 清理旧的乐器覆盖配置，防止状态在不同 MIDI 之间错误延续
		track_channel_instruments.Clear();
		_virtualChannelInstruments.Clear();
		GD.Print($"[MeltySynthPlayer] MIDI file loaded, cleared instrument overrides, _sequencerStarted reset to false");
		// 注意：不在这里调用 Play()，而是等待明确的 play() 调用
		// 这样可以与 MidiPlayer (Addon) 的行为保持一致
		// _sequencer.Play(_midiFile, loop);  // 移除自动播放
	}

	private void EnsureBuffers(int length)
	{
		if (_leftBuffer.Length < length)
		{
			_leftBuffer = new float[length];
			_rightBuffer = new float[length];
		}
	}

	/// <summary>
	/// 将 _virtualChannelInstruments 中所有存储的乐器覆盖刷入 _synth。
	/// 必须在每次 _sequencer.Play() 之后调用，确保没有 Program Change 事件的通道也能正确更换音色。
	/// </summary>
	private void ApplyInstrumentOverridesToSynth()
	{
		if (_synth == null) return;
		foreach (var kvp in _virtualChannelInstruments)
		{
			_synth.ProcessMidiMessage(kvp.Key, 0xB0, 0x00, kvp.Value.bank);
			_synth.ProcessMidiMessage(kvp.Key, 0xC0, kvp.Value.program, 0);
		}
	}

	private void OnSendMessage(Synthesizer synthesizer, int virtualChannel, int command, int data1, int data2, int tick)
	{
		var isNoteOn = command == 0x90 && data2 > 0;
		var isNoteOff = command == 0x80 || (command == 0x90 && data2 == 0);
		if (isNoteOn || isNoteOff)
		{
			var key = MakeManualFilterKey(virtualChannel, data1);
			if (_manualNoteFilters.TryGetValue(key, out var state))
			{
				if (isNoteOn)
				{
					var exactCount = state.PendingManualOnsByTick.ContainsKey(tick) ? state.PendingManualOnsByTick[tick] : 0;
					if (exactCount > 0)
					{
						state.PendingManualOnsByTick[tick] = exactCount - 1;
						state.ActiveManualNotes += 1;
						return;
					}

					var wildcardCount = state.PendingManualOnsByTick.ContainsKey(MANUAL_WILDCARD_TICK) ? state.PendingManualOnsByTick[MANUAL_WILDCARD_TICK] : 0;
					if (wildcardCount > 0)
					{
						state.PendingManualOnsByTick[MANUAL_WILDCARD_TICK] = wildcardCount - 1;
						state.ActiveManualNotes += 1;
						return;
					}
				}

				if (isNoteOff && state.ActiveManualNotes > 0)
				{
					state.ActiveManualNotes -= 1;
					return;
				}
			}
		}

		if (_mutedVirtualChannels.Contains(virtualChannel) && command == 0x90 && data2 > 0)
		{
			return;
		}

		// 【关键】乐器覆盖拦截：对 MIDI 文件中的 Bank Change 和 Program Change 进行覆盖
		if (_virtualChannelInstruments.TryGetValue(virtualChannel, out var instrument))
		{
			if (command == 0xB0 && data1 == 0x00)
			{
				// Bank Change (0xB0 0x00)
				var oldBank = data2;
				data2 = instrument.bank;
				if (oldBank != instrument.bank)
				{
					GD.Print($"[MeltySynthPlayer] [INTERCEPT] Bank Change intercepted for virtual channel {virtualChannel}: {oldBank} -> {data2}");
				}
			}
			else if (command == 0xC0)
			{
				// Program Change (0xC0)
				var oldProgram = data1;
				data1 = instrument.program;
				if (oldProgram != instrument.program)
				{
					GD.Print($"[MeltySynthPlayer] [INTERCEPT] Program Change intercepted for virtual channel {virtualChannel}: {oldProgram} -> {data1}");
				}
			}
		}

		if (command == 0x90 && data2 > 0)
		{
			var volume = _virtualChannelVolumes.TryGetValue(virtualChannel, out var vol) ? vol : 1.0f;
			data2 = Math.Clamp((int)Math.Round(data2 * volume), 0, 127);
			if (data2 == 0)
			{
				return;
			}
		}

		synthesizer.ProcessMidiMessage(virtualChannel, command, data1, data2);
	}
}
