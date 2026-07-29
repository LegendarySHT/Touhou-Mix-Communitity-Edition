using Godot;
using MeltySynth;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Threading;
using TouhouMix.Midi;

/// <summary>
/// Meltysynth MIDI 播放器后端
/// 提供与 GDScript 后端一致的 API
/// </summary>
public partial class MeltySynthPlayer : Node
{
	// 可见性: internal 以便 partial 文件 (MeltySynthPlayer.MiniaudioBridge.cs) 中的
	// MiniaudioAudioOutputBridge 实现此接口
	internal interface IAudioOutputBridge
	{
		bool Initialize(Node owner, StringName bus, int sampleRate);
		void SetBus(StringName bus);
		void Play();
		void Stop();
		void Update();
		bool IsPlaying { get; }
		object SyncRoot { get; }
		void SetSynthesizers(MidiFileSequencer sequencer, Synthesizer autoSynth, Synthesizer manualSynth, bool useSeparateSynth);
		void SetVolume(float volumeLinear);
		void EnqueueNoteOn(int virtualId, int pitch, int velocity);
		void EnqueueNoteOff(int virtualId, int pitch);
		void Dispose();
		/// <summary>设置 post-seek 后需要静音渲染丢弃的帧数 (用于消耗 seek 瞬态).</summary>
		int PostSeekSilenceFrames { get; set; }
		/// <summary>获取当前音频输出延迟(毫秒), 包含设备内部延迟 + RingBuffer 延迟.</summary>
		float GetLatencyMs();
	}
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

	private IAudioOutputBridge _audioOutput;

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

	// 系统时钟模式的时间追踪
	private bool _useSystemStopwatch = false;      // 是否启用系统时钟模式
	private bool _previousPlaying = false;         // 上一帧的播放状态

	private readonly Dictionary<int, float> _virtualChannelVolumes = new Dictionary<int, float>();
	private readonly Dictionary<int, (int bank, int program)> _virtualChannelInstruments = new Dictionary<int, (int bank, int program)>();
	private readonly Dictionary<int, int> _virtualChannelCurrentBank = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCurrentProgram = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCc7 = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCc11 = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCc10 = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelPitchBend = new Dictionary<int, int>();

	private readonly Dictionary<long, ManualFilterState> _manualNoteFilters = new Dictionary<long, ManualFilterState>();
	private readonly HashSet<int> _mutedVirtualChannels = new HashSet<int>();

	// ============ 选项 A：独立合成器用于低延迟手动音符 ============
	private Synthesizer _manualSynth;      // 专用于手动触发的音符
	private Synthesizer _autoSynth;        // 原有：用于MIDI自动播放（就是 _synth）
	private bool _useSeparateSynthForManual = true;  // 启用独立合成器
	private bool _preferNativeSequencerSeek = true;

	// 用户配置的音频缓冲区大小（帧），对齐到2的幂
	private int _desiredBufferFrames = 1024;  // 默认1024帧，与稳定工作的旧版本一致

	// 跟踪已应用通道状态到手动合成器的虚拟通道，避免每次触发音符重复设置
	private readonly ConcurrentDictionary<int, byte> _channelStateAppliedToManual = new ConcurrentDictionary<int, byte>();

	// ============ OnSendMessage 拦截器管道 ============
	private MessageHandlerContext _messageContext;
	private readonly List<IMidiMessageHandler> _handlers = new List<IMidiMessageHandler>();

	private void RequestAudioOutputPlay()
	{
		if (_audioOutput == null) return;
		if (!_audioOutput.IsPlaying)
			_audioOutput.Play();
	}


