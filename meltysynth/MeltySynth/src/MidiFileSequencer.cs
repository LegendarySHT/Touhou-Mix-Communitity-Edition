using System;
using System.Diagnostics;

namespace MeltySynth
{
    /// <summary>
    /// An instance of the MIDI file sequencer.
    /// </summary>
    /// <remarks>
    /// Note that this class does not provide thread safety.
    /// If you want to control playback and render the waveform in separate threads,
    /// you must make sure that the methods are not called at the same time.
    /// </remarks>
    public sealed class MidiFileSequencer : IAudioRenderer
    {
        private readonly Synthesizer synthesizer;

        private float speed;

        private MidiFile? midiFile;
        private bool loop;

        private int blockWrote;

        private TimeSpan currentTime;
        private int msgIndex;
        private int loopIndex;

        private bool useSystemClock;
        private bool isPaused;
        private long clockBaseTimestamp;
        private TimeSpan clockBasePosition;
        private TimeSpan pausePosition;
        private TimeSpan renderedTime;

        private bool diagnosticsEnabled;
        private double driftEmaMs;
        private double maxAbsDriftMs;
        private double latestDriftMs;
        private int driftSampleCount;

        private MessageHook? onSendMessage;

        /// <summary>
        /// Initializes a new instance of the sequencer.
        /// </summary>
        /// <param name="synthesizer">The synthesizer to be used by the sequencer.</param>
        public MidiFileSequencer(Synthesizer synthesizer)
        {
            if (synthesizer == null)
            {
                throw new ArgumentNullException(nameof(synthesizer));
            }

            this.synthesizer = synthesizer;

            speed = 1F;
            useSystemClock = false;
            isPaused = false;
            diagnosticsEnabled = false;
        }

        /// <summary>
        /// Plays the MIDI file.
        /// </summary>
        /// <param name="midiFile">The MIDI file to be played.</param>
        /// <param name="loop">If <c>true</c>, the MIDI file loops after reaching the end.</param>
        public void Play(MidiFile midiFile, bool loop)
        {
            if (midiFile == null)
            {
                throw new ArgumentNullException(nameof(midiFile));
            }

            this.midiFile = midiFile;
            this.loop = loop;

            blockWrote = synthesizer.BlockSize;

            currentTime = TimeSpan.Zero;
            msgIndex = 0;
            loopIndex = 0;
            pausePosition = TimeSpan.Zero;
            clockBasePosition = TimeSpan.Zero;
            clockBaseTimestamp = Stopwatch.GetTimestamp();
            renderedTime = TimeSpan.Zero;
            isPaused = false;
            ResetDiagnostics();

            synthesizer.Reset();
        }

        /// <summary>
        /// Stops playing.
        /// </summary>
        public void Stop()
        {
            midiFile = null;
            isPaused = false;
            currentTime = TimeSpan.Zero;
            pausePosition = TimeSpan.Zero;
            clockBasePosition = TimeSpan.Zero;
            renderedTime = TimeSpan.Zero;

            synthesizer.Reset();
        }

        /// <summary>
        /// Sets whether the sequencer position is driven by system clock.
        /// </summary>
        /// <param name="enabled">If <c>true</c>, system clock mode is enabled.</param>
        public void SetSystemClockMode(bool enabled)
        {
            if (useSystemClock == enabled)
            {
                return;
            }

            var position = Position;
            useSystemClock = enabled;
            currentTime = position;
            pausePosition = position;
            clockBasePosition = position;
            clockBaseTimestamp = Stopwatch.GetTimestamp();
            renderedTime = position;
        }

        /// <summary>
        /// Seeks to the specified playback position.
        /// </summary>
        /// <param name="position">Target position.</param>
        public void Seek(TimeSpan position)
        {
            if (midiFile == null)
            {
                return;
            }

            if (position < TimeSpan.Zero)
            {
                position = TimeSpan.Zero;
            }

            if (position > midiFile.Length)
            {
                position = midiFile.Length;
            }

            currentTime = position;
            pausePosition = position;
            clockBasePosition = position;
            clockBaseTimestamp = Stopwatch.GetTimestamp();

            var nextIndex = 0;
            var latestLoopIndex = 0;
            while (nextIndex < midiFile.Messages.Length)
            {
                if (midiFile.Times[nextIndex] >= position)
                {
                    break;
                }

                nextIndex++;
            }

            synthesizer.Reset();

            for (var i = 0; i < nextIndex; i++)
            {
                var msg = midiFile.Messages[i];
                if (msg.Type == MidiFile.MessageType.Normal)
                {
                    SendMessage(msg, midiFile.Ticks[i]);
                }
                else if (loop && msg.Type == MidiFile.MessageType.LoopStart)
                {
                    latestLoopIndex = i;
                }
            }

            msgIndex = nextIndex;
            loopIndex = latestLoopIndex;
            blockWrote = synthesizer.BlockSize;
        }

