import assert from "node:assert/strict";
import { encodeStorageValue, decodeStorageValue } from "./chapter_storage_codec.js";
import { snapshot, restore, preserveStorage } from "./chapter_storage_api.js";
import { createChapterWebHarness } from "./chapter_web_harness.js";

const heap = new ArrayBuffer(4096);
new Uint8Array(heap).fill(201);
const unsigned = new Uint8Array(heap, 7, 3);
unsigned.set([0, 128, 255]);
const signed = new Int8Array(heap, 21, 4);
signed.set([-128, -1, 0, 127]);
const data = {
  files: [
    { contents: unsigned, timestamp: new Date("2026-11-01T21:17:05.375Z"), mode: 33206 },
    { contents: signed, timestamp: new Date("2026-11-01T21:17:05.388Z"), mode: 33206 },
    { contents: Uint8Array.from([1, 128, 255]).buffer, mode: 33206 },
    { contents: new Uint16Array(heap, 30, 2), mode: 33206 },
    { contents: new DataView(heap, 45, 5), mode: 33206 },
  ],
  directory: { timestamp: new Date("2026-11-01T00:00:00Z"), mode: 16895 },
};
const encoded = encodeStorageValue(data);
const decoded = decodeStorageValue(JSON.parse(JSON.stringify(encoded)));
for (let n = 0; n < data.files.length; n++) {
  const before = data.files[n],
    after = decoded.files[n];
  assert.equal(after.contents.constructor, before.contents.constructor);
  assert.equal(after.mode, before.mode);
  if (ArrayBuffer.isView(before.contents)) {
    assert.equal(after.contents.byteOffset, before.contents.byteOffset);
    assert.equal(after.contents.byteLength, before.contents.byteLength);
    assert.equal(after.contents.length, before.contents.length);
    assert.deepEqual(
      new Uint8Array(after.contents.buffer, after.contents.byteOffset, after.contents.byteLength),
      new Uint8Array(
        before.contents.buffer,
        before.contents.byteOffset,
        before.contents.byteLength,
      ),
    );
    assert.equal(
      after.contents.buffer.byteLength,
      before.contents.byteOffset + before.contents.byteLength,
    );
  } else assert.deepEqual(new Uint8Array(after.contents), new Uint8Array(before.contents));
  if (before.timestamp) assert.equal(after.timestamp.getTime(), before.timestamp.getTime());
}
assert.deepEqual(decoded.directory, data.directory);
assert.equal(encoded.files[0].contents.bytes.length, 3);
assert.equal(encoded.files[1].contents.bytes.length, 4);
assert.deepEqual(
  decodeStorageValue({ __qaType: "Uint8Array", value: [0, 128, 255] }),
  Uint8Array.from([0, 128, 255]),
);

assert.throws(
  () =>
    decodeStorageValue({
      __qaType: "ArrayBufferView",
      constructor: "Uint8Array",
      byteOffset: 0,
      byteLength: 2,
      length: 2,
      bytes: [1],
    }),
  /Invalid/,
);

// Minimal asynchronous IndexedDB fixture: actual typed values are cloned and
// transactions signal completion after all queued request callbacks.
const rows = new Map([["original", structuredClone(data)]]);
let corruptWrites = false,
  failEnumeration = false,
  failReads = false;
const req = (operation) => {
  const result = {};
  queueMicrotask(() => {
    try {
      result.result = operation();
      result.onsuccess?.();
    } catch (error) {
      result.error = error;
      result.onerror?.();
    }
  });
  return result;
};
const db = {
  name: "/userfs",
  version: 1,
  objectStoreNames: ["FILE_DATA"],
  close() {},
  transaction() {
    const tx = {
      objectStore() {
        return {
          keyPath: null,
          autoIncrement: false,
          indexNames: [],
          getAllKeys: () => req(() => [...rows.keys()]),
          getAll: () =>
            req(() => {
              if (failReads) throw Error("record read failed");
              return structuredClone([...rows.values()]);
            }),
          put(value, key) {
            if (!corruptWrites) rows.set(key, structuredClone(value));
          },
          delete(key) {
            rows.delete(key);
          },
        };
      },
    };
    setTimeout(() => tx.oncomplete?.(), 0);
    return tx;
  },
};
globalThis.indexedDB = {
  async databases() {
    if (failEnumeration) throw Error("enumeration failed");
    return [{ name: "/userfs", version: 1 }];
  },
  open() {
    return req(() => db);
  },
};
const saved = await snapshot();
const persisted = JSON.parse(JSON.stringify(saved));
const lifecycle = [];
await assert.rejects(
  preserveStorage({
    stop: async () => {
      lifecycle.push("stop");
    },
    persistBackup: async (value) => {
      lifecycle.push("backup");
      return JSON.parse(JSON.stringify(value));
    },
    run: async () => {
      lifecycle.push("run");
      rows.set("original", { changed: true });
      rows.set("extra", { new: true });
      throw Error("action failed");
    },
  }),
  /action failed/,
);
assert.deepEqual(await snapshot(), saved);
assert.equal(rows.has("extra"), false);
assert.deepEqual(lifecycle, ["stop", "backup", "run", "stop"]);

