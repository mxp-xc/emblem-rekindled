import java.awt.image.BufferedImage;
import java.io.IOException;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.imageio.ImageIO;

/** Offline chapter-1 conversion. Call only with the reference runtime isolated in a temporary cwd. */
public final class Chapter1BattleAssets {

  private static final int CANVAS_SIZE = 256;
  private static final int ORIGIN = 96;

  private Chapter1BattleAssets() {}

  /** TSV deployment IDs are original runtime b.y identities, not p0 record indexes. */
  public static void export(Object game, ClassLoader loader, Path output, Path variantsFile)
    throws ReflectiveOperationException, IOException {
    Class<?> fighterClass = Class.forName("f", true, loader);
    Class<?> spriteClass = Class.forName("g", true, loader);
    Class<?> frameClass = Class.forName("d", true, loader);
    Map<Integer, Object> units = deployment(game);
    Map<Integer, Set<Integer>> variants = readVariants(variantsFile, units);
    Path directory = output.resolve("battle");
    Files.createDirectories(directory);
    Map<String, Object> appearances = new LinkedHashMap<>();
    for (var entry : variants.entrySet()) {
      Object unit = units.get(entry.getKey());
      for (int weaponId : entry.getValue()) {
        ReferenceState before = new ReferenceState(game, unit, fighterClass, frameClass);
        try {
          field(unit.getClass(), "F").setByte(unit, (byte) weaponId);
          Object fighter = fighterClass
            .getConstructor(game.getClass(), unit.getClass(), fighterClass)
            .newInstance(game, unit, null);
          String prefix = "appearances/unit_" + entry.getKey() + "_weapon_" + weaponId;
          Map<String, Object> appearance = exportSprite(
            get(fighter, "S"),
            spriteClass,
            directory,
            prefix
          );
          appearance.put("deploymentId", entry.getKey());
          appearance.put("weaponId", weaponId);
          appearance.put("classId", number(unit, "S"));
          appearance.put("faction", number(unit, "C"));
          appearance.put("nativeSide", number(fighter, "I") == 0 ? "left" : "right");
          appearance.put("presentationClass", number(fighter, "R"));
          appearance.put("effectKind", number(fighter, "E"));
          appearance.put("headId", number(fighter, "ah"));
          appearance.put("headPalette", number(fighter, "ai"));
          byte[] weaponFrames = (byte[]) get(fighter, "al");
          byte[] weaponOffsets = (byte[]) get(fighter, "am");
          appearance.put("weaponFrames", weaponFrames == null ? null : weaponFrames.clone());
          appearance.put("weaponOffsets", weaponOffsets == null ? null : weaponOffsets.clone());
          boolean projectile = (boolean) fighterClass.getMethod("p").invoke(fighter);
          if (projectile) {
            Object[] projectileFrames = (Object[]) get(get(fighter, "aa"), "ap");
            if (projectileFrames.length <= 5) {
              throw new IllegalStateException("Original thrown weapon frame is missing");
            }
            Object frame = frameClass
              .getConstructor(frameClass, int.class)
              .newInstance(projectileFrames[5], 0);
            field(frameClass, "e").setInt(frame, 0);
            field(frameClass, "f").setInt(frame, 0);
            appearance.put("projectile", exportFrame(frame, directory, prefix + "/projectile.png"));
            appearance.put("projectileSource", weaponId == 17 ? "f.q:F17" : "f.p:F23");
          }
          appearances.put(entry.getKey() + ":" + weaponId, appearance);
        } catch (ReflectiveOperationException error) {
          throw new ReflectiveOperationException(
            "Battle appearance failed for deployment " + entry.getKey() + ", weapon " + weaponId,
            error
          );
        } finally {
          before.restore();
        }
      }
    }
    Map<String, Object> manifest = new LinkedHashMap<>();
    manifest.put("schemaVersion", 1);
    manifest.put("chapterId", "chapter_1");
    manifest.put("texturePathsRelativeTo", "manifest.json");
    manifest.put("origin", "original_g_virtual_top_left");
    manifest.put("nominalTickUnits", 50);
    manifest.put("timing", "source logical units, not measured milliseconds");
    manifest.put("sidePolicy", "native faction side; no implicit flip_h");
    manifest.put("flagSemantics", "d.g after native-side constructor adjustments; not flip_h");
    manifest.put("appearances", appearances);
    exportBackgrounds(game, fighterClass, spriteClass, directory, manifest);
    Map<String, Object> effects = new LinkedHashMap<>();
    String[][] effectFields = {
      { "smoke", "G" },
      { "bomb", "M" },
      { "fire", "O" },
      { "wind", "P" },
      { "light", "N" },
      { "wind_cast", "Q" },
      { "power", "T" },
    };
    for (String[] effect : effectFields) {
      Object copy = spriteClass.getConstructor(spriteClass).newInstance(get(game, effect[1]));
      Map<String, Object> definition = exportSprite(
        copy,
        spriteClass,
        directory,
        "effects/" + effect[0]
      );
      definition.put("source", "i." + effect[1]);
      effects.put(effect[0], definition);
    }
    effects.put("cloud", exportFrame(get(game, "S"), directory, "effects/cloud.png"));
    for (int side = 0; side < 2; side++) {
      String source = "w" + (17 + side);
      Object frame = frameClass.getConstructor(String.class).newInstance(source);
      Map<String, Object> definition = exportFrame(frame, directory, "effects/" + source + ".png");
      definition.put("source", source);
      effects.put(side == 0 ? "strike_left" : "strike_right", definition);
    }
    manifest.put("effects", effects);
    manifest.put(
      "effectPrograms",
      Map.of(
        "physical",
        Map.of("source", "f.f:E0/E1", "rasterized", false),
        "thrown_lance",
        Map.of("source", "f.f:p/q F17", "rasterized", false),
        "thrown_axe",
        Map.of("source", "f.f:p F23", "rasterized", false),
        "magic_fire",
        Map.of("source", "f.d:E3", "rasterized", false),
        "magic_wind",
        Map.of("source", "f.d:E5", "rasterized", false),
        "magic_light",
        Map.of("source", "f.d:E7", "rasterized", false),
        "magic_drain",
        Map.of("source", "f.d:E12 and g.a:ar6", "rasterized", false),
        "rings",
        Map.of("source", "g.a:ar1/ar3", "rasterized", false),
        "particles",
        Map.of("source", "g.a/r:ar2/ar4", "rasterized", false)
      )
    );
    Files.writeString(directory.resolve("manifest.json"), Chapter1Rules.json(manifest) + "\n");
  }

