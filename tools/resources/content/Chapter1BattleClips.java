import java.awt.image.BufferedImage;
import java.io.IOException;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TreeMap;
import java.util.Vector;
import javax.imageio.ImageIO;
import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Runs original chapter-1 animation methods offline, in an isolated temporary working directory. */
public final class Chapter1BattleClips {

  private static final int TICK_MILLIS = 65;
  private static final int LOGIC_TICK_UNITS = 50;
  private final Object game;
  private final Class<?> fighterClass;
  private final Class<?> helperClass;
  private final Path directory;
  private final int width;
  private final int height;
  private final byte[][] originalWeaponFrames;
  private final Map<String, Object> textures = new LinkedHashMap<>();
  private final IdentityHashMap<Object, Integer> instances = new IdentityHashMap<>();

  private Chapter1BattleClips(Object game, ClassLoader loader, Path output)
    throws ReflectiveOperationException {
    this.game = game;
    fighterClass = Class.forName("f", true, loader);
    helperClass = Class.forName("h", true, loader);
    directory = output.resolve("battle/clips");
    width = number(game, "aL");
    height = number(game, "aM");
    byte[][] sourceWeaponFrames = (byte[][]) field(fighterClass, "aj").get(null);
    originalWeaponFrames = new byte[sourceWeaponFrames.length][];
    for (int index = 0; index < sourceWeaponFrames.length; index++) originalWeaponFrames[index] =
      sourceWeaponFrames[index].clone();
  }

  /** Input is the same legal deploymentId TAB weaponId,... TSV used by BattleAssets. */
  public static void export(Object game, ClassLoader loader, Path output, Path variantsFile)
    throws ReflectiveOperationException, IOException {
    export(game, loader, output, variantsFile, null);
  }

  /** Reuse only an explicitly declared bank stage with an identical native stage contract. */
  public static void export(
    Object game,
    ClassLoader loader,
    Path output,
    Path variantsFile,
    Path reusePlan
  ) throws ReflectiveOperationException, IOException {
    Chapter1BattleClips exporter = new Chapter1BattleClips(game, loader, output);
    try (State state = new State(game, loader)) {
      exporter.export(variantsFile, reusePlan);
    }
  }

