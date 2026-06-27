using Godot;
using MeltySynth;
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using TouhouMix.Midi;

// 此文件是 MeltySynthPlayer 的 partial 实现 (全局命名空间, 与 MeltySynthPlayer.cs 一致)
// 包含 miniaudio 音频输出后端 (作为 FMOD 的低延迟替代)
// 注意: 必须与 MeltySynthPlayer.cs 同命名空间才能合并为同一个 partial class
public partial class MeltySynthPlayer
{
        /// <summary>
        /// 音频后端选择
        /// </summary>
        public enum AudioBackend
        {
            /// <summary>使用 FMOD (原有后端, 兼容性好)</summary>
            Fmod = 0,
            /// <summary>使用 miniaudio (低延迟优先, 跨平台一致)</summary>
            Miniaudio = 1,
        }

        /// <summary>当前选择的音频后端 (默认 FMOD, 保持向后兼容)</summary>
        private AudioBackend _audioBackend = AudioBackend.Fmod;

        /// <summary>
        /// 设置音频后端. 需要在 EnsureAudioInitialized 之前调用, 或触发后端重建.
        /// </summary>
        public void SetAudioBackend(AudioBackend backend)
        {
            if (_audioBackend == backend)
            {
                GD.Print($"[MeltySynthPlayer] Audio backend already set to {backend}");
                return;
            }

            GD.Print($"[MeltySynthPlayer] Switching audio backend: {_audioBackend} → {backend}");
            _audioBackend = backend;

            // 如果音频桥已存在, 需要重建以应用新后端
            if (_audioOutput != null)
            {
                bool wasPlaying = _audioOutput.IsPlaying;
                _audioOutput.Dispose();
                _audioOutput = null;

                EnsureAudioInitialized();

                if (_sequencer != null && _autoSynth != null && _audioOutput != null)
                {
                    _audioOutput.SetSynthesizers(_sequencer, _autoSynth, _manualSynth, _useSeparateSynthForManual);
                    _audioOutput.SetVolume(_volumeLinear);
                }

                if (wasPlaying && _audioOutput != null)
                {
                    _audioOutput.Play();
                }
            }
        }

        /// <summary>
        /// miniaudio 音频输出桥
        /// 架构与 FmodAudioOutputBridge 平行, 共享 RingBuffer / 双合成器 / 渲染线程设计
        ///
        /// 关键延迟优化 (相对 FMOD 版本):
        ///   1. RingBuffer 容量: _decodeFrames × 2 (而非 ×6), 减少缓冲堆积
        ///   2. 默认 periodSize=256, periodCount=2 (对应 FMOD 256×2 ≈ 5.3ms 平均延迟)
        ///   3. miniaudio 回调直接提供 pOutput 缓冲区, 无需 FMOD 的 Sound/Channel 中间层
        ///   4. 可选 WASAPI exclusive 模式, 绕开 Windows 音频引擎 ~10ms 延迟
        /// </summary>
        internal sealed class MiniaudioAudioOutputBridge : IAudioOutputBridge
        {
            // ---- 缓冲区限制 ----
            private const int MIN_DECODE_FRAMES = 128;   // miniaudio 可比 FMOD 更小
            private const int MAX_DECODE_FRAMES = 4096;

            // ---- miniaudio 句柄 ----
            private IntPtr _bridgeHandle = IntPtr.Zero;
            private MiniaudioNative.DataProc _dataCallback;
            // GCHandle 用于将 this 指针传给 native 回调, 避免 delegate 被 GC
            private GCHandle _selfHandle;

            // ---- 合成器引用 (与 FmodAudioOutputBridge 相同) ----
            private MidiFileSequencer _sequencer = null;
            private Synthesizer _autoSynth = null;
            private Synthesizer _manualSynth = null;
            private bool _useSeparateSynth = false;

            // ---- 渲染缓冲区 (交错格式) ----
            private float[] _tempLeft = Array.Empty<float>();
            private float[] _tempRight = Array.Empty<float>();
            private float[] _manualLeft = Array.Empty<float>();
            private float[] _manualRight = Array.Empty<float>();
            private float[] _outputBuffer = Array.Empty<float>();

