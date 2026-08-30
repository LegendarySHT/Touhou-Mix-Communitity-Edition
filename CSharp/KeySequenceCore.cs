using Godot;
using System.Collections.Generic;

/// <summary>
/// KeySequenceManager 的 C# 核心：完整键序列生成算法 + C# 端 SOA 输出存储。
/// 由 GDScript 薄封装（Game/KeySequenceManager.gd）在 worker 线程调用，纯计算不碰场景树。
/// 输出（game_sequences / 背景 / 手动 / 自动 分类）全部以紧凑平行数组保存于 C#，
/// 消除 GDScript 数万 GameSequence 对象 + 每序列一个 Array 的开销。
/// 块类型：0=Block 1=Slide 2=Long（与 GDScript BlockType 一致）。
/// </summary>
[GlobalClass]
public partial class KeySequenceCore : RefCounted
{
    // ===== 配置 =====
    private int _laneCount;
    private int _densityCapPerSec;
    private float _instantThr;
    private float _shortThr;
    private float _minTapInterval;
    private float _cooldownSec;
    private float _maxTouchVelocity;
    private int _maxTouchCount;
    private bool _genInstantConnect;
    private bool _genShortConnect;
    private float _maxInstantConnectSec;
    private int _minBlockSpacing;
    private bool _handModelEnabled;
    private float _keyWidth;
    private float _screenWidth;

    private const float HOME_BIAS_COEFF = 0.4f;
    private const float CROSS_HAND_PENALTY_MULT = 2.0f;
    private const float CHORD_TOLERANCE_MS = 10.0f;
    private const float DEFAULT_BPM = 120.0f;

    // ===== 时间线 =====
    private int _timebase;
    private readonly List<double> _bpmTick = new();   // BPM 段起点 tick
    private readonly List<double> _bpmValue = new();  // 每段 BPM
    private readonly List<double> _bpmCum = new();    // 每段起点累计毫秒

    // ===== 流式跨窗口状态 =====
    private readonly List<Touch> _touches = new();
    private float[] _laneLongEnd = System.Array.Empty<float>();
    private int _batchCounter;

    // ===== 输入音符（enabled 子集，SOA）=====
    private int[] _inStartTick;
    private int[] _inDurTick;
    private int[] _inPitch;
    private int[] _inVelocity;
    private int[] _inTrack;
    private int[] _inChannel;

    // ===== 流式游标 =====
    private int _cursor;          // 已消费的输入索引
    private double _windowEndMs;  // 当前 1000ms 窗口上界
    private readonly List<int> _bgAccum = new(); // 跨窗口累积背景音符（输入索引）

    // ===== 输出（game sequences，SOA）=====
    private readonly List<int> _seqKeyId = new();
    private readonly List<int> _seqPitch = new();
    private readonly List<float> _seqStart = new();
    private readonly List<float> _seqDur = new();
    private readonly List<int> _seqType = new();
    private readonly List<int> _seqLane = new();
    private readonly List<int> _seqOrigStart = new(); // 在 _gNoteIdx 中的起始
    private readonly List<int> _seqOrigLen = new();   // 原音符个数
    private readonly List<int> _gNoteIdx = new();     // 全部 game 原音符输入索引（扁平）

    // ===== 输出（背景 / 分类）=====
    private readonly List<int> _bgNoteIdx = new();
    private readonly List<int> _manualIdx = new();
    private readonly List<int> _autoIdx = new();
    private int _nextKeyId;

    // ========== 配置 ==========
    public void Configure(int laneCount, int densityCap, float instantThr, float shortThr,
        float minTapInterval, float cooldownSec, float maxTouchVelocity, int maxTouchCount,
        bool genInstantConnect, bool genShortConnect, float maxInstantConnectSec,
        int minBlockSpacing, bool handModelEnabled, float keyWidth, float screenWidth)
    {
        _laneCount = laneCount;
        _densityCapPerSec = densityCap;
        _instantThr = instantThr;
        _shortThr = shortThr;
        _minTapInterval = minTapInterval;
        _cooldownSec = cooldownSec;
        _maxTouchVelocity = maxTouchVelocity;
        _maxTouchCount = maxTouchCount;
        _genInstantConnect = genInstantConnect;
        _genShortConnect = genShortConnect;
        _maxInstantConnectSec = maxInstantConnectSec;
        _minBlockSpacing = ValidateMinSpacing(minBlockSpacing);
        _handModelEnabled = handModelEnabled;
        _keyWidth = keyWidth;
        _screenWidth = screenWidth;
    }

    private int ValidateMinSpacing(int v) => v < 0 || v >= _laneCount ? 1 : v;

