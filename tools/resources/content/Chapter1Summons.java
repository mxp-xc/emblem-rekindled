import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Vector;

/** Explicit offline coverage of the six original summon families and both identity pools. */
public final class Chapter1Summons {

  private Chapter1Summons() {}

  private static Field field(Class<?> type, String name) throws Exception {
    for (Class<?> current = type; current != null; current = current.getSuperclass()) {
      try {
        Field result = current.getDeclaredField(name);
        result.setAccessible(true);
        return result;
      } catch (NoSuchFieldException absent) {
        // The reference unit inherits its sprite fields.
      }
    }
    throw new NoSuchFieldException(name);
  }

  private static int number(Object target, String name) throws Exception {
    return ((Number) field(target.getClass(), name).get(target)).intValue();
  }

  public static void prepare(Object game, ClassLoader loader, int classId, Path output)
    throws Exception {
    if (!List.of(28, 29, 32, 33, 36, 37).contains(classId)) {
      throw new IllegalArgumentException("Unverified summon class: " + classId);
    }
    Class<?> unitClass = Class.forName("b", true, loader);
    @SuppressWarnings("unchecked")
    Vector<Object> units = (Vector<Object>) field(game.getClass(), "as").get(game);
    // These are sampling contexts, never deployment or campaign publications.
    units.removeIf(unit -> {
      try {
        int id = number(unit, "y");
        return (id >= 20 && id <= 29) || (id >= 70 && id <= 79);
      } catch (Exception error) {
        throw new IllegalStateException(error);
      }
    });
    List<Object> casters = new ArrayList<>();
    List<Object> casterDeclarations = new ArrayList<>();
    for (int faction : new int[] { 0, 2 }) {
      Object caster = null;
      for (Object candidate : units) {
        if (number(candidate, "C") == faction) {
          caster = candidate;
          break;
        }
      }
      if (caster == null) throw new IllegalStateException("Missing summon sampling caster");
      casters.add(caster);
      casterDeclarations.add(
        Map.of(
          "id",
          number(caster, "y"),
          "faction",
          faction,
          "beforeLevel",
          number(caster, "T") + 1,
          "afterLevel",
          1
        )
      );
    }
    Field pool = field(unitClass, "ad");
    byte[] nativePool = (byte[]) pool.get(null);
    byte[] originalPool = nativePool.clone();
    // Keep the original constructor, allocation, equipment and attribute path; only
    // select the family explicitly so every supported family is actually rendered.
    Arrays.fill(nativePool, (byte) classId);
    List<Object> declarations = new ArrayList<>();
    try {
      for (Object caster : casters) {
        int faction = number(caster, "C") == 0 ? 1 : 2;
        field(unitClass, "T").setByte(caster, (byte) 0);
        for (int index = 0; index < 10; index++) {
          // Give the native helper one known free adjacent cell, independent of
          // the sampled map's occupied deployment and terrain.
          for (Object unit : units) {
            field(unitClass, "D").setByte(unit, (byte) 0);
            field(unitClass, "E").setByte(unit, (byte) 0);
          }
          field(unitClass, "D").setByte(caster, (byte) 2);
          field(unitClass, "E").setByte(caster, (byte) 2);
          field(game.getClass(), "cB").set(game, null);
          Object born = unitClass
            .getMethod("b", unitClass, boolean.class)
            .invoke(null, caster, true);
          int expectedId = (faction == 1 ? 20 : 70) + index;
          if (born == null || number(born, "y") != expectedId || number(born, "S") != classId) {
            throw new IllegalStateException("Native summon family/identity disagrees with request");
          }
          declarations.add(Map.of("sourceId", expectedId, "classId", classId, "faction", faction));
        }
      }
    } finally {
      System.arraycopy(originalPool, 0, nativePool, 0, originalPool.length);
    }
    Files.createDirectories(output);
    Files.writeString(
      output.resolve("summon_casters.json"),
      Chapter1Rules.json(casterDeclarations) + "\n"
    );
    Files.writeString(output.resolve("summons.json"), Chapter1Rules.json(declarations) + "\n");
  }
}