            // ---- 配置 ----
            private int _sampleRate = 48000;
            private int _decodeFrames = 0;
            private int _targetDecodeFrames = 256;  // 默认低延迟
            private float _volumeLinear = 1.0f;
            private const float OUTPUT_GAIN = 2.0f;

            // miniaudio period 配置 (对应 FMOD DSP buffer)
            private uint _periodSizeInFrames = 256;
            private uint _periodCount = 2;
            private MiniaudioNative.Backend _backend = MiniaudioNative.Backend.Default;
            private bool _wasapiExclusive = false;
            private bool _aaudioExclusive = false;

            private bool _initialized = false;
            private bool _playing = false;
            private int _postSeekSilenceFrames = 0;
            private StringName _bus = new StringName("Master");

            // ---- 统计 ----
            private int _underrunCount = 0;
            private float _lastSampleL = 0;
            private float _lastSampleR = 0;

            // ---- 延迟查询 ----
            private uint _actualPeriod = 0;       // 设备实际 period (TryCreateDevice 后填充)
            private uint _actualPeriodCount = 0;  // 设备实际 period 数量
            private bool _nativeGetLatencyAvailable = true;  // 旧 DLL 无此导出时设为 false

            // ---- 线程同步 ----
            internal readonly object _synthLock = new object();
            public object SyncRoot => _synthLock;

            // ---- 手动合成器活跃音符计数 ----
            private volatile int _manualActiveVoiceCount = 0;

            // ---- 性能诊断 ----
            private Stopwatch _perfStopwatch = new Stopwatch();
            private int _perfSlowCallbackCount = 0;
            private int _perfTotalCallbackCount = 0;

            // ---- 渲染线程 + 环形缓冲区 ----
            private Thread _renderThread = null;
            private volatile bool _renderThreadRunning = false;
            private RingBuffer _ringBuffer = null;

            // ---- 无锁事件队列 ----
            private struct NoteEvent
            {
                public bool IsNoteOn;
                public int VirtualId;
                public int Pitch;
                public int Velocity;
            }
            private readonly ConcurrentQueue<NoteEvent> _pendingNoteEvents =
                new ConcurrentQueue<NoteEvent>();

            // ====================================================================
            // 配置方法 (在 Initialize 前调用)
            // ====================================================================
            public MiniaudioAudioOutputBridge(float bufferLengthSeconds)
            {
                if (bufferLengthSeconds > 0)
                {
                    _targetDecodeFrames = (int)(bufferLengthSeconds * 48000);
                }
            }

            public void SetDecodeFrames(int frames)
            {
                _targetDecodeFrames = Math.Clamp(frames, MIN_DECODE_FRAMES, MAX_DECODE_FRAMES);
                GD.Print($"[MeltySynthPlayer][miniaudio] Target decode frames: {_targetDecodeFrames}");
            }

            /// <summary>
            /// 设置 miniaudio period 大小 (类似 FMOD SetDSPBufferSize)
            /// 必须在 Initialize 之前调用
            /// </summary>
            public void SetPeriodSize(uint periodSizeInFrames, uint periodCount)
            {
                _periodSizeInFrames = Math.Max(periodSizeInFrames, 64u);
                _periodCount = (uint)Math.Clamp(periodCount, 2, 4);
                GD.Print($"[MeltySynthPlayer][miniaudio] Period size target: {_periodSizeInFrames}×{_periodCount}");
            }

            /// <summary>设置后端 (Default/Wasapi/CoreAudio/Aaudio 等)</summary>
            public void SetBackend(MiniaudioNative.Backend backend)
            {
                _backend = backend;
            }

            /// <summary>启用 WASAPI 独占模式 (Windows only, 必须在 Initialize 之前)</summary>
            public void SetWASAPIExclusive(bool exclusive)
            {
                _wasapiExclusive = exclusive;
                if (exclusive)
                {
                    GD.Print("[MeltySynthPlayer][miniaudio] WASAPI exclusive mode enabled");
                }
            }

            /// <summary>启用 AAudio 低延迟独占模式 (Android only)</summary>
            public void SetAAudioExclusive(bool exclusive)
            {
                _aaudioExclusive = exclusive;
            }