    // ========== 时间参数 ==========
    public void SetMidiTimeParameters(int timebase, int[] bpmTicks, float[] bpmValues)
    {
        _timebase = timebase > 0 ? timebase : 480;
        _bpmTick.Clear(); _bpmValue.Clear(); _bpmCum.Clear();
        int n = bpmValues.Length;
        double cum = 0.0;
        for (int i = 0; i < n; i++)
        {
            double tk = bpmTicks[i];
            double bpm = bpmValues[i];
            _bpmTick.Add(tk); _bpmValue.Add(bpm); _bpmCum.Add(cum);
            if (i + 1 < n)
            {
                double nt = bpmTicks[i + 1];
                double mspt = (60000.0 / bpm) / _timebase;
                cum += (nt - tk) * mspt;
            }
        }
    }

    private float TickToMs(double tick)
    {
        int n = _bpmTick.Count;
        if (n == 0)
            return (float)((tick / _timebase) * (60000.0 / DEFAULT_BPM));
        // 首段前
        if (tick <= _bpmTick[0])
        {
            var mspt = (60000.0 / _bpmValue[0]) / _timebase;
            return (float)(_bpmCum[0] + (tick - _bpmTick[0]) * mspt);
        }
        // 末段后
        double lastT = _bpmTick[n - 1];
        if (tick >= lastT)
        {
            var mspt = (60000.0 / _bpmValue[n - 1]) / _timebase;
            return (float)(_bpmCum[n - 1] + (tick - lastT) * mspt);
        }
        // 二分找所在段
        int lo = 0, hi = n - 1;
        while (lo < hi)
        {
            int mid = (lo + hi + 1) >> 1;
            if (_bpmTick[mid] <= tick) lo = mid; else hi = mid - 1;
        }
        var mspt2 = (60000.0 / _bpmValue[lo]) / _timebase;
        return (float)(_bpmCum[lo] + (tick - _bpmTick[lo]) * mspt2);
    }

    private float TickDurToMs(double startTick, double durTick)
    {
        if (durTick <= 0.0) return 0.0f;
        float s = TickToMs(startTick), e = TickToMs(startTick + durTick);
        return System.Math.Max(0.0f, e - s);
    }

    private float CalcLaneX(int lane)
    {
        if (_laneCount <= 1) return _screenWidth * 0.5f;
        float ls = _keyWidth * 0.5f;
        float sp = (_screenWidth - _keyWidth) / (_laneCount - 1);
        return ls + lane * sp;
    }

    private int CalcLaneFromX(float x)
    {
        if (_laneCount <= 1) return 0;
        float ls = _keyWidth * 0.5f;
        float sp = (_screenWidth - _keyWidth) / (_laneCount - 1);
        if (sp <= 0.0f) return 0;
        int lane = (int)System.Math.Round((x - ls) / sp);
        return System.Math.Clamp(lane, 0, _laneCount - 1);
    }

    // ========== 一次性全量生成（worker 线程调用）==========
    public void RunGenerate(int[] startTick, int[] durTick,
        int[] pitch, int[] velocity,
        int[] track, int[] channel)
    {
        SetInput(startTick, durTick, pitch, velocity, track, channel);
        StreamBegin();
        while (StreamNextWindow()) { }
        StreamFinalize();
    }

    /// <summary>从全量 SOA + 启用索引一次性生成（worker 线程调用）。</summary>
    public void RunGenerateGather(int[] soaStartTick,
        int[] soaDurTick, int[] soaPitch,
        int[] soaVelocity, int[] soaTrack,
        int[] soaChannel, int[] enabledIdx)
    {
        SetInputGather(soaStartTick, soaDurTick, soaPitch, soaVelocity,
            soaTrack, soaChannel, enabledIdx);
        StreamBegin();
        while (StreamNextWindow()) { }
        StreamFinalize();
    }

    // ========== 流式生成（worker 线程逐窗口调用）==========
    public void SetInput(int[] startTick, int[] durTick,
        int[] pitch, int[] velocity,
        int[] track, int[] channel)
    {
        _inStartTick = startTick; _inDurTick = durTick; _inPitch = pitch;
        _inVelocity = velocity; _inTrack = track; _inChannel = channel;
    }

    /// <summary>从全量 SOA 并行数组 + 启用索引装配输入（启用子集按 SOA 顺序=start_tick 升序）。</summary>
    public void SetInputGather(int[] soaStartTick,
        int[] soaDurTick, int[] soaPitch,
        int[] soaVelocity, int[] soaTrack,
        int[] soaChannel, int[] enabledIdx)
    {
        int n = enabledIdx.Length;
        var st = new int[n];
        var du = new int[n];
        var pt = new int[n];
        var ve = new int[n];
        var tr = new int[n];
        var ch = new int[n];
        for (int i = 0; i < n; i++)
        {
            int si = enabledIdx[i];
            st[i] = soaStartTick[si]; du[i] = soaDurTick[si]; pt[i] = soaPitch[si];
            ve[i] = soaVelocity[si]; tr[i] = soaTrack[si]; ch[i] = soaChannel[si];
        }
        _inStartTick = st; _inDurTick = du; _inPitch = pt;
        _inVelocity = ve; _inTrack = tr; _inChannel = ch;
    }

