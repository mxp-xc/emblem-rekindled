import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javax.imageio.ImageIO;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Original first-chapter interface wording and pixel-frame conversion. */
public final class Chapter1Interface {

  private Chapter1Interface() {}

  /** Call only with the already initialized, paused reference runtime in a temporary cwd. */
  public static void export(Object game, ClassLoader loader, Path output) throws Exception {
    Class<?> textClass = Class.forName("e", true, loader);
    Class<?> unitClass = Class.forName("b", true, loader);
    Class<?> panelClass = Class.forName("c", true, loader);
    Method text = textClass.getMethod("b", int.class);
    Method itemStat = unitClass.getMethod("a", byte.class, byte.class);
    Method category = unitClass.getMethod("n", byte.class);
    Method jobMask = unitClass.getMethod("f", byte.class);
    Method itemIcon = unitClass.getMethod("o", byte.class);
    if (!(get(game, "as") instanceof List<?> units) || units.isEmpty()) {
      throw new IllegalArgumentException("Reference first-battle deployment is not initialized");
    }
    Path directory = output.resolve("ui");
    Files.createDirectories(directory);
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("schemaVersion", 1);
    result.put("chapterId", "chapter_1");
    result.put("pathsRelativeTo", "manifest.json");

    int[] indices = { 75, 61, 66, 67, 62, 63, 64, 65, 68, 69, 70, 71, 72, 99, 80 };
    String[] ids = {
      "hp",
      "strength",
      "defense",
      "movement",
      "resistance",
      "skill",
      "speed",
      "luck",
      "attack",
      "critical",
      "hit",
      "evasion",
      "range",
      "level",
      "durability",
    };
    Map<String, Object> labels = new LinkedHashMap<>();
    List<Object> attributes = new ArrayList<>();
    for (int id = 0; id < indices.length; id++) {
      Map<String, Object> label = line(text, indices[id]);
      labels.put(ids[id], label);
      attributes.add(
        row("id", ids[id], "sourceAttributeId", id, "label", label, "icon", "attribute_" + id)
      );
    }
    for (Object[] label : new Object[][] {
      { "equip", 30 },
      { "status", 25 },
      { "backpack", 26 },
      { "item", 26 },
      { "combatPower", 73 },
      { "gold", 15 },
      { "confirm", 6 },
      { "cancel", 7 },
      { "wait", 27 },
      { "exchange", 31 },
      { "endTurn", 29 },
      { "returnToTitle", 22 },
      { "menu", 28 },
      { "back", 9 },
      { "continue", 8 },
    })
      labels.put((String) label[0], line(text, (int) label[1]));
    result.put("labels", labels);
    result.put("attributes", attributes);

    String[] nativeTabs = (String[]) get(game, "eK");
    result.put(
      "unitInformation",
      row(
        "source",
        "i.d input524288 -> i.a(b,e); c.ad5 header; i.eK/eO/eN",
        "nativePageCount",
        3,
        "header",
        List.of("name", "className", "currentHp", "maxHp", "experience", "level", "equipMask"),
        "headerFields",
        row(
          "name",
          "b.w",
          "className",
          "b.x",
          "currentHp",
          "b.Q",
          "maxHp",
          "b.N",
          "experience",
          "b.U",
          "level",
          "b.T + 1",
          "equipMask",
          "b.H"
        ),
        "pages",
        List.of(
          row(
            "id",
            "combat",
            "nativeIndex",
            0,
            "title",
            nativeTabs[0],
            "titleSource",
            List.of(60, 68),
            "attributes",
            attributeNames((byte[]) get(game, "eO"), ids)
          ),
          row(
            "id",
            "basic",
            "nativeIndex",
            1,
            "title",
            nativeTabs[1],
            "titleSource",
            List.of(60, 73),
            "attributes",
            attributeNames((byte[]) get(game, "eN"), ids)
          ),
          row(
            "id",
            "equipment",
            "nativeIndex",
            2,
            "title",
            nativeTabs[2],
            "titleSource",
            List.of(100),
            "confirmAction",
            "itemDetails"
          )
        ),
        "baseFieldByAttribute",
        row(
          "strength",
          "I",
          "skill",
          "J",
          "speed",
          "K",
          "defense",
          "L",
          "resistance",
          "M",
          "luck",
          "P",
          "movement",
          "O"
        ),
        "attributeDisplay",
        "Original i.a(byte[],b,...): base field plus b.a(unit,stat,2,false); combat values use original b methods and equipped F",
        "missingWeaponValue",
        "--",
        "rangeSeparator",
        ".",
        "equipment",
        row(
          "source",
          "b.v pairs[itemId,remainingUses]; i.c(Vector)",
          "zeroRemainingUsesDisplay",
          "-",
          "itemConfirmSource",
          "i.a(c,int,String,byte) when c==s[2] -> c(byte[]) -> i.a(item,-1,false)"
        )
      )
    );

    Map<String, Object> jobs = new LinkedHashMap<>();
    for (int id = 0; id <= 40; id++) jobs.put(
      String.valueOf(id),
      row(
        "id",
        id,
        "name",
        line(text, 206 + id),
        "equipMask",
        ((Number) jobMask.invoke(null, (byte) id)).intValue()
      )
    );
    result.put("jobs", jobs);
    result.put(
      "equipMaskIcons",
      row(
        "1",
        "item_0",
        "2",
        "item_1",
        "4",
        "item_3",
        "8",
        "item_4",
        "16",
        "item_5",
        "32",
        "item_2"
      )
    );

    Map<String, Object> items = new LinkedHashMap<>();
    String[] statNames = {
      "power",
      "hit",
      "critical",
      "minRange",
      "maxRange",
      "weight",
      "defaultDurability",
      "price",
    };
    for (int id = 1; id <= 87; id++) {
      int mask = ((Number) category.invoke(null, (byte) id)).intValue();
      int icon = id == 29 || id == 30 ? -1 : ((Number) itemIcon.invoke(null, (byte) id)).intValue();
      Map<String, Object> item = row(
        "id",
        id,
        "name",
        line(text, 272 + id),
        "description",
        line(text, 359 + id),
        "categoryMask",
        mask,
        "icon",
        icon < 0 ? null : "item_" + icon
      );
      for (byte stat = 0; stat < statNames.length; stat++) item.put(
        statNames[stat],
        ((Number) itemStat.invoke(null, stat, (byte) id)).intValue()
      );
      item.put(
        "detailAttributes",
        id >= 53
          ? List.of("durability")
          : List.of("attack", "hit", "critical", "range", "durability")
      );
      item.put(
        "descriptionSource",
        "i.a(byte,int,boolean,int): t.bin[359+itemId]; no generated effect prose"
      );
      List<Integer> allowedJobs = new ArrayList<>();
      if (mask > 0 && mask <= 32) {
        for (int job = 0; job <= 40; job++) {
          int allowed = ((Number) jobMask.invoke(null, (byte) job)).intValue();
          if ((allowed & mask) != 0) allowedJobs.add(job);
        }
      }
      item.put("jobsWithCategoryMask", allowedJobs);
      item.put(
        "equipEligibility",
        "category capability only; original b.i/b.h and context checks may further restrict use"
      );
      items.put(String.valueOf(id), item);
    }
    result.put("items", items);
    result.put(
      "itemDetails",
      row(
        "source",
        "i.c(byte[]) -> i.a(byte[],int,boolean) -> i.a(byte,int,boolean,int)",
        "nameTextIndex",
        "272+itemId",
        "descriptionTextIndex",
        "359+itemId",
        "rawStatOrder",
        List.of("attack", "hit", "critical", "range", "durability"),
        "rawStatsUseUnitBonuses",
        false,
        "supportItemsShowOnly",
        List.of("durability"),
        "supportItemThreshold",
        53,
        "rawDescriptionWrap",
        "Original font width wrapping, then two lines per secondary panel; preserve text and let target layout wrap"
      )
    );

    Map<String, Object> textures = new LinkedHashMap<>();
    exportFrames(get(game, "A"), "attribute", "letter.sp", directory, textures);
    exportFrames(get(game, "z"), "item", "item.sp", directory, textures);
    exportFrames(get(game, "L"), "corner", "corner.sp", directory, textures);
    exportFrames(get(game, "I"), "side_arrow", "side_arrow.sp", directory, textures);
    exportFrames(get(game, "J"), "target_arrow", "arrow.sp", directory, textures);
    exportFrames(get(game, "K"), "advantage_arrow", "effud.sp", directory, textures);
    exportFrames(get(game, "H"), "button", "buttons.sp", directory, textures);
    exportFrame(get(game, "C"), "finger", "finger.png", directory, textures);
    exportFrame(get(game, "D"), "experience", "exp.png", directory, textures);

    Method rectangle = panelClass.getMethod(
      "a",
      Graphics.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class,
      int.class
    );
    result.put("mapHud", exportMapHud(game, rectangle, directory, textures));
    result.put("battleHud", exportBattleHud(game, loader, rectangle, directory, textures));
    exportPanel(
      rectangle,
      directory,
      textures,
      "window_frame",
      32,
      32,
      0,
      6061751,
      6061751,
      -1,
      15
    );
    exportPanel(
      rectangle,
      directory,
      textures,
      "content_frame",
      32,
      32,
      0,
      2182279,
      2182279,
      -1,
      15
    );
    exportPanel(
      rectangle,
      directory,
      textures,
      "menu_sample",
      160,
      96,
      12,
      6061751,
      1848415,
      100,
      3
    );
    exportPanel(
      rectangle,
      directory,
      textures,
      "header_sample",
      160,
      48,
      13,
      4284563,
      141919,
      -1,
      15
    );
    exportPanel(
      rectangle,
      directory,
      textures,
      "item_detail_sample",
      160,
      64,
      14,
      1991791,
      146243,
      -1,
      15
    );
    Map<String, Object> portraits = new LinkedHashMap<>();
    Method resource = Class.forName("h", true, loader).getMethod("c", String.class);
    for (Object unit : units) {
      int id = number(unit, "y"),
        portrait = number(unit, "A"),
        group = number(unit, "R");
      String key = portrait < 0 ? null : "portrait_" + portrait;
      if (key != null && !textures.containsKey(key)) {
        String source = String.format("portraits_%02d.png", portrait);
        byte[] bytes;
        try (InputStream input = (InputStream) resource.invoke(null, source)) {
          if (input == null) throw new IOException("Missing original portrait " + source);
          bytes = input.readAllBytes();
        }
        var image = ImageIO.read(new ByteArrayInputStream(bytes));
        if (image == null) throw new IOException("Invalid original portrait " + source);
        Files.write(directory.resolve(key + ".png"), bytes);
        textures.put(
          key,
          row(
            "texture",
            key + ".png",
            "width",
            image.getWidth(),
            "height",
            image.getHeight(),
            "source",
            source
          )
        );
      }
      portraits.put(
        String.valueOf(id),
        row(
          "portraitId",
          portrait < 0 ? null : portrait,
          "texture",
          key,
          "usesCommanderPortrait",
          number(unit, "C") == 1 && group != 7 && group != 8 && group != 9,
          "fallback",
          "unitSprite"
        )
      );
    }
    result.put("portraitByUnitId", portraits);
    result.put(
      "portraitSource",
      "i.a(b,e): C1 outside classGroups7/8/9 uses current commander.A when commander exists; otherwise unit.A; A<0 uses unit map sprite in c.ad5"
    );
    result.put("textures", textures);
    result.put(
      "styles",
      row(
        "pixelFilter",
        "nearest",
        "ninePatch",
        row(
          "texture",
          "window_frame",
          "textureMargins",
          List.of(5, 5, 5, 5),
          "contentMargins",
          List.of(8, 5, 8, 5),
          "source",
          "Original c.a renderer, all four borders enabled, equal fill colors; no ornamental corner overlay"
        ),
        "contentNinePatch",
        row(
          "texture",
          "content_frame",
          "textureMargins",
          List.of(5, 5, 5, 5),
          "contentMargins",
          List.of(8, 5, 8, 5)
        ),
        "nativeFrameLayersOutsideIn",
        List.of("#000000", "#FFFFFF", hex(9410465), hex(13094614), "#000000"),
        "frameSource",
        "i.b(Graphics,x,y,width,height) clipped to 5px edges by c.a; native corners are separate g(corner) frames",
        "borderOmitMask",
        row("top", 1, "bottom", 2, "left", 4, "right", 8),
        "nativeMenu",
        row(
          "fill",
          hex(6061751),
          "gradient",
          hex(1848415),
          "text",
          "#FFFFFF",
          "selectedRow",
          "#6888A8",
          "borderOmitMask",
          12,
          "cornerOmitMask",
          3,
          "gradientDivisor",
          100,
          "gradientSteps",
          12,
          "source",
          "i.a(e,String[],byte[]); source center anchor3 at aX,aY"
        ),
        "nativeInfoHeader",
        row("fill", hex(4284563), "gradient", hex(141919), "borderOmitMask", 13),
        "nativeTabs",
        row(
          "fill",
          hex(2181250),
          "gradient",
          hex(140117),
          "text",
          hex(15718144),
          "borderOmitMask",
          15
        ),
        "nativeInfoBody",
        row("fill", hex(2182279), "gradient", hex(2182279), "borderOmitMask", 2),
        "nativeItemDetail",
        row("fill", hex(1991791), "gradient", hex(146243), "borderOmitMask", 14)
      )
    );
    Files.writeString(directory.resolve("manifest.json"), Chapter1Rules.json(result) + "\n");
  }

