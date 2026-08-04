using Godot;
using LiteDB;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;

/// <summary>
/// ChartDb — 谱面数据唯一数据源（LiteDB）
///
/// 替代原 .charts_scan_cache.json 缓存文件，作为所有谱面/专辑/歌曲数据的存储与查询层。
/// 所有读写经 _lock 串行（LiteDB 单写多读，但项目为简单起见统一加锁）。
///
/// 规范键 = folder_name（真正唯一，= _id）。folder_hash（folder_name.split("_")[0]）作查找别名。
/// 三套别名（json _id / file_hash / hash）经索引统一解析到 folder_name。
///
/// v3：chart 文档全字段拆平，不再存整块 data JSON —— 可搜索/排序字段直接顶层、可索引；
/// song/album 子文档保留在 chart（RebuildAlbumsSongs 重建 songdata/albumdata 聚合的唯一源）；
/// chart_runtime 独立集合权威保存用户运行时配置（_runtime 不再进 chart 文档，消除冗余）。
///
/// 直接使用 BsonDocument（不用 POCO BsonMapper），规避安卓 Mono 反射/AOT 风险。
/// LiteDB 5 约定：BsonDocument 是 Dictionary&lt;string,BsonValue&gt;，读缺失键会抛异常，统一用 TryGetValue。
/// </summary>
[GlobalClass]
public partial class ChartDb : Node
{
    public const int SchemaVersion = 4;

    private LiteDatabase _db;
    private ILiteCollection<BsonDocument> _charts;
    private ILiteCollection<BsonDocument> _albums;
    private ILiteCollection<BsonDocument> _songs;
    private ILiteCollection<BsonDocument> _runtime;
    private ILiteCollection<BsonDocument> _meta;

    private readonly object _lock = new();
    private bool _isOpen;
    private string _oldCachePath = "";

    // ========== 简繁日搜索规范化（OpenccNetLib） ==========
    // 链式 jp2t→t2s：日文新字体 → 传统 → 简体，让 简/繁/日 三种写法互搜。
    // 全部 7 个可搜索字段（谱面名/原曲名/专辑名/歌手/原曲作者/上传者/简介）都可能含日文。
    //
    // 关键约束：Opencc 静态构造函数强制从 {AppContext.BaseDirectory}/dicts/dictionary_maxlength.zstd
    // 加载默认词典（DictionaryLib.DefaultLib → FromZstd）。该文件缺失时类型初始化抛异常，
    // 且 .NET 类型初始化失败后永久不可用。因此必须先让 zstd 就位到 BaseDirectory/dicts/ 再触碰 Opencc 类型。
    // 桌面：NuGet contentFiles 已拷贝到 .NET 输出目录；安卓：需从 res:// 抽取（须主线程 FileAccess）。

    private static readonly object _normLock = new();
    private static OpenccNetLib.Opencc _normT2S;
    private static OpenccNetLib.Opencc _normJp2T;
    private static bool _normPrimaryTried;   // 规范化器初始化已尝试（幂等）
    private static string _resZstdPath = ""; // 主线程 OpenDb 解析的 res:// 编译词典绝对路径（诊断用）
    private static int _mainThreadId;        // 主线程 ManagedThreadId（安卓 FileAccess 抽取须主线程）

    /// <summary>OpenccNetLib jp2t→t2s 链漏掉的常用字修正（郷 误转 鄕 而非 乡）。</summary>
    private static readonly Dictionary<char, char> _normFix = new Dictionary<char, char>
    {
        ['郷'] = '乡',
        ['鄕'] = '乡',
        ['兎'] = '兔',
    };

    /// <summary>规范化搜索副本缓存（folder_name → [song, author]）。
    /// 启动时后台线程预热全量填充 + 首次使用时惰性补缺。</summary>
    private static readonly ConcurrentDictionary<string, string[]> _normCache = new ConcurrentDictionary<string, string[]>();

    /// <summary>规范化缓存世代号：RebuildAlbumsSongs 清缓存时递增，后台预热据此自取消。</summary>
    private static int _normCacheGen;

    /// <summary>搜索诊断日志只打一次（真机排查）。</summary>
    private static bool _searchDiagLogged;

    /// <summary>规范化器诊断累积（GD.Print 不进安卓 logcat，经 GDScript 通道输出）。</summary>
    private static string _normDiag = "";

    /// <summary>诊断累积 + 控制台打印（供 GetNormalizerDiag 输出到 logcat）。</summary>
    private static void NormLog(string s)
    {
        _normDiag += s + "\n";
        GD.Print("[ChartDb][Norm] " + s);
    }

    /// <summary>返回规范化器诊断文本（暴露给 GDScript，真机排查用）。</summary>
    public string GetNormalizerDiag() => _normDiag;

    /// <summary>
    /// 打开数据库并执行 schema 迁移（一次）。
    /// dbPath / oldCachePath 均为经 ProjectSettings.globalize_path 的真实 OS 路径。
    /// </summary>
    public bool OpenDb(string dbPath, string oldCachePath)
    {
        lock (_lock)
        {
            _oldCachePath = oldCachePath ?? "";
            try
            {
                var dir = System.IO.Path.GetDirectoryName(dbPath);
                if (!string.IsNullOrEmpty(dir))
                    System.IO.Directory.CreateDirectory(dir);
                _db = new LiteDatabase(dbPath);
                BindCollections();
                EnsureIndexes();

                // schema 迁移：版本不符 → 重建 charts/albums/songs（chart_runtime 结构未变，保留避免丢配置）
                var schemaDoc = _meta.FindById("schema");
                int schema = schemaDoc != null ? (int)schemaDoc["version"].AsInt32 : 0;
                if (schema != SchemaVersion)
                {
                    GD.Print($"[ChartDb] Schema v{schema} != v{SchemaVersion}, rebuilding...");
                    _db.DropCollection("charts");
                    _db.DropCollection("albums");
                    _db.DropCollection("songs");
                    BindCollections();
                    EnsureIndexes();
                    MigrateFromOldCache();
                    _meta.Upsert(new BsonDocument { ["_id"] = "schema", ["version"] = SchemaVersion });
                }
                // 一次性：把旧键（file_hash/midi_id）的 chart_runtime 文档重键为 folder_name
                MigrateRuntimeKeys();
                _isOpen = true;
                GD.Print($"[ChartDb] Opened, charts={CountCharts()} albums={CountAlbums()} songs={CountSongs()}");
                // 主线程解析 res:// zstd 路径；Opencc 静态构造强制从 BaseDirectory/dicts/ 加载默认词典，
                // 因此必须在主线程先把 zstd 就位（安卓从 res:// 抽取）再触碰 Opencc 类型。
                // 用 CallDeferred 延迟到下一帧初始化，避开启动主路径卡顿（~0.5s 一次）。
                _mainThreadId = System.Environment.CurrentManagedThreadId;
                try { _resZstdPath = ProjectSettings.GlobalizePath("res://CSharp/ChartDb/dicts/dictionary_maxlength.zstd"); } catch { }
                CallDeferred(nameof(_DeferredInitNormalizer));
                return true;
            }
            catch (Exception e)
            {
                GD.PrintErr($"[ChartDb] Open failed: {e.Message}");
                try { _db?.Dispose(); } catch { }
                // 区分「占用」与「损坏」，避免误删用户数据（chart_runtime/收藏）：
                // - 文件被占用（另一实例/杀软，Win32 ERROR_SHARING_VIOLATION = 32）→ 保留文件，
                //   删除也大概率失败；占用是暂时的，下次启动重试即可。
                // - 确认为损坏 → 先备份为 charts.ldb.corrupt.bak 再移除，给用户手动恢复留余地。
                if (!IsSharingViolation(e) && System.IO.File.Exists(dbPath))
                {
                    try
                    {
                        var bakPath = dbPath + ".corrupt.bak";
                        if (!System.IO.File.Exists(bakPath))
                            System.IO.File.Move(dbPath, bakPath);
                        else
                            System.IO.File.Delete(dbPath);
                    }
                    catch (Exception ex)
                    {
                        GD.PrintErr($"[ChartDb] Failed to back up corrupt db: {ex.Message}");
                    }
                }
                _db = null;
                _isOpen = false;
                return false;
            }
        }
    }

    /// <summary>判断异常是否为「文件被占用」（Win32 ERROR_SHARING_VIOLATION = 32）。
    /// 用 HResult 0x80070020 判断，与系统语言无关（中文 Windows 上异常消息是本地化的）。
    /// LiteDB 可能抛自己的异常，故遍历 InnerException 链。</summary>
    private static bool IsSharingViolation(Exception e)
    {
        for (Exception cur = e; cur != null; cur = cur.InnerException)
        {
            if (cur.HResult == unchecked((int)0x80070020))
                return true;
        }
        return false;
    }

    public void CloseDb()
    {
        lock (_lock)
        {
            _db?.Dispose();
            _db = null;
            _isOpen = false;
        }
    }

    public bool IsOpen() => _isOpen && _db != null;

    public long CountCharts() => _charts.Count();
    public long CountByStatus(string status) => _charts.Count(Query.EQ("status", status));
    public long CountAlbums() => _albums.Count();
    public long CountSongs() => _songs.Count();

