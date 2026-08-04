using Godot;
using LiteDB;
using System;

/// <summary>
/// BsonValue ↔ Godot Variant 递归转换
/// 仅处理 JSON 兼容类型（null/bool/long/double/string/Dictionary/Array），
/// 引擎类型（Vector2 等）从不存储到 DB。
///
/// LiteDB 5：BsonDocument = Dictionary&lt;string,BsonValue&gt;，BsonArray = List&lt;BsonValue&gt;，
/// 标量用隐式转换构造（无 BsonString/BsonInt64 等具体类）；读缺失键会抛异常，须 TryGetValue。
/// </summary>
public static class BsonConvert
{
    public static BsonValue VariantToBson(Godot.Variant v)
    {
        switch (v.VariantType)
        {
            case Godot.Variant.Type.Nil:
                return BsonValue.Null;
            case Godot.Variant.Type.Bool:
                return v.AsBool();
            case Godot.Variant.Type.Int:
                return v.AsInt64();
            case Godot.Variant.Type.Float:
                return v.AsDouble();
            case Godot.Variant.Type.String:
                return v.AsString();
            case Godot.Variant.Type.Dictionary:
            {
                var gd = v.AsGodotDictionary();
                var bd = new BsonDocument();
                foreach (var key in gd.Keys)
                    bd[key.AsString()] = VariantToBson(gd[key]);
                return bd;
            }
            case Godot.Variant.Type.Array:
            {
                var gd = v.AsGodotArray();
                var ba = new BsonArray();
                foreach (var item in gd)
                    ba.Add(VariantToBson(item));
                return ba;
            }
            case Godot.Variant.Type.PackedStringArray:
            {
                var ba = new BsonArray();
                foreach (var s in v.AsStringArray())
                    ba.Add(s);
                return ba;
            }
            default:
                return BsonValue.Null;
        }
    }

    public static Godot.Variant BsonToVariant(BsonValue b)
    {
        if (b.IsNull)
            return default;
        if (b.IsString)
            return b.AsString;
        if (b.IsBoolean)
            return b.AsBoolean;
        if (b.IsInt32)
            return b.AsInt32;
        if (b.IsInt64)
            return b.AsInt64;
        if (b.IsDouble || b.IsDecimal)
            return b.AsDouble;
        if (b.IsDocument)
        {
            var gd = new Godot.Collections.Dictionary();
            foreach (var kv in b.AsDocument)
                gd[kv.Key] = BsonToVariant(kv.Value);
            return gd;
        }
        if (b.IsArray)
        {
            var gd = new Godot.Collections.Array();
            foreach (var item in b.AsArray)
                gd.Add(BsonToVariant(item));
            return gd;
        }
        return default;
    }

    public static Godot.Collections.Dictionary BsonToGodotDict(BsonDocument doc)
    {
        var gd = new Godot.Collections.Dictionary();
        foreach (var kv in doc)
            gd[kv.Key] = BsonToVariant(kv.Value);
        return gd;
    }

    public static string GetStr(BsonDocument d, string key, string def = "")
    {
        if (d == null) return def;
        if (!d.TryGetValue(key, out var v)) return def;
        return v.IsString ? v.AsString : def;
    }

    public static long GetLong(BsonDocument d, string key, long def = 0)
    {
        if (d == null) return def;
        if (!d.TryGetValue(key, out var v)) return def;
        if (v.IsInt64) return v.AsInt64;
        if (v.IsInt32) return v.AsInt32;
        if (v.IsDouble) return (long)v.AsDouble;
        return def;
    }

    public static double GetDouble(BsonDocument d, string key, double def = 0)
    {
        if (d == null) return def;
        if (!d.TryGetValue(key, out var v)) return def;
        if (v.IsDouble) return v.AsDouble;
        if (v.IsInt32) return v.AsInt32;
        if (v.IsInt64) return v.AsInt64;
        return def;
    }
}
