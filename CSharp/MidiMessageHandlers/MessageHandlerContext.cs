using System.Collections.Concurrent;
using System.Collections.Generic;

/// <summary>
/// OnSendMessage 管道的共享状态。持有 MeltySynthPlayer 原有字典的引用（非拷贝），
/// 避免 handler 与 MeltySynthPlayer 其他方法之间的数据同步问题。
/// </summary>
internal sealed class MessageHandlerContext
{
	public readonly ConcurrentDictionary<int, int> VirtualChannelCurrentBank;
	public readonly ConcurrentDictionary<int, int> VirtualChannelCurrentProgram;
	public readonly ConcurrentDictionary<int, int> VirtualChannelCc7;
	public readonly ConcurrentDictionary<int, int> VirtualChannelCc11;
	public readonly ConcurrentDictionary<int, int> VirtualChannelCc10;
	public readonly ConcurrentDictionary<int, int> VirtualChannelPitchBend;
	public readonly ConcurrentDictionary<int, (int bank, int program)> VirtualChannelInstruments;
	public readonly ConcurrentDictionary<int, float> VirtualChannelVolumes;
	public readonly ManualNoteFilterRegistry ManualFilterRegistry;
	public readonly ConcurrentDictionary<int, byte> MutedVirtualChannels;
	public readonly ConcurrentDictionary<int, byte> ChannelStateAppliedToManual;

	public const int ManualWildcardTick = -1;

	public MessageHandlerContext(
		ConcurrentDictionary<int, int> virtualChannelCurrentBank,
		ConcurrentDictionary<int, int> virtualChannelCurrentProgram,
		ConcurrentDictionary<int, int> virtualChannelCc7,
		ConcurrentDictionary<int, int> virtualChannelCc11,
		ConcurrentDictionary<int, int> virtualChannelCc10,
		ConcurrentDictionary<int, int> virtualChannelPitchBend,
		ConcurrentDictionary<int, (int bank, int program)> virtualChannelInstruments,
		ConcurrentDictionary<int, float> virtualChannelVolumes,
		ManualNoteFilterRegistry manualFilterRegistry,
		ConcurrentDictionary<int, byte> mutedVirtualChannels,
		ConcurrentDictionary<int, byte> channelStateAppliedToManual)
	{
		VirtualChannelCurrentBank = virtualChannelCurrentBank;
		VirtualChannelCurrentProgram = virtualChannelCurrentProgram;
		VirtualChannelCc7 = virtualChannelCc7;
		VirtualChannelCc11 = virtualChannelCc11;
		VirtualChannelCc10 = virtualChannelCc10;
		VirtualChannelPitchBend = virtualChannelPitchBend;
		VirtualChannelInstruments = virtualChannelInstruments;
		VirtualChannelVolumes = virtualChannelVolumes;
		ManualFilterRegistry = manualFilterRegistry;
		MutedVirtualChannels = mutedVirtualChannels;
		ChannelStateAppliedToManual = channelStateAppliedToManual;
	}

	public static long MakeManualFilterKey(int virtualChannel, int pitch)
	{
		return ((long)virtualChannel << 32) | (uint)pitch;
	}
}

/// <summary>
/// 手动音符过滤快照的 volatile 容器（TMX-005）。
/// 主线程构建新快照后一次性交换引用（volatile 写）；音频线程每条消息只读一次 Filters
/// （volatile 读），字典结构发布后不再修改，内部计数（ManualFilterState）仅音频线程改。
/// </summary>
internal sealed class ManualNoteFilterRegistry
{
	public volatile Dictionary<long, ManualFilterState> Filters = new Dictionary<long, ManualFilterState>();
}

/// <summary>
/// 手动音符过滤状态。从 MeltySynthPlayer 提取为独立 internal 类，
/// 以便 ManualNoteFilterHandler 在独立文件中访问。
/// </summary>
internal sealed class ManualFilterState
{
	public readonly Dictionary<int, int> PendingManualOnsByTick = new Dictionary<int, int>();
	public int ActiveManualNotes;
}
