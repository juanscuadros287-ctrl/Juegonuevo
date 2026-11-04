/**
 * Partidas guardadas en IndexedDB (funciona igual en el navegador y dentro de la app de Mac).
 * Además se pueden exportar/importar como archivo .json para respaldo.
 */
export interface SaveRecord {
  slot: string; // 'auto-1'…, 'manual-<id>'
  kind: 'auto' | 'manual';
  label: string;
  company: string;
  gameDate: string;
  savedAt: number; // reloj real (solo para mostrar y ordenar)
  data: string;
}

const DB = 'voltaje';
const STORE = 'saves';

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: 'slot' });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function tx<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await open();
  return new Promise((resolve, reject) => {
    const r = fn(db.transaction(STORE, mode).objectStore(STORE));
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}

export const saves = {
  list: async (): Promise<SaveRecord[]> => (await tx<SaveRecord[]>('readonly', (s) => s.getAll())).sort((a, b) => b.savedAt - a.savedAt),
  get: (slot: string) => tx<SaveRecord | undefined>('readonly', (s) => s.get(slot)),
  put: (rec: SaveRecord) => tx('readwrite', (s) => s.put(rec)),
  remove: (slot: string) => tx('readwrite', (s) => s.delete(slot)),
  /** Rota las ranuras automáticas: usa la más antigua. */
  async nextAutoSlot(count: number): Promise<string> {
    const all = (await saves.list()).filter((r) => r.kind === 'auto');
    for (let i = 1; i <= count; i++) if (!all.some((r) => r.slot === `auto-${i}`)) return `auto-${i}`;
    return all.sort((a, b) => a.savedAt - b.savedAt)[0].slot;
  },
};

export function downloadFile(name: string, text: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

export function pickFile(): Promise<string | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json,application/json';
    input.onchange = async () => resolve(input.files?.[0] ? await input.files[0].text() : null);
    input.click();
  });
}