    /// <summary>处理下一个 1000ms 窗口；全部输入消费完毕返回 false。</summary>
    public bool StreamNextWindow()
    {
        int n = _inStartTick.Length;
        if (_cursor >= n) return false;
        int from = _cursor, to = from;
        while (to < n && TickToMs(_inStartTick[to]) < _windowEndMs) to++;
        if (to > from)
        {
            var blocks = new List<BlockInfo>();
            ProcessWindow(from, to, blocks, _bgAccum);
        }
        _cursor = to;
        _windowEndMs += 1000.0;
        return true;
    }

    /// <summary>背景排序 + 手动/自动分类（流式全量消费后调用）。</summary>
    public void StreamFinalize() => FinalizeBackgroundAndClassify(_bgAccum);

    // ========== 跨窗口状态 ==========
    public void StreamBegin()
    {
        _laneLongEnd = new float[_laneCount];
        for (int k = 0; k < _laneCount; k++) _laneLongEnd[k] = -1.0f;
        _batchCounter = 0;
        _touches.Clear();
        InitTouches();
        _cursor = 0;
        _windowEndMs = 1000.0;
        _bgAccum.Clear();
        // 清输出
        _seqKeyId.Clear(); _seqPitch.Clear(); _seqStart.Clear(); _seqDur.Clear();
        _seqType.Clear(); _seqLane.Clear(); _seqOrigStart.Clear(); _seqOrigLen.Clear();
        _gNoteIdx.Clear(); _bgNoteIdx.Clear(); _manualIdx.Clear(); _autoIdx.Clear();
        _nextKeyId = 0;
    }

    private void InitTouches()
    {
        var caps = _maxTouchCount;
        if (!_handModelEnabled || caps <= 0)
        {
            for (int i = 0; i < caps; i++) { var t = NewTouch(i); t.Hand = -1; _touches.Add(t); }
            return;
        }
        int homePerHand = (int)System.Math.Ceiling(caps / 2.0);
        int halfLane = _laneCount / 2;
        var leftLanes = DistributeHomeLanes(0, halfLane - 1, homePerHand);
        var rightLanes = DistributeHomeLanes(halfLane, _laneCount - 1, homePerHand);
        var leftXs = new List<float>(); foreach (int l in leftLanes) leftXs.Add(CalcLaneX(l));
        var rightXs = new List<float>(); foreach (int l in rightLanes) rightXs.Add(CalcLaneX(l));

        if (caps == 1)
        {
            var t = NewTouch(0); t.Hand = -1; t.HomeX = CalcLaneX(_laneCount / 2);
            var all = new List<float>(); all.AddRange(leftXs); all.AddRange(rightXs);
            t.HandHomes = all.ToArray(); t.LastPressX = t.HomeX; _touches.Add(t);
            return;
        }
        int leftCount = (int)System.Math.Ceiling(caps / 2.0);
        int rightCount = caps - leftCount;
        for (int i = 0; i < leftCount; i++)
        {
            var t = NewTouch(_touches.Count); t.Hand = 0; t.HandHomes = leftXs.ToArray();
            t.HomeX = leftXs[System.Math.Min(i, leftXs.Count - 1)]; t.LastPressX = t.HomeX; _touches.Add(t);
        }
        for (int i = 0; i < rightCount; i++)
        {
            var t = NewTouch(_touches.Count); t.Hand = 1; t.HandHomes = rightXs.ToArray();
            t.HomeX = rightXs[System.Math.Min(i, rightXs.Count - 1)]; t.LastPressX = t.HomeX; _touches.Add(t);
        }
    }

    private static List<int> DistributeHomeLanes(int start, int end, int count)
    {
        var lanes = new List<int>();
        if (count <= 0 || end < start) return lanes;
        if (count == 1) { lanes.Add((start + end) / 2); return lanes; }
        int span = end - start;
        for (int i = 0; i < count; i++)
        {
            int lane = start + (int)System.Math.Round(i * (double)span / (count - 1));
            lanes.Add(System.Math.Clamp(lane, start, end));
        }
        return lanes;
    }

    private static Touch NewTouch(int idx)
    {
        var t = new Touch();
        t.Index = idx; t.IsFree = true; t.LastPressTimeMs = float.NegativeInfinity; t.Hand = -1;
        return t;
    }

    // ========== 滑动触点位置 ==========
    private float TouchCurrentX(int touchIdx, float atMs)
    {
        var t = _touches[touchIdx];
        if (float.IsNegativeInfinity(t.LastPressTimeMs)) return t.HomeX;
        if (!t.IsFree) return t.LastPressX;
        if (!_handModelEnabled || t.HandHomes.Length == 0) return t.LastPressX;
        float nearest = NearestHomeX(t, t.LastPressX);
        float elapsed = (atMs - t.LastPressTimeMs) / 1000.0f;
        if (elapsed <= 0.0f) return t.LastPressX;
        float maxOff = _maxTouchVelocity * elapsed;
        float dist = System.Math.Abs(nearest - t.LastPressX);
        if (dist <= maxOff) return nearest;
        return nearest > t.LastPressX ? t.LastPressX + maxOff : t.LastPressX - maxOff;
    }