    // ========== 缓存层（替代 .charts_scan_cache.json 读写） ==========

    /// <summary>
    /// 返回 { folder_name: metadata_dict }，形状与旧缓存一致。
    /// v3 起为轻量投影：不含 data 大块（只含路径/mtime/扁平化 id 字段），
    /// 使 _build_charts_index_from_data / _validate_charts_cache_worker 无需改动且不再物化整块 JSON。
    /// </summary>
    public Godot.Collections.Dictionary LoadChartsCache()
    {
        var result = new Godot.Collections.Dictionary();
        if (!IsOpen()) return result;
        lock (_lock)
        {
            foreach (var d in _charts.FindAll().ToList())
            {
                var md = DocToMetadataDict(d);
                if (md != null && md.Count > 0)
                    result[BsonConvert.GetStr(d, "folder_name")] = md;
            }
        }
        return result;
    }

    /// <summary>
    /// 批量 upsert（全量扫描 / 后台校验合并结果）。
    /// chartsData: { folder_name: metadata_dict }。
    /// 只处理带 data 的条目（扫描结果）；轻量投影条目（无 data）跳过，避免覆盖 DB 已拆平数据。
    /// 顺带从 data._runtime 为从未配置的 chart 播种 chart_runtime（磁盘 JSON 仅兜底，DB 权威）。
    /// </summary>
    public void SaveChartsCache(Godot.Collections.Dictionary chartsData)
    {
        if (!IsOpen()) return;
        lock (_lock)
        {
            _db.BeginTrans();
            try
            {
                foreach (var key in chartsData.Keys)
                {
                    var md = chartsData[key];
                    if (md.VariantType != Godot.Variant.Type.Dictionary) continue;
                    var mdDict = md.AsGodotDictionary();
                    if (!mdDict.ContainsKey("data")) continue; // 轻量投影跳过
                    var doc = MetadataDictToDoc(mdDict);
                    if (doc == null) continue;

                    // 播种 chart_runtime（仅当该 chart 从未有配置；键 = folder_name）
                    var chartKey = ComputeChartKey(doc);
                    if (!string.IsNullOrEmpty(chartKey) && !_runtime.Exists(Query.EQ("_id", chartKey)))
                    {
                        if (doc.TryGetValue("data", out var dataV) && dataV.IsDocument)
                        {
                            var data = dataV.AsDocument;
                            if (data.TryGetValue("_runtime", out var rtV) && rtV.IsDocument)
                            {
                                var rt = rtV.AsDocument;
                                rt["_id"] = chartKey;
                                _runtime.Upsert(rt);
                            }
                        }
                    }
                    doc.Remove("data");
                    _charts.Upsert(doc);
                }
                _db.Commit();
            }
            catch
            {
                _db.Rollback();
                throw;
            }
            RebuildAlbumsSongs();
        }
    }

    /// <summary>
    /// 删除单张谱面（chart + runtime + 重算聚合）。
    /// key: 任意别名（folder_name / folder_hash / json _id / file_hash / hash）。
    /// </summary>
    public void RemoveChart(string key)
    {
        if (!IsOpen()) return;
        lock (_lock)
        {
            var folderName = LookupChartKey(key);
            if (string.IsNullOrEmpty(folderName)) return;
            var doc = _charts.FindById(folderName);
            if (doc != null)
            {
                var chartKey = ComputeChartKey(doc);
                if (!string.IsNullOrEmpty(chartKey))
                    _runtime.Delete(chartKey);
            }
            _charts.Delete(folderName);
            RebuildAlbumsSongs();
        }
    }

    public void RemoveCharts(Godot.Collections.Array keys)
    {
        if (!IsOpen()) return;
        lock (_lock)
        {
            foreach (var k in keys)
            {
                var key = k.AsString();
                if (string.IsNullOrEmpty(key)) continue;
                var folderName = LookupChartKey(key);
                if (string.IsNullOrEmpty(folderName)) continue;
                var doc = _charts.FindById(folderName);
                if (doc != null)
                {
                    var chartKey = ComputeChartKey(doc);
                    if (!string.IsNullOrEmpty(chartKey))
                        _runtime.Delete(chartKey);
                }
                _charts.Delete(folderName);
            }
            RebuildAlbumsSongs();
        }
    }

    // ========== 查询（返回规范 folder_name） ==========

    public Godot.Collections.Array<string> GetAllChartKeys()
    {
        if (!IsOpen()) return new Godot.Collections.Array<string>();
        lock (_lock)
        {
            return new Godot.Collections.Array<string>(_charts.FindAll().Select(d => d["_id"].AsString).ToArray());
        }
    }

    public Godot.Collections.Array<string> GetChartsByStatus(string status)
    {
        if (!IsOpen()) return new Godot.Collections.Array<string>();
        lock (_lock)
        {
            return new Godot.Collections.Array<string>(_charts.Find(Query.EQ("status", status)).Select(d => d["_id"].AsString).ToArray());
        }
    }

    /// <summary>
    /// 统一别名解析漏斗：依序探测 _id(folder_name) → folder_hash → midi_id → file_hash → hash。
    /// 返回规范主键（folder_name），未命中返回 ""。
    /// </summary>
    public string LookupChartKey(string key)
    {
        if (!IsOpen() || string.IsNullOrEmpty(key)) return "";
        lock (_lock)
        {
            var doc = _charts.FindOne(Query.EQ("_id", key));
            if (doc != null) return doc["_id"].AsString;
            doc = _charts.FindOne(Query.EQ("folder_hash", key));
            if (doc != null) return doc["_id"].AsString;
            doc = _charts.FindOne(Query.EQ("midi_id", key));
            if (doc != null) return doc["_id"].AsString;
            doc = _charts.FindOne(Query.EQ("file_hash", key));
            if (doc != null) return doc["_id"].AsString;
            doc = _charts.FindOne(Query.EQ("hash", key));
            if (doc != null) return doc["_id"].AsString;
            return "";
        }
    }

    public bool ChartExists(string key) => !string.IsNullOrEmpty(LookupChartKey(key));

    // ========== 路径/封面 ==========

    public string GetFolderPath(string key)
    {
        var doc = FindDoc(key);
        return doc == null ? "" : BsonConvert.GetStr(doc, "path");
    }

    public string GetJsonPath(string key)
    {
        var doc = FindDoc(key);
        return doc == null ? "" : BsonConvert.GetStr(doc, "json_path");
    }

    public string GetAudioPath(string key)
    {
        var doc = FindDoc(key);
        return doc == null ? "" : BsonConvert.GetStr(doc, "audio_path");
    }

    public string GetCoverPath(string key)
    {
        var doc = FindDoc(key);
        return doc == null ? "" : BsonConvert.GetStr(doc, "cover_path");
    }

    // ========== 分组（专辑 → 歌曲 → 谱面） ==========

    public Godot.Collections.Array GetAlbums()
    {
        var arr = new Godot.Collections.Array();
        if (!IsOpen()) return arr;
        lock (_lock)
        {
            foreach (var d in _albums.FindAll().ToList())
                arr.Add(BsonConvert.BsonToGodotDict(d));
        }
        return arr;
    }

    public Godot.Collections.Dictionary GetAlbum(string albumId)
    {
        if (!IsOpen()) return new Godot.Collections.Dictionary();
        lock (_lock)
        {
            var d = _albums.FindById(albumId);
            return d == null ? new Godot.Collections.Dictionary() : BsonConvert.BsonToGodotDict(d);
        }
    }

    public bool AlbumExists(string albumId)
    {
        if (!IsOpen()) return false;
        lock (_lock)
        {
            return _albums.Exists(Query.EQ("_id", albumId));
        }
    }

    public Godot.Collections.Dictionary GetSong(string songId)
    {
        if (!IsOpen()) return new Godot.Collections.Dictionary();
        lock (_lock)
        {
            var d = _songs.FindById(songId);
            return d == null ? new Godot.Collections.Dictionary() : BsonConvert.BsonToGodotDict(d);
        }
    }

    public bool SongExists(string songId)
    {
        if (!IsOpen()) return false;
        lock (_lock)
        {
            return _songs.Exists(Query.EQ("_id", songId));
        }
    }

    public Godot.Collections.Array GetSongsByAlbum(string albumId)
    {
        var arr = new Godot.Collections.Array();
        if (!IsOpen()) return arr;
        lock (_lock)
        {
            foreach (var d in _songs.Find(Query.EQ("album_id", albumId)).ToList())
                arr.Add(BsonConvert.BsonToGodotDict(d));
        }
        return arr;
    }

    public Godot.Collections.Array<string> GetMidiKeysBySong(string songId)
    {
        if (!IsOpen()) return new Godot.Collections.Array<string>();
        lock (_lock)
        {
            var d = _songs.FindById(songId);
            if (d == null) return new Godot.Collections.Array<string>();
            var arr = d.TryGetValue("midi_ids", out var mv) && mv.IsArray ? mv.AsArray : new BsonArray();
            return new Godot.Collections.Array<string>(arr.Select(x => x.AsString).ToArray());
        }
    }

    // ========== 专辑 / 歌曲轻量投影（AlbumView/SongView/DelView 直接消费，替代 AlbumData/SongData 水合） ==========

