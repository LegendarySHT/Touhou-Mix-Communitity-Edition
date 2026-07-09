using System.Collections.Concurrent;
using System.Collections.Generic;

/// <summary>
/// OnSendMessage 管道的共享状态。持有 MeltySynthPlayer 原有字典的引用（非拷贝），
/// 避免 handler 与 MeltySynthPlayer 其他方法之间的数据同步问题。
/// </summary>
internal sealed class MessageHandlerContext
{
	public readonly Dictionary<int, int> VirtualChannelCurrentBank;
	public readonly Dictionary<int, int> VirtualChannelCurrentProgram;
	public readonly Dictionary<int, int> VirtualChannelCc7;
	public readonly Dictionary<int, int> VirtualChannelCc11;
	public readonly Dictionary<int, int> VirtualChannelCc10;
	public readonly Dictionary<int, int> VirtualChannelPitchBend;
	public readonly Dictionary<int, (int bank, int program)> VirtualChannelInstruments;
	public readonly Dictionary<int, float> VirtualChannelVolumes;
	public readonly Dictionary<long, ManualFilterState> ManualNoteFilters;
	public readonly HashSet<int> MutedVirtualChannels;
	public readonly ConcurrentDictionary<int, byte> ChannelStateAppliedToManual;

	public const int ManualWildcardTick = -1;

	public MessageHandlerContext(
		Dictionary<int, int> virtualChannelCurrentBank,
		Dictionary<int, int> virtualChannelCurrentProgram,
		Dictionary<int, int> virtualChannelCc7,
		Dictionary<int, int> virtualChannelCc11,
		Dictionary<int, int> virtualChannelCc10,
		Dictionary<int, int> virtualChannelPitchBend,
		Dictionary<int, (int bank, int program)> virtualChannelInstruments,
		Dictionary<int, float> virtualChannelVolumes,
		Dictionary<long, ManualFilterState> manualNoteFilters,
		HashSet<int> mutedVirtualChannels,
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
		ManualNoteFilters = manualNoteFilters;
		MutedVirtualChannels = mutedVirtualChannels;
		ChannelStateAppliedToManual = channelStateAppliedToManual;
	}

	public static long MakeManualFilterKey(int virtualChannel, int pitch)
	{
		return ((long)virtualChannel << 32) | (uint)pitch;
	}
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