	private void EnsureAudioInitialized()
	{
		// WASAPI 采样率策略 (借鉴 TouhouMix Unity 项目技巧, 仅 Windows 适用):
		// Realtek 驱动限制 WASAPI 共享模式 min period=480 帧.
		// - 480 帧 @ 48000Hz = 10ms (不达标)
		// - 480 帧 @ 96000Hz = 5ms  (达标 <10ms)
		// 提高采样率让同样帧数对应更短时间, 突破 Realtek 的 period 限制.
		// 如果设备原生支持 96000Hz, IAudioClient3 会用 96000Hz, period 降为 5ms.
		// 如果设备只支持 48000Hz, miniaudio 用内部重采样器做 96k→48k SRC.
		//
		// 【注意】96000Hz 技巧仅 Windows/WASAPI 需要. Android/iOS 的 AAudio/OpenSL
		// 后端本身就支持低延迟 (AAUDIO_CONTENT_TYPE_MEDIA, framesPerBurst 通常 192-240),
		// 无需高采样率技巧. 强制 96000Hz 会导致:
		//   - Android: AAudio 后端初始化失败 (noAutoConvertSRC 是 WASAPI 专用)
		//   - iOS: 类似不兼容
		// 因此非 Windows 平台直接使用 AudioServer.GetMixRate() (通常 48000Hz).
		//
		// 环境变量 MINIAUDIO_SAMPLE_RATE 可覆盖默认采样率 (方便测试).
		// 独占模式必须用设备原生采样率 (通常 48000Hz), 不能强制 96000Hz.
		int oldSampleRate = _sampleRate;
		_sampleRate = (int)AudioServer.GetMixRate();  // 重新读取 (可能 44100)
		int targetRate = _sampleRate;  // 默认使用系统采样率
		// 仅 Windows 需要高采样率技巧突破 WASAPI period 限制
		if (OS.GetName() == "Windows")
		{
			// 独占模式必须用设备原生采样率 (通常 48000Hz), 共享模式用 96000Hz 突破 period 限制
			targetRate = (System.Environment.GetEnvironmentVariable("MINIAUDIO_EXCLUSIVE") == "1") ? 48000 : 96000;
		}
		var envRate = System.Environment.GetEnvironmentVariable("MINIAUDIO_SAMPLE_RATE");
		if (!string.IsNullOrEmpty(envRate) && int.TryParse(envRate, out int envRateVal) && envRateVal > 0)
		{
			targetRate = envRateVal;
		}
		if (_sampleRate != targetRate)
		{
			GD.Print($"[MeltySynthPlayer] miniaudio: adjusting sample rate {_sampleRate} → {targetRate} " +
				$"({(OS.GetName() == "Windows" ? "high sample rate for lower latency" : "env override")})");
			_sampleRate = targetRate;
		}

		// 【关键修复】采样率变化时必须重建合成器, 否则合成器仍用旧采样率渲染.
		// 例: 合成器 44100Hz + 设备 96000Hz → 音高偏高 2.18x (尖锐声) + 序列器加速
		//     → 音符触发频率翻倍 → CPU 过载 → 大量 underrun.
		// _midiFile 对象独立于合成器, 重建后 play() 会用新 sequencer 重新加载它.
		if (_sampleRate != oldSampleRate && _autoSynth != null && !string.IsNullOrEmpty(_soundfont))
		{
			GD.Print($"[MeltySynthPlayer] Sample rate changed {oldSampleRate}→{_sampleRate}, rebuilding synthesizers");
			LoadSoundfont(_soundfont);
		}

		if (_audioOutput != null)
			return;

		var bridge = CreateAudioOutputBridge();

		// 【关键】在 Initialize() 创建音频流之前先设置合成器引用
		// 否则 Initialize() 一触发 PCM 回调，合成器还来不及设置就会报 null 错误
		if (_sequencer != null && _autoSynth != null)
		{
			bridge.SetSynthesizers(_sequencer, _autoSynth, _manualSynth, _useSeparateSynthForManual);
			bridge.SetVolume(_volumeLinear);
		}

		if (!bridge.Initialize(this, _bus, _sampleRate))
		{
			GD.PrintErr("[MeltySynthPlayer] Failed to initialize audio bridge. MIDI playback will be silent.");
			return;
		}

		_audioOutput = bridge;
		GD.Print("[MeltySynthPlayer] Audio bridge initialized with synthesizers preset");
	}

	private IAudioOutputBridge CreateAudioOutputBridge()
	{
		// 使用 miniaudio 后端: 优先低延迟, RingBuffer 容量 ×3
		var maBridge = new MiniaudioAudioOutputBridge(0);

		var osName = OS.GetName();
		uint maPeriod;

		if (osName == "Windows")
		{
			// WASAPI 共享模式 (默认): period 被强制为 480 (≈10ms), 设备延迟 ~15ms.
			// 可与 Godot AudioServer 共存, 无冲突.
			//
			// WASAPI 独占模式: period 可设到 128 (≈2.7ms), 设备延迟 ~4ms.
			// 但独占模式与 Godot AudioServer 冲突, 会导致:
			//   1. "Device was unplugged" 警告刷屏
			//   2. 独占模式虽然 period=128 成功, 但可能无声音 (设备端点被 invalidate)
			// 要启用独占模式, 必须设 Godot audio/driver/driver="Dummy".
			// 通过环境变量 MINIAUDIO_EXCLUSIVE=1 启用独占模式.
			maBridge.SetBackend(MiniaudioNative.Backend.Wasapi);
			bool useExclusive = System.Environment.GetEnvironmentVariable("MINIAUDIO_EXCLUSIVE") == "1";
			maBridge.SetWASAPIExclusive(useExclusive);
			maPeriod = useExclusive ? 128u : 256u;
		}
		else if (osName == "Android")
		{
			maBridge.SetBackend(MiniaudioNative.Backend.Aaudio);
			maBridge.SetAAudioExclusive(true);
			maPeriod = (uint)Math.Min(_desiredBufferFrames, 256);
		}
		else
		{
			maPeriod = (uint)Math.Min(_desiredBufferFrames, 256);
		}

		// _decodeFrames 初始设为 period, Initialize 后会根据 actualPeriod 上调
		maBridge.SetDecodeFrames((int)maPeriod);
		maBridge.SetPeriodSize(maPeriod, 2);

		GD.Print($"[MeltySynthPlayer] Creating miniaudio bridge: decode={maPeriod}f, period=({maPeriod},2), os={osName}, exclusive={(osName == "Windows" ? (System.Environment.GetEnvironmentVariable("MINIAUDIO_EXCLUSIVE") == "1" ? "yes" : "no") : "n/a")}");
		return maBridge;
	}