    /// <summary>
    /// 返回排序专辑投影（Array[Dictionary]）：{id, name, song_count, total_midi_count, date, earliest_uploaded_date}。
    /// method 三态：creation_time（date 主、earliest_uploaded_date 兜底、空值排最下）、
    /// download_time（earliest_uploaded_date、空值排最上）、name（专辑名升序，DelView 用）。
    /// Unknown 专辑（_id 前缀 __unknown）永远最后。direction: 0=ASC 1=DESC。
    /// 排序语义与旧 SortEngine.sort_albums / DelView._sort_albums_for_delview 一致。
    /// </summary>
    public Godot.Collections.Array GetSortedAlbumItems(string method, int direction)
    {
        var arr = new Godot.Collections.Array();
        if (!IsOpen()) return arr;
        lock (_lock)
        {
            var unknown = new List<BsonDocument>();
            var normal = new List<BsonDocument>();
            foreach (var d in _albums.FindAll().ToList())
            {
                if (d.TryGetValue("_id", out var idV) && idV.IsString && idV.AsString.StartsWith("__unknown"))
                    unknown.Add(d);
                else
                    normal.Add(d);
            }
            bool asc = direction == 0;
            if (method == "name")
            {
                normal.Sort((a, b) => asc
                    ? string.CompareOrdinal(BsonConvert.GetStr(a, "name"), BsonConvert.GetStr(b, "name"))
                    : string.CompareOrdinal(BsonConvert.GetStr(b, "name"), BsonConvert.GetStr(a, "name")));
            }
            else
            {
                normal.Sort((a, b) => CompareAlbumDates(a, b, method, asc));
            }
            foreach (var d in normal) arr.Add(AlbumItemDict(d));
            foreach (var d in unknown) arr.Add(AlbumItemDict(d));
            return arr;
        }
    }

    /// <summary>
    /// 返回专辑下所有歌曲的轻量投影（Array[Dictionary]）：{id, name, midi_count}。
    /// 替代 DataMGR.get_songs_by_album 的 SongData 水合，SongView/DelView 直接消费。
    /// </summary>
    public Godot.Collections.Array GetSongItemsByAlbum(string albumId)
    {
        var arr = new Godot.Collections.Array();
        if (!IsOpen() || string.IsNullOrEmpty(albumId)) return arr;
        lock (_lock)
        {
            foreach (var d in _songs.Find(Query.EQ("album_id", albumId)).ToList())
                arr.Add(SongItemDict(d));
            return arr;
        }
    }

    /// <summary>
    /// 专辑封面路径（DB 内直查，替代 AlbumListItem 的 水合全部分曲+首曲MidiData 链）：
    /// 专辑 → 首曲 → 首谱面 → chart.cover_path。与原 get_cover_path_by_midiData 语义一致：
    /// 只取首个，为空返回 ""（调用方用 default_cover_if_missing 兜底）。
    /// </summary>
    public string GetAlbumCoverPath(string albumId)
    {
        if (!IsOpen() || string.IsNullOrEmpty(albumId)) return "";
        lock (_lock)
        {
            var album = _albums.FindById(albumId);
            if (album == null || !album.TryGetValue("song_ids", out var sv) || !sv.IsArray || sv.AsArray.Count == 0)
                return "";
            var firstSongId = sv.AsArray[0].AsString;
            var song = _songs.FindById(firstSongId);
            if (song == null || !song.TryGetValue("midi_ids", out var mv) || !mv.IsArray || mv.AsArray.Count == 0)
                return "";
            var firstMidiId = mv.AsArray[0].AsString;
            var chart = _charts.FindById(firstMidiId);
            return chart == null ? "" : BsonConvert.GetStr(chart, "cover_path");
        }
    }

    /// <summary>
    /// 歌曲封面路径（DB 内直查）：歌曲 → 首谱面 → chart.cover_path。为空返回 ""。
    /// </summary>
    public string GetSongCoverPath(string songId)
    {
        if (!IsOpen() || string.IsNullOrEmpty(songId)) return "";
        lock (_lock)
        {
            var song = _songs.FindById(songId);
            if (song == null || !song.TryGetValue("midi_ids", out var mv) || !mv.IsArray || mv.AsArray.Count == 0)
                return "";
            var firstMidiId = mv.AsArray[0].AsString;
            var chart = _charts.FindById(firstMidiId);
            return chart == null ? "" : BsonConvert.GetStr(chart, "cover_path");
        }
    }

    /// <summary>专辑日期比较：语义移植自 SortEngine._compare_dates + _compare_albums（倒序 = 结果取反）。</summary>
    private static int CompareAlbumDates(BsonDocument a, BsonDocument b, string method, bool asc)
    {
        int cmp;
        if (method == "download_time")
        {
            cmp = CompareDates(
                BsonConvert.GetStr(a, "earliest_uploaded_date"),
                BsonConvert.GetStr(b, "earliest_uploaded_date"),
                "", "", true);
        }
        else
        {
            cmp = CompareDates(
                BsonConvert.GetStr(a, "date"),
                BsonConvert.GetStr(b, "date"),
                BsonConvert.GetStr(a, "earliest_uploaded_date"),
                BsonConvert.GetStr(b, "earliest_uploaded_date"),
                false);
        }
        return asc ? cmp : -cmp;
    }

    /// <summary>日期比较：primary 优先，primary 为空用 fallback；empty_to_top 控制空值排最上/最下。</summary>
    private static int CompareDates(string aPrimary, string bPrimary, string aFallback, string bFallback, bool emptyToTop)
    {
        var aDate = string.IsNullOrEmpty(aPrimary) ? aFallback : aPrimary;
        var bDate = string.IsNullOrEmpty(bPrimary) ? bFallback : bPrimary;
        if (string.IsNullOrEmpty(aDate) && string.IsNullOrEmpty(bDate)) return 0;
        if (string.IsNullOrEmpty(aDate)) return emptyToTop ? -1 : 1;
        if (string.IsNullOrEmpty(bDate)) return emptyToTop ? 1 : -1;
        return string.CompareOrdinal(aDate, bDate);
    }

    /// <summary>album 文档 → 列表项轻量投影字典（AlbumView/DelView 直接消费）。</summary>
    private static Godot.Collections.Dictionary AlbumItemDict(BsonDocument d)
    {
        var item = new Godot.Collections.Dictionary();
        item["id"] = d.TryGetValue("_id", out var idV) && idV.IsString ? idV.AsString : "";
        item["name"] = BsonConvert.GetStr(d, "name");
        item["song_count"] = d.TryGetValue("song_ids", out var sv) && sv.IsArray ? sv.AsArray.Count : 0;
        item["total_midi_count"] = BsonConvert.GetLong(d, "total_midi_count");
        item["date"] = BsonConvert.GetStr(d, "date");
        item["earliest_uploaded_date"] = BsonConvert.GetStr(d, "earliest_uploaded_date");
        return item;
    }

    /// <summary>song 文档 → 歌曲列表项轻量投影字典。</summary>
    private static Godot.Collections.Dictionary SongItemDict(BsonDocument d)
    {
        var item = new Godot.Collections.Dictionary();
        item["id"] = d.TryGetValue("_id", out var idV) && idV.IsString ? idV.AsString : "";
        item["name"] = BsonConvert.GetStr(d, "name");
        item["midi_count"] = d.TryGetValue("midi_ids", out var mv) && mv.IsArray ? mv.AsArray.Count : 0;
        return item;
    }

    // ========== 排序 / 搜索 ==========

    /// <summary>
    /// 按状态过滤 + 字段排序 +（可选）关键词搜索，返回规范 folder_name 数组（已有序）。
    /// sortField: 0=DEFAULT(sort_name) 1=download_count 2=love_count 3=up_count 4=trial_count 5=uploaded_date
    /// direction: 0=ASC 1=DESC
    /// </summary>
    public Godot.Collections.Array<string> GetSortedMidiKeys(string status, int sortField, int direction, string searchQuery)
    {
        if (!IsOpen()) return new Godot.Collections.Array<string>();
        lock (_lock)
        {
            return new Godot.Collections.Array<string>(SortedDocs(status, sortField, direction, searchQuery)
                .Select(d => d["_id"].AsString).ToArray());
        }
    }

    /// <summary>
    /// 按状态过滤 + 字段排序 +（可选）关键词搜索，返回有序轻量列表投影（Array[Dictionary]）。
    /// 列表视图（SortedMidiView）直接消费，替代全量水合 MidiData ——
    /// 每项仅含列表显示 + 封面查询所需的字段，见 ListItemDict。
    /// </summary>
    public Godot.Collections.Array GetSortedMidiListItems(string status, int sortField, int direction, string searchQuery)
    {
        var arr = new Godot.Collections.Array();
        if (!IsOpen()) return arr;
        lock (_lock)
        {
            foreach (var d in SortedDocs(status, sortField, direction, searchQuery))
                arr.Add(ListItemDict(d));
            return arr;
        }
    }

