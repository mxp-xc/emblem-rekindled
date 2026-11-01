import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.imageio.ImageIO;

/** Offline conversion of verified chapter-1 narrative and presentation resources. */
public final class Chapter1Story {

  private static final String SOURCE_SHA =
    "67d1c77e823816e203244a15428ba9fb635d40edba04efa3180b3334025989fe";

  private Chapter1Story() {}

  /** Chapter resources only; verified per-map events are authored JSON, not Java branches. */
  public static void exportResources(Object game, ClassLoader loader, Path output)
    throws Exception {
    verifySource(loader);
    Method text = Class.forName("e", true, loader).getMethod("b", int.class);
    Method resource = Class.forName("h", true, loader).getMethod("c", String.class);
    Path directory = output.resolve("story");
    Files.createDirectories(directory);
    Map<String, Object> manifest = new LinkedHashMap<>();
    manifest.put("texts", exportTexts(resource, text));
    Map<String, Object> images = new LinkedHashMap<>();
    Map<String, Object> speakers = new LinkedHashMap<>();
    for (Object unit : deployment(game).values()) {
      int id = number(unit, "y"),
        portraitId = number(unit, "A");
      Map<String, Object> speaker = new LinkedHashMap<>();
      speaker.put("id", id);
      speaker.put("name", get(unit, "w"));
      speaker.put("faction", number(unit, "C"));
      speaker.put("portraitId", portraitId < 0 ? null : portraitId);
      speakers.put(String.valueOf(id), speaker);
      if (portraitId >= 0) {
        String name = String.format("portraits_%02d", portraitId);
        if (!images.containsKey(name)) images.put(
          name,
          copyPng(resource, name + ".png", directory, "images/" + name + ".png")
        );
      }
    }
    manifest.put("images", images);
    manifest.put("speakers", speakers);
    Files.writeString(directory.resolve("manifest.json"), Chapter1Rules.json(manifest) + "\n");
  }

  /** The reference runtime must already be paused and initialized in an isolated temporary cwd. */
  public static void exportCommon(Object game, ClassLoader loader, Path output) throws Exception {
    verifySource(loader);
    Class<?> textClass = Class.forName("e", true, loader);
    Class<?> helperClass = Class.forName("h", true, loader);
    Class<?> spriteClass = Class.forName("g", true, loader);
    Class<?> frameClass = Class.forName("d", true, loader);
    Method text = textClass.getMethod("b", int.class);
    Method resource = helperClass.getMethod("c", String.class);
    Path directory = output.resolve("story");
    Files.createDirectories(directory);

    Map<String, Object> manifest = new LinkedHashMap<>();
    manifest.put("schemaVersion", 1);
    manifest.put("chapterId", "chapter_1");
    manifest.put("sourceSha256", SOURCE_SHA);
    manifest.put("texts", exportTexts(resource, text));
    Map<String, Object> labels = new LinkedHashMap<>();
    String[] labelNames = {
      "newGame",
      "saveArchive",
      "loadArchive",
      "settings",
      "help",
      "exit",
      "confirm",
    };
    for (int index = 0; index < labelNames.length; index++) {
      labels.put(labelNames[index], line(text, index, null));
    }
    labels.put("loadProgress", line(text, 111, null));
    labels.put("pressAnyKey", line(text, 113, null));
    labels.put("gameOver", line(text, 19, null));
    labels.put("missionComplete", line(text, 34, null));
    labels.put("returnToTitle", line(text, 22, null));
    labels.put("commanderSetup", line(text, 79, null));
    labels.put("commander", line(text, 114, null));
    labels.put("automatic", line(text, 116, null));
    labels.put("follow", line(text, 117, null));
    labels.put("attack", line(text, 68, null));
    labels.put("defend", line(text, 66, null));
    manifest.put("labels", labels);

    Map<String, Object> images = new LinkedHashMap<>();
    for (String name : List.of(
      "splash",
      "title_00",
      "title_01",
      "intro0",
      "scene0",
      "scene1",
      "scene2",
      "b0",
      "b1"
    )) {
      images.put(name, copyPng(resource, name + ".png", directory, "images/" + name + ".png"));
    }
    Map<Integer, Object> units = deployment(game);
    Set<Integer> portraits = new LinkedHashSet<>(List.of(0, 9, 10, 6, 3, 2, 5));
    for (int id : new int[] { 0, 9, 10, 11, 13, 14, 15 }) {
      Object unit = units.get(id);
      if (unit == null) throw new IllegalStateException("Missing first-battle speaker " + id);
      int portraitId = number(unit, "A");
      if (portraitId >= 0) portraits.add(portraitId);
    }
    for (int id : portraits) {
      String name = String.format("portraits_%02d", id);
      images.put(name, copyPng(resource, name + ".png", directory, "images/" + name + ".png"));
    }
    manifest.put("images", images);

    // Resource constructors may populate d.a; preserve the original cache and its identity.
    Map<Object, Object> cache = imageCache(frameClass);
    Map<Object, Object> cacheBefore = new LinkedHashMap<>(cache);
    try {
      manifest.put("world", exportWorld(game, spriteClass, resource, text, directory));
    } finally {
      cache.clear();
      cache.putAll(cacheBefore);
    }

    Map<String, Object> sequences = new LinkedHashMap<>();
    sequences.put(
      "boot",
      List.of(
        step(
          "prologue",
          "text",
          line(text, 458, null),
          "image",
          "intro0",
          "source",
          "i.h:cv0 -> i.a(0,3,3) -> t.bin[458]"
        )
      )
    );
    Map<String, Object> worldLine = line(text, 460, null);
    worldLine.put("portraitId", 10);
    sequences.put(
      "newGame",
      List.of(
        step("worldNarration", "text", worldLine, "focusNode", 0, "source", "i.G:dC0,dD0"),
        step(
          "worldMarker",
          "nodeId",
          0,
          "sourceState",
          2,
          "sourceWaitTicks",
          20,
          "source",
          "i.G:dC10"
        ),
        step("enterBattle", "battleId", "m0", "source", "i.G:dC11 -> i.F")
      )
    );
    sequences.put(
      "defeat",
      List.of(step("gameOver", "text", line(text, 19, null), "source", "i.v"))
    );
    manifest.put("sequences", sequences);
    List<Object> tutorials = new ArrayList<>();
    String[] triggers = {
      "afterCommanderSetup",
      "firstMoveSelection",
      "firstActionCompleted",
      "attackSelectionAfterTutorial4WasSeen",
      "firstAttackSelection",
      null,
      "queuedPanelType30DuringPlayerPhase",
      null,
      null,
      "completedPlayerActionAfterTutorial2WasSeen",
    };
    for (int id = 0; id < 10; id++) {
      Map<String, Object> tutorial = line(text, 447 + id, null);
      tutorial.put("id", id);
      tutorial.put("trigger", triggers[id]);
      tutorial.put("automaticTriggerVerified", triggers[id] != null);
      tutorial.put(
        "category",
        Boolean.TRUE.equals(tutorial.get("requiresInputRewrite")) ? "legacyControls" : "rules"
      );
      tutorials.add(tutorial);
    }
    manifest.put("tutorials", tutorials);
    manifest.put(
      "tutorialGroups",
      Map.of("legacyControls", List.of(0, 2, 3), "rules", List.of(1, 4, 5, 6, 7, 8, 9))
    );
    manifest.put(
      "textFormat",
      Map.of(
        "rawText",
        "Unmodified t.bin UTF string",
        "text",
        "Plain source wording, or null when legacy input requires authored replacement",
        "paragraphs",
        "Source LF-separated lines; blank entries preserve blank lines; not display pages",
        "pagination",
        "Original runtime wraps by font width and panel size, no embedded page markers",
        "speaker",
        "External unit/portrait metadata, not embedded markup"
      )
    );
    manifest.put(
      "timing",
      Map.of(
        "sourceWaitTicks",
        "original dd frame counter; not measured milliseconds",
        "sourceNarrativeOrder",
        "verified original control flow",
        "modernInputAdaptation",
        "legacy phone-control tutorial tokens require app-authored touch/mouse wording"
      )
    );
    Files.writeString(directory.resolve("manifest.json"), Chapter1Rules.json(manifest) + "\n");
  }

