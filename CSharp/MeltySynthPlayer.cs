using Godot;
using MeltySynth;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Reflection;
using TouhouMix.Midi;

/// <summary>
/// Meltysynth MIDI 播放器后端
/// 实现 IMidiPlaybackInterface 接口，提供与 GDScript 后端一致的 API
/// </summary>
public partial class MeltySynthPlayer : Node, IMidiPlaybackInterface
{
	private interface IAudioOutputBridge
	{
		bool Initialize(Node owner, StringName bus, int sampleRate);
		void SetBus(StringName bus);
		void Play();
		void Stop();
		void Update();
		bool IsPlaying { get; }
		int GetFramesAvailable();
		int GetTotalBufferFrames();
		void PushFrame(Vector2 frame);
	}

	private sealed class FmodAudioOutputBridge : IAudioOutputBridge
		{
			// 单层缓冲架构配置（最小化延迟但保持稳定性）
			private const int MIN_DECODE_FRAMES = 1024; 
			
			private FmodNative.FMOD_SOUND_PCMREAD_CALLBACK _pcmReadCallback;
			private FmodNative.FMOD_SOUND_PCMSETPOS_CALLBACK _pcmSetPosCallback;
			private IntPtr _system = IntPtr.Zero;
			private IntPtr _sound = IntPtr.Zero;
			private IntPtr _channel = IntPtr.Zero;
			
			// 直接渲染：持有合成器和序列器的引用
			private MidiFileSequencer _sequencer = null;
			private Synthesizer _autoSynth = null;
			private Synthesizer _manualSynth = null;
			private bool _useSeparateSynth = false;
			
			// 临时渲染缓冲区（交错格式）
			private float[] _tempLeft = Array.Empty<float>();
			private float[] _tempRight = Array.Empty<float>();
			private float[] _manualLeft = Array.Empty<float>();
			private float[] _manualRight = Array.Empty<float>();
			private float[] _outputBuffer = Array.Empty<float>();  // 交错格式输出缓冲区
			
			// 配置
			private int _sampleRate = 48000;
			private int _decodeFrames = 0;
			private float _volumeLinear = 1.0f;
			private const float OUTPUT_GAIN = 1.0f;  // 降低输出增益避免削波
			
			private bool _initialized = false;
			private bool _playing = false;
			private StringName _bus = new StringName("Master");
			
			// 统计信息
			private int _underrunCount = 0;
			private ulong _lastUnderrunLogMs = 0;
			private float _lastSampleL = 0;
			private float _lastSampleR = 0;
			private float _autoGain = 1.0f;
			
			// 线程同步
			private readonly object _synthLock = new object();

		public FmodAudioOutputBridge(float bufferLengthSeconds)
		{
			// bufferLengthSeconds不再用于预渲染，而是直接影响decodeFrames
		}

		/// <summary>
		/// 设置合成器引用 - 这是新架构的关键！
		/// </summary>
		public void SetSynthesizers(MidiFileSequencer sequencer, Synthesizer autoSynth, Synthesizer manualSynth, bool useSeparateSynth)
		{
			_sequencer = sequencer;
			_autoSynth = autoSynth;
			_manualSynth = manualSynth;
			_useSeparateSynth = useSeparateSynth;
		}

		public void SetVolume(float volumeLinear)
		{
			_volumeLinear = volumeLinear;
		}

		public bool Initialize(Node owner, StringName bus, int sampleRate)
			{
				if (_initialized)
				{
					return true;
				}

				_bus = bus;
				
				int systemSampleRate = (int)AudioServer.GetMixRate();
				_sampleRate = sampleRate > 0 ? sampleRate : systemSampleRate;
				
				if (_sampleRate != systemSampleRate)
				{
					GD.PushWarning($"[MeltySynthPlayer][FMOD] Sample rate mismatch: requested={_sampleRate}, system={systemSampleRate}");
				}

				// 最小化decodeFrames以实现最低延迟
				_decodeFrames = Math.Max(MIN_DECODE_FRAMES, Math.Min(512, (int)(_sampleRate * 0.010)));
				
				// 分配并清零缓冲区，避免垃圾值产生噪声
				_tempLeft = new float[_decodeFrames];
				_tempRight = new float[_decodeFrames];
				_manualLeft = new float[_decodeFrames];
				_manualRight = new float[_decodeFrames];
				_outputBuffer = new float[_decodeFrames * 2];
				
				// 确保缓冲区初始化为零
				Array.Clear(_tempLeft, 0, _tempLeft.Length);
				Array.Clear(_tempRight, 0, _tempRight.Length);
				Array.Clear(_manualLeft, 0, _manualLeft.Length);
				Array.Clear(_manualRight, 0, _manualRight.Length);
				Array.Clear(_outputBuffer, 0, _outputBuffer.Length);
				
				GD.Print($"[MeltySynthPlayer][FMOD] System audio info: mix_rate={systemSampleRate}Hz");
				GD.Print($"[MeltySynthPlayer][FMOD] Initializing bridge (DIRECT SYNTHESIS MODE): " +
					$"sample_rate={_sampleRate}, decode_buffer={_decodeFrames}f ({_decodeFrames * 1000.0 / _sampleRate:F1}ms)");

			if (!FmodNative.TryLoadNativeLibrary())
			{
				GD.PushWarning("[MeltySynthPlayer][FMOD] Native FMOD library could not be loaded.");
				return false;
			}

			if (!TryCreateSystem())
			{
				DisposeNative();
				return false;
			}

			if (!TryCreateStreamSound())
			{
				DisposeNative();
				return false;
			}

			_initialized = true;
			return true;
		}

		public void SetBus(StringName bus)
		{
			_bus = bus;
		}

		public void Play()
		{
			if (_channel == IntPtr.Zero)
			{
				return;
			}

			if (!_playing)
			{
				// 直接开始播放，不需要预填充
				FmodNative.FMOD_Channel_SetPaused(_channel, false);
				_playing = true;
				GD.Print("[MeltySynthPlayer][FMOD] Playback started (DIRECT MODE)");
			}
		}

		public void Stop()
			{
				if (_channel != IntPtr.Zero)
				{
					FmodNative.FMOD_Channel_SetPaused(_channel, true);
				}

				// 清除状态
				Array.Clear(_outputBuffer, 0, _outputBuffer.Length);
				_lastSampleL = 0;
				_lastSampleR = 0;
				
				_playing = false;
			}

		public void Update()
		{
			if (_system != IntPtr.Zero)
			{
				FmodNative.FMOD_System_Update(_system);
			}
		}

		public bool IsPlaying => _playing;

		public int GetFramesAvailable()
			{
				// 新架构下这个概念不再适用，返回一个固定值保持兼容性
				return 1024;
			}

			public int GetTotalBufferFrames()
			{
				return _decodeFrames;
			}