  private void export(Path variantsFile, Path reusePlan)
    throws ReflectiveOperationException, IOException {
    Files.createDirectories(directory);
    Map<Integer, Object> units = new LinkedHashMap<>();
    for (Object unit : (List<?>) get(game, "as")) units.put(number(unit, "y"), unit);
    Map<String, Variant> attacks = new LinkedHashMap<>();
    Map<String, Variant> defenses = new LinkedHashMap<>();
    Map<String, Object> appearances = new LinkedHashMap<>();
    Map<String, Object> mapAttacks = new LinkedHashMap<>();
    Class<?> nativeUnit = Class.forName("b", true, fighterClass.getClassLoader());
    var areaAttack = nativeUnit.getMethod("i", byte.class);
    var earthquake = nativeUnit.getMethod("h", byte.class);
    List<String> lines = Files.readAllLines(variantsFile);
    for (String line : lines) {
      if (line.isBlank() || line.startsWith("#")) continue;
      String[] columns = line.split("\t", -1);
      if (columns.length != 2) throw new IOException("Expected two TSV columns: " + line);
      int id = Integer.parseInt(columns[0]);
      Object unit = units.get(id);
      if (unit == null) throw new IOException("Unknown deployment " + id);
      for (String value : columns[1].split(",")) {
        int weapon = Integer.parseInt(value);
        boolean mapAttack =
          (boolean) areaAttack.invoke(unit, (byte) weapon) ||
          (boolean) earthquake.invoke(unit, (byte) weapon);
        boolean independentAttack = weapon > 0 && !mapAttack;
        reset();
        set(unit, "F", (byte) weapon);
        Object fighter = make(unit, null);
        Map<String, Object> geometry = geometry(fighter);
        String defense = "shape_" + digest(Chapter1Rules.json(geometry)).substring(0, 16);
        Map<String, Object> behavior = new LinkedHashMap<>(geometry);
        behavior.put("effectKind", number(fighter, "E"));
        behavior.put("thrown", fighterClass.getMethod("p").invoke(fighter));
        behavior.put("lance", fighterClass.getMethod("q").invoke(fighter));
        String attack = "action_" + digest(Chapter1Rules.json(behavior)).substring(0, 16);
        Variant variant = new Variant(unit, weapon, attack, defense, geometry, behavior);
        defenses.putIfAbsent(defense, variant);
        if (independentAttack) attacks.putIfAbsent(attack, variant);
        String appearance = id + ":" + weapon;
        Map<String, Object> appearanceDefinition = new LinkedHashMap<>();
        appearanceDefinition.put("actionGroup", independentAttack ? attack : null);
        appearanceDefinition.put("defenseGroup", defense);
        appearanceDefinition.put("canAttack", independentAttack);
        if (mapAttack) mapAttacks.put(
          appearance,
          Map.of("weapon", weapon, "defenseGroup", defense)
        );
        if (appearances.put(appearance, appearanceDefinition) != null) {
          throw new IOException("Duplicate appearance " + appearance);
        }
      }
    }
    Map<String, Object> groups = new LinkedHashMap<>();
    for (Variant variant : attacks.values()) groups.put(variant.attack, variant.behavior);
    Map<String, Object> shapes = new LinkedHashMap<>();
    for (Variant variant : defenses.values()) shapes.put(variant.defense, variant.geometry);
    Map<String, SampleRequest> candidates = new LinkedHashMap<>();
    for (Variant attacker : attacks.values()) {
      boolean normalGenerated = generatedNoncritical(attacker.behavior);
      boolean criticalGenerated = generatedCritical(attacker.behavior);
      if (normalGenerated && criticalGenerated) continue;
      for (Variant defender : defenses.values()) {
        if (attacker.side() == defender.side()) continue;
        for (int slot = 0; slot < 2; slot++) for (String outcome : List.of(
          "hit",
          "miss",
          "critical"
        )) {
          if (!outcome.equals("critical") && normalGenerated) continue;
          if (outcome.equals("critical") && criticalGenerated) continue;
          String key = attacker.attack + "/" + defender.defense + "/" + slot + "/" + outcome;
          candidates.put(key, new SampleRequest(attacker, defender, outcome, slot));
        }
      }
    }
    Map<String, Object> signature = stageSignature();
    ReusePlan reuse = readReusePlan(reusePlan);
    String stage = reuse.match(signature);
    Set<String> reusedClips = new LinkedHashSet<>(candidates.keySet());
    reusedClips.retainAll(reuse.clips.getOrDefault(stage, Set.of()));
    Set<String> reusedDeaths = new LinkedHashSet<>(defenses.keySet());
    reusedDeaths.retainAll(reuse.deaths.getOrDefault(stage, Set.of()));
    Map<String, Object> plan = new LinkedHashMap<>();
    plan.put("schemaVersion", 1);
    plan.put("matchedStage", stage);
    plan.put("nativeStage", signature);
    plan.put("mapAttacks", mapAttacks);
    plan.put("clips", planRows(candidates.keySet(), reusedClips));
    plan.put("deaths", planRows(defenses.keySet(), reusedDeaths));
    plan.put(
      "counts",
      Map.of(
        "candidateClips",
        candidates.size(),
        "newClips",
        candidates.size() - reusedClips.size(),
        "reusedClips",
        reusedClips.size(),
        "candidateDeaths",
        defenses.size(),
        "newDeaths",
        defenses.size() - reusedDeaths.size(),
        "reusedDeaths",
        reusedDeaths.size()
      )
    );
    Files.writeString(directory.resolve("motion-plan.json"), Chapter1Rules.json(plan) + "\n");
    Map<String, Object> clips = new LinkedHashMap<>();
    for (var entry : candidates.entrySet()) {
      String key = entry.getKey();
      if (!reusedClips.contains(key)) {
        SampleRequest request = entry.getValue();
        Map<String, Object> clip = sample(
          request.attacker,
          request.defender,
          request.outcome,
          request.slot,
          0,
          0
        );
        Path path = directory.resolve(key + ".json");
        Files.createDirectories(path.getParent());
        Files.writeString(path, Chapter1Rules.json(clip) + "\n");
        clips.put(key, key + ".json");
      }
    }
    Map<String, Object> deaths = new LinkedHashMap<>();
    for (Variant defender : defenses.values()) {
      if (!reusedDeaths.contains(defender.defense)) deaths.put(defender.defense, death(defender));
    }
    Map<String, Object> manifest = new LinkedHashMap<>();
    manifest.put("schemaVersion", 1);
    manifest.put("source", "chapter-1.jar f/g/i original methods, controlled result queue");
    manifest.put("evidenceKind", "ordinary reflection execution, not REA Evidence");
    manifest.put(
      "sourceSha256",
      "67d1c77e823816e203244a15428ba9fb635d40edba04efa3180b3334025989fe"
    );
    manifest.putAll(signature);
    manifest.put(
      "clock",
      "h.run targets a 65ms display period; original i.d increments bv by 50 logical units per update. J and completionWaitUnits use bv units, not wall-clock milliseconds."
    );
    manifest.put("seed", 0);
    manifest.put(
      "selection",
      "appearances[id:weapon] -> actionGroup/defenseGroup; clips[actionGroup/defenseGroup/sourceSlot/outcome]; sourceSlot 0 is battle initiator (bT), 1 is original defender/counterattacker (bU), independent of left/right faction"
    );
    manifest.put("appearances", appearances);
    manifest.put("actionGroups", groups);
    manifest.put("defenseGroups", shapes);
    manifest.put("clips", clips);
    manifest.put("deaths", deaths);
    manifest.put("textures", textures);
    manifest.put("reusedClips", new ArrayList<>(reusedClips));
    manifest.put("reusedDeaths", new ArrayList<>(reusedDeaths));
    Files.writeString(directory.resolve("manifest.json"), Chapter1Rules.json(manifest) + "\n");
    System.out.println(
      "BATTLE_CLIPS_OK appearances=" +
        appearances.size() +
        " actions=" +
        attacks.size() +
        " shapes=" +
        defenses.size() +
        " clips=" +
        clips.size() +
        " textures=" +
        textures.size()
    );
  }