	/// <summary>
	/// 设置音频缓冲区大小（帧）
	/// 注意：此设置需要重新初始化音频后端才能生效
	/// </summary>
	public void SetAudioBufferFrames(int frames)
	{
		// 对齐到 2 的幂，避免内部 DSP 块不对齐
		var aligned = 256;
		if (frames <= 256) aligned = 256;
		else if (frames <= 512) aligned = 512;
		else if (frames <= 1024) aligned = 1024;
		else aligned = 2048;
		
		// 检查缓冲区大小是否真的改变了
		if (_desiredBufferFrames == aligned)
		{
			GD.Print($"[MeltySynthPlayer] Audio buffer frames already set to {aligned}, skipping reinitialization");
			return;
		}
		
		_desiredBufferFrames = aligned;
		GD.Print($"[MeltySynthPlayer] Audio buffer frames: requested={frames}, aligned={aligned}");

		// 重新创建音频桥以应用新的缓冲区大小
		if (_audioOutput != null)
		{
			GD.Print($"[MeltySynthPlayer] Recreating audio bridge with new buffer size: {aligned} frames");
			
			// 保存当前播放状态
			bool wasPlaying = _audioOutput.IsPlaying;
			
			// 【关键修复】先销毁旧音频桥，停止其音频回调
			// 否则旧桥的 PCM 回调仍在音频线程运行，与新桥共享_sequencer
			// 两个桥各自有独立的 _synthLock，无法保护共享合成器，导致竞态条件
			_audioOutput.Dispose();
			_audioOutput = null;
			
			// 重新初始化音频桥（会使用新的 _desiredBufferFrames）
			EnsureAudioInitialized();
			
			// 恢复合成器引用
			if (_sequencer != null && _autoSynth != null)
			{
				_audioOutput.SetSynthesizers(_sequencer, _autoSynth, _manualSynth, _useSeparateSynthForManual);
				_audioOutput.SetVolume(_volumeLinear);
				GD.Print("[MeltySynthPlayer] Synthesizers restored after audio bridge recreation");
			}
			
			// 如果之前在播放，恢复播放
			if (wasPlaying && _audioOutput != null)
			{
				_audioOutput.Play();
				GD.Print("[MeltySynthPlayer] Playback resumed after audio bridge recreation");
			}
		}
		else
		{
			GD.Print($"[MeltySynthPlayer] Audio bridge not yet created, new buffer size will be applied on next initialization");
		}
	}

	/// <summary>
	/// 获取当前音频延迟 (毫秒).
	/// miniaudio 后端: 设备内部延迟 (ma_device_get_latency) + RingBuffer 延迟
	/// </summary>
	public float GetAudioLatencyMs()
	{
		if (_audioOutput is MiniaudioAudioOutputBridge maBridge)
		{
			return maBridge.GetLatencyMs();
		}
		return 0f;
	}

	/// <summary>
	/// 获取音频延迟分解 (设备延迟 ms, RingBuffer 延迟 ms).
	/// 用于诊断延迟来源
	/// </summary>
	public Godot.Collections.Dictionary GetAudioLatencyBreakdown()
	{
		var result = new Godot.Collections.Dictionary();
		if (_audioOutput is MiniaudioAudioOutputBridge maBridge)
		{
			var (deviceMs, ringMs) = maBridge.GetLatencyBreakdown();
			result["device_ms"] = deviceMs;
			result["ring_ms"] = ringMs;
			result["total_ms"] = deviceMs + ringMs;
			result["actual_period"] = (int)maBridge.ActualPeriod;
			result["actual_period_count"] = (int)maBridge.ActualPeriodCount;
		}
		else
		{
			result["device_ms"] = 0f;
			result["ring_ms"] = 0f;
			result["total_ms"] = 0f;
			result["actual_period"] = 0;
			result["actual_period_count"] = 0;
		}
		return result;
	}

