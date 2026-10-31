import java.io.IOException;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Converts verified chapter-1 objects and tables into runtime-owned semantic data. */
public final class Chapter1Rules {

  private static final String[] STAT_NAMES = {
    "strength",
    "skill",
    "speed",
    "defense",
    "magic",
    "luck",
    "maxHp",
    "move",
  };

  private Chapter1Rules() {}

  private static Field field(Class<?> type, String name) throws NoSuchFieldException {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field result = current.getDeclaredField(name);
        result.setAccessible(true);
        return result;
      } catch (NoSuchFieldException absent) {
        // Reference-unit fields also live in the sprite base class.
      }
    }
    throw new NoSuchFieldException(type.getName() + "." + name);
  }

  private static int number(Object target, String name) throws ReflectiveOperationException {
    return ((Number) field(target.getClass(), name).get(target)).intValue();
  }

  public static Map<String, Object> describeUnit(Object unit) throws ReflectiveOperationException {
    int id = number(unit, "y");
    int faction = number(unit, "C");
    int equippedTemplate = number(unit, "F");
    boolean temporary = faction == 0 && id >= 95 && id <= 99;
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("id", id);
    result.put("name", field(unit.getClass(), "w").get(unit));
    result.put("className", field(unit.getClass(), "x").get(unit));
    result.put("faction", faction);
    result.put("classId", number(unit, "S"));
    result.put("classGroup", number(unit, "R"));
    result.put("move", number(unit, "O"));
    result.put("level", number(unit, "T") + 1);
    result.put("hp", number(unit, "Q"));
    result.put("maxHp", number(unit, "N"));
    result.put("sourceId", temporary ? number(unit, "Y") : id);
    result.put("formal", faction == 0 && id >= 0 && id < 10);
    result.put("flags", number(unit, "B") & 255);
    result.put("equipMask", number(unit, "H"));
    result.put("dropTemplateId", number(unit, "G"));
    result.put("proficiency", number(unit, "V"));
    result.put("experience", number(unit, "U"));
    Map<String, Object> attributes = new LinkedHashMap<>();
    String[] fields = { "I", "J", "K", "L", "M", "P" };
    for (int index = 0; index < fields.length; index++) {
      attributes.put(STAT_NAMES[index], number(unit, fields[index]));
    }
    result.put("attributes", attributes);

    Object held = field(unit.getClass(), "v").get(unit);
    if (!(held instanceof List<?> items)) {
      throw new IllegalArgumentException("Unit " + id + " has an invalid inventory");
    }
    List<Object> inventory = new ArrayList<>();
    String equippedId = "";
    for (int slot = 0; slot < items.size(); slot++) {
      if (!(items.get(slot) instanceof byte[] pair) || pair.length != 2) {
        throw new IllegalArgumentException("Unit " + id + " has an invalid item at slot " + slot);
      }
      String instanceId = "chapter_1:unit_" + id + ":item_" + slot;
      Map<String, Object> item = new LinkedHashMap<>();
      item.put("id", instanceId);
      item.put("templateId", (int) pair[0]);
      item.put("durability", (int) pair[1]);
      inventory.add(item);
      if (slot == 0 && equippedTemplate > 0) {
        if (pair[0] != equippedTemplate) {
          throw new IllegalStateException(
            "Equipped item is not inventory slot zero for unit " + id
          );
        }
        equippedId = instanceId;
      }
    }
    if (equippedTemplate > 0 && inventory.isEmpty()) {
      throw new IllegalStateException("Equipped item is missing for unit " + id);
    }
    result.put("inventory", inventory);
    result.put("equippedInstanceId", equippedId);
    return result;
  }

  public static void export(Object game, ClassLoader loader, Path output)
    throws ReflectiveOperationException, IOException {
    Class<?> units = Class.forName("b", true, loader);
    Class<?> text = Class.forName("e", true, loader);
    Method itemStat = units.getMethod("a", byte.class, byte.class);
    Method itemCategory = units.getMethod("n", byte.class);
    Method jobMask = units.getMethod("f", byte.class);
    Method string = text.getMethod("b", int.class);
    Object deployment = field(game.getClass(), "as").get(game);
    if (!(deployment instanceof List<?> list) || list.isEmpty()) {
      throw new IllegalArgumentException("Chapter-1 deployment is not initialized");
    }
    Object sample = list.get(0);
    Method attackKind = units.getMethod("k", byte.class);
    List<Object> itemTemplates = new ArrayList<>();
    for (int id = 0; id <= 87; id++) {
      Map<String, Object> item = new LinkedHashMap<>();
      item.put("id", id);
      item.put("name", id == 0 ? "无武器" : string.invoke(null, 272 + id));
      int category = id == 0 ? 0 : ((Number) itemCategory.invoke(null, (byte) id)).intValue();
      item.put("categoryMask", category);
      String[] names = {
        "power",
        "hit",
        "critical",
        "minRange",
        "maxRange",
        "weight",
        "defaultDurability",
        "price",
      };
      for (byte stat = 0; stat < names.length; stat++) {
        item.put(names[stat], ((Number) itemStat.invoke(null, stat, (byte) id)).intValue());
      }
      int kind = ((Number) attackKind.invoke(sample, (byte) id)).intValue();
      String damageKind = "none";
      if (category > 0 && category < 64) {
        damageKind = kind <= 1 ? "physical" : kind == 2 ? "healing" : "magic";
      }
      item.put("damageKind", damageKind);
      item.put("doubleStrike", id == 10 || id == 19 || id == 27 || id == 38);
      item.put("drainsHp", id == 6 || id == 48);
      item.put("ignoresDefense", id == 12 || id == 52);
      List<Integer> effectiveGroups = new ArrayList<>();
      if (id == 9 || id == 18 || id == 26 || id == 37) {
        effectiveGroups.addAll(List.of(7, 8, 9));
      } else if (id == 11 || id == 16) {
        effectiveGroups.add(2);
      } else if (id == 20 || id == 24) {
        effectiveGroups.add(4);
      } else if (id == 39) {
        effectiveGroups.addAll(List.of(1, 3));
      }
      item.put("effectiveGroups", effectiveGroups);
      itemTemplates.add(item);
    }
    List<Object> jobTemplates = new ArrayList<>();
    for (int id = 0; id <= 40; id++) {
      Map<String, Object> job = new LinkedHashMap<>();
      job.put("id", id);
      job.put("name", string.invoke(null, 206 + id));
      job.put("classGroup", id / 4);
      job.put("equipMask", ((Number) jobMask.invoke(null, (byte) id)).intValue());
      jobTemplates.add(job);
    }
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("itemTemplates", itemTemplates);
    result.put("jobTemplates", jobTemplates);
    result.put("baseStats", statRows(field(units, "u").get(null)));
    result.put("growthRates", statRows(field(units, "t").get(null)));
    result.put("statCaps", stats(field(units, "d").get(null)));
    result.put("terrainDefense", field(game.getClass(), "ev").get(null));
    result.put("terrainEvasion", field(game.getClass(), "ew").get(null));
    result.put("baseMovementCosts", field(game.getClass(), "ex").get(null));
    result.put("aiClassOrder", field(game.getClass(), "cM").get(null));
    result.put("alliances", field(game.getClass(), "bj").get(game));
    result.put("initialGold", field(units, "r").get(null));
    result.put("shopStocks", field(units, "an").get(null));
    result.put("nodeShopStockIndices", field(units, "ao").get(null));
    Files.createDirectories(output);
    Files.writeString(output.resolve("rules.json"), json(result) + "\n");
  }

  private static Map<String, Object> stats(Object row) {
    if (!row.getClass().isArray() || Array.getLength(row) != STAT_NAMES.length) {
      throw new IllegalArgumentException("Expected eight chapter-1 stat columns");
    }
    Map<String, Object> result = new LinkedHashMap<>();
    for (int index = 0; index < STAT_NAMES.length; index++) {
      result.put(STAT_NAMES[index], ((Number) Array.get(row, index)).intValue());
    }
    return result;
  }

  private static List<Object> statRows(Object table) {
    List<Object> result = new ArrayList<>();
    for (int id = 0; id < Array.getLength(table); id++) {
      Map<String, Object> row = new LinkedHashMap<>();
      row.put("id", id);
      row.putAll(stats(Array.get(table, id)));
      result.add(row);
    }
    return result;
  }

  public static String json(Object value) {
    if (value == null) return "null";
    if (value instanceof String text) {
      StringBuilder quoted = new StringBuilder("\"");
      for (int index = 0; index < text.length(); index++) {
        char character = text.charAt(index);
        switch (character) {
          case '"':
            quoted.append("\\\"");
            break;
          case '\\':
            quoted.append("\\\\");
            break;
          case '\n':
            quoted.append("\\n");
            break;
          case '\r':
            quoted.append("\\r");
            break;
          case '\t':
            quoted.append("\\t");
            break;
          default:
            if (character < 32) {
              quoted.append(String.format("\\u%04x", (int) character));
            } else {
              quoted.append(character);
            }
        }
      }
      return quoted.append('"').toString();
    }
    if (value instanceof Number number) {
      if (!Double.isFinite(number.doubleValue())) {
        throw new IllegalArgumentException("Non-finite numbers cannot be exported as JSON");
      }
      return number.toString();
    }
    if (value instanceof Boolean) return value.toString();
    if (value instanceof Map<?, ?> map) {
      List<String> entries = new ArrayList<>();
      for (Map.Entry<?, ?> entry : map.entrySet()) {
        if (!(entry.getKey() instanceof String)) {
          throw new IllegalArgumentException("Exported JSON object keys must be strings");
        }
        entries.add(json(entry.getKey()) + ":" + json(entry.getValue()));
      }
      return "{" + String.join(",", entries) + "}";
    }
    List<String> entries = new ArrayList<>();
    if (value instanceof Iterable<?> iterable) {
      for (Object entry : iterable) entries.add(json(entry));
    } else if (value.getClass().isArray()) {
      for (int index = 0; index < Array.getLength(value); index++) {
        entries.add(json(Array.get(value, index)));
      }
    } else {
      throw new IllegalArgumentException("Unsupported export value: " + value.getClass().getName());
    }
    return "[" + String.join(",", entries) + "]";
  }
}