            public void SetSynthesizers(MidiFileSequencer sequencer, Synthesizer autoSynth, Synthesizer manualSynth, bool useSeparateSynth)
            {
                lock (_synthLock)
                {
                    _sequencer = sequencer;
                    _autoSynth = autoSynth;
                    _manualSynth = manualSynth;
                    _useSeparateSynth = useSeparateSynth;
                    GD.Print($"[MeltySynthPlayer][miniaudio] SetSynthesizers: seq={sequencer!=null}, auto={autoSynth!=null}, manual={manualSynth!=null}, separate={useSeparateSynth}");
                }
            }

            public void SetVolume(float volumeLinear)
            {
                lock (_synthLock)
                {
                    _volumeLinear = volumeLinear;
                }
                // 同时通过 miniaudio API 设置主音量 (原子操作, 线程安全)
                if (_bridgeHandle != IntPtr.Zero)
                {
                    MiniaudioNative.ma_bridge_set_volume(_bridgeHandle, volumeLinear);
                }
            }

            int IAudioOutputBridge.PostSeekSilenceFrames
            {
                get => _postSeekSilenceFrames;
                set => _postSeekSilenceFrames = value;
            }

            // ====================================================================
            // Initialize
            // ====================================================================
            public bool Initialize(Node owner, StringName bus, int sampleRate)
            {
                if (_initialized) return true;

                _bus = bus;
                int systemSampleRate = (int)AudioServer.GetMixRate();
                _sampleRate = sampleRate > 0 ? sampleRate : systemSampleRate;

                if (_sampleRate != systemSampleRate)
                {
                    GD.PushWarning($"[MeltySynthPlayer][miniaudio] Sample rate mismatch: requested={_sampleRate}, system={systemSampleRate}");
                }

                _decodeFrames = Math.Max(MIN_DECODE_FRAMES, Math.Min(MAX_DECODE_FRAMES, _targetDecodeFrames));

                // 分配渲染缓冲区 (先用 _decodeFrames, TryCreateDevice 后可能根据实际 period 上调)
                _tempLeft = new float[_decodeFrames];
                _tempRight = new float[_decodeFrames];
                _manualLeft = new float[_decodeFrames];
                _manualRight = new float[_decodeFrames];
                _outputBuffer = new float[MAX_DECODE_FRAMES * 2];

                Array.Clear(_tempLeft, 0, _tempLeft.Length);
                Array.Clear(_tempRight, 0, _tempRight.Length);
                Array.Clear(_manualLeft, 0, _manualLeft.Length);
                Array.Clear(_manualRight, 0, _manualRight.Length);
                Array.Clear(_outputBuffer, 0, _outputBuffer.Length);

                GD.Print($"[MeltySynthPlayer][miniaudio] System audio: mix_rate={systemSampleRate}Hz");
                GD.Print($"[MeltySynthPlayer][miniaudio] Initializing: " +
                    $"sample_rate={_sampleRate}, decode_buffer={_decodeFrames}f ({_decodeFrames * 1000.0 / _sampleRate:F1}ms), " +
                    $"period={_periodSizeInFrames}×{_periodCount}");

                if (!MiniaudioNative.TryLoadNativeLibrary())
                {
                    GD.PushWarning("[MeltySynthPlayer][miniaudio] Native library could not be loaded.");
                    return false;
                }

                if (!TryCreateDevice())
                {
                    DisposeNative();
                    return false;
                }

                // 根据实际 period 动态调整 _decodeFrames
                // WASAPI 共享模式可能强制 period=480 或 528, 远大于请求的 256
                // 如果 _decodeFrames < actualPeriod, 一次回调就会抽空 RingBuffer
                var qPeriod = MiniaudioNative.ma_bridge_get_period_size(_bridgeHandle, out uint actualPeriod, out uint actualCount);
                if (qPeriod == MiniaudioNative.Result.Ok && actualPeriod > 0)
                {
                    int newDecodeFrames = (int)Math.Max(_decodeFrames, actualPeriod);
                    newDecodeFrames = Math.Min(newDecodeFrames, MAX_DECODE_FRAMES);
                    if (newDecodeFrames != _decodeFrames)
                    {
                        GD.Print($"[MeltySynthPlayer][miniaudio] Adjusting decode frames: {_decodeFrames} → {newDecodeFrames} " +
                            $"(actualPeriod={actualPeriod})");
                        _decodeFrames = newDecodeFrames;
                        // 重新分配渲染缓冲区
                        _tempLeft = new float[_decodeFrames];
                        _tempRight = new float[_decodeFrames];
                        _manualLeft = new float[_decodeFrames];
                        _manualRight = new float[_decodeFrames];
                    }
                }

                // RingBuffer 容量: max(_decodeFrames, actualPeriod) × 6
                // ×6 而非 ×2: WASAPI 共享模式 period 不可控 (通常 ~10ms),
                // 需要足够缓冲来吸收渲染线程的调度抖动和 _sequencer.Render() 的耗时波动
                int effectivePeriod = (int)Math.Max(_decodeFrames, actualPeriod);
                int ringCapacity = effectivePeriod * 6;
                if (_ringBuffer == null || _ringBuffer.Capacity != ringCapacity)
                {
                    _ringBuffer = new RingBuffer(ringCapacity);
                    GD.Print($"[MeltySynthPlayer][miniaudio] Ring buffer: {ringCapacity} frames (≈{ringCapacity * 1000.0 / _sampleRate:F1}ms) " +
                        $"[capacity = {effectivePeriod}×6]");
                }

                _initialized = true;
                return true;
            }