			public void PushFrame(Vector2 frame)
			{
				// 新架构不使用这个方法（直接在回调中合成）
				// 保留空实现以保持兼容性
			}

			/// <summary>
			/// 批量推入多帧 - 新架构不使用，保留兼容性
			/// </summary>
			public void PushFrames(Span<float> left, Span<float> right)
			{
				// 新架构直接在FMOD回调中合成，忽略推送操作
			}

		private bool TryCreateSystem()
		{
			var result = FmodNative.CreateSystem(out _system);
			if (result != FmodNative.RESULT.OK || _system == IntPtr.Zero)
			{
				GD.PushWarning($"[MeltySynthPlayer][FMOD] FMOD_System_Create failed: {result}");
				return false;
			}

			GD.Print("[MeltySynthPlayer][FMOD] FMOD_System_Create succeeded");

			// 设置FMOD系统采样率与合成器一致，避免采样率转换导致的噪声
			result = FmodNative.FMOD_System_SetSoftwareFormat(_system, _sampleRate, FmodNative.SPEAKERMODE.SPEAKERMODE_STEREO, 0);
			if (result != FmodNative.RESULT.OK)
			{
				GD.PushWarning($"[MeltySynthPlayer][FMOD] FMOD_System_SetSoftwareFormat failed: {result}");
			}
			else
			{
				GD.Print($"[MeltySynthPlayer][FMOD] FMOD_System_SetSoftwareFormat succeeded: {_sampleRate}Hz");
			}

			result = FmodNative.FMOD_System_Init(_system, 32, FmodNative.INITFLAGS.NORMAL, IntPtr.Zero);
			if (result != FmodNative.RESULT.OK)
			{
				GD.PushWarning($"[MeltySynthPlayer][FMOD] FMOD_System_Init failed: {result}");
				return false;
			}

			GD.Print("[MeltySynthPlayer][FMOD] FMOD_System_Init succeeded");

			return true;
		}

		private bool TryCreateStreamSound()
		{
			_pcmReadCallback = OnPcmRead;
			_pcmSetPosCallback = OnPcmSetPos;

			uint decodeFrames = (uint)_decodeFrames;
			uint totalFrames = (uint)_sampleRate * 60;
			totalFrames = (totalFrames / decodeFrames) * decodeFrames;

			var exinfo = new FmodNative.FMOD_CREATESOUNDEXINFO
			{
				cbsize = Marshal.SizeOf<FmodNative.FMOD_CREATESOUNDEXINFO>(),
				length = totalFrames * 2 * sizeof(float),
				numchannels = 2,
				defaultfrequency = _sampleRate,
				format = FmodNative.SOUND_FORMAT.PCMFLOAT,
				decodebuffersize = decodeFrames,
				pcmreadcallback = Marshal.GetFunctionPointerForDelegate(_pcmReadCallback),
				pcmsetposcallback = Marshal.GetFunctionPointerForDelegate(_pcmSetPosCallback)
			};

			var mode = FmodNative.MODE.OPENUSER | FmodNative.MODE.CREATESTREAM | FmodNative.MODE.LOOP_NORMAL;
			var result = FmodNative.FMOD_System_CreateSound(_system, "melty_synth_stream", mode, ref exinfo, out _sound);
			if (result != FmodNative.RESULT.OK || _sound == IntPtr.Zero)
			{
				GD.PushWarning($"[MeltySynthPlayer][FMOD] FMOD_System_CreateSound failed: {result}");
				return false;
			}

			GD.Print($"[MeltySynthPlayer][FMOD] FMOD_System_CreateSound succeeded: decode_buffer={decodeFrames} frames");

			result = FmodNative.FMOD_System_PlaySound(_system, _sound, IntPtr.Zero, true, out _channel);
			if (result != FmodNative.RESULT.OK || _channel == IntPtr.Zero)
			{
				GD.PushWarning($"[MeltySynthPlayer][FMOD] FMOD_System_PlaySound failed: {result}");
				return false;
			}

			GD.Print("[MeltySynthPlayer][FMOD] FMOD_System_PlaySound succeeded (initially paused, DIRECT MODE)");

			FmodNative.FMOD_Channel_SetPaused(_channel, true);
			return true;
		}

		private void DisposeNative()
		{
			if (_channel != IntPtr.Zero)
			{
				FmodNative.FMOD_Channel_Stop(_channel);
				_channel = IntPtr.Zero;
			}

			if (_sound != IntPtr.Zero)
			{
				FmodNative.FMOD_Sound_Release(_sound);
				_sound = IntPtr.Zero;
			}

			if (_system != IntPtr.Zero)
			{
				FmodNative.FMOD_System_Close(_system);
				FmodNative.FMOD_System_Release(_system);
				_system = IntPtr.Zero;
			}

			_initialized = false;
			_playing = false;
		}

		private FmodNative.RESULT OnPcmRead(IntPtr soundraw, IntPtr data, uint datalen)
			{
				// FMOD回调：直接在音频线程中合成！
				return FillPcmDataDirect(soundraw, data, datalen);
			}

			private FmodNative.RESULT OnPcmSetPos(IntPtr soundraw, int subsound, uint position, FmodNative.TIMEUNIT postype)
			{
				// FMOD循环时调用
				return FmodNative.RESULT.OK;
			}

			/// <summary>
		/// 核心方法：直接在FMOD回调中调用MeltySynth合成
		/// 使用最小缓冲，专注于低延迟
		/// </summary>
		private FmodNative.RESULT FillPcmDataDirect(IntPtr soundraw, IntPtr data, uint datalen)
		{
			var floatCount = (int)(datalen / sizeof(float));
			var framesRequested = floatCount / 2;
			var framesToRender = Math.Min(framesRequested, _decodeFrames);
			
			// 确保_outputBuffer足够大
			int requiredBufferSize = framesRequested * 2;
			if (_outputBuffer.Length < requiredBufferSize)
			{
				Array.Resize(ref _outputBuffer, requiredBufferSize);
			}
			
			// 快速路径：如果合成器不可用，填充静音
			if (_sequencer == null || _autoSynth == null)
			{
				FillWithSilenceAndCopy(data, framesRequested);
				return FmodNative.RESULT.OK;
			}
			
			try
			{
				float scale = _volumeLinear * OUTPUT_GAIN * _autoGain;
				
				// 使用锁保护合成器访问
				lock (_synthLock)
				{
					if (_useSeparateSynth && _manualSynth != null && _manualSynth != _autoSynth)
					{
						_sequencer.Render(_tempLeft.AsSpan(0, framesToRender), _tempRight.AsSpan(0, framesToRender));
						_manualSynth.Render(_manualLeft.AsSpan(0, framesToRender), _manualRight.AsSpan(0, framesToRender));
						MixToOutput(_tempLeft, _tempRight, _manualLeft, _manualRight, framesToRender, scale);
					}
					else
					{
						_sequencer.Render(_tempLeft.AsSpan(0, framesToRender), _tempRight.AsSpan(0, framesToRender));
						MixToOutput(_tempLeft, _tempRight, null, null, framesToRender, scale);
					}
					
					// 填充剩余空间（如果需要）
					if (framesToRender < framesRequested)
					{
						FillRemainderWithDecay(framesToRender, framesRequested);
					}
				}
			}
			catch (Exception ex)
			{
				GD.PrintErr($"[MeltySynthPlayer][FMOD] Exception: {ex.Message}");
				FillWithSilenceAndCopy(data, framesRequested);
				return FmodNative.RESULT.OK;
			}
			
			Marshal.Copy(_outputBuffer, 0, data, requiredBufferSize);
			return FmodNative.RESULT.OK;
		}
		
