// Browser-only QA storage API. Use on a stopped, explicitly owned origin.
import {
  encodeStorageValue as encode,
  decodeStorageValue as decode,
} from "./chapter_storage_codec.js";

const request = (r) =>
  new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
const open = (d) =>
  new Promise((resolve, reject) => {
    const r = indexedDB.open(d.name, d.version);
    r.onupgradeneeded = () => {
      r.transaction.abort();
      reject(Error("Unexpected DB creation"));
    };
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
const commit = (tx) =>
  new Promise((resolve, reject) => {
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
const canon = (v) =>
  Array.isArray(v)
    ? v.map(canon)
    : v && typeof v === "object"
      ? Object.fromEntries(
          Object.keys(v)
            .sort()
            .map((k) => [k, canon(v[k])]),
        )
      : v;
const equal = (a, b) => JSON.stringify(canon(a)) === JSON.stringify(canon(b));

// stop must quiesce the game while keeping this origin's storage API available.
// persistBackup writes a fresh file and reads it back, rather than acknowledging
// a memory-only copy. Both are supplied by the batch's existing browser adapter.
export async function preserveStorage({ stop, persistBackup, run }) {
  if (typeof stop !== "function") throw Error("A game-stop callback is required");
  await stop();
  const saved = await snapshot();
  const persisted = await persistBackup(saved);
  if (!equal(saved, persisted)) throw Error("Persisted QA backup differs; stop before mutation");
  if (!equal(saved, await snapshot())) throw Error("Storage changed during backup");
  try {
    return await run();
  } finally {
    await stop();
    await restore(persisted);
  }
}

export async function snapshot() {
  const result = { complete: true, databases: [] };
  for (const d of (await indexedDB.databases()).sort((a, b) => a.name.localeCompare(b.name))) {
    const db = await open(d);
    try {
      const stores = [];
      for (const name of db.objectStoreNames) {
        const store = db.transaction(name, "readonly").objectStore(name);
        const [keys, values] = await Promise.all([
          request(store.getAllKeys()),
          request(store.getAll()),
        ]);
        stores.push({
          name,
          keyPath: store.keyPath,
          autoIncrement: store.autoIncrement,
          indexes: Array.from(store.indexNames).map((n) => {
            const i = store.index(n);
            return { name: n, keyPath: i.keyPath, unique: i.unique, multiEntry: i.multiEntry };
          }),
          records: keys.map((key, n) => ({ key: encode(key), value: encode(values[n]) })),
        });
      }
      result.databases.push({ name: db.name, version: db.version, stores });
    } finally {
      db.close();
    }
  }
  return result;
}

export async function restore(saved) {
  if (!saved.complete) throw Error("Incomplete QA backup");
  const current = await snapshot();
  const schema = (data) =>
    data.databases.map((d) => ({ ...d, stores: d.stores.map((s) => ({ ...s, records: [] })) }));
  if (!equal(schema(saved), schema(current)))
    throw Error("QA schema changed; preserve backup and stop");
  for (const d of saved.databases) {
    const db = await open(d);
    try {
      for (const s of d.stores) {
        const tx = db.transaction(s.name, "readwrite"),
          store = tx.objectStore(s.name);
        for (const row of s.records) {
          if (store.keyPath === null) store.put(decode(row.value), decode(row.key));
          else store.put(decode(row.value));
        }
        await commit(tx);
      }
    } finally {
      db.close();
    }
  }
  const restored = await snapshot();
  for (const d of saved.databases)
    for (const s of d.stores)
      for (const original of s.records) {
        const row = restored.databases
          .find((x) => x.name === d.name)
          .stores.find((x) => x.name === s.name)
          .records.find((x) => equal(x.key, original.key));
        if (!row || !equal(row.value, original.value))
          throw Error("Original bytes/types/metadata differ before cleanup");
      }
  for (const d of saved.databases) {
    const db = await open(d);
    try {
      for (const s of d.stores) {
        const entries = restored.databases
          .find((x) => x.name === d.name)
          .stores.find((x) => x.name === s.name).records;
        const extra = entries.filter(
          (row) => !s.records.some((original) => equal(original.key, row.key)),
        );
        if (extra.length) {
          const tx = db.transaction(s.name, "readwrite"),
            store = tx.objectStore(s.name);
          extra.forEach((row) => store.delete(decode(row.key)));
          await commit(tx);
        }
      }
    } finally {
      db.close();
    }
  }
  if (!equal(await snapshot(), saved)) throw Error("Final QA storage differs");
  return {
    allOriginalKeysBytesTypesMetadataEqual: true,
    originalsVerifiedBeforeExtraCleanup: true,
    count: saved.databases.flatMap((d) => d.stores).reduce((n, s) => n + s.records.length, 0),
  };
}
