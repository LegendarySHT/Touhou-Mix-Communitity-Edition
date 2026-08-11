using MeltySynth;

/// <summary>
/// 职责 3：静音过滤。
/// 静音通道的 NoteOn 直接 return false 终止管道。
/// 原始位置：MeltySynthPlayer.OnSendMessage 行 1493-1496。
/// </summary>
internal sealed class MuteFilterHandler : IMidiMessageHandler
{
	private readonly MessageHandlerContext _context;

	public MuteFilterHandler(MessageHandlerContext context)
	{
		_context = context;
	}

	public bool Process(Synthesizer synthesizer, int virtualChannel, ref int command, ref int data1, ref int data2, int tick)
	{
		if (_context.MutedVirtualChannels.ContainsKey(virtualChannel) && command == 0x90 && data2 > 0)
		{
			return false;
		}

		return true;
	}
}
