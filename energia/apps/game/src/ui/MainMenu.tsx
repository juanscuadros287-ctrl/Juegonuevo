import { useEffect, useState } from 'react';
import { gameData } from '@voltaje/data';
import { saves, pickFile, type SaveRecord } from '../storage/saves';
import { loadGame, startNewGame } from './session';
import { SaveList } from './SaveDialog';

export function MainMenu() {
  const [mode, setMode] = useState<'root' | 'new' | 'load'>('root');
  const [name, setName] = useState('Energía del Istmo');
  const [seed, setSeed] = useState(() => Math.floor(Math.random() * 1e9));
  const [latest, setLatest] = useState<SaveRecord | null>(null);
  const [error, setError] = useState('');

  useEffect(() => { saves.list().then((l) => setLatest(l[0] ?? null)).catch(() => {}); }, [mode]);

  const tryLoad = async (text: string) => {
    try { setError(''); await loadGame(text); } catch (e) { setError((e as Error).message); }
  };
  const country = gameData.countries[gameData.game.pais_inicial];
  const cap = gameData.game.empresa_inicial;

  return (
    <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', paddingLeft: '7vw', pointerEvents: 'none' }}>
      <div className="panel" style={{ width: 380, padding: 26, pointerEvents: 'auto' }}>
        <div style={{ fontSize: 40, fontWeight: 900, letterSpacing: '.22em', color: 'var(--accent)' }}>{gameData.game.nombre.toUpperCase()}</div>
        <div className="dim" style={{ marginBottom: 22 }}>Desarrollo de proyectos de energía en todo el mundo</div>

        {mode === 'root' && (
          <div style={{ display: 'grid', gap: 8 }}>
            {latest && <button className="primary" onClick={() => tryLoad(latest.data)}>Continuar <span style={{ fontWeight: 400 }}>· {latest.company}, {latest.gameDate}</span></button>}
            <button className={latest ? '' : 'primary'} onClick={() => setMode('new')}>Nueva partida</button>
            <button onClick={() => setMode('load')}>Cargar partida</button>
            <button onClick={async () => { const t = await pickFile(); if (t) tryLoad(t); }}>Importar archivo…</button>
          </div>
        )}

        {mode === 'new' && (
          <form style={{ display: 'grid', gap: 10 }} onSubmit={(e) => { e.preventDefault(); if (name.trim().length >= 2) startNewGame(name, seed); }}>
            <label>Nombre de tu empresa<input type="text" value={name} maxLength={40} onChange={(e) => setName(e.target.value)} autoFocus /></label>
            <label>Semilla del mundo
              <div className="row"><input type="number" value={seed} onChange={(e) => setSeed(Math.abs(Math.floor(+e.target.value || 0)))} />
                <button type="button" onClick={() => setSeed(Math.floor(Math.random() * 1e9))} title="Aleatoria">⟳</button></div>
            </label>
            <div className="panel" style={{ padding: 10, background: 'rgba(0,0,0,.2)' }}>
              <div>País inicial: <b>{country.nombre}</b></div>
              <div className="dim" style={{ fontSize: 12 }}>Capital: US$ {cap.caja_usd.toLocaleString('es-PA')} · Gastos fijos: US$ {cap.gastos_fijos_mensuales_usd.toLocaleString('es-PA')}/mes</div>
              <div className="dim" style={{ fontSize: 12 }}>Inicio: {gameData.game.fecha_inicio.slice(0, 4)}</div>
            </div>
            <div className="row"><button type="button" onClick={() => setMode('root')}>Volver</button><span className="spacer" /><button className="primary" type="submit" disabled={name.trim().length < 2}>Fundar empresa</button></div>
          </form>
        )}

        {mode === 'load' && (
          <div style={{ display: 'grid', gap: 10 }}>
            <SaveList onPick={(r) => tryLoad(r.data)} />
            <button onClick={() => setMode('root')}>Volver</button>
          </div>
        )}
        {error && <div style={{ color: 'var(--bad)', marginTop: 10 }}>{error}</div>}
      </div>
      <div className="dim" style={{ position: 'absolute', bottom: 10, right: 14, fontSize: 10.5 }}>
        Mapa: Natural Earth · Placas: Bird (2003) · Recursos aproximados (ver docs/RECURSOS.md)
      </div>
    </div>
  );
}