            private bool TryCreateDevice()
            {
                var cfg = MiniaudioNative.ConfigInitDefault();
                cfg.SampleRate = (uint)_sampleRate;
                cfg.PeriodSizeInFrames = _periodSizeInFrames;
                cfg.PeriodCount = _periodCount;
                cfg.Channels = 2;
                cfg.Backend = _backend;
                cfg.WasapiExclusive = _wasapiExclusive ? 1 : 0;
                cfg.AaudioExclusive = _aaudioExclusive ? 1 : 0;
                cfg.NoClip = 1;  // C# 侧 SoftLimit

                // 固定 GCHandle 防止 this 被 GC, 同时获得稳定指针传给 native
                _selfHandle = GCHandle.Alloc(this, GCHandleType.Normal);
                _dataCallback = OnDataCallback;  // 必须存储委托引用防 GC

                IntPtr userData = (IntPtr)_selfHandle;
                var result = MiniaudioNative.ma_bridge_init(ref cfg, _dataCallback, userData, out _bridgeHandle);
                if (result != MiniaudioNative.Result.Ok || _bridgeHandle == IntPtr.Zero)
                {
                    GD.PushWarning($"[MeltySynthPlayer][miniaudio] ma_bridge_init failed: {result}");
                    _selfHandle.Free();
                    return false;
                }

                // 查询实际参数 (驱动可能调整请求值)
                var qResult = MiniaudioNative.ma_bridge_get_period_size(_bridgeHandle, out uint actualPeriod, out uint actualCount);
                if (qResult == MiniaudioNative.Result.Ok)
                {
                    _actualPeriod = actualPeriod;
                    _actualPeriodCount = actualCount;
                    GD.Print($"[MeltySynthPlayer][miniaudio] Actual period: {actualPeriod}×{actualCount} " +
                        $"(≈{actualPeriod * actualCount / (double)_sampleRate * 1000:F1}ms total, " +
                        $"≈{actualPeriod * (actualCount - 1.5) / _sampleRate * 1000:F1}ms avg latency)");
                }

                var qSr = MiniaudioNative.ma_bridge_get_sample_rate(_bridgeHandle, out uint actualSr);
                if (qSr == MiniaudioNative.Result.Ok)
                {
                    GD.Print($"[MeltySynthPlayer][miniaudio] Actual sample rate: {actualSr}Hz");
                }

                IntPtr namePtr = MiniaudioNative.ma_bridge_get_backend_name(_bridgeHandle);
                string backendName = MiniaudioNative.PtrToStringAnsiSafe(namePtr);
                GD.Print($"[MeltySynthPlayer][miniaudio] Backend: {backendName}");

                IntPtr verPtr = MiniaudioNative.ma_bridge_get_version();
                string ver = MiniaudioNative.PtrToStringAnsiSafe(verPtr);
                GD.Print($"[MeltySynthPlayer][miniaudio] miniaudio version: {ver}");

                return true;
            }

            // ====================================================================
            // 播放控制
            // ====================================================================
            public void SetBus(StringName bus) { _bus = bus; }

