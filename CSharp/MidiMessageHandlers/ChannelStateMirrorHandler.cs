using MeltySynth;

/// <summary>
/// 职责 1：虚拟通道状态镜像。
/// 将 CC/Bank/Program/PitchBend 写入对应字典，并失效 manual 标记。
/// 原始位置：MeltySynthPlayer.OnSendMessage 行 1425-1457。
/// </summary>
internal sealed class ChannelStateMirrorHandler : IMidiMessageHandler
{
	private readonly MessageHandlerContext _context;

	public ChannelStateMirrorHandler(MessageHandlerContext context)
	{
		_context = context;
	}

	public bool Process(Synthesizer synthesizer, int virtualChannel, ref int command, ref int data1, ref int data2, int tick)
	{
		if (command == 0xB0)
		{
			if (data1 == 0x00)
			{
				_context.VirtualChannelCurrentBank[virtualChannel] = data2;
				_context.ChannelStateAppliedToManual.TryRemove(virtualChannel, out _);
			}
			else if (data1 == 0x07)
			{
				_context.VirtualChannelCc7[virtualChannel] = data2;
				_context.ChannelStateAppliedToManual.TryRemove(virtualChannel, out _);
			}
			else if (data1 == 0x0B)
			{
				_context.VirtualChannelCc11[virtualChannel] = data2;
				_context.ChannelStateAppliedToManual.TryRemove(virtualChannel, out _);
			}
			else if (data1 == 0x0A)
			{
				_context.VirtualChannelCc10[virtualChannel] = data2;
				_context.ChannelStateAppliedToManual.TryRemove(virtualChannel, out _);
			}
		}
		else if (command == 0xC0)
		{
			_context.VirtualChannelCurrentProgram[virtualChannel] = data1;
			_context.ChannelStateAppliedToManual.TryRemove(virtualChannel, out _);
		}
		else if (command == 0xE0)
		{
			_context.VirtualChannelPitchBend[virtualChannel] = (data2 << 7) | data1;
			_context.ChannelStateAppliedToManual.TryRemove(virtualChannel, out _);
		}

		return true;
	}
}
