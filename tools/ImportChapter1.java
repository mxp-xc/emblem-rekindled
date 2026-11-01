import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import javax.imageio.ImageIO;
import org.recompile.mobile.Mobile;
import org.recompile.mobile.MobilePlatform;

/** Offline importer. The unmodified source renderer is used only during conversion. */
public final class ImportChapter1 {

  private static final String SOURCE_SHA =
    "67d1c77e823816e203244a15428ba9fb635d40edba04efa3180b3334025989fe";
  private static MobilePlatform platform;
  private static int battleIndex;

  public static void main(String[] args) {
    try {
      battleIndex = args.length > 3 ? Integer.parseInt(args[3]) : 0;
      if (battleIndex < 0 || battleIndex > 1) throw new IllegalArgumentException(
        "Unverified chapter-1 battle: m" + battleIndex
      );
      run(
        Path.of(args[0]).toAbsolutePath(),
        Path.of(args[1]).toAbsolutePath(),
        Path.of(args[2]).toAbsolutePath()
      );
      System.exit(0); // The reference MIDlet owns background threads.
    } catch (Throwable error) {
      error.printStackTrace();
      System.exit(1);
    }
  }

  private static Field field(Class<?> type, String name) throws Exception {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field result = current.getDeclaredField(name);
        result.setAccessible(true);
        return result;
      } catch (NoSuchFieldException absent) {
        // Fields on reference sprites also live in their base class.
      }
    }
    throw new NoSuchFieldException(type.getName() + "." + name);
  }

  private static int number(Object target, String name) throws Exception {
    return ((Number) field(target.getClass(), name).get(target)).intValue();
  }

  private static String quote(String value) {
    return (
      "\"" +
      value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t") +
      "\""
    );
  }

  private static javax.microedition.lcdui.Image image(int width, int height) {
    var result = javax.microedition.lcdui.Image.createRGBImage(
      new int[width * height],
      width,
      height,
      true
    );
    result.setMutable(true);
    return result;
  }

  private static void draw(Object frame, javax.microedition.lcdui.Image target, int x, int y)
    throws Exception {
    frame
      .getClass()
      .getMethod("a", javax.microedition.lcdui.Graphics.class, int.class, int.class)
      .invoke(frame, target.getGraphics(), x, y);
  }

  private static void run(Path source, Path output, Path variantsFile) throws Exception {
    String sha = HexFormat.of().formatHex(
      MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(source))
    );
    if (!sha.equals(SOURCE_SHA)) throw new IllegalArgumentException(
      "Unexpected chapter-1 JAR SHA-256: " + sha
    );
    Files.createDirectories(output);
    if (battleIndex == 0) try (var archive = new java.util.zip.ZipFile(source.toFile())) {
      try (InputStream icon = archive.getInputStream(archive.getEntry("icon.png"))) {
        Files.copy(icon, output.resolve("icon.png"), StandardCopyOption.REPLACE_EXISTING);
      }
    }
    Mobile.lcdWidth = 240;
    Mobile.lcdHeight = 320;
    platform = new MobilePlatform(240, 320);
    Mobile.setPlatform(platform, () -> {});
    platform.dataPath = Path.of(".").toAbsolutePath().normalize() + "/";
    if (!platform.load(source.toUri().toString())) throw new IOException(
      "Cannot load reference JAR"
    );
    platform.runJar();
    Object canvas = null;
    Object game = null;
    long deadline = System.nanoTime() + 15_000_000_000L;
    while (System.nanoTime() < deadline) {
      if (Mobile.midlet != null) {
        canvas = field(Mobile.midlet.getClass(), "a").get(null);
        if (canvas != null) {
          // The music-choice menu is the active screen; a.t holds the game.
          game = field(Class.forName("a", false, platform.loader), "t").get(null);
          if (game != null && number(game, "bd") == 34) break;
        }
      }
      Thread.sleep(100);
    }
    if (game == null || number(game, "bd") != 34) throw new IOException(
      "Reference startup timed out"
    );
    // Deterministic offline preparation, not a natural playthrough or runtime dependency.
    field(canvas.getClass(), "o").setBoolean(null, true);
    Thread.sleep(150);
    Class<?> helper = Class.forName("h", true, platform.loader);
    field(helper, "p").set(null, new Random(0));
    field(game.getClass(), "bh").setByte(game, (byte) 0);
    game
      .getClass()
      .getMethod("a", int.class, boolean.class, boolean.class)
      .invoke(game, 0, true, true);
    game.getClass().getMethod("E").invoke(game);
    if (battleIndex == 1) prepareSecondBattle(source, canvas, game);
    int width = number(game, "cf"),
      height = number(game, "ce");
    int expectedWidth = battleIndex == 0 ? 20 : 22;
    int expectedHeight = battleIndex == 0 ? 25 : 22;
    if (width != expectedWidth || height != expectedHeight) throw new IOException(
      "Unexpected m" + battleIndex + " map size: " + width + "x" + height
    );
    byte[][] grid = (byte[][]) field(game.getClass(), "cd").get(game);
    Object[] tiles = (Object[]) field(game.getClass(), "b").get(game);
    var mapImage = image(width * 24, height * 24);
    StringBuilder map = new StringBuilder(
      "{\"width\":" + width + ",\"height\":" + height + ",\"tileSize\":24,\"tiles\":["
    );
    for (int y = 0; y < height; y++) {
      if (y > 0) map.append(',');
      map.append('[');
      for (int x = 0; x < width; x++) {
        int tile = grid[y][x] & 255;
        if (x > 0) map.append(',');
        map.append(tile);
        draw(tiles[tile], mapImage, x * 24, y * 24);
      }
      map.append(']');
    }
    map.append("],\"terrain\":[");
    Method terrain = game.getClass().getMethod("p", int.class, int.class);
    for (int y = 0; y < height; y++) {
      if (y > 0) map.append(',');
      map.append('[');
      for (int x = 0; x < width; x++) {
        if (x > 0) map.append(',');
        map.append(terrain.invoke(game, x, y));
      }
      map.append(']');
    }
    Vector<?> units = (Vector<?>) field(game.getClass(), "as").get(game);
    Set<Integer> groups = new TreeSet<>();
    for (Object unit : units) groups.add(number(unit, "R"));
    Object originalCache = field(game.getClass(), "cB").get(game);
    map.append("],\"movementCosts\":{");
    // Unit blocking belongs to live gameplay, not the generated terrain data.
    field(game.getClass(), "as").set(game, new Vector<>());
    field(game.getClass(), "cB").set(game, null);
    try {
      Method cost = Class.forName("b", true, platform.loader).getMethod(
        "a",
        int.class,
        int.class,
        byte.class,
        byte.class
      );
      boolean firstGroup = true;
      for (int group : groups) {
        if (!firstGroup) map.append(',');
        firstGroup = false;
        map.append(quote(String.valueOf(group))).append(":[");
        for (int y = 0; y < height; y++) {
          if (y > 0) map.append(',');
          map.append('[');
          for (int x = 0; x < width; x++) {
            if (x > 0) map.append(',');
            map.append(cost.invoke(null, x, y, (byte) group, (byte) 0));
          }
          map.append(']');
        }
        map.append(']');
      }
    } finally {
      field(game.getClass(), "as").set(game, units);
      field(game.getClass(), "cB").set(game, originalCache);
    }
    map.append("}}\n");
    Files.writeString(output.resolve("map.json"), map);
    ImageIO.write(mapImage.getCanvas(), "png", output.resolve("map.png").toFile());
    if (units.size() != 32) throw new IOException("Unexpected deployment count: " + units.size());
    StringBuilder json = new StringBuilder("[");
    int visibleCount = 0;
    for (int index = 0; index < units.size(); index++) {
      Object unit = units.get(index);
      int id = number(unit, "y");
      int x = number(unit, "D"),
        y = number(unit, "E");
      // Opening z() moves these two units before player control (reference i.java).
      if (battleIndex == 0 && id == 10) {
        x = 7;
        y = 9;
      }
      if (battleIndex == 0 && id == 11) {
        x = 10;
        y = 13;
      }
      boolean visible =
        battleIndex == 0 ? id != 13 && id != 14 && id != 15 : (number(unit, "B") & 1) == 0;
      if (visible) visibleCount++;
      Object[] frames = (Object[]) field(unit.getClass(), "ap").get(unit);
      var sprite = image(64, 64);
      draw(frames[0], sprite, 24, 24);
      ImageIO.write(sprite.getCanvas(), "png", output.resolve("unit_" + id + ".png").toFile());
      if (index > 0) json.append(',');
      Map<String, Object> unitData = Chapter1Rules.describeUnit(unit);
      unitData.put("x", x);
      unitData.put("y", y);
      unitData.put("visible", visible);
      int flags = ((Number) unitData.get("flags")).intValue();
      unitData.put("flags", visible ? flags & ~1 : flags | 1);
      unitData.put("sprite", "unit_" + id + ".png");
      unitData.put("spriteOffsetX", -24);
      unitData.put("spriteOffsetY", -24);
      json.append(Chapter1Rules.json(unitData));
    }
    json.append("]\n");
    Files.writeString(output.resolve("units.json"), json);
    if (battleIndex == 0) Chapter1Rules.export(game, platform.loader, output);
    Chapter1MapAssets.export(game, platform.loader, output);
    Map<Integer, Object> unitIndex = new HashMap<>();
    for (Object unit : units) unitIndex.put(number(unit, "y"), unit);
    Method category = Class.forName("b", true, platform.loader).getMethod("n", byte.class);
    StringBuilder variants = new StringBuilder();
    for (String line : Files.readAllLines(variantsFile)) {
      String[] columns = line.split("\t");
      int id = Integer.parseInt(columns[0]);
      Object unit = unitIndex.get(id);
      Set<Integer> legal = new TreeSet<>();
      legal.add(0);
      for (String candidate : columns[1].split(",")) {
        int weapon = Integer.parseInt(candidate);
        if (
          weapon > 0 &&
          weapon <= 52 &&
          (((Number) category.invoke(null, (byte) weapon)).intValue() & number(unit, "H")) != 0
        ) legal.add(weapon);
      }
      variants.append(id).append('\t');
      boolean first = true;
      for (int weapon : legal) {
        if (!first) variants.append(',');
        first = false;
        variants.append(weapon);
      }
      variants.append('\n');
    }
    Path legalVariants = variantsFile.resolveSibling("legal_battle_variants.tsv");
    Files.writeString(legalVariants, variants);
    Chapter1BattleAssets.export(game, platform.loader, output, legalVariants);
    Chapter1BattleClips.export(game, platform.loader, output, legalVariants);
    if (battleIndex == 0) Chapter1Story.export(game, platform.loader, output);
    else Chapter1Story.exportSecondBattle(game, platform.loader, output);
    Chapter1Interface.export(game, platform.loader, output);
    if (battleIndex == 0) {
      try (
        InputStream midi = (InputStream) helper.getMethod("c", String.class).invoke(null, "p.mid")
      ) {
        Files.copy(midi, output.resolve("map_music.mid"), StandardCopyOption.REPLACE_EXISTING);
      }
      try (
        InputStream midi = (InputStream) helper
          .getMethod("c", String.class)
          .invoke(null, "battle.mid")
      ) {
        Files.copy(midi, output.resolve("battle_music.mid"), StandardCopyOption.REPLACE_EXISTING);
      }
      for (String name : List.of("title", "world")) {
        try (
          InputStream midi = (InputStream) helper
            .getMethod("c", String.class)
            .invoke(null, name + ".mid")
        ) {
          Files.copy(
            midi,
            output.resolve(name + "_music.mid"),
            StandardCopyOption.REPLACE_EXISTING
          );
        }
      }
      for (String[] track : List.of(
        new String[] { "win", "victory" },
        new String[] { "over", "defeat" }
      )) {
        try (
          InputStream midi = (InputStream) helper
            .getMethod("c", String.class)
            .invoke(null, track[0] + ".mid")
        ) {
          Files.copy(
            midi,
            output.resolve(track[1] + "_music.mid"),
            StandardCopyOption.REPLACE_EXISTING
          );
        }
      }
    }
    Files.writeString(
      output.resolve("provenance.json"),
      "{\"sourceSha256\":" +
        quote(sha) +
        ",\"map\":\"1.pak:m" +
        battleIndex +
        "\",\"deployment\":" +
        quote(battleIndex == 0 ? "1.pak:p0" : "p1") +
        ",\"preparationSeed\":0,\"unitCount\":32,\"visibleUnitCount\":" +
        visibleCount +
        ",\"method\":" +
        quote(
          battleIndex == 0
            ? "offline original initializer and frame renderer; opening positions applied explicitly; map sprites are first-frame stills"
            : "controlled native m0 cleanup then m1 initializer; matched to separately replayed original entry; verified default commander6; map sprites are first-frame stills"
        ) +
        "}\n"
    );
    System.out.println(
      "IMPORT_OK m" +
        battleIndex +
        " " +
        width +
        "x" +
        height +
        " units=" +
        units.size() +
        " visible=" +
        visibleCount
    );
  }

  /** Controlled native preparation, matched against the separately replayed m0-to-m1 entry. */
  private static void prepareSecondBattle(Path source, Object canvas, Object game)
    throws Exception {
    Class<?> type = game.getClass();
    for (String name : List.of("aw", "ay", "aA", "aB", "aC")) {
      field(type, name).set(game, new Vector<>());
    }
    for (String name : List.of("bE", "bF", "bG", "bI", "bB", "bD", "bV", "bK", "cS")) {
      field(type, name).setBoolean(game, false);
    }
    field(type, "eg").setInt(game, 0);
    field(type, "eh").setInt(game, 320);
    field(type, "bd").setByte(game, (byte) 11);
    field(type, "dc").setInt(game, -1);
    canvas
      .getClass()
      .getMethod("a", Class.forName("e", false, platform.loader))
      .invoke(canvas, game);
    field(type, "be").setByte(game, (byte) 10);
    field(type, "bJ").setInt(game, 1);
    type.getMethod("d").invoke(game);
    type.getMethod("d").invoke(game);
    field(type, "bh").setByte(game, (byte) 1);
    field(type, "dr").setByte(game, (byte) 0);
    for (String name : List.of("dD", "du", "dt")) field(type, name).setByte(game, (byte) 1);
    try (var archive = new java.util.zip.ZipFile(source.toFile())) {
      try (InputStream input = archive.getInputStream(archive.getEntry("p1"))) {
        field(Class.forName("a", false, platform.loader), "B").set(null, input.readAllBytes());
      }
    }
    type.getMethod("D").invoke(game);
    type.getMethod("a", int.class, boolean.class, boolean.class).invoke(game, 1, false, true);
    type.getMethod("E").invoke(game);
    // The original opening chooses the only visible formal commander before player control.
    for (Object unit : (List<?>) field(type, "as").get(game)) {
      if (number(unit, "y") == 6) {
        field(Class.forName("b", false, platform.loader), "b").set(null, unit);
        return;
      }
    }
    throw new IOException("Verified m1 default commander6 is missing");
  }
}
