import com.sun.media.sound.AudioSynthesizer;
import java.nio.file.*;
import java.util.*;
import javax.sound.midi.*;
import javax.sound.sampled.*;

/** Offline melody conversion using the JDK's generated default soundbank. */
public final class RenderMidi {

  public static void main(String[] args) throws Exception {
    Sequence sequence = MidiSystem.getSequence(Path.of(args[0]).toFile());
    if (sequence.getDivisionType() != Sequence.PPQ) throw new IllegalArgumentException(
      "Expected PPQ MIDI"
    );
    AudioSynthesizer synth = (AudioSynthesizer) MidiSystem.getSynthesizer();
    AudioFormat format = new AudioFormat(44100, 16, 2, true, false);
    try (AudioInputStream stream = synth.openStream(format, Map.of("interpolation", "sinc"))) {
      List<MidiEvent> events = new ArrayList<>();
      for (Track track : sequence.getTracks())
        for (int i = 0; i < track.size(); i++) events.add(track.get(i));
      events.sort(Comparator.comparingLong(MidiEvent::getTick));
      long previousTick = 0;
      double micros = 0;
      int tempo = 500000;
      Receiver receiver = synth.getReceiver();
      for (MidiEvent event : events) {
        micros += ((event.getTick() - previousTick) * (double) tempo) / sequence.getResolution();
        previousTick = event.getTick();
        MidiMessage message = event.getMessage();
        if (message instanceof MetaMessage meta && meta.getType() == 0x51) {
          byte[] data = meta.getData();
          tempo = ((data[0] & 255) << 16) | ((data[1] & 255) << 8) | (data[2] & 255);
        } else if (!(message instanceof MetaMessage)) {
          receiver.send(message, Math.round(micros));
        }
      }
      long frames = (long) ((micros / 1_000_000 + 2) * format.getFrameRate());
      try (AudioInputStream limited = new AudioInputStream(stream, format, frames)) {
        AudioSystem.write(limited, AudioFileFormat.Type.WAVE, Path.of(args[1]).toFile());
      }
    } finally {
      synth.close();
    }
  }
}