  private static boolean generatedNoncritical(Map<String, Object> action) {
    int kind = ((Number) action.get("effectKind")).intValue();
    int presentation = ((Number) action.get("R")).intValue();
    return (
      kind == 3 ||
      kind == 4 ||
      kind == 5 ||
      kind == 6 ||
      kind == 7 ||
      kind == 8 ||
      kind == 11 ||
      kind == 12 ||
      ((kind == 0 || kind == 1) &&
        (presentation == 0 ||
          presentation == 2 ||
          presentation == 4 ||
          presentation == 5 ||
          presentation == 6 ||
          presentation == 8 ||
          (presentation == 7 && !Boolean.TRUE.equals(action.get("thrown")))))
    );
  }

  private static boolean generatedCritical(Map<String, Object> action) {
    int kind = ((Number) action.get("effectKind")).intValue();
    int presentation = ((Number) action.get("R")).intValue();
    boolean thrown = Boolean.TRUE.equals(action.get("thrown"));
    return (
      kind == 3 ||
      kind == 4 ||
      kind == 5 ||
      kind == 6 ||
      kind == 7 ||
      kind == 8 ||
      kind == 11 ||
      kind == 12 ||
      ((kind == 0 || kind == 1) &&
        ((thrown && (presentation == 0 || presentation == 2 || presentation == 4)) ||
          (!thrown &&
            (presentation == 0 ||
              presentation == 2 ||
              presentation == 4 ||
              presentation == 5 ||
              presentation == 6 ||
              presentation == 7 ||
              presentation == 8))))
    );
  }

  private Map<String, Object> stageSignature() throws ReflectiveOperationException {
    Map<String, Object> signature = new LinkedHashMap<>();
    signature.put("tickMillis", TICK_MILLIS);
    signature.put("logicTickUnits", LOGIC_TICK_UNITS);
    signature.put("spriteTickUnits", 50);
    signature.put("viewport", Map.of("width", width, "height", height));
    signature.put(
      "stage",
      Map.of("top", number(fighterClass, "n"), "height", number(fighterClass, "j"))
    );
    signature.put(
      "coordinates",
      "original 240x320 screen pixels; actor x/y already include aC and sampled hit jitter; add appearance frame crop offset; no flip_h"
    );
    signature.put(
      "composition",
      "sky, native terrain with backgroundOffset, then layers in recorded order; flash overlays entire viewport"
    );
    signature.put(
      "effectTails",
      "effectTailTicks continues surviving effect instances after action completion; carry these into the next action using foreground bucket and source insertion order. Fixed-seed tail sampling has no subsequent action's extra random draws."
    );
    signature.put("hpContract", hpContract());
    return signature;
  }