	public override void _Ready()
	{
		GD.Print("[MeltySynthPlayer] _Ready() called");
		EnsureAudioInitialized();
		GD.Print($"[MeltySynthPlayer] _Ready() complete: _audioOutput={( _audioOutput != null ? _audioOutput.GetType().Name : "null" )}");

		SetProcess(true);
	}

	public override void _Process(double delta)
	{
		_audioOutput?.Update();

		// 【修复D-1】记录播放开始的时刻（用于系统时钟模式）
		if (playing && !_previousPlaying)
		{
			_previousPlaying = true;
		}
		else if (!playing && _previousPlaying)
		{
			_previousPlaying = false;
		}

		// 【关键】处理待处理的 seek 操作优先级最高，即使不在播放中也要处理
		if (!double.IsNaN(_pendingSeekMs))
		{
			// GD.Print($"[MeltySynthPlayer] Processing seek to {_pendingSeekMs} ms (playing={playing})");
			
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
				_audioOutput?.Stop();
				
				// 【关键】停止 sequencer，防止在后台继续运行
				if (_sequencer != null)
				{
					_sequencer.Stop();
					// GD.Print($"[MeltySynthPlayer] Stopped sequencer for pre-roll mode");
				}
				
			// GD.Print($"[MeltySynthPlayer] Pre-roll mode: offset set to {_currentOffsetMs} ms");
				_pendingSeekMs = double.NaN;
				return;
			}

			// 正数 seek：正常处理
			// 1. 如果正在播放，停止 AudioStreamPlayer 清空缓冲区
			_audioOutput?.Stop();

			// 2. 确保 sequencer 已启动，再使用原生 Seek
			if (!_sequencerStarted)
			{
				_sequencer.Play(_midiFile, loop);
				_sequencerStarted = true;
				ApplyInstrumentOverridesToSynth();
			}

			if (_preferNativeSequencerSeek)
			{
				try
				{
					_sequencer.Seek(TimeSpan.FromMilliseconds(_pendingSeekMs));
				}
				catch (Exception ex)
				{
					GD.PrintErr($"[MeltySynthPlayer] Native sequencer seek failed, fallback to legacy seek: {ex.Message}");
					LegacySeekByFastForward(_pendingSeekMs);
				}
				// Schedule post-seek silence to consume transient note attacks.
				// Rendered audio will be silently discarded for ~50ms instead of
				// doing a synchronous flush that can crash the renderer.
				// 通过接口访问音频后端
				if (_audioOutput != null)
					_audioOutput.PostSeekSilenceFrames = (int)(_sampleRate * 0.25);
			}
			else
			{
				LegacySeekByFastForward(_pendingSeekMs);
			}
			_currentOffsetMs = 0.0;  // 清除任何 pre-roll offset
			_hasSkippedPreroolEvents = true;  // 正数seek时无需跳过事件

			// 3. 如果之前在播放，重新启动 AudioStreamPlayer
			if (playing)
			{
				RequestAudioOutputPlay();
			}
			
			// 5. 清除待处理标志
			_pendingSeekMs = double.NaN;
			
			// GD.Print("[MeltySynthPlayer] Seek completed");
			
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
					// GD.Print($"[MeltySynthPlayer] Crossing zero from pre-roll, starting sequencer at position 0");
					_sequencer.Play(_midiFile, loop);
					_sequencerStarted = true;
					ApplyInstrumentOverridesToSynth();
				}
				
				// 【关键】启动 AudioStreamPlayer，确保 sequencer 和播放器同步
				RequestAudioOutputPlay();
				
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

		if (!playing || _sequencer == null || _audioOutput == null)
		{
			return;
		}

