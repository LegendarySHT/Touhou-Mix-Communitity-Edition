using MeltySynth;

/// <summary>
/// 职责 4：乐器覆盖拦截。
/// 对 MIDI 文件中的 Bank Change (0xB0 0x00) 和 Program Change (0xC0) 进行覆盖。
/// 修改 data1/data2 为用户配置的乐器值。
/// 原始位置：MeltySynthPlayer.OnSendMessage 行 1498-1521。
/// </summary>
internal sealed class InstrumentOverrideHandler : IMidiMessageHandler
{
	private readonly MessageHandlerContext _context;

	public InstrumentOverrideHandler(MessageHandlerContext context)
	{
		_context = context;
	}

	public bool Process(Synthesizer synthesizer, int virtualChannel, ref int command, ref int data1, ref int data2, int tick)
	{
		if (_context.VirtualChannelInstruments.TryGetValue(virtualChannel, out var instrument))
		{
			if (command == 0xB0 && data1 == 0x00)
			{
				// Bank Change (0xB0 0x00)
				data2 = instrument.bank;
			}
			else if (command == 0xC0)
			{
				// Program Change (0xC0)
				data1 = instrument.program;
			}
		}

		return true;
	}
}