  private static Map<Integer, Object> deployment(Object game) throws ReflectiveOperationException {
    if (!(get(game, "as") instanceof List<?> list) || list.isEmpty()) {
      throw new IllegalArgumentException("Chapter-1 deployment is not initialized");
    }
    Map<Integer, Object> units = new LinkedHashMap<>();
    for (Object unit : list) {
      int id = number(unit, "y");
      if (units.put(id, unit) != null) {
        throw new IllegalArgumentException("Duplicate original deployment ID " + id);
      }
    }
    return units;
  }

  private static Map<Integer, Set<Integer>> readVariants(Path path, Map<Integer, Object> units)
    throws IOException {
    Map<Integer, Set<Integer>> result = new LinkedHashMap<>();
    List<String> lines = Files.readAllLines(path);
    for (int index = 0; index < lines.size(); index++) {
      String line = lines.get(index).trim();
      if (line.isEmpty() || line.startsWith("#")) continue;
      String[] columns = line.split("\t", -1);
      try {
        if (columns.length != 2) throw new IllegalArgumentException("Expected two TSV columns");
        int id = Integer.parseInt(columns[0].trim());
        if (!units.containsKey(id)) throw new IllegalArgumentException(
          "Unknown deployment ID " + id
        );
        Set<Integer> weapons = new LinkedHashSet<>();
        for (String candidate : columns[1].split(",", -1)) {
          int weapon = Integer.parseInt(candidate.trim());
          if (weapon < 0 || weapon > 59 || !weapons.add(weapon)) {
            throw new IllegalArgumentException("Invalid or duplicate weapon ID " + weapon);
          }
        }
        if (result.put(id, weapons) != null) {
          throw new IllegalArgumentException("Duplicate deployment line " + id);
        }
      } catch (IllegalArgumentException error) {
        throw new IOException("Invalid battle variants at " + path + ":" + (index + 1), error);
      }
    }
    if (result.isEmpty()) throw new IOException("Battle variants must not be empty");
    return result;
  }