  private static Object canonical(Object value) {
    if (value instanceof Map<?, ?> map) {
      Map<String, Object> sorted = new TreeMap<>();
      for (var entry : map.entrySet())
        sorted.put((String) entry.getKey(), canonical(entry.getValue()));
      return sorted;
    }
    if (value instanceof List<?> list) return list
      .stream()
      .map(Chapter1BattleClips::canonical)
      .toList();
    if (value != null && value.getClass().isArray()) {
      List<Object> entries = new ArrayList<>();
      for (int index = 0; index < Array.getLength(value); index++) entries.add(
        canonical(Array.get(value, index))
      );
      return entries;
    }
    return value;
  }

  private static Map<String, Object> planRows(Set<String> candidates, Set<String> reused) {
    List<String> pending = new ArrayList<>(candidates);
    pending.removeAll(reused);
    return Map.of(
      "candidates",
      new ArrayList<>(candidates),
      "new",
      pending,
      "reused",
      new ArrayList<>(reused)
    );
  }

  private static ReusePlan readReusePlan(Path path) throws IOException {
    Map<String, String> signatures = new LinkedHashMap<>();
    Map<String, Set<String>> clips = new LinkedHashMap<>();
    Map<String, Set<String>> deaths = new LinkedHashMap<>();
    if (path != null) {
      List<String> lines = Files.readAllLines(path);
      for (int index = 0; index < lines.size(); index++) {
        String line = lines.get(index);
        if (line.isBlank() || line.startsWith("#")) continue;
        String[] columns = line.split("\t", -1);
        if (
          columns.length != 3 || columns[1].isBlank() || columns[2].isBlank()
        ) throw new IOException("Invalid motion reuse plan at " + path + ":" + (index + 1));
        String stage = columns[1],
          value = columns[2];
        switch (columns[0]) {
          case "stage" -> {
            if (signatures.putIfAbsent(stage, value) != null) throw new IOException(
              "Duplicate motion reuse stage: " + stage
            );
          }
          case "clip" -> clips.computeIfAbsent(stage, ignored -> new LinkedHashSet<>()).add(value);
          case "death" -> deaths
            .computeIfAbsent(stage, ignored -> new LinkedHashSet<>())
            .add(value);
          default -> throw new IOException(
            "Unknown motion reuse row at " + path + ":" + (index + 1)
          );
        }
      }
      Set<String> referenced = new LinkedHashSet<>(clips.keySet());
      referenced.addAll(deaths.keySet());
      if (!signatures.keySet().containsAll(referenced)) throw new IOException(
        "Motion reuse keys reference an undeclared stage"
      );
    }
    return new ReusePlan(signatures, clips, deaths);
  }

  private record ReusePlan(
    Map<String, String> signatures,
    Map<String, Set<String>> clips,
    Map<String, Set<String>> deaths
  ) {
    private String match(Map<String, Object> nativeStage) throws IOException {
      String signature = Chapter1Rules.json(canonical(nativeStage));
      String match = null;
      for (var entry : signatures.entrySet())
        if (entry.getValue().equals(signature)) {
          if (match != null) throw new IOException(
            "Multiple bank stages match the native stage contract"
          );
          match = entry.getKey();
        }
      return match;
    }
  }

  private record SampleRequest(Variant attacker, Variant defender, String outcome, int slot) {}

  private Map<String, Object> hpContract() {
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("samplingDamage", 0);
    result.put(
      "reason",
      "action/effect tracks are independent of HP amount; positive damage changes HP/death and final wait, not action frame/motion state transitions"
    );
    result.put(
      "impact",
      "first tick with defender.A=true; sourceSlot0 defender damage begins in that tick, sourceSlot1 begins next tick; attacker recovery begins next tick for both slots"
    );
    result.put("damageStep", 4);
    result.put("recoveryStep", 4);
    result.put("damageStartDelayTicksBySlot", List.of(0, 1));
    result.put("recoveryStartDelayTicks", 1);
    result.put(
      "hpStepRule",
      "each tick defender HP=max(targetHP,HP-4), attacker recovery=min(targetHP,HP+4); native source fighter update order is bT then bU. Clear A/B in the update reaching the target. Combat rules already clamp damage/recovery to the available HP."
    );
    result.put(
      "death",
      "when defender HP reaches zero: stop defender layer and insert deaths[defenseGroup] at that tick; death layers use aS=false and source insertion order"
    );
    result.put(
      "completion",
      "run the source update order: HP/recovery update writes attacker.J=nowUnits; action entry into state5 writes J=nowUnits; attacker state5 tests nowUnits-J>=completionWaitUnits. bv/J advance 50 units per 65ms nominal display tick. sourceSlot0 tests before that tick's defender HP step, sourceSlot1 tests after it."
    );
    result.put(
      "waitDuringDamage",
      "each HP/recovery update sets attacker.J=nowUnits; state5 entry also sets J=nowUnits; physical wait150 is 3 ticks, magic wait500 is 10 ticks"
    );
    result.put(
      "lateHold",
      "if HP drain outlasts sampled frames, hold last actor/sky state, advance effectTailTicks and death clip, then omit expired effects"
    );
    result.put(
      "scope",
      "single result action; runtime sequences counter/follow-up actions from combat rules. Fixed seed is one original stochastic visual realization, not every random outcome."
    );
    return result;
  }