    private static float NearestHomeX(Touch t, float fromX)
    {
        float nearest = t.HandHomes[0];
        float minD = System.Math.Abs(nearest - fromX);
        foreach (float hx in t.HandHomes)
        {
            float d = System.Math.Abs(hx - fromX);
            if (d < minD) { minD = d; nearest = hx; }
        }
        return nearest;
    }

    private int BlockHand(float x) => x < _screenWidth * 0.5f ? 0 : 1;

    // ========== 窗口处理 ==========
    private void ProcessWindow(int from, int to, List<BlockInfo> allBlocks, List<int> bg)
    {
        if (to <= from) return;
        var windowBlocks = new List<BlockInfo>();
        BuildChords(from, to, windowBlocks, bg);
        AssignTouchesAndJudge(windowBlocks, bg);
        ReduceDensity(windowBlocks, bg);
        GenerateConnects(windowBlocks);
        ConvertToSequences(windowBlocks);
        windowBlocks.Clear();
    }

    // ========== Step A/B 建块 ==========
    private void BuildChords(int from, int to, List<BlockInfo> allBlocks, List<int> bg)
    {
        int n = to;
        int i = from;
        while (i < n)
        {
            float chordStart = TickToMs(_inStartTick[i]);
            int activeLongs = 0;
            for (int l = 0; l < _laneCount; l++)
                if (_laneLongEnd[l] > chordStart) activeLongs++;

            // 同刻合并 + 同 lane 去重（保高音）
            var laneMap = new Dictionary<int, int>(); // lane -> note idx
            int j = i;
            while (j < n)
            {
                if (TickToMs(_inStartTick[j]) - chordStart > CHORD_TOLERANCE_MS) break;
                int lane = _inPitch[j] % _laneCount;
                if (laneMap.TryGetValue(lane, out int existing))
                {
                    if (_inPitch[j] > _inPitch[existing]) { bg.Add(existing); laneMap[lane] = j; }
                    else bg.Add(j);
                }
                else laneMap[lane] = j;
                j++;
            }
            i = j;
            if (laneMap.Count == 0) continue;

            var chordBlocks = new List<BlockInfo>();
            foreach (var kv in laneMap)
            {
                int lane = kv.Key, note = kv.Value;
                float startMs = TickToMs(_inStartTick[note]);
                float durMs = TickDurToMs(_inStartTick[note], _inDurTick[note]);
                var b = GetBlock();
                b.Batch = _batchCounter; b.Lane = lane; b.StartMs = startMs; b.EndMs = startMs + durMs;
                b.DurMs = durMs; b.MainPitch = _inPitch[note]; b.X = CalcLaneX(lane);
                b.Notes.Clear(); b.Notes.Add(note);
                if (_laneLongEnd[lane] > startMs) { b.SlideForced = true; b.Type = 1; }
                chordBlocks.Add(b);
            }
            chordBlocks = EnforceMinSpacing(chordBlocks, bg);
            if (_maxTouchCount > 0 && chordBlocks.Count > 0)
            {
                if (activeLongs > 0)
                {
                    var longLanes = new List<int>();
                    for (int l = 0; l < _laneCount; l++)
                        if (_laneLongEnd[l] > chordStart) longLanes.Add(l);
                    if (longLanes.Count > 0)
                    {
                        var normals = new List<BlockInfo>();
                        foreach (var bb in chordBlocks) if (bb.Type != 1) normals.Add(bb);
                        if (normals.Count > 0)
                        {
                            normals.Sort((a, b) => MinLaneDist(a.Lane, longLanes).CompareTo(MinLaneDist(b.Lane, longLanes)));
                            int toSlide = System.Math.Min(activeLongs, normals.Count);
                            for (int k = 0; k < toSlide; k++) { normals[k].SlideForced = true; normals[k].Type = 1; }
                        }
                    }
                }
                if (chordBlocks.Count > _maxTouchCount)
                {
                    int needRemove = chordBlocks.Count - _maxTouchCount;
                    var ordinary = new List<BlockInfo>();
                    foreach (var bb in chordBlocks) if (!bb.SlideForced) ordinary.Add(bb);
                    ordinary.Sort((a, b) => a.MainPitch.CompareTo(b.MainPitch));
                    foreach (var eb in ordinary)
                    {
                        if (needRemove <= 0) break;
                        if (eb.Notes.Count > 0) bg.Add(eb.Notes[0]);
                        chordBlocks.Remove(eb); needRemove--;
                    }
                    while (needRemove > 0)
                    {
                        var slides = new List<BlockInfo>();
                        foreach (var bb in chordBlocks) if (bb.SlideForced) slides.Add(bb);
                        if (slides.Count == 0) break;
                        slides.Sort((a, b) => a.MainPitch.CompareTo(b.MainPitch));
                        var eb = slides[0];
                        if (eb.Notes.Count > 0) bg.Add(eb.Notes[0]);
                        chordBlocks.Remove(eb); needRemove--;
                    }
                }
            }
            if (chordBlocks.Count == 0) continue;
            foreach (var bb in chordBlocks)
                if (bb.Type != 1 && bb.DurMs / 1000.0f > _shortThr)
                    // 加一个手指点击冷却时间，防止长条结束后紧接同轨道 block 点击过紧
                    _laneLongEnd[bb.Lane] = bb.EndMs + _cooldownSec * 1000.0f;
            foreach (var bb in chordBlocks) allBlocks.Add(bb);
            _batchCounter++;
        }
    }