        /// <summary>
        /// Pauses playback time progression.
        /// </summary>
        public void Pause()
        {
            if (midiFile == null || isPaused)
            {
                return;
            }

            pausePosition = Position;
            currentTime = pausePosition;
            renderedTime = pausePosition;
            isPaused = true;
        }

        /// <summary>
        /// Resumes playback time progression from paused position.
        /// </summary>
        public void Resume()
        {
            if (midiFile == null || !isPaused)
            {
                return;
            }

            currentTime = pausePosition;
            clockBasePosition = pausePosition;
            clockBaseTimestamp = Stopwatch.GetTimestamp();
            isPaused = false;
        }

        /// <inheritdoc/>
        public void Render(Span<float> left, Span<float> right)
        {
            if (left.Length != right.Length)
            {
                throw new ArgumentException("The output buffers for the left and right must be the same length.");
            }

            var wrote = 0;
            while (wrote < left.Length)
            {
                if (blockWrote == synthesizer.BlockSize)
                {
                    if (useSystemClock)
                    {
                        if (!isPaused)
                        {
                            currentTime = GetSystemClockPosition();
                            if (diagnosticsEnabled)
                            {
                                var driftMs = (currentTime - renderedTime).TotalMilliseconds;
                                UpdateDiagnostics(driftMs);
                            }
                        }
                        ProcessEvents();
                    }
                    else
                    {
                        ProcessEvents();
                        if (!isPaused)
                        {
                            currentTime += MidiFile.GetTimeSpanFromSeconds((double)speed * synthesizer.BlockSize / synthesizer.SampleRate);
                        }
                    }

                    blockWrote = 0;
                }

                var srcRem = synthesizer.BlockSize - blockWrote;
                var dstRem = left.Length - wrote;
                var rem = Math.Min(srcRem, dstRem);

                synthesizer.Render(left.Slice(wrote, rem), right.Slice(wrote, rem));

                blockWrote += rem;
                wrote += rem;

                if (!isPaused)
                {
                    renderedTime += MidiFile.GetTimeSpanFromSeconds((double)speed * rem / synthesizer.SampleRate);
                }
            }
        }

        private void ProcessEvents()
        {
            if (midiFile == null)
            {
                return;
            }

            while (msgIndex < midiFile.Messages.Length)
            {
                var time = midiFile.Times[msgIndex];
                var tick = midiFile.Ticks[msgIndex];
                var msg = midiFile.Messages[msgIndex];
                if (time <= currentTime)
                {
                    if (msg.Type == MidiFile.MessageType.Normal)
                    {
                        SendMessage(msg, tick);
                    }
                    else if (loop)
                    {
                        if (msg.Type == MidiFile.MessageType.LoopStart)
                        {
                            loopIndex = msgIndex;
                        }
                        else if (msg.Type == MidiFile.MessageType.LoopEnd)
                        {
                            currentTime = midiFile.Times[loopIndex];
                            msgIndex = loopIndex;
                            synthesizer.NoteOffAll(false);

                            if (useSystemClock && !isPaused)
                            {
                                clockBasePosition = currentTime;
                                clockBaseTimestamp = Stopwatch.GetTimestamp();
                            }
                        }
                    }
                    msgIndex++;
                }
                else
                {
                    break;
                }
            }

            if (msgIndex == midiFile.Messages.Length && loop)
            {
                currentTime = midiFile.Times[loopIndex];
                msgIndex = loopIndex;
                synthesizer.NoteOffAll(false);

                if (useSystemClock && !isPaused)
                {
                    clockBasePosition = currentTime;
                    clockBaseTimestamp = Stopwatch.GetTimestamp();
                }
            }
        }

        private void SendMessage(MidiFile.Message msg, int tick)
        {
            var virtualChannel = synthesizer.GetVirtualChannelId(msg.TrackIndex, msg.Channel);
            if (onSendMessage == null)
            {
                synthesizer.ProcessMidiMessage(virtualChannel, msg.Command, msg.Data1, msg.Data2);
            }
            else
            {
                onSendMessage(synthesizer, virtualChannel, msg.Command, msg.Data1, msg.Data2, tick);
            }
        }


        private TimeSpan GetSystemClockPosition()
        {
            var elapsedTicks = Stopwatch.GetTimestamp() - clockBaseTimestamp;
            if (elapsedTicks <= 0)
            {
                return clockBasePosition;
            }

            var elapsedSeconds = elapsedTicks / (double)Stopwatch.Frequency;
            var scaledSeconds = elapsedSeconds * speed;
            var position = clockBasePosition + MidiFile.GetTimeSpanFromSeconds(scaledSeconds);

            if (midiFile != null && !loop && position > midiFile.Length)
            {
                return midiFile.Length;
            }

            return position;
        }

