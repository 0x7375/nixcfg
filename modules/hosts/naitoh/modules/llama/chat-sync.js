(() => {
  const URL = '/__chats.json';
  const DB = 'LlamaUi';
  const log = (...a) => console.log('[ChatStore]', ...a);

  let ready = false; // no saving until the startup restore has finished
  let busy = false;  // our own restore writes must not trigger a save
  let timer;

  // Paint the app's real background early, remembered per system colour scheme
  const SCHEME = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  const BG_KEY = '__bg:' + SCHEME;
  try {
    const bg = localStorage.getItem(BG_KEY);
    if (bg) {
      const s = document.createElement('style');
      s.textContent = 'html{background:' + bg + '}';
      document.documentElement.appendChild(s);
    }
  } catch { }

  const rememberBg = () => {
    try {
      for (const el of [document.body, document.documentElement]) {
        const c = getComputedStyle(el).backgroundColor;
        if (c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') {
          localStorage.setItem(BG_KEY, c);
          return;
        }
      }
    } catch { }
  };
  window.addEventListener('load', () => setTimeout(rememberBg, 1000));

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations().then((rs) => rs.forEach((r) => r.unregister()));
    navigator.serviceWorker.register = () => new Promise(() => { }); // never resolves
    if (window.caches) caches.keys().then((ks) => ks.forEach((k) => caches.delete(k)));
  }

  console.log('[ChatStore] script loaded');

  const req = (r) => new Promise((res, rej) => {
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
  const openDb = () => req(indexedDB.open(DB));

  const dump = async () => {
    const db = await openDb();
    try {
      const stores = {};
      for (const s of db.objectStoreNames) {
        stores[s] = await req(db.transaction(s, 'readonly').objectStore(s).getAll());
      }
      return stores;
    } finally {
      db.close();
    }
  };

  const fetchServer = async () => {
    try {
      const r = await fetch(URL, { cache: 'no-store' });
      if (!r.ok) return null;
      const data = await r.json();
      return data.stores ? data : null;
    } catch {
      return null;
    }
  };

  // Replace local data with the server copy, then reload.
  // sessionStorage.__rev records the revision this tab is in sync with, which prevents reload loops.
  const restore = async (server) => {
    busy = true;
    const db = await openDb();
    try {
      for (const [s, items] of Object.entries(server.stores)) {
        if (!db.objectStoreNames.contains(s)) continue;
        await new Promise((res, rej) => {
          const tx = db.transaction(s, 'readwrite');
          const store = tx.objectStore(s);
          store.clear();
          for (const item of items) store.put(item);
          tx.oncomplete = res;
          tx.onerror = tx.onabort = () => rej(tx.error);
        });
      }
    } finally {
      db.close();
    }
    sessionStorage.__rev = String(server.ts);
    log('restored from server, reloading');
    location.reload();
  };

  const save = () => {
    if (!ready || busy) return;
    clearTimeout(timer);
    timer = setTimeout(async () => {
      timer = null;
      try {
        const server = await fetchServer();
        if (server && sessionStorage.__rev !== String(server.ts)) {
          return restore(server); // another device saved since we synced: server wins
        }
        const stores = await dump();
        if (Object.values(stores).every((items) => items.length === 0)) return; // never save an empty DB
        const ts = Date.now();
        const r = await fetch(URL, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ts, stores }),
        });
        if (r.ok) { sessionStorage.__rev = String(ts); log('saved'); }
        else console.error('[ChatStore] save failed, status', r.status);
      } catch (e) {
        console.error('[ChatStore] save error', e);
      }
    }, 500);
  };

  const start = async () => {
    try {
      const server = await fetchServer();
      if (server && sessionStorage.__rev !== String(server.ts)) return restore(server);
    } catch (e) {
      console.error('[ChatStore] start error', e);
    }
    ready = true;
    log('ready');
  };

  let lastCheck = 0;
  const check = async () => {
    if (!ready || busy || timer) return;
    const now = Date.now();
    if (now - lastCheck < 3000) return; // throttle
    lastCheck = now;
    const server = await fetchServer();
    if (server && sessionStorage.__rev !== String(server.ts)) restore(server);
  };
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') check();
  });
  window.addEventListener('focus', check);
  document.addEventListener('pointerdown', check, true);

  // Save after any write transaction commits
  const origTx = IDBDatabase.prototype.transaction;
  IDBDatabase.prototype.transaction = function(...args) {
    const tx = origTx.apply(this, args);
    if (args[1] && args[1] !== 'readonly') tx.addEventListener('complete', save);
    return tx;
  };

  // Wait for the app to create its DB, without creating it ourselves
  let tries = 0;
  const wait = setInterval(async () => {
    try {
      const dbs = await indexedDB.databases();
      if (++tries % 20 === 1) log('waiting, dbs =', dbs.map((d) => d.name));
      if (!dbs.some((d) => d.name === DB)) return;
      const db = await openDb();
      const ok = db.objectStoreNames.length > 0;
      db.close();
      if (ok) { clearInterval(wait); start(); }
    } catch (e) {
      console.error('[ChatStore] wait error', e);
    }
  }, 150);
})();