  private static List<String> attributeNames(byte[] attributes, String[] ids) {
    List<String> result = new ArrayList<>();
    for (byte attribute : attributes) result.add(ids[attribute]);
    return result;
  }

  private static Map<String, Object> exportMapHud(
    Object game,
    Method rectangle,
    Path directory,
    Map<String, Object> textures
  ) throws Exception {
    int height = ((Number) get(game, "a")).intValue();
    Map<String, Object> styles = new LinkedHashMap<>();
    for (boolean enemy : new boolean[] { false, true }) {
      String key = enemy ? "map_hud_enemy_background" : "map_hud_background";
      int fill = enemy ? 11157567 : 6061751;
      int gradient = enemy ? 0x400600 : 1848415;
      Image image = canvas(64, height);
      rectangle.invoke(
        null,
        image.getGraphics(),
        0,
        0,
        64,
        height,
        14,
        fill,
        gradient,
        0,
        5,
        1,
        12,
        3
      );
      save(image, directory.resolve(key + ".png"));
      textures.put(
        key,
        row(
          "texture",
          key + ".png",
          "width",
          64,
          "height",
          height,
          "source",
          "i.a(Graphics,int) -> c.a; native HUD background at width64",
          "borderOmitMask",
          14,
          "cornerOmitMask",
          3
        )
      );
      styles.put(
        enemy ? "enemy" : "normal",
        row(
          "texture",
          key,
          "fill",
          hex(fill),
          "gradient",
          hex(gradient),
          "borderOmitMask",
          14,
          "cornerOmitMask",
          3,
          "gradientDivisor",
          1,
          "gradientSteps",
          12,
          "textureMargins",
          List.of(5, 5, 5, 0)
        )
      );
    }
    Object unit = ((List<?>) get(game, "as")).get(0);
    Method hpBar = game
      .getClass()
      .getMethod("a", Graphics.class, unit.getClass(), byte.class, int.class, int.class, int.class);
    for (boolean full : new boolean[] { false, true }) {
      String key = full ? "map_hud_hp_full" : "map_hud_hp_empty";
      Image image = canvas(64, 6);
      hpBar.invoke(
        game,
        image.getGraphics(),
        unit,
        (byte) (full ? number(unit, "N") : 0),
        0,
        0,
        64
      );
      save(image, directory.resolve(key + ".png"));
      textures.put(
        key,
        row(
          "texture",
          key + ".png",
          "width",
          64,
          "height",
          6,
          "source",
          "i.a(Graphics,b,byte,x,y,width): native HP bar " + (full ? "full" : "empty")
        )
      );
    }
    byte[] defense = (byte[]) get(game, "ev"),
      avoid = (byte[]) get(game, "ew");
    List<Object> terrainValues = new ArrayList<>();
    for (int id = 0; id < defense.length; id++) terrainValues.add(
      row(
        "terrainId",
        id,
        "defense",
        (int) defense[id],
        "avoid",
        (int) avoid[id],
        "nameTextIndex",
        null
      )
    );
    return row(
      "source",
      "i.a(Graphics,int); native cursor selection i.i(x,y) sets Y=q(x,y)",
      "nativeReferenceLayout",
      row(
        "screenWidth",
        number(game, "aL"),
        "screenHeight",
        number(game, "aM"),
        "top",
        number(game, "aW"),
        "height",
        height,
        "contentTopInset",
        5,
        "tilePreviewSize",
        24,
        "purpose",
        "Reference presentation geometry, not a target viewport or gameplay rule"
      ),
      "icons",
      row(
        "menu",
        "button_0",
        "confirm",
        "button_0",
        "back",
        "button_1",
        "continue",
        "button_2",
        "hp",
        "attribute_0",
        "level",
        "attribute_13",
        "evasion",
        "attribute_11",
        "defense",
        "attribute_2"
      ),
      "labels",
      row("menu", "menu", "hp", "hp", "level", "level", "evasion", "evasion", "defense", "defense"),
      "styles",
      styles,
      "unit",
      row(
        "fields",
        List.of("name", "currentHp", "maxHp", "level"),
        "sourceFields",
        row("name", "b.w", "currentHp", "b.Q", "maxHp", "b.N", "level", "b.T+1"),
        "showsPortrait",
        false,
        "showsClassName",
        false,
        "showsBaseAttributes",
        false,
        "enemyStyleFaction",
        2
      ),
      "hpBar",
      row(
        "emptyTexture",
        "map_hud_hp_empty",
        "fullTexture",
        "map_hud_hp_full",
        "outerColor",
        "#000000",
        "backgroundColor",
        hex(2312057),
        "fillColor",
        hex(16760371),
        "nativeHeight",
        6,
        "borderWidth",
        1,
        "cornerCutPixels",
        1,
        "fillWidth",
        "(width-2)*currentHp/maxHp; positive HP has at least one filled pixel; maxHp0 returns before fill"
      ),
      "terrain",
      row(
        "fields",
        List.of("tilePreview", "evasionBonus", "defenseBonus"),
        "nameTextIndex",
        null,
        "originalHudShowsName",
        false,
        "previewSource",
        "Original selected tile b[cd[y][x]]; target may sample map.png at the selected map cell",
        "terrainIdSource",
        "map.json.terrain[y][x] (original ey[cd[y][x]])",
        "defenseValuesReference",
        "../rules.json:terrainDefense",
        "avoidValuesReference",
        "../rules.json:terrainEvasion",
        "positivePrefix",
        "+",
        "values",
        terrainValues
      ),
      "softkeyFrameMapping",
      List.of(
        row("frame", 0, "sourceTextIndices", List.of(6, 28)),
        row("frame", 1, "sourceTextIndices", List.of(9)),
        row("frame", 2, "sourceTextIndices", List.of(8))
      ),
      "selectionRule",
      "Normal map browsing updates Y from the cursor cell. Movement-range cursor changes preserve the selected Y; action/system menus preserve it too. Y!=null shows unit; otherwise terrain."
    );
  }