  private Map<String, Object> sample(
    Variant attacker,
    Variant defender,
    String outcome,
    int slot,
    int damage,
    int recovery
  ) throws ReflectiveOperationException, IOException {
    reset();
    set(attacker.unit, "F", (byte) attacker.weapon);
    set(defender.unit, "F", (byte) defender.weapon);
    Object first = make(slot == 0 ? attacker.unit : defender.unit, null);
    Object second = make(slot == 0 ? defender.unit : attacker.unit, first);
    set(first, "b", second);
    Object af = slot == 0 ? first : second;
    Object df = slot == 0 ? second : first;
    fighterClass.getMethod("a").invoke(first);
    fighterClass.getMethod("a").invoke(second);
    set(game.getClass(), "bT", first);
    set(game.getClass(), "bU", second);
    set(af, "y", (byte) 20);
    set(df, "y", (byte) 40);
    Vector<byte[]> results = new Vector<>();
    results.add(new byte[] {
      (byte) slot,
      (byte) (outcome.equals("miss") ? 1 : 0),
      (byte) (outcome.equals("critical") ? 0 : 1),
      0,
      0,
      (byte) damage,
      (byte) recovery,
    });
    set(game.getClass(), "aD", results);
    set(game.getClass(), "aE", (byte) 0);
    fighterClass.getMethod("g").invoke(null);
    List<Object> ticks = new ArrayList<>();
    int impact = -1;
    int settle = -1;
    for (int tick = 0; tick < 256; tick++) {
      set(game, "bv", tick * (long) LOGIC_TICK_UNITS);
      game.getClass().getMethod("s").invoke(game);
      if ((boolean) get(df, "A") && impact < 0) impact = tick;
      if (number(af, "d") == 5 && settle < 0) settle = tick;
      Map<String, Object> frame = render(af, df);
      frame.put("attackerState", number(af, "d"));
      frame.put("attackerStep", number(af, "e"));
      frame.put("defenderHp", number(df, "y"));
      frame.put("attackerHp", number(af, "y"));
      ticks.add(frame);
      if ((boolean) get(game, "bV")) {
        if (settle < 0) throw new IOException("Action ended without settle phase");
        Map<String, Object> clip = new LinkedHashMap<>();
        clip.put("attackerAppearance", attacker.appearance());
        clip.put("defenderAppearance", defender.appearance());
        clip.put("outcome", outcome);
        clip.put("sourceSlot", slot);
        clip.put("impactTick", impact);
        clip.put("settleTick", settle);
        int completionWaitUnits = number(af, "E") <= 1 ? 150 : 500;
        clip.put("completionWaitUnits", completionWaitUnits);
        clip.put("completionWaitTicks", completionWaitUnits / LOGIC_TICK_UNITS);
        clip.put("terrainPlacement", Map.of("attacker", terrain(af), "defender", terrain(df)));
        clip.put("ticks", ticks);
        List<Object> tail = new ArrayList<>();
        for (int extra = 1; extra <= 64; extra++) {
          if (
            ((List<?>) get(game, "aC"))
              .stream()
              .allMatch(sprite -> sprite == actorSprite(af) || sprite == actorSprite(df))
          ) break;
          updateSprites();
          fighterClass.getMethod("f").invoke(first);
          fighterClass.getMethod("f").invoke(second);
          @SuppressWarnings("unchecked")
          List<Map<String, Object>> all = (List<Map<String, Object>>) render(af, df).get("layers");
          tail.add(
            all
              .stream()
              .filter(layer -> !layer.containsKey("actor"))
              .toList()
          );
          if (extra == 64) throw new IOException("Original effect tail did not expire");
        }
        clip.put("effectTailTicks", tail);
        return clip;
      }
    }
    throw new IOException(
      "Original action did not finish: " +
        attacker.appearance() +
        " -> " +
        defender.appearance() +
        " " +
        outcome
    );
  }

