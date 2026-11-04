import { useEffect, useState } from 'react';
import { saves, downloadFile, pickFile, type SaveRecord } from '../storage/saves';
import { sim } from '../worker/client';
import { loadGame, quitToMenu, saveGame } from './session';
import { ui, useUi } from './store';

export function SaveList({ onPick, refresh = 0 }: { onPick: (r: SaveRecord) => void; refresh?: number }) {
  const [list, setList] = useState<SaveRecord[] | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => { saves.list().then(setList).catch(() => setList([])); }, [tick, refresh]);
  if (!list) return <div className="dim">Cargando…</div>;
  if (!list.length) return <div className="dim">No hay partidas guardadas.</div>;
  return (
    <div className="scroll" style={{ display: 'grid', gap: 6, maxHeight: 300 }}>
      {list.map((r) => (
        <div key={r.slot} className="row panel" style={{ padding: '8px 10px', background: 'rgba(0,0,0,.2)' }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontWeight: 600 }}>{r.label} {r.kind === 'auto' && <span className="badge" style={{ border: '1px solid var(--panel-border)' }}>auto</span>}</div>
            <div className="dim" style={{ fontSize: 11 }}>{r.company} · {r.gameDate} · {new Date(r.savedAt).toLocaleString('es-PA')}</div>
          </div>
          <button onClick={() => onPick(r)}>Cargar</button>
          <button className="danger" title="Borrar" onClick={async () => { if (confirm(`¿Borrar "${r.label}"?`)) { await saves.remove(r.slot); setTick((t) => t + 1); } }}>✕</button>
        </div>
      ))}
    </div>
  );
}

function Modal({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.45)', display: 'grid', placeItems: 'center' }} onClick={() => ui.set({ dialog: null })}>
      <div className="panel" style={{ width: 460, padding: 20, background: 'var(--panel-solid)' }} onClick={(e) => e.stopPropagation()}>
        <div className="row" style={{ marginBottom: 12 }}><div style={{ fontSize: 16, fontWeight: 700 }}>{title}</div><span className="spacer" /><button onClick={() => ui.set({ dialog: null })}>✕</button></div>
        {children}
      </div>
    </div>
  );
}

export function Dialogs() {
  const dialog = useUi((s) => s.dialog);
  const company = useUi((s) => s.game?.company.name ?? '');
  const [label, setLabel] = useState('');
  const [refresh, setRefresh] = useState(0);
  const [error, setError] = useState('');
  useEffect(() => { setLabel(company); setError(''); }, [dialog, company]);
  if (!dialog) return null;

  if (dialog === 'save') {
    return (
      <Modal title="Guardar partida">
        <form className="row" onSubmit={async (e) => { e.preventDefault(); await saveGame('manual', label); setRefresh((r) => r + 1); ui.toast('Partida guardada', 'good'); }}>
          <input type="text" value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Nombre de la partida" />
          <button className="primary" type="submit">Guardar</button>
        </form>
        <div style={{ margin: '14px 0 6px' }} className="dim">Partidas existentes</div>
        <SaveList refresh={refresh} onPick={async (r) => { if (confirm('¿Cargar esa partida? Perderás el progreso no guardado.')) { await loadGame(r.data); } }} />
        <div className="row" style={{ marginTop: 12 }}>
          <button onClick={async () => { const t = await sim.save(); downloadFile(`voltaje-${company.replace(/\W+/g, '_')}.json`, t); }}>Exportar a archivo…</button>
        </div>
      </Modal>
    );
  }
  if (dialog === 'load') {
    const load = async (text: string) => { try { await loadGame(text); ui.toast('Partida cargada', 'good'); } catch (e) { setError((e as Error).message); } };
    return (
      <Modal title="Cargar partida">
        <SaveList onPick={(r) => load(r.data)} />
        <div className="row" style={{ marginTop: 12 }}>
          <button onClick={async () => { const t = await pickFile(); if (t) load(t); }}>Importar archivo…</button>
        </div>
        {error && <div style={{ color: 'var(--bad)', marginTop: 8 }}>{error}</div>}
      </Modal>
    );
  }
  return (
    <Modal title="Menú">
      <div style={{ display: 'grid', gap: 8 }}>
        <button onClick={() => ui.set({ dialog: 'save' })}>Guardar partida</button>
        <button onClick={() => ui.set({ dialog: 'load' })}>Cargar partida</button>
        <button className="danger" onClick={() => { if (confirm('¿Salir al menú principal? Perderás el progreso no guardado.')) quitToMenu(); }}>Salir al menú principal</button>
      </div>
    </Modal>
  );
}