    private static int MinLaneDist(int lane, List<int> longLanes)
    {
        int best = 1 << 30;
        foreach (int ll in longLanes) { int d = System.Math.Abs(lane - ll); if (d < best) best = d; }
        return best;
    }

    private BlockInfo GetBlock()
    {
        // 池化：多数窗口块在窗口结束会被 Clear，这里只在新 window 内新建
        var b = new BlockInfo();
        return b;
    }

    private List<BlockInfo> EnforceMinSpacing(List<BlockInfo> blocks, List<int> bg)
    {
        if (blocks.Count <= 1 || _minBlockSpacing <= 0) return blocks;
        var sorted = new List<BlockInfo>(blocks);
        sorted.Sort((a, b) => b.MainPitch.CompareTo(a.MainPitch));
        var kept = new List<BlockInfo>();
        foreach (var block in sorted)
        {
            bool conflict = false;
            foreach (var kb in kept)
                if (System.Math.Abs(block.Lane - kb.Lane) <= _minBlockSpacing) { conflict = true; break; }
            if (conflict) { if (block.Notes.Count > 0) bg.Add(block.Notes[0]); }
            else kept.Add(block);
        }
        return kept;
    }

    // ========== Step C/D 触点匹配与类型判定 ==========
    private void AssignTouchesAndJudge(List<BlockInfo> blocks, List<int> bg)
    {
        if (blocks.Count == 0) return;
        var byBatch = new Dictionary<int, List<BlockInfo>>();
        foreach (var b in blocks)
        {
            if (!byBatch.TryGetValue(b.Batch, out var list)) { list = new List<BlockInfo>(); byBatch[b.Batch] = list; }
            list.Add(b);
        }
        var batchIds = new List<int>(byBatch.Keys); batchIds.Sort();
        foreach (int bid in batchIds)
        {
            var batch = byBatch[bid];
            MatchBlocksToTouches(batch);
            batch.Sort((a, b) => a.StartMs.CompareTo(b.StartMs));
            foreach (var b in batch) JudgeBlockType(b);
        }
        ReconcileSpacingAfterClamp(blocks, bg);
    }

    private void MatchBlocksToTouches(List<BlockInfo> group)
    {
        int nb = group.Count, nt = _touches.Count;
        var sorted = new List<BlockInfo>(group);
        sorted.Sort((a, b) => a.X.CompareTo(b.X));
        if (nb > nt)
        {
            sorted.Sort((a, b) => a.StartMs.CompareTo(b.StartMs));
            foreach (var b in sorted) b.TouchIndex = -1;
            return;
        }
        var best = new int[nb];
        for (int i = 0; i < nb; i++) best[i] = -1;
        bool found = Enumerate(nb, nt, true, sorted, best);
        if (!found)
        {
            for (int i = 0; i < nb; i++) best[i] = -1;
            Enumerate(nb, nt, false, sorted, best);
        }
        sorted.Sort((a, b) => a.StartMs.CompareTo(b.StartMs));
        for (int i = 0; i < nb; i++) sorted[i].TouchIndex = best[i];
    }

    private float ComboCost(int k, int nt, List<BlockInfo> sorted, int[] combo)
    {
        float cost = 0.0f;
        for (int i = 0; i < k; i++)
        {
            var blk = sorted[i]; var t = _touches[combo[i]];
            float tx = TouchCurrentX(t.Index, blk.StartMs);
            float dist = System.Math.Abs(tx - blk.X);
            cost += dist;
            if (t.LastPressTimeMs >= 0)
            {
                float dt = (blk.StartMs - t.LastPressTimeMs) / 1000.0f;
                if (dt > 0)
                {
                    float maxFeas = _maxTouchVelocity * dt;
                    if (dist > maxFeas) cost += (dist - maxFeas) * 10.0f;
                }
            }
            if (_handModelEnabled && t.Hand >= 0 && _maxTouchCount >= 2)
            {
                if (BlockHand(blk.X) != t.Hand) cost += _screenWidth * CROSS_HAND_PENALTY_MULT;
                cost += System.Math.Abs(t.HomeX - blk.X) * HOME_BIAS_COEFF;
            }
        }
        return cost;
    }

