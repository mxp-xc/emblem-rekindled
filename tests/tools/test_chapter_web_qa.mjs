import assert from "node:assert/strict";
import {
  encodeStorageValue,
  decodeStorageValue,
} from "../../tools/resources/web/chapter_storage_codec.js";
import {
  snapshot,
  restore,
  preserveStorage,
} from "../../tools/resources/web/chapter_storage_api.js";
import { createChapterWebHarness } from "../../tools/resources/web/chapter_web_harness.js";

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
const cyclic = {};
cyclic.self = cyclic;
for (const value of [
  new Map([["slot", 7]]),
  new Set([1, 2]),
  /record/,
  { __qaType: "Date", value: "2026-01-01T00:00:00Z", note: "ordinary" },
  { nested: undefined },
  [undefined],
  new Array(1),
  Object.assign([1], { note: "must not be discarded" }),
  Object.assign([1], { note: new Map([["slot", 7]]) }),
  { nested: NaN },
  { nested: Infinity },
  { nested: -0 },
  { nested: 1n },
  cyclic,
]) {
  rows.set("unsupported", value);
  let ran = false,
    persistedUnsupported = false;
  await assert.rejects(
    preserveStorage({
      stop: async () => {},
      persistBackup: async (saved) => {
        persistedUnsupported = true;
        return saved;
      },
      run: async () => {
        ran = true;
      },
    }),
    /Unsupported|Reserved|Cyclic/,
  );
  assert.equal(ran, false);
  assert.equal(persistedUnsupported, false);
  assert.strictEqual(rows.get("unsupported"), value);
  rows.delete("unsupported");
}
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

// The browser contract fixture opens no browser or origin. It checks public
// operation ordering and supplies captured state, storage and artifact responses.
let runtimeBuild = "fixed";
const calls = [];
let readStates = [],
  loading = false,
  startupError = null;
const battle = { turn: 3, units: [{ id: 1, hp: 7 }] };
const storedBattle = { record: { state: battle }, bytes: [0, 128, 255] };
const state = (ui = {}, extra = {}) => ({
  ok: true,
  build: { buildId: runtimeBuild },
  viewport: [200, 200],
  map: { origin: [0, 0], size: [200, 200], center: [0, 0], zoom: 1 },
  ui,
  snapshot: { state: battle },
  controls: ["保存进度", "游戏设置", "读取进度", "GameSpeed", "Speed_32"].map((text) => ({
    text,
    name: text,
    rect: [10, 10, 20, 20],
  })),
  ...extra,
});
const browser = {
  async evaluate(expression) {
    assert.equal(loading, false, "page reads must wait for startup readiness");
    if (expression === "[innerWidth,innerHeight]") {
      calls.push(["viewport"]);
      return [200, 200];
    }
    if (expression.includes("playtest_request.json")) {
      calls.push(["read"]);
      return readStates.length ? readStates.shift() : state();
    }
    if (expression.includes("battle_save.json")) {
      calls.push(["stored"]);
      return structuredClone(storedBattle);
    }
    if (expression.includes("fetch(")) {
      calls.push(["artifact"]);
      return { ok: true };
    }
    throw Error("Unexpected page expression");
  },
  async key(value) {
    calls.push(["key", value]);
  },
  async click(...args) {
    calls.push(["click", ...args]);
  },
  async drag(...args) {
    calls.push(["drag", ...args]);
  },
  async settle() {
    calls.push(["settle"]);
  },
  async reload() {
    calls.push(["reload"]);
    loading = true;
  },
  async ready(options) {
    calls.push(["ready", options]);
    assert.equal(loading, true);
    if (startupError) throw startupError;
    loading = false;
  },
  async screenshot() {
    calls.push(["screenshot"]);
    return "fixture-png";
  },
};
const options = { browser, buildId: "fixed", artifactOrigin: "http://127.0.0.1:1234" };
assert.throws(() => createChapterWebHarness({ ...options, buildId: "" }), /Explicit/);
assert.throws(() => createChapterWebHarness({ ...options, browser: {} }), /Browser operation/);
const h = createChapterWebHarness(options);
await h.cell(0, 0, true);
assert.deepEqual(calls, [
  ["read"],
  ["viewport"],
  ["click", [112, 112], { clickCount: 2 }],
  ["settle"],
]);
calls.length = 0;
await h.key("Escape");
assert.deepEqual(calls, [["key", "Escape"], ["settle"]]);

// An offscreen target is brought into view by native drag before the click.
calls.length = 0;
readStates = [
  state({}, { map: { origin: [0, 0], size: [200, 200], center: [100, 100], zoom: 1 } }),
  state(),
];
await h.cell(0, 0);
assert.deepEqual(
  calls.map((call) => call[0]),
  ["read", "viewport", "drag", "settle", "read", "viewport", "click", "settle"],
);

const coldReads = () => {
  const menu = state({ menu: true, menuPage: "settings" }, { speed: 1 });
  const title = state(
    { title: true, titleOptions: true, titleEntries: ["游戏设置", "读取进度"] },
    { speed: 1 },
  );
  return [
    menu,
    menu,
    menu,
    menu,
    title,
    title,
    menu,
    menu,
    menu,
    menu,
    state(menu.ui, { speed: 32 }),
    { ...title, controls: [...title.controls].reverse() },
    title,
    state({}, { ready: true }),
  ];
};
calls.length = 0;
readStates = coldReads();
const continued = await h.saveCold("fixture");
assert.deepEqual(continued.snapshot.state, battle);
assert.equal(readStates.length, 0);
const reloadIndex = calls.findIndex((call) => call[0] === "reload");
assert.deepEqual(calls.slice(reloadIndex, reloadIndex + 3), [
  ["reload"],
  ["ready", { timeout: 15000 }],
  ["read"],
]);
assert.ok(calls.some((call) => call[0] === "screenshot"));

// Startup failure stops cold continuation before any new game probe.
calls.length = 0;
readStates = coldReads();
startupError = Error("startup timed out");
await assert.rejects(h.saveCold("failed-start"), /startup timed out/);
assert.deepEqual(calls.slice(-2), [["reload"], ["ready", { timeout: 15000 }]]);
startupError = null;
loading = false;
// Reloading into another package must fail before selecting a title option.
calls.length = 0;
readStates = coldReads();
readStates[4].build = { buildId: "another-package" };
await assert.rejects(h.saveCold("wrong-package"), /Unexpected captured build/);
assert.deepEqual(calls.slice(-2), [["ready", { timeout: 15000 }], ["read"]]);
readStates = [];
runtimeBuild = "stale";
await assert.rejects(h.read(), /Unexpected captured build/);
await assert.rejects(
  h.wait(() => true),
  /Unexpected captured build/,
);
runtimeBuild = "fixed";
const pageError = Error("page evaluation failed");
const failingPage = createChapterWebHarness({
  ...options,
  browser: {
    ...browser,
    evaluate: async () => {
      throw pageError;
    },
  },
});
await assert.rejects(failingPage.read(), (error) => error === pageError);
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
  "PASS isolated chapter QA: codec, recovery, backup failures, build identity, browser contract and cold continuation",
);