            public void Play()
            {
                if (_bridgeHandle == IntPtr.Zero) return;
                if (!_playing)
                {
                    if (_renderThread == null || !_renderThread.IsAlive)
                        StartRenderThread();

                    _ringBuffer?.Clear();

                    // 预填充 RingBuffer: 在启动音频设备前, 先填充到 50% 容量
                    // 避免设备启动后第一次回调就 underrun (rbFill=0 问题)
                    int targetFill = _ringBuffer.Capacity / 2;
                    int fillTimeoutMs = 0;
                    while (_ringBuffer.ReadableFrames < targetFill && fillTimeoutMs < 500)
                    {
                        Thread.Sleep(2);
                        fillTimeoutMs += 2;
                    }
                    GD.Print($"[MeltySynthPlayer][miniaudio] Pre-fill: {_ringBuffer.ReadableFrames}/{targetFill} frames " +
                        $"(waited {fillTimeoutMs}ms)");

                    var r = MiniaudioNative.ma_bridge_start(_bridgeHandle);
                    if (r != MiniaudioNative.Result.Ok)
                    {
                        GD.PushWarning($"[MeltySynthPlayer][miniaudio] ma_bridge_start failed: {r}");
                        return;
                    }
                    _playing = true;
                    GD.Print("[MeltySynthPlayer][miniaudio] Playback started");
                }
            }

            public void Stop()
            {
                if (_bridgeHandle != IntPtr.Zero)
                {
                    MiniaudioNative.ma_bridge_stop(_bridgeHandle);
                }
                StopRenderThread();
                _ringBuffer?.Clear();
                Array.Clear(_outputBuffer, 0, _outputBuffer.Length);
                _lastSampleL = 0;
                _lastSampleR = 0;
                _playing = false;
            }

            public void Update()
            {
                // miniaudio 不需要像 FMOD_System_Update 那样的轮询
            }

            public bool IsPlaying => _playing;

            public int GetFramesAvailable() => 1024;  // 兼容性占位

            public int GetTotalBufferFrames() => _decodeFrames;

            public void PushFrame(Vector2 frame) { /* 兼容性空实现 */ }

            // ====================================================================
            // 音符事件
            // ====================================================================
            public void EnqueueNoteOn(int virtualId, int pitch, int velocity)
            {
                _pendingNoteEvents.Enqueue(new NoteEvent
                {
                    IsNoteOn = true,
                    VirtualId = virtualId,
                    Pitch = pitch,
                    Velocity = velocity
                });
                Interlocked.Increment(ref _manualActiveVoiceCount);
            }

            public void EnqueueNoteOff(int virtualId, int pitch)
            {
                _pendingNoteEvents.Enqueue(new NoteEvent
                {
                    IsNoteOn = false,
                    VirtualId = virtualId,
                    Pitch = pitch,
                    Velocity = 0
                });
                Interlocked.Decrement(ref _manualActiveVoiceCount);
            }

            // ====================================================================
            // miniaudio 数据回调 (实时音频线程)
            // 签名: void(IntPtr pUserData, IntPtr pOutput, uint frameCount)
            // pOutput: 交错 float32 stereo 缓冲区, 容量 = frameCount * 2 * sizeof(float)
            // ====================================================================
            // 注意: 回调必须是 static 以保证 AOT (iOS) 兼容性
            // this 通过 GCHandle 回查, 委托通过 _dataCallback 字段防止 GC
            private static void OnDataCallback(IntPtr pUserData, IntPtr pOutput, uint frameCount)
            {
                // 静态方法 + GCHandle 回查实例, 避免 this 委托被 GC
                if (pUserData == IntPtr.Zero) return;
                var self = (MiniaudioAudioOutputBridge)GCHandle.FromIntPtr(pUserData).Target;
                if (self == null) return;
                self.FillDataFromRingBuffer(pOutput, (int)frameCount);
            }