    private bool HardConstraintOk(int k, List<BlockInfo> sorted, int[] combo)
    {
        for (int i = 0; i < k; i++)
        {
            var blk = sorted[i]; var t = _touches[combo[i]];
            if (t.LastPressTimeMs >= 0)
            {
                float occupyEnd = t.LastPressTimeMs + _cooldownSec * 1000.0f;
                if (blk.StartMs < occupyEnd) return false;
            }
            if (t.LastPressTimeMs >= 0)
            {
                float dt = (blk.StartMs - t.LastPressTimeMs) / 1000.0f;
                if (dt > 0)
                {
                    float tx = TouchCurrentX(t.Index, blk.StartMs);
                    float req = System.Math.Abs(blk.X - tx) / dt;
                    if (req > _maxTouchVelocity) return false;
                }
            }
        }
        return true;
    }

    private bool Enumerate(int k, int nTouches, bool hard, List<BlockInfo> sorted, int[] outMatch)
    {
        var combo = new int[k];
        for (int i = 0; i < k; i++) combo[i] = i;
        float minCost = float.PositiveInfinity;
        bool found = false;
        while (true)
        {
            if (hard && !HardConstraintOk(k, sorted, combo))
            {
                int skip = k - 1;
                while (skip >= 0 && combo[skip] == nTouches - k + skip) skip--;
                if (skip < 0) break;
                combo[skip]++;
                for (int j = skip + 1; j < k; j++) combo[j] = combo[j - 1] + 1;
                continue;
            }
            float c = ComboCost(k, nTouches, sorted, combo);
            if (c < minCost) { minCost = c; System.Array.Copy(combo, outMatch, k); found = true; }
            int idx = k - 1;
            while (idx >= 0 && combo[idx] == nTouches - k + idx) idx--;
            if (idx < 0) break;
            combo[idx]++;
            for (int j = idx + 1; j < k; j++) combo[j] = combo[j - 1] + 1;
        }
        return found;
    }

    private void JudgeBlockType(BlockInfo b)
    {
        float durSec = b.DurMs / 1000.0f;
        if (b.TouchIndex < 0 || b.TouchIndex >= _touches.Count) return;
        var t = _touches[b.TouchIndex];
        if (b.SlideForced) b.Type = 1;
        else if (durSec <= _instantThr) b.Type = 1;
        else if (durSec <= _shortThr) b.Type = 0;
        else b.Type = 2;

        if (!t.IsFree)
        {
            float occupyEnd = t.LastPressTimeMs + _cooldownSec * 1000.0f;
            if (b.StartMs > occupyEnd) t.IsFree = true;
            // prev_block 仅用于连块输出，当前消费方已不读，忽略
        }
        if (t.LastPressTimeMs >= 0)
        {
            float dt = (b.StartMs - t.LastPressTimeMs) / 1000.0f;
            if (dt > 0)
            {
                float tx = TouchCurrentX(t.Index, b.StartMs);
                float maxOff = _maxTouchVelocity * dt;
                float dist = System.Math.Abs(b.X - tx);
                if (dist > maxOff)
                {
                    b.X = b.X > tx ? tx + maxOff : tx - maxOff;
                    b.Lane = CalcLaneFromX(b.X);
                    b.X = CalcLaneX(b.Lane);
                }
            }
        }
        if (t.LastPressTimeMs >= 0)
        {
            float gap = (b.StartMs - t.LastPressTimeMs) / 1000.0f;
            if (gap < _minTapInterval) b.Type = 1;
        }
        t.IsFree = false;
        t.LastPressTimeMs = b.StartMs;
        t.LastPressX = b.X;
    }

    private void ReconcileSpacingAfterClamp(List<BlockInfo> blocks, List<int> bg)
    {
        if (blocks.Count <= 1 || _minBlockSpacing <= 0) return;
        var byBatch = new Dictionary<int, List<BlockInfo>>();
        foreach (var b in blocks)
        {
            if (!byBatch.TryGetValue(b.Batch, out var list)) { list = new List<BlockInfo>(); byBatch[b.Batch] = list; }
            list.Add(b);
        }
        var toRemove = new HashSet<BlockInfo>();
        foreach (var kv in byBatch)
        {
            var batch = kv.Value;
            if (batch.Count <= 1) continue;
            var kept = EnforceMinSpacing(batch, bg);
            var keptSet = new HashSet<BlockInfo>(kept);
            foreach (var b in batch) if (!keptSet.Contains(b)) toRemove.Add(b);
        }
        if (toRemove.Count == 0) return;
        int w = 0;
        for (int i = 0; i < blocks.Count; i++)
            if (!toRemove.Contains(blocks[i])) blocks[w++] = blocks[i];
        blocks.RemoveRange(w, blocks.Count - w);
    }

