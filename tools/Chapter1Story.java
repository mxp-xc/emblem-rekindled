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

  /** The reference runtime must already be paused and initialized in an isolated temporary cwd. */
  public static void export(Object game, ClassLoader loader, Path output) throws Exception {
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
    manifest.put("battleId", "m0");
    manifest.put("worldNode", 0);
    manifest.put("battleNumber", 1);
    manifest.put("pathsRelativeTo", "manifest.json");
    manifest.put("sourceSha256", SOURCE_SHA);
    manifest.put("battleName", line(text, 139, null));
    manifest.put("objective", line(text, 156, null));
    // i.z:m0/dc15 checks victory before the required-survivor failure branch.
    manifest.put(
      "outcomeRules",
      Map.of(
        "enemyFaction",
        2,
        "escapeUnitId",
        0,
        "escapeRow",
        24,
        "requiredUnitIds",
        List.of(0, 9)
      )
    );

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
    Map<String, Object> speakers = new LinkedHashMap<>();
    Set<Integer> portraits = new LinkedHashSet<>(List.of(0, 9, 10, 6, 3, 2, 5));
    for (int id : new int[] { 0, 9, 10, 11, 13, 14, 15 }) {
      Object unit = units.get(id);
      if (unit == null) throw new IllegalStateException("Missing first-battle speaker " + id);
      int portraitId = number(unit, "A");
      Map<String, Object> speaker = new LinkedHashMap<>();
      speaker.put("id", id);
      speaker.put("name", get(unit, "w"));
      speaker.put("faction", number(unit, "C"));
      speaker.put("portraitId", portraitId < 0 ? null : portraitId);
      speakers.put(String.valueOf(id), speaker);
      if (portraitId >= 0) portraits.add(portraitId);
    }
    for (int id : portraits) {
      String name = String.format("portraits_%02d", id);
      images.put(name, copyPng(resource, name + ".png", directory, "images/" + name + ".png"));
    }
    manifest.put("images", images);
    manifest.put("speakers", speakers);

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
    List<Object> opening = new ArrayList<>();
    opening.add(
      step(
        "focus",
        "cell",
        List.of(8, 11),
        "instant",
        true,
        "sourceWaitTicks",
        26,
        "source",
        "i.z:m0/dc0"
      )
    );
    opening.add(step("dialogue", "text", line(text, 477, 9), "source", "i.z:m0/dc1"));
    opening.add(step("dialogue", "text", line(text, 478, 0), "source", "i.z:m0/dc1"));
    opening.add(
      step(
        "unitEntrance",
        "unitId",
        10,
        "from",
        List.of(7, 10),
        "to",
        List.of(7, 9),
        "source",
        "i.z:m0/dc1"
      )
    );
    opening.add(
      step(
        "dialogue",
        "text",
        line(text, 479, 10),
        "sourceWaitTicksAfter",
        15,
        "source",
        "i.z:m0/dc1..2"
      )
    );
    List<Object> northern = new ArrayList<>();
    for (int id : new int[] { 52, 53, 55, 56, 50, 54 }) {
      Object unit = units.get(id);
      int x = number(unit, "D"),
        y = number(unit, "E");
      northern.add(
        step("unitEntrance", "unitId", id, "from", List.of(x, y - 3), "to", List.of(x, y))
      );
    }
    // Show both northern flanks before leaving this view; only the original six move.
    for (int id : new int[] { 48, 49, 51, 57 }) {
      Object unit = units.get(id);
      List<Integer> cell = List.of(number(unit, "D"), number(unit, "E"));
      northern.add(step("unitEntrance", "unitId", id, "from", cell, "to", cell));
    }
    opening.add(
      step(
        "parallelEntrances",
        "focus",
        List.of(9, 1),
        "units",
        northern,
        "sourceHoldTicksAfter",
        9,
        "source",
        "i.z:m0/dc3; presentation:northern-flanks"
      )
    );
    opening.add(
      step(
        "focus",
        "cell",
        List.of(2, 3),
        "holdTicksAfter",
        6,
        "source",
        "presentation:northern-left-flank"
      )
    );
    opening.add(
      step(
        "focus",
        "cell",
        List.of(16, 3),
        "holdTicksAfter",
        6,
        "source",
        "presentation:northern-right-flank"
      )
    );
    opening.add(
      step(
        "unitEntrance",
        "unitId",
        11,
        "from",
        List.of(10, 12),
        "to",
        List.of(10, 13),
        "source",
        "i.z:m0/dc4"
      )
    );
    opening.add(step("dialogue", "text", line(text, 480, 11), "source", "i.z:m0/dc4"));
    opening.add(step("focus", "cell", List.of(9, 22), "source", "i.z:m0/dc5"));
    opening.add(step("revealFaction", "faction", 2, "sourceWaitTicks", 10, "source", "i.z:m0/dc6"));
    opening.add(
      step(
        "dialogue",
        "text",
        line(text, 481, 0),
        "sourceWaitTicksAfter",
        20,
        "source",
        "i.z:m0/dc7..8"
      )
    );
    opening.add(step("objective", "text", line(text, 156, null), "source", "i.z:m0/dc11 -> i.o"));
    opening.add(step("instruction", "text", line(text, 455, null), "source", "i.z:m0/dc12"));
    List<Integer> commanders = new ArrayList<>();
    for (Object unit : units.values()) {
      if (
        number(unit, "C") == 0 && number(unit, "y") < 10 && (number(unit, "B") & 1) == 0
      ) commanders.add(number(unit, "y"));
    }
    opening.add(
      step(
        "commanderSetup",
        "candidates",
        commanders,
        "defaultCommanderId",
        commanders.isEmpty() ? null : commanders.get(0),
        "defaultMode",
        "automatic",
        "defaultStance",
        "attack",
        "source",
        "i.z:m0/dc13 -> i.a(e,1)"
      )
    );
    opening.add(step("tutorial", "tutorialId", 0, "source", "i.z:m0/dc14 -> i.e(0,0)"));
    sequences.put("opening", opening);

    List<Object> reinforcementUnits = new ArrayList<>();
    for (int id : new int[] { 13, 14, 15 }) {
      Object unit = units.get(id);
      reinforcementUnits.add(
        step(
          "unitEntrance",
          "unitId",
          id,
          "from",
          List.of(number(unit, "D"), number(unit, "E")),
          "to",
          List.of(number(unit, "D"), number(unit, "E"))
        )
      );
    }
    sequences.put(
      "reinforcements",
      List.of(
        step(
          "parallelEntrances",
          "focus",
          List.of(16, 21),
          "units",
          reinforcementUnits,
          "source",
          "i.k:m0/bo1"
        ),
        step("dialogue", "text", line(text, 482, 15)),
        step("dialogue", "text", line(text, 483, 14)),
        step("dialogue", "text", line(text, 484, 13))
      )
    );
    manifest.put(
      "turnEvents",
      List.of(
        Map.of(
          "id",
          "reinforcements",
          "afterEnemyPhaseOfRound",
          1,
          "unitIds",
          List.of(13, 14, 15),
          "sequence",
          "reinforcements"
        )
      )
    );
    manifest.put("aiChanges", List.of());

    List<Object> routes = exportRoutes(game, text);
    manifest.put("routeChoices", routes);
    sequences.put(
      "victory",
      List.of(
        step("dialogue", "text", line(text, 485, 9), "source", "i.z:m0/dc16"),
        step("dialogue", "text", line(text, 486, 0)),
        step("dialogue", "text", line(text, 487, 9)),
        step("dialogue", "text", line(text, 488, 0)),
        step("routeChoice", "options", routes, "source", "i.z:m0/dc17; i.a(e,String[],byte[])"),
        step(
          "missionComplete",
          "text",
          line(text, 34, null),
          "goldReward",
          1000,
          "source",
          "i.z:m0/dc18 -> i.t"
        )
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
      "initialBattlePresentation",
      Map.of(
        "hiddenFactions",
        List.of(2),
        "hiddenUnitIds",
        List.of(13, 14, 15),
        "unitPositionOverrides",
        Map.of("10", List.of(7, 10), "11", List.of(10, 12))
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

  /** m1-specific narrative; the importer supplies the unchanged chapter presentation metadata. */
  public static void exportSecondBattle(Object game, ClassLoader loader, Path output)
    throws Exception {
    verifySource(loader);
    Class<?> textClass = Class.forName("e", true, loader);
    Class<?> helperClass = Class.forName("h", true, loader);
    Class<?> spriteClass = Class.forName("g", true, loader);
    Class<?> frameClass = Class.forName("d", true, loader);
    Method text = textClass.getMethod("b", int.class);
    Method resource = helperClass.getMethod("c", String.class);
    Path directory = output.resolve("story");
    Files.createDirectories(directory);
    Map<Integer, Object> units = deployment(game);
    Map<String, Object> manifest = new LinkedHashMap<>();
    manifest.put("battleId", "m1");
    manifest.put("worldNode", 1);
    manifest.put("battleNumber", 2);
    manifest.put("battleName", line(text, 140, null));
    manifest.put("objective", line(text, 157, null));
    manifest.put(
      "outcomeRules",
      Map.of("enemyFaction", 2, "defeatUnitId", 81, "requiredUnitIds", List.of(0, 6))
    );
    Map<String, Object> speakers = new LinkedHashMap<>();
    Set<Integer> portraitIds = new LinkedHashSet<>(List.of(0, 9, 10, 6, 7, 1));
    for (int id : new int[] { 0, 9, 6, 51, 81 }) {
      Object unit = units.get(id);
      if (unit == null) throw new IllegalStateException("Missing m1 speaker " + id);
      int portrait = number(unit, "A");
      Map<String, Object> speaker = new LinkedHashMap<>();
      speaker.put("id", id);
      speaker.put("name", get(unit, "w"));
      speaker.put("faction", number(unit, "C"));
      speaker.put("portraitId", portrait < 0 ? null : portrait);
      speakers.put(String.valueOf(id), speaker);
      if (portrait >= 0) portraitIds.add(portrait);
    }
    Map<String, Object> images = new LinkedHashMap<>();
    for (int id : portraitIds) {
      String name = String.format("portraits_%02d", id);
      images.put(name, copyPng(resource, name + ".png", directory, "images/" + name + ".png"));
    }
    manifest.put("speakers", speakers);
    manifest.put("images", images);
    Map<Object, Object> cache = imageCache(frameClass);
    Map<Object, Object> before = new LinkedHashMap<>(cache);
    try {
      manifest.put("world", exportWorld(game, spriteClass, resource, text, directory));
    } finally {
      cache.clear();
      cache.putAll(before);
    }
    List<Object> routes = new ArrayList<>();
    int[] nextNodes = { 2, 8 };
    int[] classTextIndices = { 218, 210 };
    byte[] characterByNode = (byte[]) field(game.getClass(), "di").get(null);
    for (int route = 0; route < nextNodes.length; route++) {
      int character = characterByNode[nextNodes[route]];
      String name = (String) text.invoke(null, 174 + character);
      String className = (String) text.invoke(null, classTextIndices[route]);
      routes.add(
        step(
          "route",
          "nodeId",
          nextNodes[route],
          "characterId",
          character,
          "name",
          name,
          "nameTextIndex",
          174 + character,
          "className",
          className,
          "classTextIndex",
          classTextIndices[route],
          "label",
          name + "(" + className + ")",
          "portraitId",
          character,
          "routeIndex",
          route
        )
      );
    }
    manifest.put("routeChoices", routes);
    Map<String, Object> sequences = new LinkedHashMap<>();
    sequences.put(
      "opening",
      List.of(
        step(
          "battleTitle",
          "text",
          Map.of("sourceTextIndex", -1, "text", "第2战\n" + text.invoke(null, 140)),
          "sourceDurationUnits",
          2000,
          "source",
          "i.y:m1 -> c.ad10/ap2000"
        ),
        step("focus", "cell", List.of(5, 6), "instant", true, "source", "i.z:m1/dc0"),
        step("focus", "cell", List.of(12, 6), "source", "i.z:m1/dc1"),
        step("dialogue", "text", line(text, 489, 81), "source", "i.z:m1/dc2"),
        step("dialogue", "text", line(text, 490, 6), "source", "i.z:m1/dc3"),
        step("objective", "text", line(text, 157, null), "source", "i.z:m1/dc4"),
        step(
          "commanderSetup",
          "candidates",
          List.of(6),
          "defaultCommanderId",
          6,
          "defaultMode",
          "automatic",
          "defaultStance",
          "attack",
          "source",
          "i.z:m1/dc5"
        )
      )
    );
    List<Object> firstEntrances = new ArrayList<>();
    List<Object> secondEntrances = new ArrayList<>();
    List<Object> enemyEntrances = new ArrayList<>();
    for (int id : new int[] { 97, 95, 96 }) firstEntrances.add(entrance(units.get(id), 3, 0));
    for (int id : new int[] { 98, 0, 9 }) secondEntrances.add(entrance(units.get(id), 3, 0));
    for (int id : new int[] { 63, 59, 60 }) enemyEntrances.add(entrance(units.get(id), 0, 3));
    List<Object> alliedArrival = List.of(
      step("dialogue", "text", line(text, 491, 51), "source", "i.k:m1/bo1"),
      step("dialogue", "text", line(text, 492, 81)),
      step("parallelEntrances", "focus", List.of(2, 3), "units", firstEntrances),
      step("parallelEntrances", "focus", List.of(1, 15), "units", secondEntrances),
      step("dialogue", "text", line(text, 493, 6)),
      step("dialogue", "text", line(text, 494, 0))
    );
    sequences.put("allied_arrival", alliedArrival);
    sequences.put("reinforcements", alliedArrival);
    sequences.put(
      "enemy_arrival",
      List.of(
        step(
          "parallelEntrances",
          "focus",
          List.of(5, 2),
          "units",
          enemyEntrances,
          "source",
          "i.k:m1/bo2"
        ),
        step("dialogue", "text", line(text, 495, 81))
      )
    );
    sequences.put(
      "victory",
      List.of(
        step("dialogue", "text", line(text, 498, 6), "source", "i.z:m1/dc7,dD1"),
        step("routeChoice", "options", routes, "source", "i.z:m1/dc8,dD1"),
        step(
          "missionComplete",
          "text",
          line(text, 34, null),
          "goldReward",
          1000,
          "source",
          "i.z:m1/dc9 -> i.t"
        )
      )
    );
    manifest.put("sequences", sequences);
    manifest.put(
      "turnEvents",
      List.of(
        Map.of(
          "id",
          "allied_arrival",
          "afterEnemyPhaseOfRound",
          1,
          "unitIds",
          List.of(95, 96, 97, 98, 0, 9),
          "sequence",
          "allied_arrival"
        ),
        Map.of(
          "id",
          "enemy_arrival",
          "afterEnemyPhaseOfRound",
          2,
          "unitIds",
          List.of(63, 59, 60),
          "sequence",
          "enemy_arrival"
        )
      )
    );
    manifest.put(
      "aiChanges",
      List.of(
        Map.of(
          "beforeEnemyPhaseOfRound",
          9,
          "unitIds",
          List.of(65, 52, 51, 81, 68),
          "flagsSet",
          16,
          "policyClear",
          2
        )
      )
    );
    manifest.put(
      "initialBattlePresentation",
      Map.of(
        "hiddenFactions",
        List.of(),
        "hiddenUnitIds",
        List.of(),
        "unitPositionOverrides",
        Map.of()
      )
    );
    Files.writeString(directory.resolve("battle.json"), Chapter1Rules.json(manifest) + "\n");
  }

  private static Map<String, Object> entrance(Object unit, int left, int above) throws Exception {
    int x = number(unit, "D"),
      y = number(unit, "E");
    return step(
      "unitEntrance",
      "unitId",
      number(unit, "y"),
      "from",
      List.of(x - left, y - above),
      "to",
      List.of(x, y)
    );
  }

  private static List<Object> exportRoutes(Object game, Method text) throws Exception {
    byte[] characterByNode = (byte[]) field(game.getClass(), "di").get(null);
    byte[][] routes = (byte[][]) field(game.getClass(), "dq").get(null);
    int[] classes = { 226, 222, 214, 222 };
    int[] nodes = { 1, 3, 5, 7 };
    List<Object> result = new ArrayList<>();
    for (int index = 0; index < nodes.length; index++) {
      int node = nodes[index],
        character = characterByNode[node];
      String name = (String) text.invoke(null, 174 + character);
      String className = (String) text.invoke(null, classes[index]);
      int routeIndex = -1;
      for (int candidate = 0; candidate < routes.length; candidate++) {
        if (routes[candidate][0] == 0 && routes[candidate][1] == node) {
          routeIndex = candidate;
          break;
        }
      }
      result.add(
        step(
          "route",
          "nodeId",
          node,
          "characterId",
          character,
          "name",
          name,
          "nameTextIndex",
          174 + character,
          "className",
          className,
          "classTextIndex",
          classes[index],
          "label",
          name + "(" + className + ")",
          "portraitId",
          character,
          "routeIndex",
          routeIndex
        )
      );
    }
    return result;
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