    /// <summary>
    /// 按任意别名键（folder_name / folder_hash / midi_id / file_hash / hash）批量取轻量列表投影。
    /// 收藏夹浏览用：保持传入顺序，跳过失效引用；searchQuery 非空时在收集集内过滤（含简繁日规范化）。
    /// </summary>
    public Godot.Collections.Array GetMidiListItemsByKeys(Godot.Collections.Array keys, string searchQuery = "")
    {
        var arr = new Godot.Collections.Array();
        if (!IsOpen()) return arr;
        lock (_lock)
        {
            var docs = new List<BsonDocument>();
            foreach (var kv in keys)
            {
                var key = kv.AsString();
                if (string.IsNullOrEmpty(key)) continue;
                var folderName = LookupChartKey(key);
                if (string.IsNullOrEmpty(folderName)) continue;
                var d = _charts.FindById(folderName);
                if (d != null) docs.Add(d);
            }
            if (!string.IsNullOrEmpty(searchQuery))
                docs = FilterSearch(docs, searchQuery);
            foreach (var d in docs)
                arr.Add(ListItemDict(d));
            return arr;
        }
    }

    /// <summary>
    /// chart 文档 → 列表项轻量投影字典（SortedMidiView 直接消费）。
    /// id = midi_id（点击水合用，可经 LookupChartKey 解析回 folder_name）。
    /// </summary>
    private static Godot.Collections.Dictionary ListItemDict(BsonDocument d)
    {
        var item = new Godot.Collections.Dictionary();
        item["id"] = BsonConvert.GetStr(d, "midi_id");
        item["key"] = d["_id"].AsString;
        item["name"] = BsonConvert.GetStr(d, "name");
        item["artist_name"] = BsonConvert.GetStr(d, "artist_name");
        item["status"] = BsonConvert.GetStr(d, "status", "PENDING");
        item["download_count"] = BsonConvert.GetLong(d, "download_count");
        item["trial_count"] = BsonConvert.GetLong(d, "trial_count");
        item["up_count"] = BsonConvert.GetLong(d, "up_count");
        item["love_count"] = BsonConvert.GetLong(d, "love_count");
        item["file_hash"] = BsonConvert.GetStr(d, "file_hash");
        return item;
    }

    /// <summary>
    /// 状态过滤 + 字段排序 +（可选）关键词搜索，返回有序 BsonDocument 列表。
    /// 与 GetSortedMidiKeys 语义完全一致（FindAll/Find + FilterSearch + LINQ OrderBy，
    /// 字符串 StringComparer.Ordinal），供键数组与轻量投影两种出口复用。
    /// </summary>
    private List<BsonDocument> SortedDocs(string status, int sortField, int direction, string searchQuery)
    {
        var docs = string.IsNullOrEmpty(status) || status == "ALL"
            ? _charts.FindAll().ToList()
            : _charts.Find(Query.EQ("status", status)).ToList();

        if (!string.IsNullOrEmpty(searchQuery))
            docs = FilterSearch(docs, searchQuery);

        bool asc = direction == 0;
        IEnumerable<BsonDocument> sorted;
        switch (sortField)
        {
            case 1:
                sorted = asc ? docs.OrderBy(d => BsonConvert.GetLong(d, "download_count")) : docs.OrderByDescending(d => BsonConvert.GetLong(d, "download_count"));
                break;
            case 2:
                sorted = asc ? docs.OrderBy(d => BsonConvert.GetLong(d, "love_count")) : docs.OrderByDescending(d => BsonConvert.GetLong(d, "love_count"));
                break;
            case 3:
                sorted = asc ? docs.OrderBy(d => BsonConvert.GetLong(d, "up_count")) : docs.OrderByDescending(d => BsonConvert.GetLong(d, "up_count"));
                break;
            case 4:
                sorted = asc ? docs.OrderBy(d => BsonConvert.GetLong(d, "trial_count")) : docs.OrderByDescending(d => BsonConvert.GetLong(d, "trial_count"));
                break;
            case 5:
                sorted = asc ? docs.OrderBy(d => BsonConvert.GetStr(d, "uploaded_date"), StringComparer.Ordinal) : docs.OrderByDescending(d => BsonConvert.GetStr(d, "uploaded_date"), StringComparer.Ordinal);
                break;
            default:
                sorted = asc ? docs.OrderBy(d => BsonConvert.GetStr(d, "sort_name"), StringComparer.Ordinal) : docs.OrderByDescending(d => BsonConvert.GetStr(d, "sort_name"), StringComparer.Ordinal);
                break;
        }
        return sorted.ToList();
    }

    /// <summary>
    /// 多关键词 AND 匹配（原名/专辑名/谱面名/歌手/原曲作者/上传者/简介，大小写不敏感）。
    /// </summary>
    public Godot.Collections.Array<string> SearchMidiKeys(string query)
    {
        if (!IsOpen() || string.IsNullOrEmpty(query)) return new Godot.Collections.Array<string>();
        lock (_lock)
        {
            var docs = _charts.FindAll().ToList();
            return new Godot.Collections.Array<string>(FilterSearch(docs, query).Select(d => d["_id"].AsString).ToArray());
        }
    }

    // ========== 运行时配置（chart_runtime，权威） ==========

    public Godot.Collections.Dictionary GetRuntime(string chartKey)
    {
        if (!IsOpen()) return null;
        lock (_lock)
        {
            var d = _runtime.FindById(ResolveRuntimeKey(chartKey));
            if (d == null) return null;
            var gd = BsonConvert.BsonToGodotDict(d);
            gd.Remove("_id");
            return gd;
        }
    }

    public void SaveRuntime(string chartKey, Godot.Collections.Dictionary dict)
    {
        if (!IsOpen() || string.IsNullOrEmpty(chartKey)) return;
        lock (_lock)
        {
            var bd = (BsonDocument)BsonConvert.VariantToBson(dict);
            bd["_id"] = ResolveRuntimeKey(chartKey);
            _runtime.Upsert(bd);
            // v3 起运行时配置只存 DB，不再写回 chart.json，无需同步 _json_mtime
            // （保留刷新反而会掩盖外部 chart.json 内容更新，使增量校验永不触发）
        }
    }

    public void ClearRuntime(string chartKey)
    {
        if (!IsOpen() || string.IsNullOrEmpty(chartKey)) return;
        lock (_lock)
        {
            _runtime.Delete(ResolveRuntimeKey(chartKey));
        }
    }

    /// <summary>
    /// 把任意别名（folder_name / folder_hash / json _id / file_hash / hash）解析为
    /// chart_runtime 的规范主键 folder_name（真正唯一，避免 hash 撞车互相覆盖配置）。
    /// 无法解析时回退用传入键（防御）。
    /// </summary>
    private string ResolveRuntimeKey(string chartKey)
    {
        var folderName = LookupChartKey(chartKey);
        return string.IsNullOrEmpty(folderName) ? chartKey : folderName;
    }

    // ========== 水合（MidiData.from_json 所需的 chart JSON 形状） ==========

    /// <summary>
    /// 组装 chart JSON 形状的字典（键名与 MidiData.from_json 一致），
    /// 供 DataManager 惰性水合 MidiData。含注入的 _runtime（chart_runtime 权威）。
    /// key 可为任意别名。
    /// </summary>
    public Godot.Collections.Dictionary GetChartJson(string key)
    {
        lock (_lock)
        {
            if (!IsOpen() || string.IsNullOrEmpty(key)) return new Godot.Collections.Dictionary();
            var folderName = LookupChartKey(key);
            if (string.IsNullOrEmpty(folderName)) return new Godot.Collections.Dictionary();
            var doc = _charts.FindById(folderName);
            if (doc == null) return new Godot.Collections.Dictionary();

            var gd = new Godot.Collections.Dictionary();
            gd["_id"] = BsonConvert.GetStr(doc, "midi_id");
            gd["name"] = BsonConvert.GetStr(doc, "name");
            gd["desc"] = BsonConvert.GetStr(doc, "description");
            gd["status"] = BsonConvert.GetStr(doc, "status", "PENDING");
            gd["artistName"] = BsonConvert.GetStr(doc, "artist_name");
            gd["uploaderName"] = BsonConvert.GetStr(doc, "uploader_name");
            gd["author"] = BsonConvert.GetStr(doc, "author_name");
            gd["uploadedDate"] = BsonConvert.GetStr(doc, "uploaded_date");
            gd["trialCount"] = BsonConvert.GetLong(doc, "trial_count");
            gd["downloadCount"] = BsonConvert.GetLong(doc, "download_count");
            gd["loveCount"] = BsonConvert.GetLong(doc, "love_count");
            gd["upCount"] = BsonConvert.GetLong(doc, "up_count");
            gd["downCount"] = BsonConvert.GetLong(doc, "down_count");
            gd["avgAccuracy"] = BsonConvert.GetDouble(doc, "avg_accuracy");
            gd["passCount"] = BsonConvert.GetLong(doc, "pass_count");
            gd["failCount"] = BsonConvert.GetLong(doc, "fail_count");
            gd["hash"] = BsonConvert.GetStr(doc, "hash");
            gd["file_hash"] = BsonConvert.GetStr(doc, "file_hash");
            gd["sCount"] = BsonConvert.GetLong(doc, "s_count");
            gd["aCount"] = BsonConvert.GetLong(doc, "a_count");
            gd["bCount"] = BsonConvert.GetLong(doc, "b_count");
            gd["cCount"] = BsonConvert.GetLong(doc, "c_count");
            gd["dCount"] = BsonConvert.GetLong(doc, "d_count");
            gd["fCount"] = BsonConvert.GetLong(doc, "f_count");

            // song/album 子文档（from_json 不读，但保留完整性 + 供 _ensureMidi 关联）
            if (doc.TryGetValue("song", out var sv) && sv.IsDocument)
                gd["song"] = BsonConvert.BsonToVariant(sv);
            if (doc.TryGetValue("album", out var av) && av.IsDocument)
                gd["album"] = BsonConvert.BsonToVariant(av);

            // 规范化搜索副本（全部可搜索字段简繁日互搜用）；MidiData.from_json 读取
            // 走 GetNormField 读 _normCache（启动后台预热 + 惰性补缺），主线程水合不再逐张转换
            gd["_search_song_name"] = GetNormField(doc, 0);
            gd["_search_author_name"] = GetNormField(doc, 1);
            gd["_search_album_name"] = GetNormField(doc, 2);
            gd["_search_artist_name"] = GetNormField(doc, 3);
            gd["_search_name"] = GetNormField(doc, 4);
            gd["_search_uploader_name"] = GetNormField(doc, 5);

            // 注入 chart_runtime（权威，主键 folder_name），覆盖磁盘 JSON 里的旧 _runtime
            var rt = _runtime.FindById(doc["_id"].AsString);
            if (rt != null)
            {
                var rtDict = new Godot.Collections.Dictionary();
                foreach (var kv in rt)
                    if (kv.Key != "_id") rtDict[kv.Key] = BsonConvert.BsonToVariant(kv.Value);
                gd["_runtime"] = rtDict;
            }

            // 派生关联键（供 MidiData 直接持有扁平 song/album 字段，不再水合 SongData/AlbumData）
            gd["song_id"] = BsonConvert.GetStr(doc, "song_id");
            gd["album_id"] = BsonConvert.GetStr(doc, "album_id");
            gd["song_name"] = BsonConvert.GetStr(doc, "song_name");
            gd["album_name"] = BsonConvert.GetStr(doc, "album_name");
            return gd;
        }
    }