    // ========== Step 5.5 密度削减 ==========
    private void ReduceDensity(List<BlockInfo> allBlocks, List<int> bg)
    {
        if (_densityCapPerSec <= 0 || allBlocks.Count == 0) return;
        float budget = _densityCapPerSec;
        var groupsByBatch = new Dictionary<int, (List<BlockInfo> blocks, float time, double cost, double prio, bool slideOnly)>();
        foreach (var b in allBlocks)
        {
            if (!groupsByBatch.TryGetValue(b.Batch, out var g)) g = (new List<BlockInfo>(), b.StartMs, 0, 0, false);
            g.blocks.Add(b);
            groupsByBatch[b.Batch] = g;
        }
        var secondGroups = new Dictionary<int, List<int>>(); // sec -> batch ids
        foreach (var kv in groupsByBatch)
        {
            var g = kv.Value;
            var m = ComputeMetrics(g.blocks);
            g.cost = m.cost; g.prio = m.prio; g.slideOnly = m.slideOnly;
            groupsByBatch[kv.Key] = g;
            int sec = (int)System.Math.Floor(g.time / 1000.0);
            if (!secondGroups.TryGetValue(sec, out var list)) { list = new List<int>(); secondGroups[sec] = list; }
            list.Add(kv.Key);
        }
        var keptBatches = new HashSet<int>();
        foreach (var kv in secondGroups)
        {
            int sec = kv.Key;
            var batchIds = kv.Value;
            float slotW = 1000.0f / budget;
            int nSlots = _densityCapPerSec;
            var skeleton = new Dictionary<int, int>(); // slot -> batch
            for (int idx = 0; idx < batchIds.Count; idx++)
            {
                int bid = batchIds[idx];
                var g = groupsByBatch[bid];
                float tInSec = g.time - sec * 1000.0f;
                int slot = (int)System.Math.Min(System.Math.Floor(tInSec / slotW), nSlots - 1);
                if (!skeleton.TryGetValue(slot, out int cur) || g.prio > groupsByBatch[cur].prio)
                    skeleton[slot] = bid;
            }
            var keptIdx = new HashSet<int>();
            double totalCost = 0;
            foreach (int bid in skeleton.Values) { keptIdx.Add(bid); totalCost += groupsByBatch[bid].cost; }
            if (totalCost > budget)
            {
                var slideEject = new List<int>(); var nonSlideEject = new List<int>();
                foreach (int bid in keptIdx)
                { if (groupsByBatch[bid].slideOnly) slideEject.Add(bid); else nonSlideEject.Add(bid); }
                slideEject.Sort((a, b) => groupsByBatch[a].prio.CompareTo(groupsByBatch[b].prio));
                foreach (int bid in slideEject)
                {
                    if (totalCost <= budget) break;
                    if (!keptIdx.Contains(bid)) continue;
                    keptIdx.Remove(bid); totalCost -= groupsByBatch[bid].cost;
                }
                if (totalCost > budget)
                {
                    nonSlideEject.Sort((a, b) => groupsByBatch[a].prio.CompareTo(groupsByBatch[b].prio));
                    foreach (int bid in nonSlideEject)
                    {
                        if (totalCost <= budget) break;
                        if (!keptIdx.Contains(bid)) continue;
                        keptIdx.Remove(bid); totalCost -= groupsByBatch[bid].cost;
                    }
                }
            }
            if (totalCost < budget)
            {
                double remainder = budget - totalCost;
                var candidates = new List<int>();
                foreach (int bid in batchIds)
                    if (!keptIdx.Contains(bid) && groupsByBatch[bid].cost <= remainder) candidates.Add(bid);
                candidates.Sort((a, b) => groupsByBatch[b].prio.CompareTo(groupsByBatch[a].prio));
                foreach (int bid in candidates)
                    if (groupsByBatch[bid].cost <= remainder) { keptIdx.Add(bid); remainder -= groupsByBatch[bid].cost; }
            }
            foreach (int bid in keptIdx)
                foreach (var b in groupsByBatch[bid].blocks) keptBatches.Add(b.Batch);
        }
        int w = 0;
        for (int i = 0; i < allBlocks.Count; i++)
        {
            var b = allBlocks[i];
            if (keptBatches.Contains(b.Batch)) allBlocks[w++] = b;
            else foreach (int note in b.Notes) bg.Add(note);
        }
        allBlocks.RemoveRange(w, allBlocks.Count - w);
    }

    private (double cost, double prio, bool slideOnly) ComputeMetrics(List<BlockInfo> blocks)
    {
        int count = blocks.Count;
        if (count == 0) return (0, 0, false);
        double cost = 0; int velSum = 0, maxPitch = 0, nonSlide = 0;
        foreach (var b in blocks)
        {
            bool isSlide = b.Type == 1;
            cost += isSlide ? 0.33 : 1.0;
            if (!isSlide) nonSlide++;
            if (b.Notes.Count > 0) velSum += _inVelocity[b.Notes[0]];
            if (b.MainPitch > maxPitch) maxPitch = b.MainPitch;
        }
        double avgVel = velSum / (double)count;
        double prio = 1.5 * avgVel / 127.0 + 1.5 * maxPitch / 127.0;
        prio -= 0.3 * System.Math.Max(0, nonSlide - 1);
        return (cost, prio, nonSlide == 0);
    }

