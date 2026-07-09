using System;
using MeltySynth;

/// <summary>
/// 职责 5：音量缩放。
/// NoteOn velocity 按通道音量缩放。若缩放后为 0 则 return false 终止管道。
/// 原始位置：MeltySynthPlayer.OnSendMessage 行 1523-1531。
/// </summary>
internal sealed class VolumeScaleHandler : IMidiMessageHandler
{
	private readonly MessageHandlerContext _context;

	public VolumeScaleHandler(MessageHandlerContext context)
	{
		_context = context;
	}

	public bool Process(Synthesizer synthesizer, int virtualChannel, ref int command, ref int data1, ref int data2, int tick)
	{
		if (command == 0x90 && data2 > 0)
		{
			var volume = _context.VirtualChannelVolumes.TryGetValue(virtualChannel, out var vol) ? vol : 1.0f;
			data2 = Math.Clamp((int)Math.Round(data2 * volume), 0, 127);
			if (data2 == 0)
			{
				return false;
			}
		}

		return true;
	}
}
