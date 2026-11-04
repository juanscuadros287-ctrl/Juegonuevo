import { gameData } from '@voltaje/data';
import { currentDate, formatDate } from '@voltaje/sim';
import { ui, useUi } from './store';
import { fmtUsd } from './format';

export function TopBar() {
  const game = useUi((s) => s.game);
  const speedId = useUi((s) => s.speedId);
  if (!game) return null;
  const date = currentDate(game);
  const cash = game.company.cashUsd;
  const runway = game.company.monthlyFixedCostUsd > 0 ? cash / game.company.monthlyFixedCostUsd : Infinity;

  return (
    <div className="panel row" style={{ position: 'absolute', top: 12, left: 12, right: 12, padding: '8px 12px', gap: 14 }}>
      <div style={{ fontWeight: 800, letterSpacing: '.18em', color: 'var(--accent)' }}>{gameData.game.nombre.toUpperCase()}</div>
      <div style={{ fontWeight: 600 }}>{game.company.name}</div>
      <div className="spacer" />
      <div className="mono" style={{ minWidth: 150, textAlign: 'right', fontSize: 14 }} data-testid="date">{formatDate(date)}</div>
      <div className="row" style={{ gap: 4 }}>
        <button className={speedId === null ? 'active' : ''} onClick={() => ui.setSpeed(null)} title="Pausa (Espacio)">❚❚</button>
        {gameData.game.velocidades.map((v, i) => (
          <button key={v.id} className={speedId === v.id ? 'active' : ''} onClick={() => ui.setSpeed(v.id)}
            title={`${v.dias_por_segundo} día(s) por segundo (tecla ${i + 1})`}>{v.etiqueta}</button>
        ))}
      </div>
      <div className="spacer" />
      <div title={`Gastos fijos: ${fmtUsd(game.company.monthlyFixedCostUsd)}/mes · alcanza para ${runway === Infinity ? '∞' : Math.max(0, Math.floor(runway))} meses`}>
        <span className="dim">Caja </span>
        <span className="mono" style={{ fontSize: 15, fontWeight: 700, color: cash < 0 ? 'var(--bad)' : runway < 6 ? 'var(--warn)' : 'var(--good)' }} data-testid="cash">{fmtUsd(cash)}</span>
      </div>
      <div className="row" style={{ gap: 4 }}>
        <button onClick={() => ui.set({ dialog: 'save' })} title="Guardar (⌘S)">Guardar</button>
        <button onClick={() => ui.set({ dialog: 'load' })}>Cargar</button>
        <button onClick={() => ui.set({ dialog: 'menu' })}>Menú</button>
      </div>
    </div>
  );
}