    // ========== Step E 连块 ==========
    private void GenerateConnects(List<BlockInfo> blocks)
    {
        // 连块仅用于 GameSequence 输出标记 connected_prev（当前消费方未读），移植语义保留但无需建表
        if (blocks.Count == 0) return;
    }

    // ========== Step 7 转 GameSequence（SOA 输出）==========
    private void ConvertToSequences(List<BlockInfo> blocks)
    {
        foreach (var b in blocks)
        {
            if (b.Notes.Count == 0) continue;
            int main = b.Notes[0];
            int origStart = _gNoteIdx.Count;
            int key = _nextKeyId++;
            _seqKeyId.Add(key);
            _seqPitch.Add(_inPitch[main]);
            _seqStart.Add(b.StartMs);
            _seqDur.Add(b.DurMs);
            _seqType.Add(b.Type);
            _seqLane.Add(b.Lane);
            foreach (int note in b.Notes) _gNoteIdx.Add(note);
            _seqOrigStart.Add(origStart);
            _seqOrigLen.Add(b.Notes.Count);
        }
    }

    // ========== Step 8 背景排序 + 分类 ==========
    private void FinalizeBackgroundAndClassify(List<int> bg)
    {
        // 背景按 (时间, 音高) 排序
        var idx = new List<int>(bg.Count);
        for (int i = 0; i < bg.Count; i++) idx.Add(i);
        idx.Sort((a, b) =>
        {
            float ta = TickToMs(_inStartTick[bg[a]]), tb = TickToMs(_inStartTick[bg[b]]);
            if (ta == tb) return _inPitch[bg[a]].CompareTo(_inPitch[bg[b]]);
            return ta.CompareTo(tb);
        });
        _bgNoteIdx.Clear();
        foreach (int i in idx) _bgNoteIdx.Add(bg[i]);

        // 手动 = 全部 game 原音符；自动 = 背景
        _manualIdx.Clear();
        foreach (int note in _gNoteIdx) _manualIdx.Add(note);
        _autoIdx.Clear();
        foreach (int note in _bgNoteIdx) _autoIdx.Add(note);
    }

    // ========== 输出访问器 ==========
    public int GameSeqCount => _seqKeyId.Count;
    public int SeqKeyId(int i) => _seqKeyId[i];
    public int SeqPitch(int i) => _seqPitch[i];
    public float SeqStartMs(int i) => _seqStart[i];
    public float SeqDurMs(int i) => _seqDur[i];
    public int SeqType(int i) => _seqType[i];
    public int SeqLane(int i) => _seqLane[i];
    public int SeqOrigStart(int i) => _seqOrigStart[i];
    public int SeqOrigLen(int i) => _seqOrigLen[i];
    public int GNoteAt(int j) => _gNoteIdx[j];
    public int GNoteCount => _gNoteIdx.Count;
    public int BgNoteCount => _bgNoteIdx.Count;
    public int BgNoteAt(int j) => _bgNoteIdx[j];
    public int ManualCount => _manualIdx.Count;
    public int ManualAt(int i) => _manualIdx[i];
    public int AutoCount => _autoIdx.Count;
    public int AutoAt(int i) => _autoIdx[i];

    // ========== 输入音符访问器（manual/auto 索引指向 enabled 输入数组）==========
    public int InputCount => _inStartTick.Length;
    public int InputStartTickAt(int i) => _inStartTick[i];
    public int InputPitchAt(int i) => _inPitch[i];
    public int InputVelocityAt(int i) => _inVelocity[i];
    public int InputTrackAt(int i) => _inTrack[i];
    public int InputChannelAt(int i) => _inChannel[i];

    /// <summary>清空输出（PlayView 退出时释放，避免单槽缓存常驻）</summary>
    public void ClearOutput()
    {
        _seqKeyId.Clear(); _seqPitch.Clear(); _seqStart.Clear(); _seqDur.Clear();
        _seqType.Clear(); _seqLane.Clear(); _seqOrigStart.Clear(); _seqOrigLen.Clear();
        _gNoteIdx.Clear(); _bgNoteIdx.Clear(); _manualIdx.Clear(); _autoIdx.Clear();
    }

    private class Touch
    {
        public int Index;
        public bool IsFree = true;
        public float LastPressX;
        public float LastPressTimeMs = float.NegativeInfinity;
        public int LastPressBlock = -1;
        public int Hand = -1;
        public float HomeX;
        public float[] HandHomes = System.Array.Empty<float>();
    }

    private class BlockInfo
    {
        public readonly List<int> Notes = new();
        public int Batch;
        public int Lane;
        public float X;
        public float StartMs;
        public float EndMs;
        public float DurMs;
        public int Type;        // 0 Block 1 Slide 2 Long
        public bool SlideForced;
        public int TouchIndex = -1;
        public int PrevBlock = -1;
        public int MainPitch;
    }
}