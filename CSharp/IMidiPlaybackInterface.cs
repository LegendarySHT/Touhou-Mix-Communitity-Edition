using Godot;
using System;

namespace TouhouMix.Midi
{
	/// <summary>
	/// MIDI 播放后端接口 - C# 版本
	/// 
	/// 此接口镜像 GDScript 中的 MidiPlaybackInterface，
	/// 用于确保 C# 后端实现与 GDScript 后端保持一致的 API。
	/// 
	/// 所有继承此接口的 MIDI 播放器必须实现以下所有方法。
	/// </summary>
	public interface IMidiPlaybackInterface
	{
		// ===================== 基本控制 =====================
		
		/// <summary>加载 MIDI 文件</summary>
		/// <param name="filePath">MIDI 文件路径</param>
		/// <returns>加载成功返回 true</returns>
		bool load_midi(string filePath);
		
		/// <summary>播放</summary>
		void play();
		
		/// <summary>暂停</summary>
		void pause();
		
		/// <summary>恢复播放</summary>
		void resume();
		
		/// <summary>停止</summary>
		void stop();
		
		/// <summary>跳转到指定位置（毫秒）</summary>
		/// <param name="positionMs">目标位置（毫秒）</param>
		void seek(float positionMs);
		
		// ===================== 配置相关 =====================
		
		/// <summary>设置音源文件</summary>
		/// <param name="soundfontPath">SoundFont 文件路径</param>
		/// <returns>设置成功返回 true</returns>
		bool set_soundfont(string soundfontPath);
		
		/// <summary>设置主音量（dB）</summary>
		/// <param name="volumeDb">音量值（分贝）</param>
		void set_volume_db(float volumeDb);
		
		/// <summary>设置特定轨道通道的音量（线性值，0.0-1.0）</summary>
		/// <param name="trackIndex">轨道索引</param>
		/// <param name="channel">MIDI 通道</param>
		/// <param name="volumeLinear">线性音量值（0.0-1.0）</param>
		void set_track_channel_volume(int trackIndex, int channel, float volumeLinear);
		
		/// <summary>获取特定轨道通道的音量</summary>
		/// <param name="trackIndex">轨道索引</param>
		/// <param name="channel">MIDI 通道</param>
		/// <returns>线性音量值（0.0-1.0）</returns>
		float get_track_channel_volume(int trackIndex, int channel);
		
		/// <summary>设置轨道通道的乐器</summary>
		/// <param name="trackIndex">轨道索引</param>
		/// <param name="channel">MIDI 通道</param>
		/// <param name="bank">Bank 编号</param>
		/// <param name="program">Program 编号</param>
		void set_track_channel_instrument(int trackIndex, int channel, int bank, int program);
		
		/// <summary>获取轨道通道的乐器</summary>
		/// <param name="trackIndex">轨道索引</param>
		/// <param name="channel">MIDI 通道</param>
		/// <returns>包含 "bank" 和 "program" 键的字典</returns>
		Godot.Collections.Dictionary get_track_channel_instrument(int trackIndex, int channel);
		
		// ===================== 状态查询 =====================
		
		/// <summary>获取当前播放位置（毫秒）</summary>
		/// <returns>播放位置（毫秒）</returns>
		float get_position_ms();
		
		/// <summary>获取当前播放位置（tick）</summary>
		/// <returns>播放位置（tick）</returns>
		float get_position_tick();
		
		/// <summary>获取总时长（毫秒）</summary>
		/// <returns>总时长（毫秒）</returns>
		float get_duration_ms();
		
		/// <summary>检查是否正在播放</summary>
		/// <returns>正在播放返回 true</returns>
		bool is_playing();
		
		// ===================== 高级功能 =====================
		
		/// <summary>设置静音状态</summary>
		/// <param name="trackIndex">轨道索引</param>
		/// <param name="channel">MIDI 通道</param>
		/// <param name="muted">是否静音</param>
		void set_track_channel_mute(int trackIndex, int channel, bool muted);
		
		/// <summary>手动触发 Note On</summary>
		/// <param name="pitch">音高</param>
		/// <param name="velocity">力度</param>
		/// <param name="channel">MIDI 通道</param>
		void trigger_note_on(int pitch, int velocity, int channel);
		
		/// <summary>手动触发 Note Off</summary>
		/// <param name="pitch">音高</param>
		/// <param name="velocity">力度</param>
		/// <param name="channel">MIDI 通道</param>
		void trigger_note_off(int pitch, int velocity, int channel);
		
		/// <summary>获取可用乐器列表</summary>
		/// <returns>乐器列表</returns>
		Godot.Collections.Array get_presets_list();
		
		/// <summary>获取乐器名称</summary>
		/// <param name="program">Program 编号</param>
		/// <param name="bank">Bank 编号（默认0）</param>
		/// <returns>乐器名称</returns>
		string get_preset_name(int program, int bank = 0);
		
		/// <summary>设置手动控制的 note 列表</summary>
		/// <param name="manuallyControlled">格式：{channel: {pitch: true}}</param>
		void set_manually_controlled_notes(Godot.Collections.Dictionary manuallyControlled);
		
		// ===================== 信号 =====================
		// 注意：C# 中的信号需要在实现类中使用 [Signal] 特性声明
		// signal finished
		// signal soundfont_changed(soundfont_path: String)
	}
}