  private static Map<String, Object> exportBattleHud(
    Object game,
    ClassLoader loader,
    Method rectangle,
    Path directory,
    Map<String, Object> textures
  ) throws Exception {
    int screenWidth = number(game, "aV"),
      screenHeight = number(game, "aM");
    Object numberFont = ((Object[]) field(Class.forName("h", true, loader), "q").get(null))[0];
    int digitWidth = number(numberFont, "at") + 1;
    int digitHeight = number(numberFont, "au");
    exportFrames(numberFont, "number", "lchars.sp", directory, textures);
    Class<?> fontClass = Class.forName("h", true, loader);
    int firstCharacter = ((short[]) field(fontClass, "r").get(null))[0];
    byte[] characterFrames = ((byte[][]) field(fontClass, "t").get(null))[0];
    Map<String, Object> numberGlyphs = new LinkedHashMap<>();
    for (int index = 0; index < characterFrames.length; index++) {
      if (characterFrames[index] >= 0) numberGlyphs.put(
        String.valueOf((char) (firstCharacter + index)),
        "number_" + characterFrames[index]
      );
    }
    // Original f constructor layout, without constructing f or registering a battle sprite.
    int m = digitHeight * 2 + 5,
      l = 13,
      j = 60,
      k;
    int space = screenHeight - j - m * 2 - l * 2;
    if (space > 60) {
      int extra = Math.min((space - 60) / 5, 10);
      m += extra;
      l += extra;
      j += extra;
      k = (space - extra * 5) / 2;
    } else if (space >= 0) {
      k = space / 2;
    } else {
      m = 18;
      k = 0;
    }
    int n = k + l + m;
    int hudHeight = m + l;
    int forecastBottomHeight = Math.max(31, number(game, "a"));
    Map<String, Object> styles = new LinkedHashMap<>();
    for (Object[] definition : new Object[][] {
      { "battle_hud_top", hudHeight, 13, 6061751, 3890583, 15 },
      { "battle_hud_bottom", hudHeight, 14, 11157567, 0x400600, 15 },
      { "forecast_hud_top", 31, 13, 6061751, 1848415, 12 },
      { "forecast_hud_bottom", forecastBottomHeight, 14, 11157567, 0x400600, 3 },
    }) {
      String key = (String) definition[0];
      int height = (int) definition[1],
        flags = (int) definition[2];
      int fill = (int) definition[3],
        gradient = (int) definition[4];
      int corners = (int) definition[5];
      Image image = canvas(64, height);
      // Forecast corner decorations extend outside the panel; export them separately via corner_*.
      rectangle.invoke(
        null,
        image.getGraphics(),
        0,
        0,
        64,
        height,
        flags,
        fill,
        gradient,
        0,
        5,
        1,
        12,
        15
      );
      save(image, directory.resolve(key + ".png"));
      textures.put(
        key,
        row(
          "texture",
          key + ".png",
          "width",
          64,
          "height",
          height,
          "source",
          key.startsWith("battle_") ? "f.a(Graphics) -> c.a" : "c.ad12 -> c.a, settled ar0",
          "borderOmitMask",
          flags,
          "cornerOmitMask",
          15,
          "nativeCornerOmitMask",
          corners
        )
      );
      styles.put(
        key,
        row(
          "texture",
          key,
          "fill",
          hex(fill),
          "gradient",
          hex(gradient),
          "borderOmitMask",
          flags,
          "cornerOmitMask",
          corners,
          "gradientDivisor",
          1,
          "gradientSteps",
          12,
          "gradientBlend",
          List.of(0, 5),
          "textureMargins",
          flags == 13 ? List.of(0, 0, 0, 5) : List.of(0, 5, 0, 0)
        )
      );
    }
    Object[] hpFrames = (Object[]) get(game, "R");
    exportFrame(hpFrames[0], "battle_hp_full", "hp_on.png via game.R[0]", directory, textures);
    exportFrame(hpFrames[1], "battle_hp_empty", "hp_off.png via game.R[1]", directory, textures);
    int segmentWidth = number(hpFrames[0], "c"),
      segmentHeight = number(hpFrames[0], "d");
    int hpX = digitWidth * 2 + 2;
    int topHpBaseY = n - m,
      bottomHpBaseY = n + j + 5;
    int barOffsetY = ((m - 5) >> 2) - (segmentHeight >> 1);
    List<Object> columns = List.of(
      row("id", "attack", "icon", "attribute_8", "nativeX", 0),
      row("id", "hit", "icon", "attribute_10", "nativeX", screenWidth / 3),
      row("id", "critical", "icon", "attribute_9", "nativeX", (screenWidth / 3) * 2)
    );
    return row(
      "source",
      "f.a(Graphics), f.a/b(Graphics,int,int), f.d(Graphics,int,int); i.a(Graphics,String[],...)",
      "nativeReferenceLayout",
      row(
        "screenWidth",
        screenWidth,
        "screenHeight",
        screenHeight,
        "sourceMetrics",
        row("k", k, "l", l, "m", m, "j", j, "n", n),
        "topRect",
        List.of(0, n - hudHeight, screenWidth, hudHeight),
        "bottomRect",
        List.of(0, n + j, screenWidth, hudHeight),
        "animationRect",
        List.of(0, n, screenWidth, j),
        "purpose",
        "Original viewport geometry only; target layout may scale while preserving content and HP segment semantics"
      ),
      "styles",
      styles,
      "numberFont",
      row(
        "source",
        "h.q[0] lchars; h.r/t character mapping",
        "glyphs",
        numberGlyphs,
        "advance",
        digitWidth,
        "height",
        digitHeight
      ),
      "forecastColumns",
      columns,
      "predictionRow",
      row(
        "source",
        "i.c(b,b,canAttack): attack/hit/critical; no counterattack displays --",
        "topY",
        k + ((l - 13) >> 1),
        "bottomY",
        n + j + m + ((l - 13) >> 1),
        "valueOffset",
        List.of(26, 6),
        "missingValue",
        "--"
      ),
      "currentHp",
      row(
        "sourceField",
        "f.y (animated displayed HP, initialized from b.Q)",
        "textOriginTop",
        List.of(0, topHpBaseY + 6),
        "textOriginBottom",
        List.of(0, bottomHpBaseY + 6),
        "numberFontIndex",
        0,
        "digitAdvance",
        digitWidth,
        "numberHeight",
        digitHeight
      ),
      "segmentedHpBar",
      row(
        "source",
        "f.d(Graphics,int,int); f.y current HP, f.z max HP initialized from b.N",
        "fullTexture",
        "battle_hp_full",
        "emptyTexture",
        "battle_hp_empty",
        "topOrigin",
        List.of(hpX, topHpBaseY + barOffsetY),
        "bottomOrigin",
        List.of(hpX, bottomHpBaseY + barOffsetY),
        "pixelsPerHp",
        2,
        "segmentWidth",
        segmentWidth,
        "segmentHeight",
        segmentHeight,
        "wrapAtSegmentIndex",
        2,
        "rowGap",
        2,
        "firstSegmentClipLeftPixels",
        1,
        "maxHpLayout",
        "Draw floor(maxHp*2/segmentWidth) empty segments, then maxHp*2%segmentWidth cropped pixels. Segment index2 resets x to origin and advances y by segmentHeight+2 once.",
        "currentHpLayout",
        "Overlay floor(currentHp*2/segmentWidth) full segments and remaining cropped pixels, with the same index2 wrap. First segment of either row clips its leftmost pixel, including partial segments.",
        "usesNormalizedBarWidth",
        false
      ),
      "forecast",
      row(
        "source",
        "c.ad12; settled gradient phase ar0 (initial ar4 counts down)",
        "nativeReferenceLayout",
        row(
          "topRect",
          List.of(0, 0, screenWidth, 31),
          "bottomRect",
          List.of(0, screenHeight - forecastBottomHeight, screenWidth, forecastBottomHeight),
          "topPredictionY",
          0,
          "bottomPredictionY",
          screenHeight - forecastBottomHeight + 5,
          "hpBarTopRect",
          List.of(screenWidth / 3, digitHeight + 6, screenWidth / 3, 6),
          "hpBarBottomRect",
          List.of(
            screenWidth / 3,
            screenHeight - forecastBottomHeight + 5 + digitHeight + 6,
            screenWidth / 3,
            6
          )
        ),
        "topBackground",
        "forecast_hud_top",
        "advantageUp",
        "advantage_arrow_0",
        "advantageDown",
        "advantage_arrow_1",
        "targetArrow",
        "target_arrow_1",
        "bottomBackground",
        "forecast_hud_bottom",
        "hpBar",
        "mapHud.hpBar",
        "hpText",
        "currentHp/maxHp; original number origin at x=2*(width/3), rowPredictionY+13",
        "cornerOverlays",
        List.of(
          row(
            "texture",
            "corner_2",
            "panel",
            "top",
            "corner",
            "bottomLeft",
            "extendsOutsidePanel",
            true
          ),
          row(
            "texture",
            "corner_3",
            "panel",
            "top",
            "corner",
            "bottomRight",
            "extendsOutsidePanel",
            true
          ),
          row(
            "texture",
            "corner_0",
            "panel",
            "bottom",
            "corner",
            "topLeft",
            "extendsOutsidePanel",
            true
          ),
          row(
            "texture",
            "corner_1",
            "panel",
            "bottom",
            "corner",
            "topRight",
            "extendsOutsidePanel",
            true
          )
        ),
        "canReuseBattleBackground",
        false,
        "backgroundDifference",
        "Top gradient and both native heights differ; forecast adds outward corner decorations."
      )
    );
  }