  private Map<String, Object> death(Variant defender)
    throws ReflectiveOperationException, IOException {
    reset();
    set(defender.unit, "F", (byte) defender.weapon);
    Object fighter = make(defender.unit, null);
    fighterClass.getMethod("b").invoke(fighter);
    List<Object> ticks = new ArrayList<>();
    for (int tick = 0; tick < 32; tick++) {
      if (tick > 0) updateSprites();
      ticks.add(render(null, null).get("layers"));
      if (((List<?>) get(game, "aC")).isEmpty()) {
        return Map.of(
          "source",
          "f.b() death bomb/smoke, sampled at HP=0 before next sprite update",
          "ticks",
          ticks
        );
      }
    }
    throw new IOException("Death effect did not expire");
  }

  private void updateSprites() throws ReflectiveOperationException {
    @SuppressWarnings("unchecked")
    List<Object> sprites = (List<Object>) get(game, "aC");
    for (Object sprite : List.copyOf(sprites)) sprite.getClass().getMethod("a").invoke(sprite);
    for (int index = sprites.size() - 1; index >= 0; index--) {
      if (!((boolean) get(sprites.get(index), "aI"))) sprites.remove(index);
    }
  }

  private static Object actorSprite(Object fighter) {
    try {
      return get(fighter, "S");
    } catch (ReflectiveOperationException error) {
      throw new IllegalStateException(error);
    }
  }

  private Map<String, Object> terrain(Object fighter) throws ReflectiveOperationException {
    Object[] tiles = (Object[]) get(fighter, "L");
    Map<String, Object> placement = new LinkedHashMap<>();
    placement.put(
      "x",
      number(fighter, "I") == 0 ? number(game, "aX") - number(fighter, "i") : number(game, "aX")
    );
    placement.put(
      "y",
      number(fighterClass, "n") + number(fighterClass, "j") - number(tiles[0], "d")
    );
    placement.put("clipWidth", number(game, "aX"));
    placement.put("clipHeight", number(tiles[0], "d"));
    placement.put("tileCount", number(fighter, "M"));
    placement.put("tileWidth", number(fighter, "N"));
    placement.put("offsetX", number(fighter, "h"));
    placement.put("markedTile", number(fighter, "af"));
    placement.put(
      "source",
      "f.c(Graphics,x,y): choose runtime terrain via battle manifest; tile j uses frame1 when j==markedTile, otherwise frame j; apply backgroundOffset to x/y and clip"
    );
    return placement;
  }

  private Map<String, Object> render(Object af, Object df)
    throws ReflectiveOperationException, IOException {
    int shakeX = 0;
    int shakeY = 0;
    if ((boolean) get(game, "bK")) {
      shakeX = ((Number) helperClass.getMethod("e").invoke(null)).intValue() % 10;
      if ((boolean) get(game, "bL")) shakeX = 0;
      shakeY = ((Number) helperClass.getMethod("e").invoke(null)).intValue() % 3;
    }
    Image sky = image();
    if (af != null) game
      .getClass()
      .getMethod("a", Graphics.class, int.class, int.class)
      .invoke(game, sky.getGraphics(), shakeX, shakeY);
    @SuppressWarnings("unchecked")
    List<Object> registry = (List<Object>) get(game, "aC");
    // This is the stable aS partition performed by i.a(Graphics), which also changes next tick's registry order.
    registry.sort(
      Comparator.comparing(sprite -> {
        try {
          return (boolean) get(sprite, "aS");
        } catch (ReflectiveOperationException error) {
          throw new IllegalStateException(error);
        }
      })
    );
    List<Object> layers = new ArrayList<>();
    Object actorSprite = af == null ? null : get(af, "S");
    Object defenderSprite = df == null ? null : get(df, "S");
    for (Object sprite : registry) {
      if (sprite == actorSprite || sprite == defenderSprite) {
        int jitterX = 0;
        int jitterY = 0;
        if ((boolean) get(sprite, "aA") && number(sprite, "aK") > 0) {
          jitterX = (
            (Number) helperClass.getMethod("a", int.class, int.class).invoke(null, -4, 5)
          ).intValue();
          jitterY = (
            (Number) helperClass.getMethod("a", int.class, int.class).invoke(null, -1, 2)
          ).intValue();
        }
        byte[] sequence = (byte[]) get(sprite, "aV");
        Map<String, Object> layer = new LinkedHashMap<>();
        layer.put("actor", sprite == actorSprite ? "attacker" : "defender");
        layer.put("frame", (int) sequence[number(sprite, "aq")]);
        layer.put("x", number(sprite, "av") + jitterX);
        layer.put("y", number(sprite, "aw") + number(sprite, "aC") + jitterY);
        layer.put("visible", get(sprite, "aA"));
        layer.put("foreground", get(sprite, "aS"));
        layers.add(layer);
      } else {
        Image raster = image();
        sprite
          .getClass()
          .getMethod("a", Graphics.class, int.class, int.class)
          .invoke(sprite, raster.getGraphics(), 0, number(sprite, "aC"));
        Map<String, Object> layer = raster(raster.getCanvas());
        if (layer != null) {
          layer.put("instance", instances.computeIfAbsent(sprite, ignored -> instances.size()));
          layer.put("foreground", get(sprite, "aS"));
          layer.put("sourceProgram", number(sprite, "ar"));
          layers.add(layer);
        }
      }
    }
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("sky", raster(sky.getCanvas()));
    result.put("backgroundOffset", List.of(shakeX, shakeY));
    result.put("layers", layers);
    result.put(
      "flash",
      (boolean) get(game, "cS") && (number(game, "cT") & 1) == 0 ? number(game, "cU") : null
    );
    return result;
  }