            /// <summary>
            /// 从环形缓冲区读取音频写入 miniaudio 输出缓冲区
            /// 预期耗时 < 0.5ms (纯内存拷贝)
            /// </summary>
            private void FillDataFromRingBuffer(IntPtr pOutput, int framesRequested)
            {
                if (_ringBuffer == null)
                {
                    FillWithSilence(pOutput, framesRequested);
                    return;
                }

                // 防御性: 若 native 回调请求量超过 _outputBuffer 容量, 截断避免越界
                // 实践中音频回调请求量通常等于 periodSize (如 256), 远小于 MAX_DECODE_FRAMES
                if (framesRequested > MAX_DECODE_FRAMES)
                {
                    GD.PushWarning($"[MeltySynthPlayer][miniaudio] framesRequested={framesRequested} exceeds MAX_DECODE_FRAMES={MAX_DECODE_FRAMES}, clamping");
                    framesRequested = MAX_DECODE_FRAMES;
                }

                _perfStopwatch.Restart();

                int read = _ringBuffer.Read(_outputBuffer, 0, framesRequested);

                if (read < framesRequested)
                {
                    // Underrun
                    FillRemainderWithDecay(read, framesRequested);
                    _underrunCount++;
                    // 前 10 次每次都打印, 之后每 100 次打印一次
                    if (_underrunCount <= 10 || _underrunCount % 100 == 1)
                    {
                        GD.Print($"[MeltySynthPlayer][miniaudio] Underrun #{_underrunCount} " +
                            $"(read={read}/{framesRequested}, rbFill={_ringBuffer.ReadableFrames}, " +
                            $"rbCap={_ringBuffer.Capacity}, decode={_decodeFrames})");
                    }
                }

                Marshal.Copy(_outputBuffer, 0, pOutput, framesRequested * 2);

                _perfStopwatch.Stop();
                _perfTotalCallbackCount++;
                double elapsedMs = _perfStopwatch.Elapsed.TotalMilliseconds;
                double budgetMs = (double)framesRequested / _sampleRate * 1000.0 * 0.3;
                if (elapsedMs > budgetMs)
                {
                    _perfSlowCallbackCount++;
                    if (_perfSlowCallbackCount <= 1 || _perfSlowCallbackCount % 300 == 0)
                    {
                        GD.Print($"[MeltySynthPlayer][miniaudio] PERF: callback {elapsedMs:F3}ms " +
                            $"(budget={budgetMs:F2}ms, frames={framesRequested}, " +
                            $"slow={_perfSlowCallbackCount}/{_perfTotalCallbackCount}, " +
                            $"rbFill={_ringBuffer.ReadableFrames})");
                    }
                }
            }

            // ====================================================================
            // 渲染线程 (与 FmodAudioOutputBridge 几乎相同)
            // ====================================================================
            private void StartRenderThread()
            {
                if (_renderThread != null && _renderThread.IsAlive) return;

                _renderThreadRunning = true;
                _renderThread = new Thread(RenderThreadLoop)
                {
                    Name = "MeltySynth-MA-Render",
                    IsBackground = true,
                    Priority = ThreadPriority.Highest
                };
                _renderThread.Start();
                GD.Print("[MeltySynthPlayer][miniaudio] Render thread started");
            }

            private void StopRenderThread()
            {
                if (_renderThread == null || !_renderThread.IsAlive)
                {
                    _renderThreadRunning = false;
                    return;
                }

                GD.Print("[MeltySynthPlayer][miniaudio] Stopping render thread...");
                _renderThreadRunning = false;
                if (!_renderThread.Join(2000))
                {
                    GD.PushWarning("[MeltySynthPlayer][miniaudio] Render thread did not stop within 2s");
                }
                else
                {
                    GD.Print("[MeltySynthPlayer][miniaudio] Render thread stopped");
                }
                _renderThread = null;
            }