    // ========== 内部 ==========

    private BsonDocument FindDoc(string key)
    {
        if (!IsOpen()) return null;
        lock (_lock)
        {
            var folderName = LookupChartKey(key);
            return string.IsNullOrEmpty(folderName) ? null : _charts.FindById(folderName);
        }
    }

    private void BindCollections()
    {
        _charts = _db.GetCollection("charts");
        _albums = _db.GetCollection("albums");
        _songs = _db.GetCollection("songs");
        _runtime = _db.GetCollection("chart_runtime");
        _meta = _db.GetCollection("meta");
    }

    private void EnsureIndexes()
    {
        _charts.EnsureIndex("folder_hash", "$.folder_hash");
        _charts.EnsureIndex("midi_id", "$.midi_id");
        _charts.EnsureIndex("file_hash", "$.file_hash");
        _charts.EnsureIndex("hash", "$.hash");
        _charts.EnsureIndex("status", "$.status");
        _charts.EnsureIndex("uploaded_date", "$.uploaded_date");
        _charts.EnsureIndex("download_count", "$.download_count");
        _charts.EnsureIndex("love_count", "$.love_count");
        _charts.EnsureIndex("up_count", "$.up_count");
        _charts.EnsureIndex("trial_count", "$.trial_count");
        _charts.EnsureIndex("song_id", "$.song_id");
        _charts.EnsureIndex("album_id", "$.album_id");
        _charts.EnsureIndex("sort_name", "$.sort_name");
        _songs.EnsureIndex("album_id", "$.album_id");
    }