		/// <summary>
		/// 混合到输出缓冲区（交错格式）
		/// </summary>
		private void MixToOutput(float[] autoLeft, float[] autoRight, float[] manualLeft, float[] manualRight, int frames, float scale)
		{
			for (int i = 0; i < frames; i++)
			{
				float left = autoLeft[i];
				float right = autoRight[i];
				
				if (manualLeft != null)
				{
					left += manualLeft[i];
					right += manualRight[i];
				}
				
				// 先限幅，再应用音量（避免削波）
				left = SoftLimit(left);
				right = SoftLimit(right);
				
				// 应用音量（线性）
				left *= scale;
				right *= scale;
				
				// 交错格式
				_outputBuffer[i * 2] = left;
				_outputBuffer[i * 2 + 1] = right;
			}
			
			_lastSampleL = _outputBuffer[(frames - 1) * 2];
			_lastSampleR = _outputBuffer[(frames - 1) * 2 + 1];
		}
		
		/// <summary>
		/// 软限幅 - 使用tanh避免硬截断
		/// </summary>
		private float SoftLimit(float sample)
		{
			// 使用tanh进行软限幅，保留波形形状
			return (float)Math.Tanh(sample * 0.9) * 0.95f;
		}
		
		/// <summary>
		/// 填充静音（交错格式）
		/// </summary>
		private void FillWithSilence(IntPtr data, int frames)
		{
			// 确保_outputBuffer足够大
			int requiredBufferSize = frames * 2;
			if (_outputBuffer.Length < requiredBufferSize)
			{
				Array.Resize(ref _outputBuffer, requiredBufferSize);
			}
			
			float decay = (float)Math.Exp(-2.0 / frames);
			float l = _lastSampleL;
			float r = _lastSampleR;
			
			for (int i = 0; i < frames; i++)
			{
				// 交错格式
				_outputBuffer[i * 2] = l;
				_outputBuffer[i * 2 + 1] = r;
				l *= decay;
				r *= decay;
			}
			
			_lastSampleL = l;
			_lastSampleR = r;
			
			Marshal.Copy(_outputBuffer, 0, data, requiredBufferSize);
		}
		
		/// <summary>
		/// 填充静音并复制到目标（填充所有请求的帧）
		/// </summary>
		private void FillWithSilenceAndCopy(IntPtr data, int totalFrames)
		{
			// 确保_outputBuffer足够大
			int requiredBufferSize = totalFrames * 2;
			if (_outputBuffer.Length < requiredBufferSize)
			{
				Array.Resize(ref _outputBuffer, requiredBufferSize);
			}
			
			float decay = (float)Math.Exp(-2.0 / Math.Max(1, totalFrames));
			float l = _lastSampleL;
			float r = _lastSampleR;
			
			for (int i = 0; i < totalFrames; i++)
			{
				// 交错格式
				_outputBuffer[i * 2] = l;
				_outputBuffer[i * 2 + 1] = r;
				l *= decay;
				r *= decay;
			}
			
			_lastSampleL = l;
			_lastSampleR = r;
			
			Marshal.Copy(_outputBuffer, 0, data, requiredBufferSize);
		}
		
		/// <summary>
		/// 填充剩余空间（交错格式）
		/// </summary>
		private void FillRemainderWithDecay(int startFrame, int endFrame)
		{
			int frames = endFrame - startFrame;
			float decay = (float)Math.Exp(-2.0 / frames);
			float l = _lastSampleL;
			float r = _lastSampleR;
			
			for (int i = startFrame; i < endFrame; i++)
			{
				// 交错格式
				_outputBuffer[i * 2] = l;
				_outputBuffer[i * 2 + 1] = r;
				l *= decay;
				r *= decay;
			}
			
			_lastSampleL = l;
			_lastSampleR = r;
		}

			// 兼容性方法（保留但不再使用）
			public int GetWaterLevelPercent() { return 50; }
			public bool NeedPreRender() { return false; }
			public bool ShouldStopPreRender() { return true; }
			public int GetUnderrunCount() { return System.Threading.Interlocked.CompareExchange(ref _underrunCount, 0, 0); }
	}

	private static class FmodNative
	{
		private const uint FMOD_VERSION = 0x00020306;

		internal enum RESULT : int
		{
			OK = 0
		}

		[Flags]
		internal enum MODE : uint
		{
			DEFAULT = 0x00000000,
			LOOP_NORMAL = 0x00000002,
			CREATESTREAM = 0x00000080,
			OPENUSER = 0x00000400
		}

		internal enum INITFLAGS : uint
		{
			NORMAL = 0x00000000
		}

		internal enum SOUND_FORMAT : int
		{
			PCMFLOAT = 5
		}

		internal enum TIMEUNIT : uint
		{
			MS = 0x00000001
		}

		internal enum SPEAKERMODE : int
		{
			SPEAKERMODE_DEFAULT = 0,
			SPEAKERMODE_MONO = 1,
			SPEAKERMODE_STEREO = 2,
			SPEAKERMODE_QUAD = 3,
			SPEAKERMODE_SURROUND = 4,
			SPEAKERMODE_5POINT1 = 5,
			SPEAKERMODE_7POINT1 = 6,
			SPEAKERMODE_MAX = 7
		}