            private void RenderThreadLoop()
            {
                GD.Print("[MeltySynthPlayer][miniaudio] Render thread loop started");
                int idleCount = 0;
                Span<NoteEvent> localEvents = stackalloc NoteEvent[32];

                while (_renderThreadRunning)
                {
                    // 1. 等待可写空间
                    // 使用 _decodeFrames 作为最小可写阈值: 渲染线程每次写 _decodeFrames 帧
                    // 当 RingBuffer 接近满时, 等待音频回调消耗数据
                    int writable = _ringBuffer.WritableFrames;
                    if (writable < _decodeFrames)
                    {
                        // 可写空间不足, 短暂等待让音频回调消耗数据
                        // Sleep(1) 足够让 WASAPI 音频线程执行一次回调 (period ~10ms)
                        Thread.Sleep(1);
                        continue;
                    }

                    // 2. 清零渲染缓冲区
                    Array.Clear(_tempLeft, 0, _decodeFrames);
                    Array.Clear(_tempRight, 0, _decodeFrames);
                    Array.Clear(_manualLeft, 0, _decodeFrames);
                    Array.Clear(_manualRight, 0, _decodeFrames);

                    // 3. 无锁出队
                    int eventCount = 0;
                    while (eventCount < 32 && _pendingNoteEvents.TryDequeue(out localEvents[eventCount]))
                        eventCount++;

                    lock (_synthLock)
                    {
                        if (_sequencer == null || _autoSynth == null)
                        {
                            idleCount++;
                            if (idleCount % 500 == 1)
                                GD.Print($"[MeltySynthPlayer][miniaudio] Render waiting for synthesizers (idle={idleCount})");
                            Thread.Sleep(10);
                            continue;
                        }
                        idleCount = 0;

                        if (_postSeekSilenceFrames > 0)
                        {
                            // 与 FmodAudioOutputBridge 一致: 渲染到 discard 缓冲区以推进 sequencer,
                            // 但输出静音衰减, 丢弃瞬态音符攻击
                            int silence = Math.Min(_decodeFrames, _postSeekSilenceFrames);
                            var discardSpan = _tempLeft.AsSpan(0, silence);
                            _sequencer.Render(discardSpan, discardSpan);
                            _postSeekSilenceFrames -= silence;
                            FillOutputBufferWithDecay(0, _decodeFrames);
                        }
                        else
                        {
                            // 处理音符事件
                            for (int i = 0; i < eventCount; i++)
                            {
                                var synth = (_useSeparateSynth && _manualSynth != null) ? _manualSynth : _autoSynth;
                                if (synth == null) continue;
                                if (localEvents[i].IsNoteOn)
                                    synth.NoteOn(localEvents[i].VirtualId, localEvents[i].Pitch, localEvents[i].Velocity);
                                else
                                    synth.NoteOff(localEvents[i].VirtualId, localEvents[i].Pitch);
                            }

                            float scale = _volumeLinear * OUTPUT_GAIN;

                            bool shouldRenderManual = _useSeparateSynth && _manualSynth != null
                                && _manualSynth != _autoSynth && _manualActiveVoiceCount > 0;

                            if (shouldRenderManual)
                            {
                                _sequencer.Render(_tempLeft.AsSpan(0, _decodeFrames), _tempRight.AsSpan(0, _decodeFrames));
                                _manualSynth.Render(_manualLeft.AsSpan(0, _decodeFrames), _manualRight.AsSpan(0, _decodeFrames));
                                MixToOutput(_tempLeft, _tempRight, _manualLeft, _manualRight, _decodeFrames, scale);
                            }
                            else
                            {
                                _sequencer.Render(_tempLeft.AsSpan(0, _decodeFrames), _tempRight.AsSpan(0, _decodeFrames));
                                MixToOutput(_tempLeft, _tempRight, null, null, _decodeFrames, scale);
                            }
                        }
                    }

                    // 4. 写入环形缓冲区
                    _ringBuffer.Write(_outputBuffer, 0, _decodeFrames);
                }

                GD.Print("[MeltySynthPlayer][miniaudio] Render thread loop exited");
            }