        private void ResetDiagnostics()
        {
            driftEmaMs = 0.0;
            maxAbsDriftMs = 0.0;
            latestDriftMs = 0.0;
            driftSampleCount = 0;
        }

        private void UpdateDiagnostics(double driftMs)
        {
            latestDriftMs = driftMs;
            var absDrift = Math.Abs(driftMs);
            if (absDrift > maxAbsDriftMs)
            {
                maxAbsDriftMs = absDrift;
            }

            const double alpha = 0.1;
            if (driftSampleCount == 0)
            {
                driftEmaMs = driftMs;
            }
            else
            {
                driftEmaMs = driftEmaMs + alpha * (driftMs - driftEmaMs);
            }

            driftSampleCount++;
        }
        /// <summary>
        /// Gets the synthesizer used by the sequencer.
        /// </summary>
        public Synthesizer Synthesizer => synthesizer;

        /// <summary>
        /// Gets the currently playing MIDI file.
        /// </summary>
        public MidiFile? MidiFile => midiFile;

        /// <summary>
        /// Gets the current playback position.
        /// </summary>
        public TimeSpan Position
        {
            get
            {
                if (midiFile == null)
                {
                    return currentTime;
                }

                if (useSystemClock && !isPaused)
                {
                    return GetSystemClockPosition();
                }

                return currentTime;
            }
        }

        /// <summary>
        /// Gets a value that indicates whether the current playback position is at the end of the sequence.
        /// </summary>
        /// <remarks>
        /// If the <see cref="Play(MidiFile, bool)">Play</see> method has not yet been called, this value is true.
        /// This value will never be <c>true</c> when loop playback is enabled.
        /// </remarks>
        public bool EndOfSequence
        {
            get
            {
                if (midiFile == null)
                {
                    return true;
                }
                else
                {
                    return msgIndex == midiFile.Messages.Length;
                }
            }
        }

        /// <summary>
        /// Gets or sets the playback speed.
        /// </summary>
        /// <remarks>
        /// The default value is 1.
        /// The tempo will be multiplied by this value.
        /// </remarks>
        public float Speed
        {
            get => speed;

            set
            {
                if (value >= 0)
                {
                    if (useSystemClock && midiFile != null && !isPaused)
                    {
                        currentTime = GetSystemClockPosition();
                        clockBasePosition = currentTime;
                        clockBaseTimestamp = Stopwatch.GetTimestamp();
                    }

                    speed = value;
                }
                else
                {
                    throw new ArgumentOutOfRangeException("The playback speed must be a non-negative value.");
                }
            }
        }

        /// <summary>
        /// Gets a value indicating whether system clock mode is enabled.
        /// </summary>
        public bool UseSystemClock => useSystemClock;

        /// <summary>
        /// Gets a value indicating whether the sequencer is paused.
        /// </summary>
        public bool IsPaused => isPaused;

        /// <summary>
        /// Enables or disables runtime drift diagnostics.
        /// </summary>
        public void SetDiagnosticsEnabled(bool enabled)
        {
            diagnosticsEnabled = enabled;
            if (!enabled)
            {
                ResetDiagnostics();
            }
        }

        /// <summary>
        /// Gets drift diagnostics between system-clock target time and rendered sample time.
        /// </summary>
        public string GetDiagnosticsSnapshot()
        {
            return $"samples={driftSampleCount}, latest={latestDriftMs:F3}ms, ema={driftEmaMs:F3}ms, maxAbs={maxAbsDriftMs:F3}ms";
        }

        /// <summary>
        /// Gets or sets the method for modifying MIDI messages during playback.
        /// If <c>null</c>, MIDI messages are sent to the synthesizer without any changes.
        /// </summary>
        public MessageHook? OnSendMessage
        {
            get => onSendMessage;
            set => onSendMessage = value;
        }



        /// <summary>
        /// Represents the method that is called each time a MIDI message is processed during playback.
        /// </summary>
        /// <param name="synthesizer">The synthesizer used by the sequencer.</param>
        /// <param name="channel">The channel to which the message will be sent.</param>
        /// <param name="command">The type of the message.</param>
        /// <param name="data1">The first data part of the message.</param>
        /// <param name="data2">The second data part of the message.</param>
        /// <param name="tick">The absolute MIDI tick of the message.</param>
        public delegate void MessageHook(Synthesizer synthesizer, int channel, int command, int data1, int data2, int tick);
    }
}