  private static void exportBackgrounds(
    Object game,
    Class<?> fighterClass,
    Class<?> spriteClass,
    Path directory,
    Map<String, Object> manifest
  ) throws ReflectiveOperationException, IOException {
    byte[] choices = (byte[]) field(fighterClass, "P").get(null);
    String[] sources = (String[]) field(fighterClass, "Q").get(null);
    byte[] palettes = (byte[]) field(game.getClass(), "bi").get(null);
    int palette = palettes[number(game, "bh")];
    Set<Integer> terrains = new LinkedHashSet<>();
    var terrainAt = game.getClass().getMethod("p", int.class, int.class);
    for (int y = 0; y < number(game, "ce"); y++) {
      for (int x = 0; x < number(game, "cf"); x++) {
        terrains.add(((Number) terrainAt.invoke(game, x, y)).intValue());
      }
    }
    Map<String, Object> mapping = new LinkedHashMap<>();
    Map<String, Object> backgrounds = new LinkedHashMap<>();
    for (int terrain : terrains) {
      if (terrain < 0 || terrain >= choices.length) {
        throw new IllegalArgumentException("Unknown original battle terrain " + terrain);
      }
      String source = sources[choices[terrain]];
      mapping.put(Integer.toString(terrain), source);
      if (backgrounds.containsKey(source)) continue;
      Object sprite = spriteClass
        .getConstructor(String.class, String.class, byte.class)
        .newInstance(source, sources[0], (byte) palette);
      Map<String, Object> definition = exportSprite(
        sprite,
        spriteClass,
        directory,
        "backgrounds/" + source
      );
      definition.put("source", source);
      definition.put("palette", palette);
      backgrounds.put(source, definition);
    }
    manifest.put("terrainBackgrounds", mapping);
    manifest.put("backgrounds", backgrounds);
  }

  private static Map<String, Object> exportSprite(
    Object sprite,
    Class<?> spriteClass,
    Path directory,
    String prefix
  ) throws ReflectiveOperationException, IOException {
    Object[] frames = (Object[]) get(sprite, "ap");
    if (frames == null || frames.length == 0) {
      throw new IllegalStateException("Original sprite has no frames: " + prefix);
    }
    Map<String, Object> definition = new LinkedHashMap<>();
    definition.put("virtualWidth", number(sprite, "at"));
    definition.put("virtualHeight", number(sprite, "au"));
    definition.put("sequences", get(sprite, "as"));
    definition.put("sequenceStepUnits", number(sprite, "aF"));
    byte[] identity = new byte[frames.length];
    for (int index = 0; index < identity.length; index++) identity[index] = (byte) index;
    field(spriteClass, "aV").set(sprite, identity);
    field(spriteClass, "av").setInt(sprite, 0);
    field(spriteClass, "aw").setInt(sprite, 0);
    List<Object> converted = new ArrayList<>();
    for (int index = 0; index < frames.length; index++) {
      field(spriteClass, "aq").setInt(sprite, index);
      Map<String, Object> frame = rasterize(sprite, directory, prefix + "/frame_" + index + ".png");
      frame.put("index", index);
      frame.put("bodyWidth", number(frames[index], "c"));
      frame.put("bodyHeight", number(frames[index], "d"));
      frame.put("bodyOffsetX", number(frames[index], "e"));
      frame.put("bodyOffsetY", number(frames[index], "f"));
      frame.put("originalFlag", number(frames[index], "g"));
      converted.add(frame);
    }
    definition.put("frames", converted);
    return definition;
  }

  private static Map<String, Object> exportFrame(Object frame, Path directory, String texture)
    throws ReflectiveOperationException, IOException {
    Map<String, Object> result = rasterize(frame, directory, texture);
    result.put("virtualWidth", number(frame, "c"));
    result.put("virtualHeight", number(frame, "d"));
    result.put("originalFlag", number(frame, "g"));
    return result;
  }

  private static Map<String, Object> rasterize(Object renderable, Path directory, String texture)
    throws ReflectiveOperationException, IOException {
    var image = javax.microedition.lcdui.Image.createRGBImage(
      new int[CANVAS_SIZE * CANVAS_SIZE],
      CANVAS_SIZE,
      CANVAS_SIZE,
      true
    );
    image.setMutable(true);
    renderable
      .getClass()
      .getMethod("a", javax.microedition.lcdui.Graphics.class, int.class, int.class)
      .invoke(renderable, image.getGraphics(), ORIGIN, ORIGIN);
    BufferedImage rgba = image.getCanvas();
    int left = CANVAS_SIZE,
      top = CANVAS_SIZE,
      right = -1,
      bottom = -1;
    for (int y = 0; y < CANVAS_SIZE; y++) {
      for (int x = 0; x < CANVAS_SIZE; x++) {
        if (rgba.getRGB(x, y) >>> 24 == 0) continue;
        left = Math.min(left, x);
        top = Math.min(top, y);
        right = Math.max(right, x);
        bottom = Math.max(bottom, y);
      }
    }
    if (left == 0 || top == 0 || right == CANVAS_SIZE - 1 || bottom == CANVAS_SIZE - 1) {
      throw new IllegalStateException("Sampling canvas clipped an original frame: " + texture);
    }
    boolean empty = right < 0;
    if (empty) left = top = right = bottom = ORIGIN;
    Path path = directory.resolve(texture);
    Files.createDirectories(path.getParent());
    if (
      !ImageIO.write(
        rgba.getSubimage(left, top, right - left + 1, bottom - top + 1),
        "png",
        path.toFile()
      )
    ) {
      throw new IOException("No PNG writer available for " + path);
    }
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("texture", texture);
    result.put("offsetX", left - ORIGIN);
    result.put("offsetY", top - ORIGIN);
    result.put("width", right - left + 1);
    result.put("height", bottom - top + 1);
    result.put("empty", empty);
    return result;
  }