  private static Map<String, Object> exportWorld(
    Object game,
    Class<?> sprites,
    Method resource,
    Method text,
    Path directory
  ) throws Exception {
    Object mapSprite = sprites.getConstructor(String.class).newInstance("bmap");
    Object[] frames = (Object[]) get(mapSprite, "ap");
    int width, height;
    byte[][] grid;
    try (
      DataInputStream input = new DataInputStream((InputStream) resource.invoke(null, "world"))
    ) {
      width = input.readUnsignedByte();
      height = input.readUnsignedByte();
      if (width != 12 || height != 12) throw new IOException(
        "Unexpected original world dimensions"
      );
      grid = new byte[height][width];
      for (byte[] row : grid) input.readFully(row);
      if (input.read() != -1) throw new IOException("Unexpected world resource tail");
    }
    var canvas = javax.microedition.lcdui.Image.createRGBImage(
      new int[width * height * 24 * 24],
      width * 24,
      height * 24,
      true
    );
    canvas.setMutable(true);
    Method draw = frames[0]
      .getClass()
      .getMethod("a", javax.microedition.lcdui.Graphics.class, int.class, int.class);
    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
      int id = grid[y][x] & 255;
      if (id >= frames.length) throw new IOException("Unknown world tile " + id);
      draw.invoke(frames[id], canvas.getGraphics(), x * 24, y * 24);
    }
    ImageIO.write(canvas.getCanvas(), "png", directory.resolve("world.png").toFile());
    byte[] points = (byte[]) field(game.getClass(), "dp").get(null);
    byte[] marker = (byte[]) field(game.getClass(), "do").get(null);
    List<Object> nodes = new ArrayList<>();
    for (int index = 0; index < points.length / 2; index++) {
      Map<String, Object> narration = line(text, 460 + index, null);
      narration.put("portraitId", 10);
      nodes.add(
        step(
          "worldNode",
          "id",
          index,
          "name",
          text.invoke(null, 139 + index),
          "position",
          List.of((int) points[index * 2], (int) points[index * 2 + 1]),
          "markerId",
          (int) marker[index],
          "entryNarration",
          narration
        )
      );
    }
    return step(
      "world",
      "texture",
      "world.png",
      "width",
      width,
      "height",
      height,
      "tileSize",
      24,
      "nodes",
      nodes,
      "routes",
      field(game.getClass(), "dq").get(null),
      "initialVisibleNodes",
      List.of(0),
      "focusNode",
      0,
      "markerAnchor",
      33,
      "source",
      "1.pak:world + g(bmap).ap; original i.g(Graphics)"
    );
  }

  private static Map<String, Object> line(Method text, int index, Integer speakerId)
    throws Exception {
    Map<String, Object> result = new LinkedHashMap<>();
    String raw = (String) text.invoke(null, index);
    List<String> tokens = new ArrayList<>();
    for (String token : List.of("%K5", "%K0", "%K7", "%K9", "%KM", "%U", "左右软键", "*", "#")) {
      if (raw.contains(token)) tokens.add(token);
    }
    boolean rewrite = !tokens.isEmpty() || index == 113;
    if (index == 113) tokens.add("任意键");
    result.put("sourceTextIndex", index);
    result.put("rawText", raw);
    result.put("text", rewrite ? null : raw);
    result.put("paragraphs", rewrite ? List.of() : List.of(raw.split("\\n", -1)));
    result.put("requiresInputRewrite", rewrite);
    result.put("legacyInputTokens", tokens);
    result.put("speakerId", speakerId);
    return result;
  }

  private static Map<String, Object> exportTexts(Method resource, Method text) throws Exception {
    Map<String, Object> result = new LinkedHashMap<>();
    try (
      DataInputStream input = new DataInputStream((InputStream) resource.invoke(null, "t.bin"))
    ) {
      int count = input.readInt();
      if (count < 1 || count > 10000) throw new IOException("Invalid original text count");
      for (int index = 0; index < count; index++) result.put(
        String.valueOf(index),
        line(text, index, null)
      );
    }
    return result;
  }

  private static Map<String, Object> step(String kind, Object... values) {
    if (values.length % 2 != 0) throw new IllegalArgumentException(
      "Metadata requires key/value pairs"
    );
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("kind", kind);
    for (int index = 0; index < values.length; index += 2) result.put(
      (String) values[index],
      values[index + 1]
    );
    return result;
  }

  private static Map<String, Object> copyPng(
    Method resource,
    String name,
    Path directory,
    String relative
  ) throws Exception {
    byte[] bytes;
    try (InputStream input = (InputStream) resource.invoke(null, name)) {
      if (input == null) throw new IOException("Missing original story resource " + name);
      bytes = input.readAllBytes();
    }
    BufferedImage decoded = ImageIO.read(new ByteArrayInputStream(bytes));
    if (decoded == null) throw new IOException("Invalid original PNG " + name);
    Path target = directory.resolve(relative);
    Files.createDirectories(target.getParent());
    Files.write(target, bytes);
    return step(
      "image",
      "texture",
      relative,
      "width",
      decoded.getWidth(),
      "height",
      decoded.getHeight(),
      "source",
      name
    );
  }

  private static Map<Integer, Object> deployment(Object game) throws Exception {
    Object value = get(game, "as");
    if (!(value instanceof List<?> units)) throw new IllegalStateException(
      "Reference deployment is missing"
    );
    Map<Integer, Object> result = new LinkedHashMap<>();
    for (Object unit : units) result.put(number(unit, "y"), unit);
    return result;
  }

  private static void verifySource(ClassLoader loader) throws Exception {
    if (!(loader instanceof URLClassLoader source)) throw new IllegalArgumentException(
      "Expected original MIDlet URL loader"
    );
    for (URL url : source.getURLs()) {
      if (!url.getProtocol().equals("file")) continue;
      Path path = Path.of(url.toURI());
      if (!Files.isRegularFile(path)) continue;
      String sha = HexFormat.of().formatHex(
        MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(path))
      );
      if (sha.equals(SOURCE_SHA)) return;
    }
    throw new IOException("Chapter-1 source JAR SHA-256 mismatch");
  }

  @SuppressWarnings("unchecked")
  private static Map<Object, Object> imageCache(Class<?> frameClass) throws Exception {
    Object value = field(frameClass, "a").get(null);
    if (!(value instanceof Map<?, ?>)) throw new IllegalStateException(
      "Reference image cache is missing"
    );
    return (Map<Object, Object>) value;
  }

  private static Object get(Object target, String name) throws Exception {
    return field(target.getClass(), name).get(target);
  }

  private static int number(Object target, String name) throws Exception {
    return ((Number) get(target, name)).intValue();
  }

  private static Field field(Class<?> type, String name) throws NoSuchFieldException {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field result = current.getDeclaredField(name);
        result.setAccessible(true);
        return result;
      } catch (NoSuchFieldException absent) {
        // Reference unit fields also live on their sprite base class.
      }
    }
    throw new NoSuchFieldException(type.getName() + "." + name);
  }
}