		// 直接在回调中合成，主循环只需要确保播放已启动
		RequestAudioOutputPlay();
	}

	public override void _ExitTree()
	{
		GD.Print("[MeltySynthPlayer] _ExitTree() called, disposing audio resources");
		if (_audioOutput != null)
		{
			_audioOutput.Dispose();
			_audioOutput = null;
		}
		_sequencer = null;
		_synth = null;
		_autoSynth = null;
		_manualSynth = null;
		_soundFont = null;
		_midiFile = null;
	}

	public void play()
	{
		EnsureAudioInitialized();
		GD.Print($"[MeltySynthPlayer] play() called - _midiFile={_midiFile != null}, _sequencerStarted={_sequencerStarted}, _audioOutput={( _audioOutput != null ? "OK" : "NULL" )}, _synth={(_synth != null ? "OK" : "NULL")}, _autoSynth={(_autoSynth != null ? "OK" : "NULL")}");
		if (_sequencer == null)
		{
			GD.PrintErr("[MeltySynthPlayer] Cannot play: sequencer is null");
			return;
		}

		// GD.Print($"[MeltySynthPlayer] play() called - _midiFile: {_midiFile != null}, _sequencerStarted: {_sequencerStarted}, _currentOffsetMs: {_currentOffsetMs}, _audioOutput.IsPlaying: {_audioOutput?.IsPlaying}");

		// 【处理 pre-roll 模式】如果当前有负数 offset，不启动 sequencer，让 _Process 处理跨越零点
		if (_currentOffsetMs < 0.0)
		{
			// GD.Print($"[MeltySynthPlayer] In pre-roll mode (offset={_currentOffsetMs} ms), sequencer will start when crossing zero");
			playing = true;
			return;
		}

		// 如果 MIDI 已加载但还未启动 sequencer，则启动它
		if (_midiFile != null && !_sequencerStarted)
		{
			// GD.Print($"[MeltySynthPlayer] Starting sequencer with MIDI file, loop={loop}");
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
			// GD.Print("[MeltySynthPlayer] Sequencer already started, resuming playback");
		}
		
		playing = true;
		RequestAudioOutputPlay();
	}

	public void stop()
	{
		playing = false;
		_audioOutput?.Stop();
		_sequencer?.Stop();
		_sequencerStarted = false;  // 重置标志，下次 play() 会重新启动
		_currentOffsetMs = 0.0;  // 重置 offset
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

		// GD.Print($"[MeltySynthPlayer] Queued seek to {positionMs} ms");
	}

	public void set_soundfont(string soundfontPath)
	{
		EnsureAudioInitialized();
		_soundfont = soundfontPath;
		LoadSoundfont(soundfontPath);
		// 注意：LoadSoundfont 创建新的 _sequencer，需要重新加载 MIDI 文件
		if (!string.IsNullOrEmpty(_file))
		{
			// GD.Print($"[MeltySynthPlayer] Reloading MIDI after soundfont change: {_file}");
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
		
		_audioOutput?.SetVolume(_volumeLinear);
	}

	public void set_bus(StringName targetBus)
	{
		_bus = targetBus;
		if (_audioOutput != null)
		{
			_audioOutput.SetBus(targetBus);
		}
	}

	public void set_loop(bool enabled)
	{
		loop = enabled;
		// GD.Print($"[MeltySynthPlayer] Loop set to: {enabled}");
	}

	public void set_max_polyphony(int value)
	{
		max_polyphony = Math.Max(16, Math.Min(256, value));
		GD.Print($"[MeltySynthPlayer] Max polyphony set to: {max_polyphony}");
		
		// 注意：Synthesizer.MaximumPolyphony 是只读属性，只能在创建时设置
		// 新设置将在下一次加载 SoundFont 时生效
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

		if (!playing)
		{
			return 0.0;
		}

		// 【修复D-3】使用 Sequencer 内部系统时钟模式（如果启用）
		if (_useSystemStopwatch)
		{
			if (_sequencer == null || !_sequencerStarted)
			{
				return 0.0;
			}

			double resultMs = _sequencer.Position.TotalMilliseconds;

			// 补偿设备缓冲延迟: Position 是墙钟时间, 比实际音频输出领先一个设备缓冲周期
			// 玩家根据听到的音频触摸, 判定必须用实际音频位置而非墙钟位置
			if (_audioOutput != null && _audioOutput.IsPlaying)
			{
				float deviceLatencyMs = _audioOutput.GetLatencyMs();
				resultMs = Math.Max(0.0, resultMs - deviceLatencyMs);
			}

			return resultMs;
		}

		// 【原有逻辑】使用 sequencer.Position + 缓冲补偿
		if (_sequencer == null || !_sequencerStarted) return 0.0;

		var sequencerMs = _sequencer.Position.TotalMilliseconds;

		// 补偿设备缓冲延迟: 用 GetLatencyMs() 获取真实延迟(设备内部 + RingBuffer)
		// 替代原先 GetTotalBufferFrames - GetFramesAvailable 的计算(后者在直接渲染模式下返回占位值导致负数)
		if (_audioOutput != null && _audioOutput.IsPlaying)
		{
			float latencyMs = _audioOutput.GetLatencyMs();
			return Math.Max(0.0, sequencerMs - latencyMs);
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

	// 【修复D】设置是否使用系统时钟模式
	public void set_use_system_stopwatch(bool enabled)
	{
		_useSystemStopwatch = enabled;
		if (_sequencer != null)
		{
			_sequencer.SetSystemClockMode(enabled);
			_sequencer.SetDiagnosticsEnabled(enabled);
		}
		// GD.Print($"[MeltySynthPlayer] System stopwatch mode: {(_useSystemStopwatch ? "ON" : "OFF")}" +
		// 	$", sequencerReady={_sequencer != null}, sequencerStarted={_sequencerStarted}");
	}

	public bool get_use_system_stopwatch()
	{
		return _useSystemStopwatch;
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
		_virtualChannelCurrentBank[virtualId] = bank;
		_virtualChannelCurrentProgram[virtualId] = program;

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
					// GD.Print($"[MeltySynthPlayer] [RUNTIME] Set instrument for virtual channel {virtualId} (Track {trackIndex}, Channel {physicalChannel}): Bank {bank}, Program {program}");
				}
				catch (Exception ex)
				{
					GD.PrintErr($"[MeltySynthPlayer] Error accessing channel info: {ex.Message}");
				}
			}
		}

		if (_manualSynth != null)
		{
			_manualSynth.ProcessMidiMessage(virtualId, 0xB0, 0x00, bank);
			_manualSynth.ProcessMidiMessage(virtualId, 0xC0, program, 0);
		}

		// 通道状态变化，清除缓存以强制下次触发时重新应用
		_channelStateAppliedToManual.TryRemove(virtualId, out _);
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
						AddManualFilterCount(virtualChannel, pitch, MessageHandlerContext.ManualWildcardTick, int.MaxValue / 4);
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
		// GD.Print($"[MeltySynthPlayer] Manual control mapping updated: vc_pitch_entries={mappedPairs}, pending_manual_ons={pendingOns}");
	}

	private void AddManualFilterCount(int virtualChannel, int pitch, int tick, int count)
	{
		if (count <= 0)
		{
			return;
		}

		var key = MessageHandlerContext.MakeManualFilterKey(virtualChannel, pitch);
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
				AddManualFilterCount(virtualChannel, pitch, MessageHandlerContext.ManualWildcardTick, 1);
			}
			return;
		}

		if (startTickMapVariant.VariantType == Variant.Type.Int)
		{
			AddManualFilterCount(virtualChannel, pitch, MessageHandlerContext.ManualWildcardTick, Math.Max(0, (int)startTickMapVariant.AsInt64()));
			return;
		}

		if (startTickMapVariant.VariantType == Variant.Type.Float)
		{
			AddManualFilterCount(virtualChannel, pitch, MessageHandlerContext.ManualWildcardTick, Math.Max(0, (int)Math.Round(startTickMapVariant.AsDouble())));
			return;
		}

		AddManualFilterCount(virtualChannel, pitch, MessageHandlerContext.ManualWildcardTick, 1);
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
		trigger_note_on(pitch, velocity, channel, 0);
	}

	public void trigger_note_on(int pitch, int velocity, int channel, int trackIndex)
	{
		var virtualId = trackIndex * 16 + channel;
		var volume = _virtualChannelVolumes.TryGetValue(virtualId, out var vol) ? vol : 1.0f;
		var scaledVelocity = Math.Clamp((int)Math.Round(velocity * volume), 0, 127);

		if (_mutedVirtualChannels.Contains(virtualId) || scaledVelocity == 0)
		{
			return;
		}

		// 应用通道状态（Bank/Program/CC等），缓存确保仅首次触发时生效
		ApplyChannelStateToManualSynth(virtualId);

		if (_audioOutput != null)
		{
			// 正常路径：无锁入队，音频线程在 FillPcmDataDirect 中处理
			_audioOutput.EnqueueNoteOn(virtualId, pitch, scaledVelocity);
			// 确保 audio device 已启动：非播放状态（如 DelayAdjust 校准）下 _Process 不渲染，
			// audio device 可能处于停止状态，入队的音符不会被消费。此处强制启动。
			RequestAudioOutputPlay();
		}
		else
		{
			// 回退路径：音频输出未就绪，直接调用合成器
			var synth = (_useSeparateSynthForManual && _manualSynth != null) ? _manualSynth : _synth;
			synth?.NoteOn(virtualId, pitch, scaledVelocity);
		}
	}

	public void trigger_note_off(int pitch, int _velocity, int channel)
	{
		trigger_note_off(pitch, _velocity, channel, 0);
	}

	public void trigger_note_off(int pitch, int _velocity, int channel, int trackIndex)
	{
		var virtualId = trackIndex * 16 + channel;

		if (_audioOutput != null)
		{
			// 正常路径：无锁入队
			_audioOutput.EnqueueNoteOff(virtualId, pitch);
		}
		else
		{
			// 回退路径：直接调用合成器
			var synth = (_useSeparateSynthForManual && _manualSynth != null) ? _manualSynth : _synth;
			synth?.NoteOff(virtualId, pitch);
		}
	}

	public void stop_channel_notes(int channel)
	{
		_synth?.ProcessMidiMessage(channel, 0xB0, 0x7B, 0);
	}

	private void stop_channel_notes_manual(int channel)
	{
		_manualSynth?.ProcessMidiMessage(channel, 0xB0, 0x7B, 0);
	}

	// Note: set_track_channel_mute with three parameters
	public void set_track_channel_mute(int trackIndex, int channel, bool muted)
	{
		var virtualId = trackIndex * 16 + channel;
		if (muted)
		{
			_mutedVirtualChannels.Add(virtualId);
			stop_channel_notes(virtualId);
			stop_channel_notes_manual(virtualId);
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
		if (_sequencer != null)
		{
			_sequencer.Pause();
		}
		// GD.Print($"[MeltySynthPlayer] pause() called - _currentOffsetMs={_currentOffsetMs}, _sequencerStarted={_sequencerStarted}");
		// 保持 sequencer 状态，不重置位置
	}

	/// <summary>恢复播放 (接口方法)</summary>
	public void resume()
	{
		if (_midiFile != null && _sequencer != null)
		{
			_sequencer.Resume();

			// 【处理 pre-roll 模式】如果在 pre-roll 中，继续等待跨越零点
			if (_currentOffsetMs < 0.0)
			{
				// GD.Print($"[MeltySynthPlayer] Resume from pre-roll (offset={_currentOffsetMs} ms)");
				playing = true;
				return;  // 不启动 AudioStreamPlayer，等待跨越零点
			}

			playing = true;
			_audioOutput?.Play();
		}
	}

	/// <summary>跳转到指定位置 (接口别名)</summary>
	public void seek(float positionMs)
	{
		seek_ms((double)positionMs);
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
				// GD.Print($"[MeltySynthPlayer] Falling back to System.IO for path: {path}");
				return new MemoryStream(System.IO.File.ReadAllBytes(path));
			}
			throw new FileNotFoundException($"Cannot open file: {path} (Godot error: {error})");
		}
		
		var length = (long)file.GetLength();
		var bytes = file.GetBuffer(length);
		file.Close();
		// GD.Print($"[MeltySynthPlayer] Loaded {length} bytes from: {path}");
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
			MaximumPolyphony = max_polyphony,
		BlockSize = 512,
		EnableReverbAndChorus = false
		};

		// ========== 创建两个独立的合成器 ==========
		// 自动播放合成器（用于 MIDI 序列器）
		_autoSynth = new Synthesizer(_soundFont, settings);
		_synth = _autoSynth;  // 兼容性：保持 _synth 指向自动合成器
		GD.Print($"[MeltySynthPlayer] Created autoSynth: sampleRate={settings.SampleRate}, polyphony={settings.MaximumPolyphony}");

		// 初始化 OnSendMessage 拦截器管道（仅一次，字典引用持久有效）
		if (_messageContext == null)
		{
			_messageContext = new MessageHandlerContext(
				_virtualChannelCurrentBank, _virtualChannelCurrentProgram,
				_virtualChannelCc7, _virtualChannelCc11, _virtualChannelCc10,
				_virtualChannelPitchBend, _virtualChannelInstruments,
				_virtualChannelVolumes, _manualNoteFilters,
				_mutedVirtualChannels, _channelStateAppliedToManual);
			_handlers.Clear();
			_handlers.Add(new ChannelStateMirrorHandler(_messageContext));
			_handlers.Add(new ManualNoteFilterHandler(_messageContext));
			_handlers.Add(new MuteFilterHandler(_messageContext));
			_handlers.Add(new InstrumentOverrideHandler(_messageContext));
			_handlers.Add(new VolumeScaleHandler(_messageContext));
			_handlers.Add(new SynthForwarderHandler());
		}

		_sequencer = new MidiFileSequencer(_autoSynth)
		{
			OnSendMessage = OnSendMessage
		};
		_sequencer.SetSystemClockMode(_useSystemStopwatch);
		_sequencer.SetDiagnosticsEnabled(_useSystemStopwatch);
		GD.Print("[MeltySynthPlayer] Created sequencer with autoSynth");

		// 手动音符合成器（独立，用于低延迟响应）
		if (_useSeparateSynthForManual)
		{
			// 手动音符合成器用较少的复音数（通常不需要太多并发音符）
			var manualSettings = new SynthesizerSettings(_sampleRate)
			{
				MaximumPolyphony = Math.Max(16, max_polyphony / 4),  // 至少 16 个复音
			BlockSize = 512,
			EnableReverbAndChorus = false
			};
			_manualSynth = new Synthesizer(_soundFont, manualSettings);
			// GD.Print($"[MeltySynthPlayer] Created separate synthesizers: " +
			// 		$"auto={max_polyphony} voices, manual={manualSettings.MaximumPolyphony} voices");
		}
		else
		{
			_manualSynth = _autoSynth;  // 回退：使用同一个合成器
			// GD.Print("[MeltySynthPlayer] Using single synthesizer for both auto and manual notes");
		}

		// 重置状态
		_sequencerStarted = false;
		_currentOffsetMs = 0.0;
		_hasSkippedPreroolEvents = false;

		// ========== 新架构：将合成器引用传递给音频桥接器 ==========
		_audioOutput?.SetSynthesizers(_sequencer, _autoSynth, _manualSynth, _useSeparateSynthForManual);
		_audioOutput?.SetVolume(_volumeLinear);
		GD.Print("[MeltySynthPlayer] Synthesizers passed to audio bridge");

		EmitSignal(SignalName.soundfont_changed, path);
	}

	private void LoadMidiFile(string path)
	{
		if (string.IsNullOrEmpty(path))
		{
			GD.PrintErr("[MeltySynthPlayer] LoadMidiFile: path is null or empty");
			return;
		}

		// GD.Print($"[MeltySynthPlayer] LoadMidiFile: {path}");

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
		// GD.Print($"[MeltySynthPlayer] MIDI file loaded, cleared instrument overrides, _sequencerStarted reset to false");
		// 注意：不在这里调用 Play()，而是等待明确的 play() 调用
		// 这样可以与 MidiPlayer (Addon) 的行为保持一致
		// _sequencer.Play(_midiFile, loop);  // 移除自动播放
	}

	private void LegacySeekByFastForward(double targetMs)
	{
		if (_sequencer == null || _midiFile == null || _synth == null)
		{
			return;
		}

		var restoreSystemClock = _useSystemStopwatch;
		if (restoreSystemClock)
		{
			_sequencer.SetSystemClockMode(false);
			_sequencer.SetDiagnosticsEnabled(false);
		}

		if (targetMs < 0.0)
		{
			targetMs = 0.0;
		}

		var targetSeconds = targetMs / 1000.0;
		var targetFrames = (long)(_sampleRate * targetSeconds);

		_sequencer.Play(_midiFile, loop);
		_sequencerStarted = true;
		ApplyInstrumentOverridesToSynth();

		var scratchLeft = new float[_synth.BlockSize];
		var scratchRight = new float[_synth.BlockSize];
		long remaining = targetFrames;

		while (remaining > 0)
		{
			var block = (int)Math.Min(remaining, _synth.BlockSize);
			_sequencer.Render(scratchLeft.AsSpan(0, block), scratchRight.AsSpan(0, block));
			remaining -= block;
		}

		if (restoreSystemClock)
		{
			_sequencer.SetSystemClockMode(true);
			_sequencer.SetDiagnosticsEnabled(true);
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
		foreach (var handler in _handlers)
		{
			if (!handler.Process(synthesizer, virtualChannel, ref command, ref data1, ref data2, tick))
				return;
		}
	}

	private void ApplyChannelStateToManualSynth(int virtualChannel)
	{
		if (_manualSynth == null)
		{
			return;
		}

		// 如果该通道状态已经应用过，跳过（大幅减少每次触发音符的MIDI消息开销）
		if (_channelStateAppliedToManual.ContainsKey(virtualChannel))
		{
			return;
		}

		if (_virtualChannelCurrentBank.TryGetValue(virtualChannel, out var bank))
		{
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xB0, 0x00, bank);
		}
		else if (_virtualChannelInstruments.TryGetValue(virtualChannel, out var overrideInstrument))
		{
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xB0, 0x00, overrideInstrument.bank);
		}

		if (_virtualChannelCurrentProgram.TryGetValue(virtualChannel, out var program))
		{
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xC0, program, 0);
		}
		else if (_virtualChannelInstruments.TryGetValue(virtualChannel, out var overrideProgram))
		{
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xC0, overrideProgram.program, 0);
		}

		if (_virtualChannelCc7.TryGetValue(virtualChannel, out var cc7))
		{
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xB0, 0x07, cc7);
		}
		if (_virtualChannelCc11.TryGetValue(virtualChannel, out var cc11))
		{
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xB0, 0x0B, cc11);
		}
		if (_virtualChannelCc10.TryGetValue(virtualChannel, out var cc10))
		{
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xB0, 0x0A, cc10);
		}
		if (_virtualChannelPitchBend.TryGetValue(virtualChannel, out var pitchBend14))
		{
			var lsb = pitchBend14 & 0x7F;
			var msb = (pitchBend14 >> 7) & 0x7F;
			_manualSynth.ProcessMidiMessage(virtualChannel, 0xE0, lsb, msb);
		}

		// 标记通道状态已应用
		_channelStateAppliedToManual.TryAdd(virtualChannel, 0);
	}
}
