import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;

/** Finite offline preparation through the original emblem action, never a runtime dependency. */
public final class Chapter1Promotions {

  private static Field field(Class<?> type, String name) throws ReflectiveOperationException {
    Field result = type.getDeclaredField(name);
    result.setAccessible(true);
    return result;
  }

  public static void prepare(Object game, ClassLoader loader, Path output) throws Exception {
    Class<?> type = Class.forName("b", true, loader);
    Method use = type.getMethod("a", type, byte[].class);
    List<?> units = (List<?>) field(game.getClass(), "as").get(game);
    List<Object> changes = new ArrayList<>();
    for (Object unit : units) {
      int faction = field(type, "C").getByte(unit),
        from = field(type, "S").getByte(unit);
      if (faction != 0 || from < 0 || from > 20 || from % 4 != 0) continue;
      int minimum = (
        (Number) ((Map<?, ?>) Chapter1Rules.promotions(loader).get(from / 4)).get("minimumLevel")
      ).intValue();
      field(type, "T").setByte(unit, (byte) (minimum - 1));
      @SuppressWarnings("unchecked")
      Vector<byte[]> inventory = (Vector<byte[]>) field(type, "v").get(unit);
      byte[] emblem = new byte[] { 76, 1 };
      inventory.add(emblem);
      if (!Boolean.TRUE.equals(use.invoke(null, unit, emblem))) throw new IllegalStateException(
        "Original emblem action rejected preparation"
      );
      int to = field(type, "S").getByte(unit);
      if (to != from + 1) throw new IllegalStateException("Unexpected original promotion class");
      changes.add(
        Map.of("id", (int) field(type, "y").getByte(unit), "fromClassId", from, "toClassId", to)
      );
    }
    Files.writeString(output.resolve("promotion_units.json"), Chapter1Rules.json(changes) + "\n");
  }
}