  private static Field field(Class<?> type, String name) throws NoSuchFieldException {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field result = current.getDeclaredField(name);
        result.setAccessible(true);
        return result;
      } catch (NoSuchFieldException absent) {
        // Sprite state is declared on both the original unit and its base class.
      }
    }
    throw new NoSuchFieldException(type.getName() + "." + name);
  }

  private static Object get(Object target, String name) throws ReflectiveOperationException {
    return field(target.getClass(), name).get(target);
  }

  private static int number(Object target, String name) throws ReflectiveOperationException {
    return ((Number) get(target, name)).intValue();
  }

  /** Restores array contents and nested-array identities, including f.r()'s mutations of f.aj. */
  private static final class ArrayState {

    private final Object array;
    private final Object[] entries;
    private final List<ArrayState> children = new ArrayList<>();

    private ArrayState(Object value) {
      array = value;
      entries = new Object[Array.getLength(value)];
      for (int index = 0; index < entries.length; index++) {
        Object entry = Array.get(value, index);
        entries[index] = entry;
        if (entry != null && entry.getClass().isArray()) children.add(new ArrayState(entry));
      }
    }

    private void restore() {
      for (int index = 0; index < entries.length; index++) Array.set(array, index, entries[index]);
      for (ArrayState child : children) child.restore();
    }
  }

  private static final class ReferenceState {

    private final Object game;
    private final Object unit;
    private final Object equipment;
    private final Object faction;
    private final List<Object> inventory;
    private final List<Object> items;
    private final List<Object> registry;
    private final List<Object> registrations;
    private final Map<Object, Object> cache;
    private final Map<Object, Object> cached;
    private final Map<Field, Object> staticValues = new LinkedHashMap<>();
    private final List<ArrayState> arrays = new ArrayList<>();

    @SuppressWarnings("unchecked")
    private ReferenceState(Object owner, Object actor, Class<?> fighterClass, Class<?> frameClass)
      throws ReflectiveOperationException {
      game = owner;
      unit = actor;
      equipment = get(unit, "F");
      faction = get(unit, "C");
      inventory = (List<Object>) get(unit, "v");
      items = new ArrayList<>(inventory);
      for (Object item : items) {
        if (item != null && item.getClass().isArray()) arrays.add(new ArrayState(item));
      }
      registry = (List<Object>) get(game, "aC");
      registrations = new ArrayList<>(registry);
      cache = (Map<Object, Object>) field(frameClass, "a").get(null);
      cached = new LinkedHashMap<>(cache);
      for (Field entry : fighterClass.getDeclaredFields()) {
        if (!Modifier.isStatic(entry.getModifiers())) continue;
        entry.setAccessible(true);
        Object value = entry.get(null);
        if (!Modifier.isFinal(entry.getModifiers())) staticValues.put(entry, value);
        if (value != null && value.getClass().isArray()) arrays.add(new ArrayState(value));
      }
    }

    private void restore() throws ReflectiveOperationException {
      field(unit.getClass(), "F").set(unit, equipment);
      field(unit.getClass(), "C").set(unit, faction);
      field(unit.getClass(), "v").set(unit, inventory);
      inventory.clear();
      inventory.addAll(items);
      field(game.getClass(), "aC").set(game, registry);
      registry.clear();
      registry.addAll(registrations);
      cache.clear();
      cache.putAll(cached);
      for (var entry : staticValues.entrySet()) entry.getKey().set(null, entry.getValue());
      for (ArrayState state : arrays) state.restore();
    }
  }
}
