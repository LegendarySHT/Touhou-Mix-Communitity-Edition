using MeltySynth;

/// <summary>
/// MIDI 消息处理器接口。返回 false 终止管道（不再传递给后续 handler）。
/// 可通过 ref 参数修改 command/data1/data2。
/// </summary>
internal interface IMidiMessageHandler
{
	bool Process(Synthesizer synthesizer, int virtualChannel, ref int command, ref int data1, ref int data2, int tick);
}
