using MeltySynth;

/// <summary>
/// 职责 2：手动音符过滤。
/// 拦截被手动触发的音符，转发到 _manualSynth（由 MeltySynthPlayer.ApplyChannelStateToManual 处理）。
/// 命中则 return false 终止管道（不传递给自动合成器）。
/// 原始位置：MeltySynthPlayer.OnSendMessage 行 1459-1491。
/// </summary>
internal sealed class ManualNoteFilterHandler : IMidiMessageHandler
{
	private readonly MessageHandlerContext _context;

	public ManualNoteFilterHandler(MessageHandlerContext context)
	{
		_context = context;
	}

	public bool Process(Synthesizer synthesizer, int virtualChannel, ref int command, ref int data1, ref int data2, int tick)
	{
		var isNoteOn = command == 0x90 && data2 > 0;
		var isNoteOff = command == 0x80 || (command == 0x90 && data2 == 0);
		if (isNoteOn || isNoteOff)
		{
			var key = MessageHandlerContext.MakeManualFilterKey(virtualChannel, data1);
			if (_context.ManualNoteFilters.TryGetValue(key, out var state))
			{
				if (isNoteOn)
				{
					var exactCount = state.PendingManualOnsByTick.ContainsKey(tick) ? state.PendingManualOnsByTick[tick] : 0;
					if (exactCount > 0)
					{
						state.PendingManualOnsByTick[tick] = exactCount - 1;
						state.ActiveManualNotes += 1;
						return false;
					}

					var wildcardCount = state.PendingManualOnsByTick.ContainsKey(MessageHandlerContext.ManualWildcardTick) ? state.PendingManualOnsByTick[MessageHandlerContext.ManualWildcardTick] : 0;
					if (wildcardCount > 0)
					{
						state.PendingManualOnsByTick[MessageHandlerContext.ManualWildcardTick] = wildcardCount - 1;
						state.ActiveManualNotes += 1;
						return false;
					}
				}

				if (isNoteOff && state.ActiveManualNotes > 0)
				{
					state.ActiveManualNotes -= 1;
					return false;
				}
			}
		}

		return true;
	}
}
