import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javax.imageio.ImageIO;

/** Exports the original map renderer's active cycle and completed-action sprite. */
public final class Chapter1MapAssets {

  private Chapter1MapAssets() {}

  public static void export(Object game, ClassLoader loader, Path output)
    throws ReflectiveOperationException, IOException {
    Class<?> sprite = Class.forName("g", true, loader);
    Object raw = get(game, "as");
    if (!(raw instanceof List<?> units) || units.size() != 32) {
      throw new IllegalArgumentException("Expected a verified 32-unit deployment");
    }
    Object[][] templates = (Object[][]) get(game, "V");
    Method mapClass = game.getClass().getMethod("r", int.class);
    Map<String, Object> definitions = new LinkedHashMap<>();
    for (Object unit : units) {
      int id = number(unit, "y");
      int group = number(unit, "R");
      int faction = number(unit, "C");
      int mapped = ((Number) mapClass.invoke(null, group)).intValue();
      Object completed = templates[faction == 2 ? 1 : 0][mapped];
      Map<String, Object> definition = new LinkedHashMap<>();
      definition.put("deploymentId", id);
      definition.put("classId", number(unit, "S"));
      definition.put("faction", faction);
      definition.put("logicalTileSize", 24);
      definition.put("canvasWidth", 64);
      definition.put("canvasHeight", 64);
      definition.put("spriteOffsetX", -24);
      definition.put("spriteOffsetY", -24);
      List<Object> frames = exportCycle(unit, sprite, output, "map_units/unit_" + id + "/active");
      List<Integer> sequence = new ArrayList<>();
      for (int index = 0; index < frames.size(); index++) sequence.add(index);
      definition.put("frames", frames);
      definition.put("idleSequence", sequence);
      definition.put("walkSequence", new ArrayList<>(sequence));
      definition.put("idleStepSeconds", 0.39);
      definition.put("walkStepSeconds", 0.39);
      definition.put(
        "completedFrame",
        exportCycle(completed, sprite, output, "map_units/unit_" + id + "/completed").get(0)
      );
      definition.put("directionalAnimation", false);
      definitions.put(String.valueOf(id), definition);
    }
    Map<String, Object> manifest = new LinkedHashMap<>();
    manifest.put("schemaVersion", 1);
    manifest.put("chapterId", "chapter_1");
    manifest.put("texturePathsRelativeTo", "map_animations.json");
    manifest.put(
      "timing",
      "Original b.a uses 300 logical units: six 50-unit map updates at the 65ms target frame period; nominal 0.39 seconds"
    );
    manifest.put(
      "completedPolicy",
      "al=2 uses the native V[0/1] static completed-action palette; no active cycle"
    );
    manifest.put("units", definitions);
    Files.createDirectories(output);
    Files.writeString(output.resolve("map_animations.json"), Chapter1Rules.json(manifest) + "\n");
  }

  private static List<Object> exportCycle(
    Object original,
    Class<?> sprite,
    Path output,
    String prefix
  ) throws ReflectiveOperationException, IOException {
    if (original == null) throw new IllegalArgumentException(
      "Missing original map sprite " + prefix
    );
    Object copy = copySprite(original, sprite, new IdentityHashMap<>());
    field(sprite, "av").setInt(copy, 0);
    field(sprite, "aw").setInt(copy, 0);
    field(sprite, "aK").setInt(copy, -1); // No transient shake in the source definition.
    byte[] sequence = ((byte[]) get(copy, "aV")).clone();
    Object[] physicalFrames = (Object[]) get(copy, "ap");
    if (sequence.length == 0) throw new IllegalArgumentException("Empty map sequence " + prefix);
    Method draw = sprite.getMethod(
      "a",
      javax.microedition.lcdui.Graphics.class,
      int.class,
      int.class
    );
    List<Object> result = new ArrayList<>();
    for (int index = 0; index < sequence.length; index++) {
      int sourceFrame = sequence[index] & 255;
      if (sourceFrame >= physicalFrames.length) throw new IllegalArgumentException(
        "Invalid map frame " + prefix
      );
      field(sprite, "aq").setInt(copy, index);
      var image = javax.microedition.lcdui.Image.createRGBImage(new int[64 * 64], 64, 64, true);
      image.setMutable(true);
      draw.invoke(copy, image.getGraphics(), 24, 24);
      String path = prefix + "_" + index + ".png";
      Path destination = output.resolve(path);
      Files.createDirectories(destination.getParent());
      ImageIO.write(image.getCanvas(), "png", destination.toFile());
      Object frame = physicalFrames[sourceFrame];
      Map<String, Object> metadata = new LinkedHashMap<>();
      metadata.put("texture", path);
      metadata.put("sourceFrame", sourceFrame);
      metadata.put("sourceOffsetX", number(frame, "e"));
      metadata.put("sourceOffsetY", number(frame, "f"));
      metadata.put("sourceWidth", number(frame, "c"));
      metadata.put("sourceHeight", number(frame, "d"));
      metadata.put("originalFlag", number(frame, "g"));
      result.add(metadata);
    }
    return result;
  }

  private static Object copySprite(Object original, Class<?> sprite, Map<Object, Object> copies)
    throws ReflectiveOperationException {
    if (original == null) return null;
    if (copies.containsKey(original)) return copies.get(original);
    if (number(original, "ar") != 0) {
      throw new IllegalArgumentException(
        "A procedural sprite is not a verified chapter-1 map unit"
      );
    }
    Object copy = sprite.getConstructor(sprite).newInstance(original);
    copies.put(original, copy);
    for (String layer : List.of("ax", "ay")) {
      field(sprite, layer).set(copy, copySprite(get(original, layer), sprite, copies));
    }
    field(sprite, "az").set(copy, get(original, "az"));
    return copy;
  }

  private static Object get(Object target, String name) throws ReflectiveOperationException {
    return field(target.getClass(), name).get(target);
  }

  private static int number(Object target, String name) throws ReflectiveOperationException {
    return ((Number) get(target, name)).intValue();
  }

  private static Field field(Class<?> type, String name) throws NoSuchFieldException {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field result = current.getDeclaredField(name);
        result.setAccessible(true);
        return result;
      } catch (NoSuchFieldException absent) {
        // Continue into the reference sprite base class.
      }
    }
    throw new NoSuchFieldException(type.getName() + "." + name);
  }
}
