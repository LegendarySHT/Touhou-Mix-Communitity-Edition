using MeltySynth;

/// <summary>
/// 职责 6：转发合成器。
/// 管道末端：将处理后的 MIDI 消息转发到自动合成器。
/// 原始位置：MeltySynthPlayer.OnSendMessage 行 1533。
/// </summary>
internal sealed class SynthForwarderHandler : IMidiMessageHandler
{
	public bool Process(Synthesizer synthesizer, int virtualChannel, ref int command, ref int data1, ref int data2, int tick)
	{
		synthesizer.ProcessMidiMessage(virtualChannel, command, data1, data2);
		return true;
	}
}