  private static Map<String, Object> line(Method text, int index) throws Exception {
    String value = (String) text.invoke(null, index);
    return row(
      "sourceTextIndex",
      index,
      "text",
      value,
      "paragraphs",
      List.of(value.split("\\n", -1))
    );
  }

  private static void exportFrames(
    Object sprite,
    String prefix,
    String source,
    Path directory,
    Map<String, Object> textures
  ) throws Exception {
    Object[] frames = (Object[]) get(sprite, "ap");
    for (int index = 0; index < frames.length; index++) exportFrame(
      frames[index],
      prefix + "_" + index,
      source + ":frame" + index,
      directory,
      textures
    );
  }

  private static void exportFrame(
    Object frame,
    String key,
    String source,
    Path directory,
    Map<String, Object> textures
  ) throws Exception {
    int width = number(frame, "c"),
      height = number(frame, "d");
    int x = number(frame, "e"),
      y = number(frame, "f");
    Image canvas = canvas(width, height);
    frame
      .getClass()
      .getMethod("a", Graphics.class, int.class, int.class)
      .invoke(frame, canvas.getGraphics(), -x, -y);
    save(canvas, directory.resolve(key + ".png"));
    textures.put(
      key,
      row(
        "texture",
        key + ".png",
        "width",
        width,
        "height",
        height,
        "originalOffset",
        List.of(x, y),
        "source",
        source
      )
    );
  }

