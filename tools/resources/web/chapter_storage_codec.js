// QA storage values only. Preserve view type/offset/length without copying the full heap.
const viewTypes = {
  Int8Array,
  Uint8Array,
  Uint8ClampedArray,
  Int16Array,
  Uint16Array,
  Int32Array,
  Uint32Array,
  Float32Array,
  Float64Array,
  BigInt64Array,
  BigUint64Array,
  DataView,
};
const maxViewAllocation = 64 * 1024 * 1024;

export function encodeStorageValue(value, ancestors = new WeakSet()) {
  if (value instanceof Date) return { __qaType: "Date", value: value.toISOString() };
  if (ArrayBuffer.isView(value)) {
    const constructor = Object.prototype.toString.call(value).slice(8, -1);
    if (!viewTypes[constructor]) throw Error("Unsupported view type: " + constructor);
    if (value.byteOffset + value.byteLength > maxViewAllocation)
      throw Error("QA view offset plus byte length exceeds64MiB; stop before mutation");
    return {
      __qaType: "ArrayBufferView",
      constructor,
      byteOffset: value.byteOffset,
      byteLength: value.byteLength,
      length: constructor === "DataView" ? value.byteLength : value.length,
      bytes: Array.from(new Uint8Array(value.buffer, value.byteOffset, value.byteLength)),
    };
  }
  if (value instanceof ArrayBuffer)
    return { __qaType: "ArrayBuffer", value: Array.from(new Uint8Array(value)) };
  if (value && typeof value === "object") {
    if (
      !Array.isArray(value) &&
      Object.getPrototypeOf(value) !== Object.prototype &&
      Object.getPrototypeOf(value) !== null
    )
      throw Error("Unsupported storage object type; stop before mutation");
    if (Object.hasOwn(value, "__qaType"))
      throw Error("Reserved storage tag in ordinary object; stop before mutation");
    if (Array.isArray(value)) {
      const keys = Object.keys(value);
      if (keys.length !== value.length || keys.some((key, index) => key !== String(index)))
        throw Error("Unsupported sparse array or array properties; stop before mutation");
    }
    if (ancestors.has(value)) throw Error("Cyclic storage value; stop before mutation");
    ancestors.add(value);
    try {
      return Array.isArray(value)
        ? Array.from(value, (item) => encodeStorageValue(item, ancestors))
        : Object.fromEntries(
            Object.entries(value).map(([key, item]) => [key, encodeStorageValue(item, ancestors)]),
          );
    } finally {
      ancestors.delete(value);
    }
  }
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean" ||
    (typeof value === "number" && Number.isFinite(value) && !Object.is(value, -0))
  )
    return value;
  throw Error("Unsupported storage value; stop before mutation");
}

export function decodeStorageValue(value) {
  if (Array.isArray(value)) return value.map(decodeStorageValue);
  if (value && typeof value === "object") {
    if (value.__qaType === "Date") return new Date(value.value);
    if (value.__qaType === "ArrayBuffer") return Uint8Array.from(value.value).buffer;
    // Read the already retained backups without rewriting their on-disk format.
    if (value.__qaType === "Uint8Array") return Uint8Array.from(value.value);
    if (value.__qaType === "ArrayBufferView") {
      const constructor = viewTypes[value.constructor];
      if (
        !constructor ||
        !Number.isSafeInteger(value.byteOffset) ||
        value.byteOffset < 0 ||
        !Number.isSafeInteger(value.length) ||
        value.length < 0 ||
        !Number.isSafeInteger(value.byteLength) ||
        value.byteLength < 0 ||
        value.byteOffset + value.byteLength > maxViewAllocation ||
        value.bytes.length !== value.byteLength
      )
        throw Error("Invalid saved ArrayBuffer view");
      // Only offset + actual view bytes are allocated. Prefix bytes are zero-filled;
      // unrelated bytes outside the original view are intentionally not collected.
      const buffer = new ArrayBuffer(value.byteOffset + value.byteLength);
      new Uint8Array(buffer, value.byteOffset, value.byteLength).set(value.bytes);
      const restored = new constructor(buffer, value.byteOffset, value.length);
      if (restored.byteLength !== value.byteLength) throw Error("Saved view length differs");
      return restored;
    }
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, decodeStorageValue(item)]),
    );
  }
  return value;
}