let entered = false;
await assert.rejects(
  preserveStorage({
    stop: async () => {},
    persistBackup: async () => ({}),
    run: async () => {
      entered = true;
    },
  }),
  /backup differs/,
);
assert.equal(entered, false);
failEnumeration = true;
await assert.rejects(
  preserveStorage({
    stop: async () => {},
    persistBackup: async (value) => value,
    run: async () => {
      entered = true;
    },
  }),
  /enumeration failed/,
);
assert.equal(entered, false);
failEnumeration = false;
failReads = true;
await assert.rejects(
  preserveStorage({
    stop: async () => {},
    persistBackup: async (value) => value,
    run: async () => {
      entered = true;
    },
  }),
  /record read failed/,
);
assert.equal(entered, false);
failReads = false;
await assert.rejects(
  preserveStorage({
    stop: async () => {},
    persistBackup: async () => {
      throw Error("readback failed");
    },
    run: async () => {
      entered = true;
    },
  }),
  /readback failed/,
);
assert.equal(entered, false);
assert.deepEqual(await snapshot(), saved);

rows.set("original", { changed: true });
rows.set("extra", { new: true });
corruptWrites = true;
await assert.rejects(restore(persisted), /before cleanup/);
assert.equal(rows.has("extra"), true);
assert.deepEqual(persisted, saved);
corruptWrites = false;
await restore(persisted);
assert.deepEqual(await snapshot(), saved);

// Harness performs native input and checks captured runtime identity. No browser
// or origin is opened: CDP returns only the supplied read-only fixture.
let runtimeBuild = "fixed";
const clicks = [],
  keys = [];
const tab = {
  async click(...args) {
    clicks.push(args);
  },
  async pressKey(...args) {
    keys.push(args);
  },
  async getAXState() {},
};
const cdp = {
  async send(method, { expression }) {
    assert.equal(method, "Runtime.evaluate");
    return {
      result: {
        value:
          expression === "[innerWidth,innerHeight]"
            ? [200, 200]
            : {
                ok: true,
                build: { buildId: runtimeBuild },
                viewport: [200, 200],
                map: { origin: [0, 0], size: [200, 200], center: [0, 0], zoom: 1 },
              },
      },
    };
  },
};
assert.throws(
  () => createChapterWebHarness({ tab, cdp, buildId: "", artifactOrigin: "http://127.0.0.1:1234" }),
  /Explicit/,
);
const h = createChapterWebHarness({
  tab,
  cdp,
  buildId: "fixed",
  artifactOrigin: "http://127.0.0.1:1234",
});
await h.cell(0, 0, true);
assert.deepEqual(clicks, [[[112, 112], { clickCount: 2 }]]);
await h.key("Escape");
assert.deepEqual(keys, [[null, "Escape"]]);
runtimeBuild = "stale";
await assert.rejects(h.read(), /Unexpected captured build/);
await assert.rejects(
  h.wait(() => true),
  /Unexpected captured build/,
);
const originalPerformance = globalThis.performance;
let tick = 0;
globalThis.performance = { now: () => tick++ };
try {
  await assert.rejects(
    h.wait(() => false, { timeout: 1 }),
    /boundary/,
  );
  await assert.rejects(
    h.phase("failure", async () => {
      throw Error("phase failed");
    }),
    /phase failed/,
  );
  assert.ok(h.evidence().timings.failure >= 0);
} finally {
  globalThis.performance = originalPerformance;
}
console.log(
  "PASS isolated chapter QA: codec, recovery, backup failures, build identity, real-input adapter",
);