  private static void exportPanel(
    Method rectangle,
    Path directory,
    Map<String, Object> textures,
    String key,
    int width,
    int height,
    int flags,
    int fill,
    int gradient,
    int divisor,
    int corners
  ) throws Exception {
    Image canvas = canvas(width, height);
    rectangle.invoke(
      null,
      canvas.getGraphics(),
      0,
      0,
      width,
      height,
      flags,
      fill,
      gradient,
      4,
      5,
      divisor,
      -1,
      corners
    );
    save(canvas, directory.resolve(key + ".png"));
    textures.put(
      key,
      row(
        "texture",
        key + ".png",
        "width",
        width,
        "height",
        height,
        "source",
        "original c.a(Graphics,...) renderer",
        "borderOmitMask",
        flags,
        "cornerOmitMask",
        corners
      )
    );
  }

  private static Image canvas(int width, int height) {
    Image image = Image.createRGBImage(new int[width * height], width, height, true);
    image.setMutable(true);
    return image;
  }

  private static void save(Image image, Path target) throws IOException {
    if (!ImageIO.write(image.getCanvas(), "png", target.toFile())) throw new IOException(
      "Cannot export interface PNG " + target
    );
  }

  private static String hex(int color) {
    return String.format("#%06X", color);
  }

  private static Map<String, Object> row(Object... entries) {
    Map<String, Object> result = new LinkedHashMap<>();
    for (int index = 0; index < entries.length; index += 2) result.put(
      (String) entries[index],
      entries[index + 1]
    );
    return result;
  }

  private static Object get(Object target, String name) throws Exception {
    return field(target.getClass(), name).get(target);
  }

  private static int number(Object target, String name) throws Exception {
    return ((Number) get(target, name)).intValue();
  }

  private static Field field(Class<?> type, String name) throws Exception {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field field = current.getDeclaredField(name);
        field.setAccessible(true);
        return field;
      } catch (NoSuchFieldException absent) {
        /* Reference UI fields may be inherited. */
      }
    }
    throw new NoSuchFieldException(type.getName() + "." + name);
  }
}