            // ====================================================================
            // 辅助方法 (与 FmodAudioOutputBridge 相同, 独立副本以避免跨类访问)
            // ====================================================================
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
                    left = SoftLimit(left);
                    right = SoftLimit(right);
                    left *= scale;
                    right *= scale;
                    _outputBuffer[i * 2] = left;
                    _outputBuffer[i * 2 + 1] = right;
                }
                _lastSampleL = _outputBuffer[(frames - 1) * 2];
                _lastSampleR = _outputBuffer[(frames - 1) * 2 + 1];
            }

            private static float SoftLimit(float sample)
            {
                return (float)Math.Tanh(sample * 0.9) * 0.95f;
            }

            private void FillWithSilence(IntPtr data, int frames)
            {
                int required = frames * 2;
                if (_outputBuffer.Length < required)
                {
                    Array.Resize(ref _outputBuffer, required);
                }
                float decay = (float)Math.Exp(-2.0 / Math.Max(1, frames));
                float l = _lastSampleL;
                float r = _lastSampleR;
                for (int i = 0; i < frames; i++)
                {
                    _outputBuffer[i * 2] = l;
                    _outputBuffer[i * 2 + 1] = r;
                    l *= decay;
                    r *= decay;
                }
                _lastSampleL = l;
                _lastSampleR = r;
                Marshal.Copy(_outputBuffer, 0, data, required);
            }

            private void FillRemainderWithDecay(int startFrame, int endFrame)
            {
                int frames = endFrame - startFrame;
                float decay = (float)Math.Exp(-2.0 / Math.Max(1, frames));
                float l = _lastSampleL;
                float r = _lastSampleR;
                for (int i = startFrame; i < endFrame; i++)
                {
                    _outputBuffer[i * 2] = l;
                    _outputBuffer[i * 2 + 1] = r;
                    l *= decay;
                    r *= decay;
                }
                _lastSampleL = l;
                _lastSampleR = r;
            }

            private void FillOutputBufferWithDecay(int startFrameIgnored, int totalFrames)
            {
                float decay = (float)Math.Exp(-2.0 / Math.Max(1, totalFrames));
                float l = _lastSampleL;
                float r = _lastSampleR;
                for (int i = 0; i < totalFrames; i++)
                {
                    _outputBuffer[i * 2] = l;
                    _outputBuffer[i * 2 + 1] = r;
                    l *= decay;
                    r *= decay;
                }
                _lastSampleL = l;
                _lastSampleR = r;
            }

            // ====================================================================
            // 销毁
            // ====================================================================
            private void DisposeNative()
            {
                if (_bridgeHandle != IntPtr.Zero)
                {
                    MiniaudioNative.ma_bridge_uninit(_bridgeHandle);
                    _bridgeHandle = IntPtr.Zero;
                }
                if (_selfHandle.IsAllocated)
                {
                    _selfHandle.Free();
                }
                _initialized = false;
                _playing = false;
            }

            public void Dispose()
            {
                StopRenderThread();
                DisposeNative();
            }

            // 兼容性方法
            public int GetUnderrunCount() => System.Threading.Interlocked.CompareExchange(ref _underrunCount, 0, 0);

            /// <summary>
            /// 获取当前总音频延迟 (毫秒)
            /// = 设备内部延迟 (ma_device_get_latency 或 period 估算) + RingBuffer 延迟
            /// </summary>
            public float GetLatencyMs()
            {
                float deviceLatencyMs = 0f;

                // 1. 尝试获取 native 设备延迟 (真实值)
                if (_nativeGetLatencyAvailable && _bridgeHandle != IntPtr.Zero)
                {
                    try
                    {
                        var r = MiniaudioNative.ma_bridge_get_latency(_bridgeHandle, out uint latencyFrames);
                        if (r == MiniaudioNative.Result.Ok)
                        {
                            deviceLatencyMs = latencyFrames * 1000.0f / _sampleRate;
                        }
                        else
                        {
                            // 后端不支持 ma_device_get_latency, 用 period 估算
                            deviceLatencyMs = EstimateDeviceLatencyMs();
                        }
                    }
                    catch (EntryPointNotFoundException)
                    {
                        // 旧版 DLL 无此导出, 不再尝试
                        _nativeGetLatencyAvailable = false;
                        GD.Print("[MeltySynthPlayer][miniaudio] ma_bridge_get_latency not found in DLL, using estimate");
                        deviceLatencyMs = EstimateDeviceLatencyMs();
                    }
                }
                else
                {
                    deviceLatencyMs = EstimateDeviceLatencyMs();
                }

                // 2. RingBuffer 延迟 (应用层缓冲, 尚未进入设备)
                float ringLatencyMs = 0f;
                if (_ringBuffer != null)
                {
                    ringLatencyMs = _ringBuffer.ReadableFrames * 1000.0f / _sampleRate;
                }

                return deviceLatencyMs + ringLatencyMs;
            }

            /// <summary>用 period size × count 估算设备延迟 (fallback)</summary>
            private float EstimateDeviceLatencyMs()
            {
                if (_actualPeriod > 0 && _actualPeriodCount > 0)
                {
                    return _actualPeriod * _actualPeriodCount * 1000.0f / _sampleRate;
                }
                return 0f;
            }
        }
}
