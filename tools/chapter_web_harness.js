// One fresh factory per fixed package avoids retained helpers closing over an old build.
// browser supplies page evaluation, native input, settling, startup readiness and
// PNG screenshot capture; client-specific handles stay in the execution environment.
export function createChapterWebHarness({ browser, buildId, artifactOrigin }) {
  if (!buildId || !/^http:\/\/127\.0\.0\.1:\d+$/.test(artifactOrigin))
    throw Error("Explicit fixed buildId and loopback artifact origin required");
  for (const method of [
    "evaluate",
    "key",
    "click",
    "drag",
    "settle",
    "reload",
    "ready",
    "screenshot",
  ])
    if (typeof browser?.[method] !== "function")
      throw Error("Browser operation required: " + method);
  const inputs = [],
    timings = {};
  const prefix = "/userfs/godot/app_userdata/纹章传说：重燃/";
  const canonical = (value) =>
    Array.isArray(value)
      ? value.map(canonical)
      : value && typeof value === "object"
        ? Object.fromEntries(
            Object.keys(value)
              .sort()
              .map((key) => [key, canonical(value[key])]),
          )
        : value;
  const equal = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
  const evaluate = (expression) => browser.evaluate(expression);
  const saveArtifact = async (name, value) => {
    if (!/^[A-Za-z0-9_-]+$/.test(name)) throw Error("Invalid artifact name");
    return evaluate(
      `(async()=>{const r=await fetch(${JSON.stringify(artifactOrigin + "/" + name + ".json")},{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(${JSON.stringify(value)})});if(!r.ok)throw Error(await r.text());return r.json()})()`,
    );
  };
  const read = async () => {
    const value = await evaluate(`(async()=>{
      const prefix=${JSON.stringify(prefix)},requestId='chapter-qa-'+Date.now()+'-'+Math.random();
      engine.copyToFS(prefix+'playtest_request.json',new TextEncoder().encode(JSON.stringify({requestId})).buffer);
      const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('/userfs');r.onupgradeneeded=()=>{r.transaction.abort();reject(Error('Unexpected DB creation'))};r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
      try{const end=performance.now()+15000;while(performance.now()<end){const r=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA').get(prefix+'playtest_state.json'),row=await new Promise((resolve,reject)=>{r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});if(row){const result=JSON.parse(new TextDecoder().decode(row.contents));if(result.requestId===requestId)return result}await new Promise(resolve=>setTimeout(resolve,15))}throw Error('No correlated read-only response')}finally{db.close()}
    })()`);
    if (!value.ok || value.build.buildId !== buildId)
      throw Error("Unexpected captured build: " + JSON.stringify(value.build));
    return value;
  };
  const key = async (value) => {
    inputs.push({ key: value, at: Date.now() });
    await browser.key(value);
    await browser.settle();
  };
  const click = async (point) => {
    inputs.push({ click: point, at: Date.now() });
    await browser.click(point);
    await browser.settle();
  };
  const control = async (label, byName = false) => {
    const state = await read();
    const item = state.controls.find(
      (item) => item.enabled !== false && (byName ? item.name === label : item.text === label),
    );
    if (!item) throw Error("Visible control missing: " + label);
    // Browser native input uses CSS points; Godot window may be a Retina renderbuffer.
    const css = await evaluate("[innerWidth,innerHeight]");
    const [x, y, width, height] = item.rect;
    await click([
      ((x + width / 2) * css[0]) / state.viewport[0],
      ((y + height / 2) * css[1]) / state.viewport[1],
    ]);
  };
  const cell = async (x, y, double = false) => {
    let point;
    for (let attempt = 0; attempt < 5; attempt++) {
      const state = await read(),
        view = state.map,
        css = await evaluate("[innerWidth,innerHeight]");
      const scale = css.map((value, axis) => value / state.viewport[axis]);
      const origin = view.origin.map((value, axis) => value * scale[axis]);
      const size = view.size.map((value, axis) => value * scale[axis]);
      point = [x, y].map(
        (value, axis) =>
          origin[axis] +
          size[axis] / 2 +
          (value + 0.5 - view.center[axis]) * 24 * view.zoom * scale[axis],
      );
      if (
        point.every(
          (value, axis) => value >= origin[axis] + 20 && value <= origin[axis] + size[axis] - 20,
        )
      )
        break;
      const delta = point.map((value, axis) =>
        Math.max(
          -size[axis] + 72,
          Math.min(size[axis] - 72, origin[axis] + size[axis] / 2 - value),
        ),
      );
      const start = delta.map(
        (value, axis) =>
          origin[axis] +
          (Math.abs(value) > 1 ? (value < 0 ? size[axis] - 36 : 36) : size[axis] / 2),
      );
      const end = start.map((value, axis) => value + delta[axis]);
      inputs.push({ drag: [start, end], purpose: "Bring cell into map viewport", at: Date.now() });
      await browser.drag(start, end);
      await browser.settle();
      if (attempt === 4) throw Error("Target cell is outside the map viewport");
    }
    if (double) {
      // TacticalMap accepts two taps within350ms. A state read round trip between
      // separate clicks can exceed that limit on a busy host.
      inputs.push({ click: point, clickCount: 2, at: Date.now() });
      await browser.click(point, { clickCount: 2 });
      await browser.settle();
    } else await click(point);
  };
  const wait = async (predicate, { advance = false, timeout = 30000 } = {}) => {
    const deadline = performance.now() + timeout;
    while (performance.now() < deadline) {
      const state = await read();
      if (predicate(state)) return state;
      if (advance && state.ui.commander) await key("Escape");
      else if (
        advance &&
        (state.ui.dialogue || state.ui.prologue || state.ui.feedback === "tutorial")
      )
        await key("Return");
    }
    throw Error("Expected business boundary not reached");
  };
  const title = async (text) => {
    let state;
    const deadline = performance.now() + 20000;
    while (performance.now() < deadline) {
      state = await read();
      if (!state.ui.title) throw Error("Title selector is not open");
      if (state.ui.titleOptions && !state.ui.prologue) break;
      await key("Return");
    }
    if (!state.ui.titleOptions || state.ui.prologue)
      throw Error("Title selector did not become ready");
    const entries = state.ui.titleEntries,
      selected = state.controls.find((item) => entries.includes(item.text))?.text;
    if (!selected || !entries.includes(text)) throw Error("Title option missing");
    const forward =
      (entries.indexOf(text) - entries.indexOf(selected) + entries.length) % entries.length;
    const backward =
      (entries.indexOf(selected) - entries.indexOf(text) + entries.length) % entries.length;
    for (let n = 0; n < Math.min(forward, backward); n++)
      await key(forward <= backward ? "Right" : "Left");
    await control(text);
  };
  const speed = async (value) => {
    let state = await read();
    if (!(state.ui.menu && state.ui.menuPage === "settings")) {
      if (state.ui.title) await title("游戏设置");
      else {
        if (!state.ui.menu) await control("Menu", true);
        state = await read();
        if (state.ui.menuPage !== "settings") await control("游戏设置");
      }
    }
    await control("GameSpeed", true);
    await control("Speed_" + value, true);
    if ((await read()).speed !== value) throw Error("Session rate not applied");
  };
  const stored = async (name) => {
    if (!/^[A-Za-z0-9_-]+\.json$/.test(name)) throw Error("Invalid record name");
    return evaluate(
      `(async()=>{const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('/userfs');r.onupgradeneeded=()=>{r.transaction.abort();reject(Error('Unexpected DB creation'))};r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});try{const r=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA').get(${JSON.stringify(prefix + name)}),row=await new Promise((resolve,reject)=>{r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});return row?{record:JSON.parse(new TextDecoder().decode(row.contents)),bytes:Array.from(new Uint8Array(row.contents.buffer,row.contents.byteOffset,row.contents.byteLength)),constructor:row.contents.constructor.name,byteOffset:row.contents.byteOffset,length:row.contents.length}:null}finally{db.close()}})()`,
    );
  };
  const capture = async (name, state) => {
    const png = await browser.screenshot();
    await saveArtifact(name, { png });
    if (state) await saveArtifact(name + "-state", state);
  };
  const saveCold = async (name) => {
    const expected = (await read()).snapshot.state;
    if (!(await read()).ui.menu) await control("Menu", true);
    await control("保存进度");
    const deadline = performance.now() + 15000;
    let saved;
    while (performance.now() < deadline) {
      await read();
      saved = await stored("battle_save.json");
      if (saved && equal(saved.record.state, expected)) break;
    }
    if (!saved || !equal(saved.record.state, expected))
      throw Error("Requested state did not persist");
    await saveArtifact(name + "-saved", saved);
    await browser.reload();
    await browser.ready({ timeout: 15000 });
    await title("游戏设置");
    if ((await read()).speed !== 1) throw Error("Cold startup did not use1x");
    await speed(32);
    await key("Escape");
    await title("读取进度");
    const state = await wait((state) => state.ready && !state.ui.title);
    if (!equal(state.snapshot.state, expected)) throw Error("Cold battle state differs");
    if (!equal((await stored("battle_save.json")).bytes, saved.bytes))
      throw Error("Cold continue bytes differ");
    await capture(name + "-cold-equal", state);
    return state;
  };
  const phase = async (name, run) => {
    const start = performance.now();
    try {
      return await run();
    } finally {
      timings[name] = (performance.now() - start) / 1000;
    }
  };
  return {
    buildId,
    read,
    key,
    click,
    control,
    cell,
    wait,
    title,
    speed,
    stored,
    capture,
    saveCold,
    saveArtifact,
    phase,
    evidence: () => ({ buildId, inputs, timings }),
  };
}