  private Image image() {
    Image image = Image.createRGBImage(new int[width * height], width, height, true);
    image.setMutable(true);
    return image;
  }

  private Map<String, Object> raster(BufferedImage image) throws IOException {
    int left = width,
      top = height,
      right = -1,
      bottom = -1;
    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
      if (image.getRGB(x, y) >>> 24 == 0) continue;
      left = Math.min(left, x);
      top = Math.min(top, y);
      right = Math.max(right, x);
      bottom = Math.max(bottom, y);
    }
    if (right < 0) return null;
    BufferedImage cropped = image.getSubimage(left, top, right - left + 1, bottom - top + 1);
    String id = pixelsDigest(cropped);
    if (!textures.containsKey(id)) {
      Path path = directory.resolve("textures/" + id + ".png");
      Files.createDirectories(path.getParent());
      if (!ImageIO.write(cropped, "png", path.toFile())) throw new IOException(
        "PNG writer unavailable"
      );
      textures.put(
        id,
        Map.of(
          "texture",
          "textures/" + id + ".png",
          "width",
          cropped.getWidth(),
          "height",
          cropped.getHeight()
        )
      );
    }
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("texture", id);
    result.put("x", left);
    result.put("y", top);
    return result;
  }

  private Map<String, Object> geometry(Object fighter) throws ReflectiveOperationException {
    Object sprite = get(fighter, "S");
    Map<String, Object> result = new LinkedHashMap<>();
    for (String name : List.of("R", "I", "o", "p", "q", "r", "u"))
      result.put(name, get(fighter, name));
    for (String name : List.of("at", "au", "aF", "aT")) result.put(name, get(sprite, name));
    result.put("sequences", get(sprite, "as"));
    List<Object> frames = new ArrayList<>();
    for (Object frame : (Object[]) get(sprite, "ap")) {
      frames.add(
        List.of(
          number(frame, "c"),
          number(frame, "d"),
          number(frame, "e"),
          number(frame, "f"),
          number(frame, "g")
        )
      );
    }
    result.put("frames", frames);
    return result;
  }

  private Object make(Object unit, Object opponent) throws ReflectiveOperationException {
    return fighterClass
      .getConstructor(game.getClass(), unit.getClass(), fighterClass)
      .newInstance(game, unit, opponent);
  }

  private void reset() throws ReflectiveOperationException {
    instances.clear();
    byte[][] sourceWeaponFrames = (byte[][]) field(fighterClass, "aj").get(null);
    for (int index = 0; index < sourceWeaponFrames.length; index++) System.arraycopy(
      originalWeaponFrames[index],
      0,
      sourceWeaponFrames[index],
      0,
      originalWeaponFrames[index].length
    );
    set(game, "aC", new Vector<>());
    set(game, "ay", new Vector<>());
    set(game, "bV", false);
    set(game, "bD", false);
    set(game, "bK", false);
    set(game, "cS", false);
    set(game, "bv", 0L);
    set(game, "cR", 0);
    set(fighterClass, "ad", false);
    set(fighterClass, "F", 8968191);
    set(fighterClass, "H", 0);
    set(fighterClass, "G", false);
    set(helperClass, "p", new Random(0));
  }

  private record Variant(
    Object unit,
    int weapon,
    String attack,
    String defense,
    Map<String, Object> geometry,
    Map<String, Object> behavior
  ) {
    private int side() {
      return ((Number) geometry.get("I")).intValue();
    }

    private String appearance() throws ReflectiveOperationException {
      return number(unit, "y") + ":" + weapon;
    }
  }

  private static String pixelsDigest(BufferedImage image) {
    ByteBuffer bytes = ByteBuffer.allocate(8 + image.getWidth() * image.getHeight() * 4);
    bytes.putInt(image.getWidth()).putInt(image.getHeight());
    for (int pixel : image.getRGB(
      0,
      0,
      image.getWidth(),
      image.getHeight(),
      null,
      0,
      image.getWidth()
    ))
      bytes.putInt(pixel);
    return digest(bytes.array());
  }

  private static String digest(String value) {
    return digest(value.getBytes(java.nio.charset.StandardCharsets.UTF_8));
  }

  private static String digest(byte[] value) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
    } catch (NoSuchAlgorithmException impossible) {
      throw new AssertionError(impossible);
    }
  }

  private static Field field(Class<?> type, String name) throws NoSuchFieldException {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field field = current.getDeclaredField(name);
        field.setAccessible(true);
        return field;
      } catch (NoSuchFieldException absent) {
        /* Original sprite fields also live on the base class. */
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

  private static int number(Class<?> type, String name) throws ReflectiveOperationException {
    return ((Number) field(type, name).get(null)).intValue();
  }

  private static void set(Object target, String name, Object value)
    throws ReflectiveOperationException {
    field(target.getClass(), name).set(target, value);
  }

  private static void set(Class<?> type, String name, Object value)
    throws ReflectiveOperationException {
    field(type, name).set(null, value);
  }

  /** Restores field references and container contents, including static source weapon tables. */
  private static final class State implements AutoCloseable {

    private final List<RunnableRestore> restore = new ArrayList<>();
    private final IdentityHashMap<Object, Boolean> containers = new IdentityHashMap<>();

    private State(Object game, ClassLoader loader) throws ReflectiveOperationException {
      fields(game.getClass(), game, false);
      for (Object unit : (List<?>) get(game, "as")) fields(unit.getClass(), unit, false);
      for (String name : List.of("f", "i", "h", "d"))
        fields(Class.forName(name, true, loader), null, true);
    }

    private void fields(Class<?> type, Object target, boolean statics)
      throws ReflectiveOperationException {
      for (
        Class<?> current = type;
        current != null && current != Object.class;
        current = current.getSuperclass()
      ) {
        for (Field field : current.getDeclaredFields()) {
          if (Modifier.isStatic(field.getModifiers()) != statics) continue;
          field.setAccessible(true);
          Object value = field.get(target);
          if (!Modifier.isFinal(field.getModifiers())) restore.add(() -> field.set(target, value));
          container(value);
        }
      }
    }

    @SuppressWarnings({ "unchecked", "rawtypes" })
    private void container(Object value) {
      if (value == null || containers.put(value, true) != null) return;
      if (value.getClass().isArray()) {
        int length = Array.getLength(value);
        Object[] entries = new Object[length];
        for (int index = 0; index < length; index++) {
          entries[index] = Array.get(value, index);
          container(entries[index]);
        }
        restore.add(() -> {
          for (int index = 0; index < length; index++) Array.set(value, index, entries[index]);
        });
      } else if (value instanceof List list) {
        List copy = new ArrayList(list);
        for (Object entry : copy) container(entry);
        restore.add(() -> {
          list.clear();
          list.addAll(copy);
        });
      } else if (value instanceof Map map) {
        Map copy = new LinkedHashMap(map);
        for (Object entry : copy.values()) container(entry);
        restore.add(() -> {
          map.clear();
          map.putAll(copy);
        });
      }
    }

    public void close() throws ReflectiveOperationException {
      for (int index = restore.size() - 1; index >= 0; index--) restore.get(index).run();
    }
  }

  private interface RunnableRestore {
    void run() throws ReflectiveOperationException;
  }
}