    /// <summary>
    /// 一次性迁移：schema 重建后从旧 .charts_scan_cache.json 导入（若存在）。
    /// 逐条拆平 + 播种 chart_runtime + 剥离 data 大块。
    /// </summary>
    private void MigrateFromOldCache()
    {
        if (string.IsNullOrEmpty(_oldCachePath) || !System.IO.File.Exists(_oldCachePath))
            return;
        try
        {
            var json = System.IO.File.ReadAllText(_oldCachePath);
            var root = JsonNode.Parse(json)?.AsObject();
            if (root == null) return;
            var chartsNode = root["charts"]?.AsObject();
            if (chartsNode == null) return;
            int count = 0;
            foreach (var kv in chartsNode)
            {
                var obj = kv.Value?.AsObject();
                if (obj == null) continue;
                var bd = JsonNodeToBson(obj).AsDocument;
                if (!bd.ContainsKey("folder_name")) continue;
                bd["_id"] = bd["folder_name"];
                FlattenDoc(bd);

                var chartKey = ComputeChartKey(bd);
                if (!string.IsNullOrEmpty(chartKey) && !_runtime.Exists(Query.EQ("_id", chartKey)))
                {
                    if (bd.TryGetValue("data", out var dataV) && dataV.IsDocument)
                    {
                        var data = dataV.AsDocument;
                        if (data.TryGetValue("_runtime", out var rtV) && rtV.IsDocument)
                        {
                            var rt = rtV.AsDocument;
                            rt["_id"] = chartKey;
                            _runtime.Upsert(rt);
                        }
                    }
                }
                bd.Remove("data");
                _charts.Upsert(bd);
                count++;
            }
            RebuildAlbumsSongs();
            // 备份旧缓存并删除
            try
            {
                if (!System.IO.File.Exists(_oldCachePath + ".bak"))
                    System.IO.File.Copy(_oldCachePath, _oldCachePath + ".bak");
            }
            catch { }
            try { System.IO.File.Delete(_oldCachePath); } catch { }
            GD.Print($"[ChartDb] Migrated {count} charts from old cache");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ChartDb] Migration failed: {e.Message}");
        }
    }

    /// <summary>
    /// 一次性迁移：把旧键（file_hash/midi_id）的 chart_runtime 文档重键为 folder_name。
    /// 幂等：已是 folder_name 主键（能直接命中 charts._id）的跳过；无法解析的保留原键（孤儿，无害）。
    /// </summary>
    private void MigrateRuntimeKeys()
    {
        lock (_lock)
        {
            var toFix = new List<(string oldKey, string newKey)>();
            foreach (var rt in _runtime.FindAll().ToList())
            {
                var id = rt.TryGetValue("_id", out var idV) && idV.IsString ? idV.AsString : "";
                if (string.IsNullOrEmpty(id)) continue;
                if (_charts.Exists(Query.EQ("_id", id))) continue; // 已是 folder_name
                var folderName = LookupChartKey(id);
                if (!string.IsNullOrEmpty(folderName) && folderName != id)
                    toFix.Add((id, folderName));
            }
            foreach (var fix in toFix)
            {
                var rt = _runtime.FindById(fix.oldKey);
                if (rt != null)
                {
                    rt["_id"] = fix.newKey;
                    _runtime.Delete(fix.oldKey);
                    _runtime.Upsert(rt);
                }
            }
            if (toFix.Count > 0)
                GD.Print($"[ChartDb] Re-keyed {toFix.Count} chart_runtime docs to folder_name");
        }
    }

    private static BsonValue JsonNodeToBson(JsonNode node)
    {
        if (node == null) return BsonValue.Null;
        if (node is JsonObject obj)
        {
            var d = new BsonDocument();
            foreach (var kv in obj)
                d[kv.Key] = JsonNodeToBson(kv.Value);
            return d;
        }
        if (node is JsonArray arr)
        {
            var a = new BsonArray();
            foreach (var item in arr)
                a.Add(JsonNodeToBson(item));
            return a;
        }
        if (node is JsonValue val)
        {
            if (val.TryGetValue<string>(out var s)) return s;
            if (val.TryGetValue<long>(out var l)) return l;
            if (val.TryGetValue<double>(out var d)) return d;
            if (val.TryGetValue<bool>(out var b)) return b;
            return BsonValue.Null;
        }
        return BsonValue.Null;
    }

    /// <summary>
    /// 从 metadata dict（GDScript 扫描形状）构建 chart BsonDocument 并拆平。
    /// 主键用 folder_name（真正唯一；folder_hash 可能因用户数据命名不规整而撞车）。
    /// </summary>
    private static BsonDocument MetadataDictToDoc(Godot.Collections.Dictionary md)
    {
        var bd = (BsonDocument)BsonConvert.VariantToBson(md);
        if (!bd.ContainsKey("folder_name")) return null;
        bd["_id"] = bd["folder_name"];
        FlattenDoc(bd);
        return bd;
    }

    /// <summary>
    /// 从 chart 文档的 data 子文档拆平可排序/搜索/分组的字段到顶层。
    /// 幂等：无 data（已拆平）时补齐缺省字段，不覆盖现有值。
    /// song/album 子文档原样保留（RebuildAlbumsSongs 与 GetChartJson 复用）。
    /// </summary>
    private static void FlattenDoc(BsonDocument doc)
    {
        var fn = BsonConvert.GetStr(doc, "folder_name");
        var idx = fn.IndexOf('_');
        doc["folder_hash"] = idx >= 0 ? fn.Substring(0, idx) : fn;

        BsonDocument d = null;
        if (doc.TryGetValue("data", out var dataV) && dataV.IsDocument)
            d = dataV.AsDocument;

        if (d != null)
        {
            doc["midi_id"] = BsonConvert.GetStr(d, "_id");
            var hash = BsonConvert.GetStr(d, "hash");
            var fileHash = BsonConvert.GetStr(d, "file_hash");
            doc["hash"] = hash;
            doc["file_hash"] = string.IsNullOrEmpty(fileHash) ? hash : fileHash;
            doc["name"] = BsonConvert.GetStr(d, "name");
            doc["description"] = BsonConvert.GetStr(d, "desc");
            doc["status"] = BsonConvert.GetStr(d, "status", "PENDING");
            doc["artist_name"] = BsonConvert.GetStr(d, "artistName");
            doc["uploader_name"] = BsonConvert.GetStr(d, "uploaderName");

            var author = d.TryGetValue("author", out var authorV) ? authorV : BsonValue.Null;
            if (author.IsString) doc["author_name"] = author.AsString;
            else if (author.IsDocument) doc["author_name"] = BsonConvert.GetStr(author.AsDocument, "name");
            else doc["author_name"] = "";

            doc["uploaded_date"] = BsonConvert.GetStr(d, "uploadedDate");
            doc["trial_count"] = BsonConvert.GetLong(d, "trialCount");
            doc["download_count"] = BsonConvert.GetLong(d, "downloadCount");
            doc["love_count"] = BsonConvert.GetLong(d, "loveCount");
            doc["up_count"] = BsonConvert.GetLong(d, "upCount");
            doc["down_count"] = BsonConvert.GetLong(d, "downCount");
            doc["pass_count"] = BsonConvert.GetLong(d, "passCount");
            doc["fail_count"] = BsonConvert.GetLong(d, "failCount");
            doc["avg_accuracy"] = BsonConvert.GetDouble(d, "avgAccuracy");
            doc["s_count"] = BsonConvert.GetLong(d, "sCount");
            doc["a_count"] = BsonConvert.GetLong(d, "aCount");
            doc["b_count"] = BsonConvert.GetLong(d, "bCount");
            doc["c_count"] = BsonConvert.GetLong(d, "cCount");
            doc["d_count"] = BsonConvert.GetLong(d, "dCount");
            doc["f_count"] = BsonConvert.GetLong(d, "fCount");

            if (d.TryGetValue("song", out var songV) && songV.IsDocument)
                doc["song"] = songV;
            if (d.TryGetValue("album", out var albumV) && albumV.IsDocument)
                doc["album"] = albumV;
        }
        else
        {
            // 已拆平文档：补齐缺省字段（不覆盖现有值）
            if (!doc.ContainsKey("midi_id")) doc["midi_id"] = "";
            if (!doc.ContainsKey("file_hash")) doc["file_hash"] = "";
            if (!doc.ContainsKey("hash")) doc["hash"] = "";
            if (!doc.ContainsKey("name")) doc["name"] = "";
            if (!doc.ContainsKey("description")) doc["description"] = "";
            if (!doc.ContainsKey("status")) doc["status"] = "PENDING";
            if (!doc.ContainsKey("artist_name")) doc["artist_name"] = "";
            if (!doc.ContainsKey("uploader_name")) doc["uploader_name"] = "";
            if (!doc.ContainsKey("author_name")) doc["author_name"] = "";
            if (!doc.ContainsKey("uploaded_date")) doc["uploaded_date"] = "";
            if (!doc.ContainsKey("trial_count")) doc["trial_count"] = (long)0;
            if (!doc.ContainsKey("download_count")) doc["download_count"] = (long)0;
            if (!doc.ContainsKey("love_count")) doc["love_count"] = (long)0;
            if (!doc.ContainsKey("up_count")) doc["up_count"] = (long)0;
            if (!doc.ContainsKey("down_count")) doc["down_count"] = (long)0;
            if (!doc.ContainsKey("pass_count")) doc["pass_count"] = (long)0;
            if (!doc.ContainsKey("fail_count")) doc["fail_count"] = (long)0;
            if (!doc.ContainsKey("avg_accuracy")) doc["avg_accuracy"] = 0.0;
            if (!doc.ContainsKey("s_count")) doc["s_count"] = (long)0;
            if (!doc.ContainsKey("a_count")) doc["a_count"] = (long)0;
            if (!doc.ContainsKey("b_count")) doc["b_count"] = (long)0;
            if (!doc.ContainsKey("c_count")) doc["c_count"] = (long)0;
            if (!doc.ContainsKey("d_count")) doc["d_count"] = (long)0;
            if (!doc.ContainsKey("f_count")) doc["f_count"] = (long)0;
        }

        // 派生分组键：优先子文档，缺省保留现有值（孤儿由 RebuildAlbumsSongs 改写为 __unknown）
        string songId = BsonConvert.GetStr(doc, "song_id");
        string songName = BsonConvert.GetStr(doc, "song_name");
        if (doc.TryGetValue("song", out var sdV) && sdV.IsDocument)
        {
            var s = sdV.AsDocument;
            songId = BsonConvert.GetStr(s, "_id");
            songName = BsonConvert.GetStr(s, "name");
        }
        string albumId = BsonConvert.GetStr(doc, "album_id");
        string albumName = BsonConvert.GetStr(doc, "album_name");
        if (doc.TryGetValue("album", out var adV) && adV.IsDocument)
        {
            var a = adV.AsDocument;
            albumId = BsonConvert.GetStr(a, "_id");
            albumName = BsonConvert.GetStr(a, "name");
        }
        doc["song_id"] = songId;
        doc["song_name"] = songName;
        doc["album_id"] = albumId;
        doc["album_name"] = albumName;
        doc["sort_name"] = albumName + "\u0001" + songName + "\u0001" + BsonConvert.GetStr(doc, "name");
    }

    /// <summary>
    /// chart 文档 → 轻量 metadata dict（ChartMetadata.from_dict 兼容，不含 data 大块）。
    /// </summary>
    private static Godot.Collections.Dictionary DocToMetadataDict(BsonDocument doc)
    {
        var md = new Godot.Collections.Dictionary();
        md["id"] = BsonConvert.GetStr(doc, "folder_hash");
        foreach (var key in new[] { "folder_name", "path", "json_path", "audio_path", "cover_path", "is_complete", "audio_entries", "_json_mtime", "_mid_mtime", "midi_id", "file_hash", "hash" })
        {
            if (doc.TryGetValue(key, out var v))
                md[key] = BsonConvert.BsonToVariant(v);
        }
        return md;
    }

    /// <summary>
    /// chart_runtime 的规范主键 = folder_name（doc._id，真正唯一）。
    /// 旧版曾用 file_hash/midi_id（可能撞车互相覆盖配置），已统一为 folder_name。
    /// </summary>
    private static string ComputeChartKey(BsonDocument doc)
    {
        return doc["_id"].AsString;
    }

    private static List<BsonDocument> FilterSearch(List<BsonDocument> docs, string query)
    {
        var kws = query.ToLowerInvariant().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        if (kws.Length == 0) return docs;
        // 规范化查询词（全部字段简繁日互搜用）
        var normQuery = NormalizeCore(query);
        var normKws = normQuery.ToLowerInvariant()
            .Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        var result = docs.Where(d =>
        {
            var name = BsonConvert.GetStr(d, "name").ToLowerInvariant();
            var song = BsonConvert.GetStr(d, "song_name").ToLowerInvariant();
            var album = BsonConvert.GetStr(d, "album_name").ToLowerInvariant();
            var artist = BsonConvert.GetStr(d, "artist_name").ToLowerInvariant();
            var author = BsonConvert.GetStr(d, "author_name").ToLowerInvariant();
            var uploader = BsonConvert.GetStr(d, "uploader_name").ToLowerInvariant();
            var desc = BsonConvert.GetStr(d, "description").ToLowerInvariant();
            // 6 个字段走规范化副本（简繁日互搜）+ 原文匹配兜底；简介保持原文匹配
            var normSong = GetNormField(d, 0);
            var normAuthor = GetNormField(d, 1);
            var normAlbum = GetNormField(d, 2);
            var normArtist = GetNormField(d, 3);
            var normName = GetNormField(d, 4);
            var normUploader = GetNormField(d, 5);
            for (int i = 0; i < kws.Length; i++)
            {
                var kw = kws[i];
                var nkw = i < normKws.Length ? normKws[i] : kw;
                if (!(name.Contains(kw) || normName.Contains(nkw) ||
                      song.Contains(kw) || normSong.Contains(nkw) ||
                      album.Contains(kw) || normAlbum.Contains(nkw) ||
                      artist.Contains(kw) || normArtist.Contains(nkw) ||
                      author.Contains(kw) || normAuthor.Contains(nkw) ||
                      uploader.Contains(kw) || normUploader.Contains(nkw) ||
                      desc.Contains(kw)))
                    return false;
            }
            return true;
        }).ToList();
        if (!_searchDiagLogged)
        {
            _searchDiagLogged = true;
            GD.Print($"[ChartDb][Norm] FilterSearch: query='{query}' normQuery='{normQuery}' 命中 {result.Count}/{docs.Count}");
        }
        return result;
    }

    // ========== 简繁日规范化实现 ==========

    /// <summary>
    /// 搜索文本规范化（暴露给 GDScript）：把 简/繁/日 写法归一到简体。
    /// 链式 jp2t→t2s + 常用缺口字修正。词典加载失败时退化原文（搜索=普通匹配，不崩溃）。
    /// </summary>
    public string NormalizeForSearch(string text) => NormalizeCore(text);

    private static string NormalizeCore(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        EnsureNormalizer();
        if (_normT2S == null || _normJp2T == null) return text;
        var s = _normT2S.Convert(_normJp2T.Convert(text));
        if (_normFix.Count > 0)
        {
            var sb = new System.Text.StringBuilder(s.Length);
            foreach (var ch in s)
                sb.Append(_normFix.TryGetValue(ch, out var r) ? r : ch);
            s = sb.ToString();
        }
        return s;
    }

    /// <summary>
    /// 懒加载规范化器（须主线程：安卓需 FileAccess 抽取 zstd 到 BaseDirectory/dicts/）。
    /// 触碰 Opencc 类型前必须先确保默认词典就位（见 EnsureDefaultDictInPlace），
    /// 否则其静态构造函数抛异常后类型永久不可用。
    /// </summary>
    private static void EnsureNormalizer()
    {
        if (_normT2S != null) return;
        lock (_normLock)
        {
            if (_normT2S != null) return;
            if (!_normPrimaryTried)
            {
                _normPrimaryTried = true;
                NormLog($"BaseDir={AppContext.BaseDirectory}");
                NormLog($"BaseDir/dicts zstd 已存在={System.IO.File.Exists(System.IO.Path.Combine(AppContext.BaseDirectory, "dicts", "dictionary_maxlength.zstd"))}");
                NormLog($"res:// zstd File.Exists={_resZstdPath.Length > 0 && System.IO.File.Exists(_resZstdPath)}");
                EnsureDefaultDictInPlace();
                if (TryCreateNormalizer()) { LogNormalizerReady("默认词典"); return; }
                NormLog("所有加载路径失败，搜索退化为普通匹配");
            }
        }
    }

    /// <summary>
    /// 确保 OpenccNetLib 能加载默认词典 zstd。
    /// 桌面：NuGet contentFiles 已把 zstd 拷到 BaseDirectory/dicts/，直接可用。
    /// 安卓：AppContext.BaseDirectory 为空（程序集从 APK 内存加载），OpenccNetLib 用相对路径
    /// "dicts/..." 解析到进程 CWD（安卓根目录只读）。因此把 zstd 写到可写的 user://files/dicts/，
    /// 并 Directory.SetCurrentDirectory 指到 user://files/，使相对路径命中。
    /// 核心约束：Opencc 静态构造强制加载默认词典，缺失则类型初始化抛异常且永久不可用。
    /// </summary>
    private static void EnsureDefaultDictInPlace()
    {
        var baseTarget = System.IO.Path.Combine(AppContext.BaseDirectory, "dicts", "dictionary_maxlength.zstd");
        if (System.IO.File.Exists(baseTarget)) return;
        if (System.Environment.CurrentManagedThreadId != _mainThreadId)
        {
            NormLog("默认 zstd 缺失且不在主线程，跳过抽取");
            return;
        }
        try
        {
            var resExists = Godot.FileAccess.FileExists("res://CSharp/ChartDb/dicts/dictionary_maxlength.zstd");
            NormLog($"res:// FileExists={resExists}");
            if (!resExists)
            {
                NormLog("res:// zstd 不存在（未导出？Android 导出过滤需含 *.zstd）");
                return;
            }
            using var src = Godot.FileAccess.Open("res://CSharp/ChartDb/dicts/dictionary_maxlength.zstd", Godot.FileAccess.ModeFlags.Read);
            if (src == null) { NormLog("打开 res:// zstd 失败"); return; }
            var buf = src.GetBuffer((long)src.GetLength());
            NormLog($"读入 {buf.Length} 字节");

            // 安卓：BaseDirectory 为空 → 目标目录用可写的 user://，并把 CWD 指过去
            string targetDir;
            if (string.IsNullOrEmpty(AppContext.BaseDirectory))
            {
                var userBase = ProjectSettings.GlobalizePath("user://files/");
                System.IO.Directory.CreateDirectory(userBase);
                targetDir = System.IO.Path.Combine(userBase, "dicts");
                System.IO.Directory.CreateDirectory(targetDir);
                try
                {
                    System.IO.Directory.SetCurrentDirectory(userBase);
                    NormLog($"已设置 CWD={userBase}");
                }
                catch (Exception e) { NormLog($"设置 CWD 失败: {e.Message}"); }
            }
            else
            {
                targetDir = System.IO.Path.Combine(AppContext.BaseDirectory, "dicts");
                System.IO.Directory.CreateDirectory(targetDir);
            }
            var target = System.IO.Path.Combine(targetDir, "dictionary_maxlength.zstd");
            System.IO.File.WriteAllBytes(target, buf);
            NormLog($"已就位 zstd 到 {target} ({buf.Length} 字节)");
        }
        catch (Exception e)
        {
            NormLog($"就位 zstd 失败: {e.Message}");
        }
    }

    /// <summary>主线程延迟帧初始化规范化器（OpenDb 后一帧执行，避开启动主路径卡顿）。</summary>
    private void _DeferredInitNormalizer()
    {
        try { EnsureNormalizer(); }
        catch (Exception e) { GD.Print($"[ChartDb][Norm] 延迟初始化异常: {e.Message}"); }
        // 词典就绪 → 后台预热全库规范化缓存（缓存被 RebuildAlbumsSongs 清空时按世代号自取消）
        if (_normT2S == null) return;
        try
        {
            lock (_lock)
            {
                if (_charts != null)
                    PrewarmNormCache(_charts.FindAll().ToList());
            }
        }
        catch (Exception e) { GD.Print($"[ChartDb][Norm] 预热启动失败: {e.Message}"); }
    }

    /// <summary>词典就绪后打印诊断 + 样本转换结果（真机排查：验证转换是否正常）。</summary>
    private static void LogNormalizerReady(string via)
    {
        GD.Print($"[ChartDb][Norm] 词典加载成功 via {via}");
        GD.Print($"[ChartDb][Norm] 早見沙織 -> {NormalizeCore("早見沙織")}");
        GD.Print($"[ChartDb][Norm] 東方紅魔郷 -> {NormalizeCore("東方紅魔郷")}");
        GD.Print($"[ChartDb][Norm] 音楽 -> {NormalizeCore("音楽")}");
        GD.Print($"[ChartDb][Norm] 純白色的蕾絲 -> {NormalizeCore("純白色的蕾絲")}");
    }

    private static bool TryCreateNormalizer()
    {
        try
        {
            _normT2S = new OpenccNetLib.Opencc("t2s");
            _normJp2T = new OpenccNetLib.Opencc("jp2t");
            return true;
        }
        catch (Exception e)
        {
            NormLog($"new Opencc 失败: {e.Message}");
            _normT2S = null;
            _normJp2T = null;
            return false;
        }
    }

    /// <summary>取某 chart 文档的规范化搜索副本（缓存命中优先，惰性转换）。
    /// 6 个字段转换（简介除外）：谱面名/原曲名/专辑名/歌手/原曲作者/上传者
    /// 都可能含日文（忠于原始的标题、声优名、幻乐团等），统一归一消除「简体搜不到繁体」。
    /// 简介文本太长且无规范化必要，保持原文匹配。</summary>
    private static string GetNormField(BsonDocument doc, int idx)
    {
        var key = doc["_id"].AsString;
        if (_normCache.TryGetValue(key, out var arr)) return arr[idx];
        var fresh = new[]
        {
            NormalizeCore(BsonConvert.GetStr(doc, "song_name")),
            NormalizeCore(BsonConvert.GetStr(doc, "author_name")),
            NormalizeCore(BsonConvert.GetStr(doc, "album_name")),
            NormalizeCore(BsonConvert.GetStr(doc, "artist_name")),
            NormalizeCore(BsonConvert.GetStr(doc, "name")),
            NormalizeCore(BsonConvert.GetStr(doc, "uploader_name")),
        };
        _normCache.TryAdd(key, fresh);
        return fresh[idx];
    }

    /// <summary>后台线程填充全库规范化搜索副本缓存（纯字符串转换：无锁、无场景树/DB 访问）。
    /// 词典须已就绪（_normT2S != null）。世代号变化（RebuildAlbumsSongs 清缓存）时自取消，
    /// 避免旧快照覆盖重建后的新值；转换失败/被打断的缺口由 GetNormField 惰性补上。</summary>
    private static void PrewarmNormCache(List<BsonDocument> docs)
    {
        if (_normT2S == null) return;
        var gen = System.Threading.Volatile.Read(ref _normCacheGen);
        System.Threading.Tasks.Task.Run(() =>
        {
            try
            {
                foreach (var doc in docs)
                {
                    if (System.Threading.Volatile.Read(ref _normCacheGen) != gen) return;
                    var key = doc.TryGetValue("_id", out var idV) ? idV.AsString : "";
                    if (string.IsNullOrEmpty(key) || _normCache.ContainsKey(key)) continue;
                    var fresh = new[]
                    {
                        NormalizeCore(BsonConvert.GetStr(doc, "song_name")),
                        NormalizeCore(BsonConvert.GetStr(doc, "author_name")),
                        NormalizeCore(BsonConvert.GetStr(doc, "album_name")),
                        NormalizeCore(BsonConvert.GetStr(doc, "artist_name")),
                        NormalizeCore(BsonConvert.GetStr(doc, "name")),
                        NormalizeCore(BsonConvert.GetStr(doc, "uploader_name")),
                    };
                    _normCache.TryAdd(key, fresh);
                }
            }
            catch { /* 后台预热失败不致命，缺口由惰性补上 */ }
        });
    }

    /// <summary>安卓 APK 内 res:// 词典无法被 .NET File.IO 直读，用 Godot FileAccess 抽取到 user://files/dicts/。</summary>
    private static void TryExtractDictsToUser()
    {
        try
        {
            const string resDir = "res://CSharp/ChartDb/dicts/";
            const string userDir = "user://files/dicts/";
            var userReal = ProjectSettings.GlobalizePath(userDir);
            Godot.DirAccess.MakeDirRecursiveAbsolute(userReal);
            using var da = Godot.DirAccess.Open(resDir);
            if (da == null) return;
            foreach (var f in da.GetFiles())
            {
                if (f.EndsWith(".import")) continue;
                using var src = Godot.FileAccess.Open(resDir + f, Godot.FileAccess.ModeFlags.Read);
                if (src == null) continue;
                var buf = src.GetBuffer((long)src.GetLength());
                using var dst = Godot.FileAccess.Open(userDir + f, Godot.FileAccess.ModeFlags.Write);
                if (dst == null) continue;
                dst.StoreBuffer(buf);
            }
            if (System.IO.Directory.Exists(userReal))
            {
                OpenccNetLib.Opencc.UseDictionaryFromPath(userReal);
                TryCreateNormalizer();
            }
        }
        catch { }
    }

    /// <summary>
    /// 判断是否孤儿谱面（缺 song/album，或已被归入 __unknown 分组）。
    /// 关键：__unknown 前缀也算孤儿——否则首次归组后文档带非空 __unknown id，
    /// 后续重建会被误当正常文档，用其真实 album/song 子文档覆盖 Unknown 分组名。
    /// </summary>
    private static bool IsOrphanChart(string albumId, string songId)
    {
        if (string.IsNullOrEmpty(albumId) || string.IsNullOrEmpty(songId)) return true;
        if (albumId.StartsWith("__unknown") || songId.StartsWith("__unknown")) return true;
        return false;
    }

    /// <summary>
    /// 从全部 chart 文档重建 albums/songs 派生集合（幂等）。
    /// albums/songs 字段用 JSON 键名（AlbumData/SongData.from_json 直接消费），
    /// 另附聚合字段（song_ids/midi_ids/total_midi_count/earliest_uploaded_date）。
    /// 孤儿（缺 album 或 song）归入 __unknown_album__ / __unknown_song__。
    /// </summary>
    private void RebuildAlbumsSongs()
    {
        // 图表变更 → 规范化搜索副本缓存失效（song_name/author_name 可能被孤儿归组改写）
        _normCache.Clear();
        System.Threading.Interlocked.Increment(ref _normCacheGen); // 后台预热自取消世代号
        var albums = new Dictionary<string, BsonDocument>();
        var songs = new Dictionary<string, BsonDocument>();

        foreach (var doc in _charts.FindAll().ToList())
        {
            var albumId = BsonConvert.GetStr(doc, "album_id");
            var songId = BsonConvert.GetStr(doc, "song_id");
            if (IsOrphanChart(albumId, songId)) continue; // 孤儿单独处理

            if (!albums.ContainsKey(albumId))
            {
                var a = new BsonDocument { ["_id"] = albumId, ["song_ids"] = new BsonArray(), ["total_midi_count"] = (long)0, ["earliest_uploaded_date"] = "" };
                if (doc.TryGetValue("album", out var albumV) && albumV.IsDocument)
                {
                    var ab = albumV.AsDocument;
                    a["name"] = BsonConvert.GetStr(ab, "name");
                    a["abbr"] = BsonConvert.GetStr(ab, "abbr");
                    a["date"] = BsonConvert.GetStr(ab, "date");
                    a["description"] = BsonConvert.GetStr(ab, "description");
                    a["coverUrl"] = BsonConvert.GetStr(ab, "coverUrl");
                }
                albums[albumId] = a;
            }
            if (!songs.ContainsKey(songId))
            {
                var s = new BsonDocument { ["_id"] = songId, ["album_id"] = albumId, ["albumId"] = albumId, ["midi_ids"] = new BsonArray(), ["name"] = "", ["nameEn"] = "", ["track"] = (long)0, ["description"] = "" };
                if (doc.TryGetValue("song", out var songV) && songV.IsDocument)
                {
                    var sb = songV.AsDocument;
                    s["name"] = BsonConvert.GetStr(sb, "name");
                    s["nameEn"] = BsonConvert.GetStr(sb, "nameEn");
                    s["track"] = BsonConvert.GetLong(sb, "track");
                    s["description"] = BsonConvert.GetStr(sb, "description");
                }
                songs[songId] = s;
            }

            var albumDoc = albums[albumId];
            albumDoc["total_midi_count"] = albumDoc["total_midi_count"].AsInt64 + 1;
            var albumSongs = albumDoc["song_ids"].AsArray;
            bool hasSong = false;
            foreach (var x in albumSongs)
                if (x.IsString && x.AsString == songId) { hasSong = true; break; }
            if (!hasSong)
                albumSongs.Add(songId);
            var ud = BsonConvert.GetStr(doc, "uploaded_date");
            if (!string.IsNullOrEmpty(ud))
            {
                var cur = BsonConvert.GetStr(albumDoc, "earliest_uploaded_date");
                if (string.IsNullOrEmpty(cur) || string.CompareOrdinal(ud, cur) < 0)
                    albumDoc["earliest_uploaded_date"] = ud;
            }
            songs[songId]["midi_ids"].AsArray.Add(doc["_id"].AsString);
        }

        // 孤儿 → __unknown 分组（替代 DataManager._ensure_unknown_grouping）
        var unknownAlbum = new BsonDocument
        {
            ["_id"] = "__unknown_album__", ["name"] = "Unknown", ["abbr"] = "",
            ["date"] = "", ["description"] = "", ["coverUrl"] = "",
            ["song_ids"] = new BsonArray(), ["total_midi_count"] = (long)0, ["earliest_uploaded_date"] = ""
        };
        var unknownSong = new BsonDocument
        {
            ["_id"] = "__unknown_song__", ["name"] = "Unknown", ["nameEn"] = "",
            ["track"] = (long)0, ["album_id"] = "__unknown_album__", ["albumId"] = "__unknown_album__", ["description"] = "",
            ["midi_ids"] = new BsonArray()
        };
        var anyOrphan = false;
        foreach (var doc in _charts.FindAll().ToList())
        {
            var albumId = BsonConvert.GetStr(doc, "album_id");
            var songId = BsonConvert.GetStr(doc, "song_id");
            if (!IsOrphanChart(albumId, songId)) continue;
            anyOrphan = true;
            doc["album_id"] = "__unknown_album__";
            doc["album_name"] = "Unknown";
            doc["song_id"] = "__unknown_song__";
            doc["song_name"] = "Unknown";
            doc["sort_name"] = "Unknown\u0001Unknown\u0001" + BsonConvert.GetStr(doc, "name");
            _charts.Upsert(doc);
            unknownAlbum["total_midi_count"] = unknownAlbum["total_midi_count"].AsInt64 + 1;
            var us = unknownAlbum["song_ids"].AsArray;
            bool hasUnknownSong = false;
            foreach (var x in us)
                if (x.IsString && x.AsString == "__unknown_song__") { hasUnknownSong = true; break; }
            if (!hasUnknownSong)
                us.Add("__unknown_song__");
            unknownSong["midi_ids"].AsArray.Add(doc["_id"].AsString);
            var ud = BsonConvert.GetStr(doc, "uploaded_date");
            if (!string.IsNullOrEmpty(ud))
            {
                var cur = BsonConvert.GetStr(unknownAlbum, "earliest_uploaded_date");
                if (string.IsNullOrEmpty(cur) || string.CompareOrdinal(ud, cur) < 0)
                    unknownAlbum["earliest_uploaded_date"] = ud;
            }
        }
        if (anyOrphan)
        {
            albums["__unknown_album__"] = unknownAlbum;
            songs["__unknown_song__"] = unknownSong;
        }

        _db.DropCollection("albums");
        _db.DropCollection("songs");
        BindCollections();
        foreach (var kv in albums)
            _albums.Upsert(kv.Value);
        foreach (var kv in songs)
            _songs.Upsert(kv.Value);

        // 规范化缓存已清空 → 后台线程重填（词典就绪时；纯转换，不占主线程）
        if (_normT2S != null)
            PrewarmNormCache(_charts.FindAll().ToList());
    }
}