		[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
		internal delegate RESULT FMOD_SOUND_PCMREAD_CALLBACK(IntPtr soundraw, IntPtr data, uint datalen);

		[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
		internal delegate RESULT FMOD_SOUND_PCMSETPOS_CALLBACK(IntPtr soundraw, int subsound, uint position, TIMEUNIT postype);

		[StructLayout(LayoutKind.Sequential)]
		internal struct FMOD_CREATESOUNDEXINFO
		{
				public int cbsize;
			public uint length;
			public uint fileoffset;
			public int numchannels;
			public int defaultfrequency;
			public SOUND_FORMAT format;
			public uint decodebuffersize;
			public int initialsubsound;
			public int numsubsounds;
			public IntPtr inclusionlist;
				public int inclusionlistnum;
			public IntPtr pcmreadcallback;
			public IntPtr pcmsetposcallback;
				public IntPtr nonblockcallback;
				public IntPtr dlsname;
				public IntPtr encryptionkey;
				public int maxpolyphony;
				public IntPtr userdata;
				public int suggestedsoundtype;
				public Guid fsbguid;
				public IntPtr fileuseropen;
				public IntPtr fileuserclose;
				public IntPtr fileuserread;
				public IntPtr fileuserseek;
				public IntPtr fileuserasyncread;
				public IntPtr fileuserasynccancel;
				public IntPtr fileuserdata;
		}

		private static readonly object _loadLock = new object();
		private static IntPtr _libraryHandle = IntPtr.Zero;
		private static bool _resolverInstalled = false;

		static FmodNative()
		{
			InstallResolver();
		}

		private static void InstallResolver()
		{
			if (_resolverInstalled)
			{
				return;
			}

			System.Runtime.InteropServices.NativeLibrary.SetDllImportResolver(typeof(FmodNative).Assembly, ResolveLibrary);
			_resolverInstalled = true;
		}

		internal static bool TryLoadNativeLibrary()
		{
			if (_libraryHandle != IntPtr.Zero)
			{
				return true;
			}

			lock (_loadLock)
			{
				if (_libraryHandle != IntPtr.Zero)
				{
					return true;
				}

				var libraryPath = ResolveLibraryPath();
				if (string.IsNullOrEmpty(libraryPath))
				{
					return false;
				}

				try
				{
					_libraryHandle = System.Runtime.InteropServices.NativeLibrary.Load(libraryPath);
					return _libraryHandle != IntPtr.Zero;
				}
				catch (Exception ex)
				{
					GD.PushWarning($"[MeltySynthPlayer][FMOD] Failed to load native library '{libraryPath}': {ex.Message}");
					return false;
				}
			}
		}

		private static IntPtr ResolveLibrary(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
		{
			if (!libraryName.Equals("fmod", StringComparison.OrdinalIgnoreCase))
			{
				return IntPtr.Zero;
			}

			if (TryLoadNativeLibrary())
			{
				return _libraryHandle;
			}

			return IntPtr.Zero;
		}

		private static string ResolveLibraryPath()
		{
			var baseDir = ProjectSettings.GlobalizePath("res://addons/fmod/libs");
			if (OS.GetName() == "Windows")
			{
				var debugName = OS.IsDebugBuild() ? "fmodL.dll" : "fmod.dll";
				var path = Path.Combine(baseDir, "windows", debugName);
				return File.Exists(path) ? path : string.Empty;
			}

			if (OS.GetName() == "Linux")
			{
				var debugName = OS.IsDebugBuild() ? "libfmodL.so" : "libfmod.so";
				var path = Path.Combine(baseDir, "linux", debugName);
				return File.Exists(path) ? path : string.Empty;
			}

			if (OS.GetName() == "macOS")
			{
				var debugName = OS.IsDebugBuild() ? "libfmodL.dylib" : "libfmod.dylib";
				var path = Path.Combine(baseDir, "macos", debugName);
				return File.Exists(path) ? path : string.Empty;
			}

			if (OS.GetName() == "Android")
			{
				return OS.IsDebugBuild() ? "libfmodL.so" : "libfmod.so";
			}

			if (OS.GetName() == "iOS")
			{
				var debugSuffix = OS.IsDebugBuild() ? "L" : "";
				string targetName;
				if (OS.IsDebugBuild() || OS.HasFeature("editor"))
				{
					targetName = "iphonesimulator";
				}
				else
				{
					targetName = "iphoneos";
				}
				var libName = $"libfmod{debugSuffix}_{targetName}.a";
				var path = Path.Combine(baseDir, "iOS", libName);
				return File.Exists(path) ? path : string.Empty;
			}

			return string.Empty;
		}

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_Create(out IntPtr system, uint version);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_SetSoftwareFormat(IntPtr system, int samplerate, SPEAKERMODE speakermode, int numrawspeakers);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_Init(IntPtr system, int maxchannels, INITFLAGS flags, IntPtr extradriverdata);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_Update(IntPtr system);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_Close(IntPtr system);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_Release(IntPtr system);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_CreateSound(IntPtr system, string name_or_data, MODE mode, ref FMOD_CREATESOUNDEXINFO exinfo, out IntPtr sound);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_System_PlaySound(IntPtr system, IntPtr sound, IntPtr channelgroup, bool paused, out IntPtr channel);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_Channel_SetPaused(IntPtr channel, bool paused);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_Channel_Stop(IntPtr channel);

		[DllImport("fmod", CallingConvention = CallingConvention.Cdecl)]
		internal static extern RESULT FMOD_Sound_Release(IntPtr sound);

		internal static RESULT CreateSystem(out IntPtr system)
		{
			return FMOD_System_Create(out system, FMOD_VERSION);
		}
	}

	private sealed class GodotAudioOutputBridge : IAudioOutputBridge
	{
		private readonly Node _owner;
		private AudioStreamPlayer _player;
		private AudioStreamGenerator _generator;
		private AudioStreamGeneratorPlayback _playback;
		private readonly float _bufferLengthSeconds;

		public GodotAudioOutputBridge(Node owner, float bufferLengthSeconds)
		{
			_owner = owner;
			_bufferLengthSeconds = Math.Clamp(bufferLengthSeconds, 0.005f, 0.1f);
		}

		public bool Initialize(Node owner, StringName bus, int sampleRate)
		{
			if (_player != null)
			{
				return true;
			}

			_player = new AudioStreamPlayer();
			_player.Bus = bus;
			_owner.AddChild(_player);

			_generator = new AudioStreamGenerator
			{
				MixRate = sampleRate,
				BufferLength = _bufferLengthSeconds
			};

			_player.Stream = _generator;
			return true;
		}

		public void SetBus(StringName bus)
		{
			if (_player != null)
			{
				_player.Bus = bus;
			}
		}

		public void Play()
		{
			if (_player == null)
			{
				return;
			}

			if (!_player.Playing)
			{
				_player.Play();
				_playback = _player.GetStreamPlayback() as AudioStreamGeneratorPlayback;
			}
		}

		public void Stop()
		{
			_player?.Stop();
			_playback = null;
		}

		public void Update()
		{
		}

		public bool IsPlaying => _player != null && _player.Playing;

		public int GetFramesAvailable()
		{
			if (_player == null || _generator == null)
			{
				return 0;
			}

			_playback ??= _player.GetStreamPlayback() as AudioStreamGeneratorPlayback;
			return _playback != null ? _playback.GetFramesAvailable() : 0;
		}

		public int GetTotalBufferFrames()
		{
			if (_generator == null)
			{
				return 0;
			}

			return Math.Max(1, (int)(_generator.BufferLength * AudioServer.GetMixRate()));
		}

		public void PushFrame(Vector2 frame)
		{
			_playback ??= _player?.GetStreamPlayback() as AudioStreamGeneratorPlayback;
			_playback?.PushFrame(frame);
		}
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
	public Godot.Collections.Dictionary _track_channel_instruments = new Godot.Collections.Dictionary();

	private IAudioOutputBridge _audioOutput;

	private Synthesizer _synth;
	private MidiFileSequencer _sequencer;
	private MidiFile _midiFile;
	private SoundFont _soundFont;

	private int _sampleRate;
	private float _volumeLinear = 1.0f;
	private const float MELTYSYNTH_OUTPUT_GAIN = 1.0f; //音量增益，整体调整meltySynth整体音量
	private bool _sequencerStarted = false;  // 追踪 sequencer 是否已启动
	private double _pendingSeekMs = double.NaN;  // 待处理的 seek 位置（NaN 表示无待处理的 seek）
	private double _currentOffsetMs = 0.0;  // 当前相对于 sequencer 的时间偏移（支持负数 pre-roll）
	private bool _hasSkippedPreroolEvents = false;  // 标志：已跳过 pre-roll 事件

	// 系统时钟模式的时间追踪
	private bool _useSystemStopwatch = false;      // 是否启用系统时钟模式
	private ulong _playStartTime = 0;              // 播放开始时的系统时间（毫秒）
	private double _playStartPositionMs = 0.0;     // 播放开始时的MIDI位置
	private bool _previousPlaying = false;         // 上一帧的播放状态

	private readonly Dictionary<int, float> _virtualChannelVolumes = new Dictionary<int, float>();
	private readonly Dictionary<int, (int bank, int program)> _virtualChannelInstruments = new Dictionary<int, (int bank, int program)>();
	private readonly Dictionary<int, int> _virtualChannelCurrentBank = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCurrentProgram = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCc7 = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCc11 = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelCc10 = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _virtualChannelPitchBend = new Dictionary<int, int>();
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
	private bool _preferNativeSequencerSeek = false;
	private bool _fmodPendingStart = false;
	private int _fmodWarmupQueuedFrames = 0;
	private int _fmodTargetQueuedFrames = 0;
	private int _fmodLowWatermarkFrames = 0;
	private int _fmodBurstFrames = 0;

	// A1: 目标排队帧策略（尽量维持短队列，降低触发到发声延迟）
	private bool _a1QueueControlEnabled = true;
	private int _targetQueuedFrames = 384;
	private int _minTargetQueuedFrames = 256;
	private int _maxTargetQueuedFrames = 768;
	private int _underrunThresholdFrames = 128;
	private int _a1StableWindowFrames = 120;
	private int _a1StepUpFrames = 64;
	private int _a1StepDownFrames = 32;
	private int _framesSinceUnderrun = 0;
	private int _underrunCount = 0;
	private bool _wasBelowUnderrunThreshold = false;
	private bool _a1DebugLog = false;
	private ulong _a1LastLatencyLogMs = 0;

	private enum A1AudioPreset
	{
		UltraLowLatency = 0,
		Balanced = 1,
		StabilityFirst = 2,
		Custom = 3
	}

	private bool IsFmodAudioBackend()
	{
		return _audioOutput is FmodAudioOutputBridge;
	}

	private void RequestAudioOutputPlay()
	{
		if (_audioOutput == null)
		{
			return;
		}

		if (IsFmodAudioBackend())
		{
			// 新架构：直接播放，不需要预启动机制
			if (!_audioOutput.IsPlaying)
			{
				_audioOutput.Play();
			}
			return;
		}

		_audioOutput.Play();
	}

	private void ConfigureFmodPlaybackWatermarks()
	{
		_fmodPendingStart = false;

		if (!IsFmodAudioBackend() || _audioOutput == null || _sampleRate <= 0)
		{
			return;
		}

		var totalBufferFrames = Math.Max(1, _audioOutput.GetTotalBufferFrames());
		var warmupMin = Math.Max(1, Math.Min(512, totalBufferFrames));
		var lowMin = Math.Max(1, Math.Min(256, totalBufferFrames));

		_fmodWarmupQueuedFrames = Math.Clamp((int)Math.Round(_sampleRate * 0.024d), warmupMin, totalBufferFrames);
		_fmodTargetQueuedFrames = Math.Clamp((int)Math.Round(_sampleRate * 0.030d), _fmodWarmupQueuedFrames, totalBufferFrames);
		_fmodLowWatermarkFrames = Math.Clamp((int)Math.Round(_sampleRate * 0.018d), lowMin, _fmodTargetQueuedFrames);
		_fmodBurstFrames = Math.Clamp((int)Math.Round(_sampleRate * 0.024d), _fmodLowWatermarkFrames, totalBufferFrames);

		GD.Print($"[MeltySynthPlayer][FMOD] fixed watermarks configured: warmup={_fmodWarmupQueuedFrames}, low={_fmodLowWatermarkFrames}, target={_fmodTargetQueuedFrames}, burst={_fmodBurstFrames}, total={totalBufferFrames}");
	}

	private void EnsureAudioInitialized()
	{
		if (_audioOutput != null)
		{
			return;
		}

		_sampleRate = (int)AudioServer.GetMixRate();
		var bufferLengthSeconds = GetPreferredBufferLengthSeconds();
		var bridge = CreateAudioOutputBridge();
		if (bridge == null || !bridge.Initialize(this, _bus, _sampleRate))
		{
			if (!(bridge is GodotAudioOutputBridge))
			{
				GD.PushWarning("[MeltySynthPlayer] Selected audio bridge failed to initialize; falling back to Godot audio bridge.");
			}

			bridge = new GodotAudioOutputBridge(this, bufferLengthSeconds);
			if (!bridge.Initialize(this, _bus, _sampleRate))
			{
				GD.PrintErr("[MeltySynthPlayer] Failed to initialize Godot audio bridge.");
				return;
			}
		}

		_audioOutput = bridge;
		ConfigureFmodPlaybackWatermarks();
		
		// ========== 新架构：如果合成器已存在，立即传递给FMOD桥接器 ==========
		if (IsFmodAudioBackend() && _audioOutput is FmodAudioOutputBridge fmodBridge &&
			_sequencer != null && _autoSynth != null)
		{
			fmodBridge.SetSynthesizers(_sequencer, _autoSynth, _manualSynth, _useSeparateSynthForManual);
			fmodBridge.SetVolume(_volumeLinear);
			GD.Print("[MeltySynthPlayer] Synthesizers passed to FMOD bridge on initialization");
		}
	}

	private IAudioOutputBridge CreateAudioOutputBridge()
	{
		var bufferLengthSeconds = GetPreferredBufferLengthSeconds();
		var requestedBackend = "auto";

		if (ClassDB.ClassExists("FmodServer") && Engine.HasSingleton("FmodManager"))
		{
			var fmodManager = Engine.GetSingleton("FmodManager");
			if (fmodManager != null)
			{
				if (fmodManager.HasMethod("get_melty_audio_output_backend"))
				{
					requestedBackend = (string)fmodManager.Call("get_melty_audio_output_backend");
				}
			}
		}

		if (requestedBackend == "godot")
		{
			GD.Print("[MeltySynthPlayer] Godot audio bridge selected by configuration");
			return new GodotAudioOutputBridge(this, bufferLengthSeconds);
		}

		if (requestedBackend == "fmod")
		{
			GD.Print("[MeltySynthPlayer] FMOD audio bridge selected by configuration");
			return new FmodAudioOutputBridge(bufferLengthSeconds);
		}

		GD.Print("[MeltySynthPlayer] Auto audio bridge selection: trying FMOD bridge first");
		return new FmodAudioOutputBridge(bufferLengthSeconds);
	}

	private float GetPreferredBufferLengthSeconds()
	{
		var bufferLengthSeconds = 0.025f;
		if (Engine.HasSingleton("FmodManager"))
		{
			var fmodManager = Engine.GetSingleton("FmodManager");
			if (fmodManager != null && fmodManager.HasMethod("get_melty_audio_buffer_length_seconds"))
			{
				bufferLengthSeconds = Convert.ToSingle(fmodManager.Call("get_melty_audio_buffer_length_seconds"));
			}
		}

		return bufferLengthSeconds;
	}

	public override void _Ready()
	{
		EnsureAudioInitialized();

		// Windows 上略微提高队列目标，优先消除轻微杂声。
		if (OS.GetName() == "Windows")
		{
			_targetQueuedFrames = 448;
			_minTargetQueuedFrames = 320;
			_maxTargetQueuedFrames = 896;
			_underrunThresholdFrames = 160;
		}

		// Android 默认更保守，优先稳定播放避免欠载。
		if (OS.GetName() == "Android")
		{
			_targetQueuedFrames = 512;
			_minTargetQueuedFrames = 320;
			_maxTargetQueuedFrames = 896;
			_underrunThresholdFrames = 160;
		}

		SetProcess(true);
	}

	public void apply_a1_audio_config(
		int preset,
		int customTargetQueuedFrames,
		int customMinTargetQueuedFrames,
		int customMaxTargetQueuedFrames,
		int customUnderrunThresholdFrames,
		int customStableWindowFrames,
		int customStepUpFrames,
		int customStepDownFrames,
		bool enableDebugLog = false)
	{
		var selectedPreset = (A1AudioPreset)Math.Clamp(preset, 0, 3);

		switch (selectedPreset)
		{
			case A1AudioPreset.UltraLowLatency:
				_targetQueuedFrames = 320;
				_minTargetQueuedFrames = 192;
				_maxTargetQueuedFrames = 640;
				_underrunThresholdFrames = 96;
				_a1StableWindowFrames = 150;
				_a1StepUpFrames = 48;
				_a1StepDownFrames = 24;
				break;
			case A1AudioPreset.Balanced:
				_targetQueuedFrames = 448;
				_minTargetQueuedFrames = 256;
				_maxTargetQueuedFrames = 896;
				_underrunThresholdFrames = 128;
				_a1StableWindowFrames = 140;
				_a1StepUpFrames = 64;
				_a1StepDownFrames = 24;
				break;
			case A1AudioPreset.StabilityFirst:
				_targetQueuedFrames = 640;
				_minTargetQueuedFrames = 384;
				_maxTargetQueuedFrames = 1152;
				_underrunThresholdFrames = 192;
				_a1StableWindowFrames = 100;
				_a1StepUpFrames = 96;
				_a1StepDownFrames = 16;
				break;
			case A1AudioPreset.Custom:
				_targetQueuedFrames = customTargetQueuedFrames;
				_minTargetQueuedFrames = customMinTargetQueuedFrames;
				_maxTargetQueuedFrames = customMaxTargetQueuedFrames;
				_underrunThresholdFrames = customUnderrunThresholdFrames;
				_a1StableWindowFrames = customStableWindowFrames;
				_a1StepUpFrames = customStepUpFrames;
				_a1StepDownFrames = customStepDownFrames;
				break;
		}


		_minTargetQueuedFrames = Math.Clamp(_minTargetQueuedFrames, 64, 4096);
		_maxTargetQueuedFrames = Math.Clamp(_maxTargetQueuedFrames, _minTargetQueuedFrames, 8192);
		_targetQueuedFrames = Math.Clamp(_targetQueuedFrames, _minTargetQueuedFrames, _maxTargetQueuedFrames);
		_underrunThresholdFrames = Math.Clamp(_underrunThresholdFrames, 32, _targetQueuedFrames);
		_a1StableWindowFrames = Math.Clamp(_a1StableWindowFrames, 15, 600);
		_a1StepUpFrames = Math.Clamp(_a1StepUpFrames, 8, 512);
		_a1StepDownFrames = Math.Clamp(_a1StepDownFrames, 4, 256);

		_a1DebugLog = enableDebugLog;
		_framesSinceUnderrun = 0;
		_wasBelowUnderrunThreshold = false;

		GD.Print($"[MeltySynthPlayer][A1] config applied: preset={(int)selectedPreset}, target={_targetQueuedFrames}, " +
			$"min={_minTargetQueuedFrames}, max={_maxTargetQueuedFrames}, underrun_threshold={_underrunThresholdFrames}, " +
			$"stable_window={_a1StableWindowFrames}, step_up={_a1StepUpFrames}, step_down={_a1StepDownFrames}, debug={_a1DebugLog}");
	}

	public override void _Process(double delta)
	{
		_audioOutput?.Update();

		// 【修复D-1】记录播放开始的时刻（用于系统时钟模式）
		if (playing && !_previousPlaying)
		{
			_playStartTime = Time.GetTicksMsec();
			_playStartPositionMs = 0.0;
			_previousPlaying = true;
			if (_useSystemStopwatch)
			{
				// GD.Print($"[MeltySynthPlayer] Play started at system time {_playStartTime}ms");
			}
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
				_fmodPendingStart = false;
				
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

		// ========== 新架构：FMOD后端直接在回调中合成，跳过主循环渲染 ==========
		if (IsFmodAudioBackend() && _audioOutput is FmodAudioOutputBridge)
		{
			// 只需要确保播放已启动
			RequestAudioOutputPlay();
			// 不需要在这里渲染，直接在FMOD回调中处理
			return;
		}

		// 【正常渲染流程】（用于Godot后端）
		RequestAudioOutputPlay();

		var framesAvailable = _audioOutput.GetFramesAvailable();
		if (framesAvailable <= 0)
		{
			return;
		}

		var renderFrames = framesAvailable;
		var totalBufferFrames = Math.Max(1, _audioOutput.GetTotalBufferFrames());
		var queuedFrames = Math.Max(0, totalBufferFrames - framesAvailable);
		var isFmodBackend = IsFmodAudioBackend();

		if (isFmodBackend)
		{
			if (_fmodWarmupQueuedFrames <= 0 || _fmodTargetQueuedFrames <= 0)
			{
				ConfigureFmodPlaybackWatermarks();
			}

			if (_fmodPendingStart)
			{
				var warmupNeedFrames = Math.Max(0, _fmodWarmupQueuedFrames - queuedFrames);
				renderFrames = Math.Min(framesAvailable, Math.Max(_fmodBurstFrames, warmupNeedFrames));
			}
			else if (queuedFrames < _fmodLowWatermarkFrames)
			{
				var refillNeedFrames = Math.Max(0, _fmodTargetQueuedFrames - queuedFrames);
				renderFrames = Math.Min(framesAvailable, Math.Max(_fmodBurstFrames, refillNeedFrames));
			}
			else if (queuedFrames < _fmodTargetQueuedFrames)
			{
				renderFrames = Math.Min(framesAvailable, _fmodTargetQueuedFrames - queuedFrames);
			}
			else
			{
				renderFrames = 0;
			}
		}
		else if (_a1QueueControlEnabled)
		{
			var theoreticalLatencyMs = (double)queuedFrames / _sampleRate * 1000.0;
			var targetLatencyMs = (double)_targetQueuedFrames / _sampleRate * 1000.0;
			var belowThreshold = queuedFrames < _underrunThresholdFrames;

			if (belowThreshold)
			{
				_framesSinceUnderrun = 0;
				if (!_wasBelowUnderrunThreshold)
				{
					_underrunCount += 1;
					_targetQueuedFrames = Math.Min(_maxTargetQueuedFrames, _targetQueuedFrames + _a1StepUpFrames);
				}
			}
			else
			{
				_framesSinceUnderrun += 1;
				if (_framesSinceUnderrun >= _a1StableWindowFrames)
				{
					_targetQueuedFrames = Math.Max(_minTargetQueuedFrames, _targetQueuedFrames - _a1StepDownFrames);
					_framesSinceUnderrun = 0;
				}
			}

			_wasBelowUnderrunThreshold = belowThreshold;

			var needFrames = Math.Max(0, _targetQueuedFrames - queuedFrames);
			renderFrames = Math.Min(framesAvailable, needFrames);

			if (queuedFrames == 0)
			{
				var burstFrames = Math.Min(framesAvailable, Math.Max(_targetQueuedFrames * 2, totalBufferFrames / 2));
				renderFrames = Math.Max(renderFrames, burstFrames);
			}

			if (_a1DebugLog && Engine.GetProcessFrames() % 60 == 0)
			{
				GD.Print($"[MeltySynthPlayer][A1] queued={queuedFrames}, target={_targetQueuedFrames}, " +
					$"render={renderFrames}, avail={framesAvailable}, underrun={_underrunCount}");
			}

			var nowMs = Time.GetTicksMsec();
			if (nowMs - _a1LastLatencyLogMs >= 1000)
			{
				_a1LastLatencyLogMs = nowMs;
				GD.Print($"[MeltySynthPlayer][A1] theoretical_latency_ms={theoreticalLatencyMs:F2}, " +
					$"target_latency_ms={targetLatencyMs:F2}, queued={queuedFrames}, target={_targetQueuedFrames}, underrun={_underrunCount}");
			}
		}

		if (isFmodBackend && _fmodPendingStart)
		{
			var queuedAfterRender = queuedFrames + renderFrames;
			if (queuedAfterRender >= _fmodWarmupQueuedFrames)
			{
				_audioOutput.Play();
				_fmodPendingStart = false;
			}
		}

		if (renderFrames <= 0)
		{
			return;
		}

		EnsureBuffers(renderFrames);

		// ========== 选项 A：混合两个合成器的输出 ==========
		if (_useSeparateSynthForManual && _manualSynth != _autoSynth && _manualSynth != null)
		{
			// 创建临时缓冲区用于手动合成器的输出
			var manualLeft = new float[renderFrames];
			var manualRight = new float[renderFrames];

			// 自动播放合成（MIDI 序列）
			_sequencer.Render(_leftBuffer.AsSpan(0, renderFrames), 
							 _rightBuffer.AsSpan(0, renderFrames));

			// 手动合成（低延迟响应）
			try
			{
				_manualSynth.Render(manualLeft.AsSpan(0, renderFrames), 
								   manualRight.AsSpan(0, renderFrames));
			}
			catch (Exception ex)
			{
				GD.PrintErr($"[MeltySynthPlayer] Error processing manual synth: {ex.Message}");
			}

			for (var i = 0; i < renderFrames; i++)
			{
				_leftBuffer[i] = _leftBuffer[i] + manualLeft[i];
				_rightBuffer[i] = _rightBuffer[i] + manualRight[i];
			}
		}
		else
		{
			// 原有逻辑：仅使用自动合成器
			_sequencer.Render(_leftBuffer.AsSpan(0, renderFrames), 
							 _rightBuffer.AsSpan(0, renderFrames));
		}

		var scale = _volumeLinear * MELTYSYNTH_OUTPUT_GAIN;

		// 优化：使用批量推送（如果支持）
		if (isFmodBackend && _audioOutput is FmodAudioOutputBridge fmodBridge)
		{
			// 使用批量推送优化性能，减少原子操作次数
			for (var i = 0; i < renderFrames; i++)
			{
				_leftBuffer[i] = Math.Clamp(_leftBuffer[i] * scale, -1.0f, 1.0f);
				_rightBuffer[i] = Math.Clamp(_rightBuffer[i] * scale, -1.0f, 1.0f);
			}
			fmodBridge.PushFrames(_leftBuffer.AsSpan(0, renderFrames), _rightBuffer.AsSpan(0, renderFrames));
		}
		else
		{
			// 标准逐帧推送
			for (var i = 0; i < renderFrames; i++)
			{
				var left = Math.Clamp(_leftBuffer[i] * scale, -1.0f, 1.0f);
				var right = Math.Clamp(_rightBuffer[i] * scale, -1.0f, 1.0f);
				_audioOutput.PushFrame(new Vector2(left, right));
			}
		}

		// 【修复循环】检查序列器是否已到达结束
		if (_sequencer.EndOfSequence)
		{
			// GD.Print($"[MeltySynthPlayer] EndOfSequence detected, loop={loop}");
			if (loop)
			{
				// 循环播放：重新启动 sequencer
				// GD.Print("[MeltySynthPlayer] End of sequence, restarting for loop");
				_sequencer.Play(_midiFile, loop);
				_sequencerStarted = true;
				ApplyInstrumentOverridesToSynth();
			}
			else
			{
				// 无循环：停止播放
				// GD.Print("[MeltySynthPlayer] End of sequence, stopping playback (no loop)");
				playing = false;
				_audioOutput?.Stop();
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
		_fmodPendingStart = false;
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
		
		// 【修复D-2】同时更新系统时钟基准点
		if (_useSystemStopwatch)
		{
			_playStartPositionMs = positionMs;
			_playStartTime = Time.GetTicksMsec();
		}
		
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
		
		// 同步到FMOD桥接器
		if (IsFmodAudioBackend() && _audioOutput is FmodAudioOutputBridge fmodBridge)
		{
			fmodBridge.SetVolume(_volumeLinear);
		}
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
			
			if (Engine.GetProcessFrames() % 30 == 0)
			{
				// GD.Print($"[MeltySynthPlayer] get_position_ms (sequencer system clock): result={resultMs:F1}ms, " +
				// 	$"drift=({_sequencer.GetDiagnosticsSnapshot()})");
			}
			
			return resultMs;
		}

		// 【原有逻辑】使用 sequencer.Position + 缓冲补偿
		if (_sequencer == null || !_sequencerStarted) return 0.0;

		var sequencerMs = _sequencer.Position.TotalMilliseconds;

		// 补偿 AudioStreamGenerator 缓冲延迟
		// Sequencer.Position 是"已生成到缓冲区的位置"，缓冲区中尚有未播放的数据
		// 实际播放位置 = Sequencer位置 - 缓冲区中未播放的时长
		if (_audioOutput != null && _audioOutput.IsPlaying)
		{
			int totalBufferFrames = _audioOutput.GetTotalBufferFrames();
			int framesAvailable = _audioOutput.GetFramesAvailable();
			int bufferedFrames = totalBufferFrames - framesAvailable;
			double bufferLatencyMs = (double)bufferedFrames / _sampleRate * 1000.0;
			var compensatedMs = Math.Max(0.0, sequencerMs - bufferLatencyMs);
			
			if (Engine.GetProcessFrames() % 30 == 0)
			{
				// GD.Print($"[MeltySynthPlayer] get_position_ms debug: " +
				// 	$"sequencer={sequencerMs:F1}ms, " +
				// 	$"bufferLatency={bufferLatencyMs:F1}ms, " +
				// 	$"framesAvailable={framesAvailable}/{totalBufferFrames}, " +
				// 	$"result={compensatedMs:F1}ms");
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
		// GD.Print($"[MeltySynthPlayer] Manual control mapping updated: vc_pitch_entries={mappedPairs}, pending_manual_ons={pendingOns}");
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

		ApplyChannelStateToManualSynth(virtualId);

		// ========== 优化：直接调用手动合成器 ==========
		if (!_useSeparateSynthForManual || _manualSynth == null)
		{
			// 回退：使用自动合成器
			_synth?.NoteOn(virtualId, pitch, scaledVelocity);
			return;
		}
		
		try
		{
			_manualSynth.NoteOn(virtualId, pitch, scaledVelocity);
			// GD.Print($"[MeltySynthPlayer] Manual NoteOn: pitch={pitch}, velocity={velocity}, " +
			// 		$"channel={channel}, track={trackIndex}, virtualId={virtualId}");
		}
		catch (Exception ex)
		{
			GD.PrintErr($"[MeltySynthPlayer] Error in trigger_note_on: {ex.Message}");
		}
	}

	public void trigger_note_off(int pitch, int _velocity, int channel)
	{
		trigger_note_off(pitch, _velocity, channel, 0);
	}

	public void trigger_note_off(int pitch, int _velocity, int channel, int trackIndex)
	{
		var virtualId = trackIndex * 16 + channel;

		// ========== 优化：直接调用手动合成器 ==========
		if (!_useSeparateSynthForManual || _manualSynth == null)
		{
			_synth?.NoteOff(virtualId, pitch);
			return;
		}
		
		try
		{
			_manualSynth.NoteOff(virtualId, pitch);
			//GD.Print($"[MeltySynthPlayer] Manual NoteOff: pitch={pitch}, channel={channel}, track={trackIndex}");
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
		_sequencer.SetSystemClockMode(_useSystemStopwatch);
		_sequencer.SetDiagnosticsEnabled(_useSystemStopwatch);

		// 手动音符合成器（独立，用于低延迟响应）
		if (_useSeparateSynthForManual)
		{
			// 手动音符合成器用较少的复音数（通常不需要太多并发音符）
			var manualSettings = new SynthesizerSettings(_sampleRate)
			{
				MaximumPolyphony = Math.Max(16, max_polyphony / 4)  // 至少 16 个复音
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

		// ========== 新架构：将合成器引用传递给FMOD桥接器 ==========
		if (IsFmodAudioBackend() && _audioOutput is FmodAudioOutputBridge fmodBridge)
		{
			fmodBridge.SetSynthesizers(_sequencer, _autoSynth, _manualSynth, _useSeparateSynthForManual);
			fmodBridge.SetVolume(_volumeLinear);
			GD.Print("[MeltySynthPlayer] Synthesizers passed to FMOD bridge (DIRECT MODE)");
		}

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

	private void EnsureBuffers(int length)
	{
		if (_leftBuffer.Length < length)
		{
			_leftBuffer = new float[length];
			_rightBuffer = new float[length];
		}
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
		if (command == 0xB0)
		{
			if (data1 == 0x00)
			{
				_virtualChannelCurrentBank[virtualChannel] = data2;
			}
			else if (data1 == 0x07)
			{
				_virtualChannelCc7[virtualChannel] = data2;
			}
			else if (data1 == 0x0B)
			{
				_virtualChannelCc11[virtualChannel] = data2;
			}
			else if (data1 == 0x0A)
			{
				_virtualChannelCc10[virtualChannel] = data2;
			}
		}
		else if (command == 0xC0)
		{
			_virtualChannelCurrentProgram[virtualChannel] = data1;
		}
		else if (command == 0xE0)
		{
			_virtualChannelPitchBend[virtualChannel] = (data2 << 7) | data1;
		}

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
					// GD.Print($"[MeltySynthPlayer] [INTERCEPT] Bank Change intercepted for virtual channel {virtualChannel}: {oldBank} -> {data2}");
				}
			}
			else if (command == 0xC0)
			{
				// Program Change (0xC0)
				var oldProgram = data1;
				data1 = instrument.program;
				if (oldProgram != instrument.program)
				{
					// GD.Print($"[MeltySynthPlayer] [INTERCEPT] Program Change intercepted for virtual channel {virtualChannel}: {oldProgram} -> {data1}");
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

	private void ApplyChannelStateToManualSynth(int virtualChannel)
	{
		if (_manualSynth == null)
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
	}
}
