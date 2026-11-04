import { currentDate, formatDate } from '@voltaje/sim';
import { ui, useUi } from './store';
import { quitToMenu } from './session';
import { fmtMoney } from './format';

/** Pantalla de quiebra: la partida terminó (el worker ya no avanza ni acepta comandos). */
export function GameOver() {
  const game = useUi((s) => s.game);
  const f = useUi((s) => s.views?.finance);
  const dialog = useUi((s) => s.dialog);
  if (!game?.finance.bankrupt || dialog === 'load') return null;
  const ops = game.projects.filter((p) => p.stage === 'operacion').length;
  return (
    <div className="modal-back" style={{ background: 'rgba(5,10,18,.78)' }} data-testid="game-over">
      <div className="panel modal" style={{ width: 520, textAlign: 'center', padding: 30 }}>
        <div style={{ fontSize: 13, letterSpacing: '.3em', color: 'var(--bad)', fontWeight: 700 }}>QUIEBRA</div>
        <div style={{ fontSize: 26, fontWeight: 800, margin: '8px 0 4px' }}>{game.company.name} cerró sus puertas</div>
        <div className="dim">{formatDate(currentDate(game))}</div>
        <div className="panel" style={{ margin: '18px 0', padding: 14, background: 'rgba(0,0,0,.25)', textAlign: 'left' }}>
          <table className="kv"><tbody>
            <tr><td>Caja final</td><td style={{ color: 'var(--bad)' }}>{fmtMoney(game.company.cashUsd)}</td></tr>
            <tr><td>Deuda</td><td>{fmtMoney(f?.balance.debtUsd ?? 0)}</td></tr>
            <tr><td>Proyectos desarrollados</td><td>{game.projects.length}</td></tr>
            <tr><td>Plantas en operación</td><td>{ops}</td></tr>
          </tbody></table>
        </div>
        <div className="dim" style={{ fontSize: 12, marginBottom: 16 }}>La caja cerró en negativo {f?.bankruptcy.monthsLimit ?? 3} meses seguidos sin crédito de emergencia disponible.</div>
        <div className="row" style={{ justifyContent: 'center' }}>
          <button onClick={() => ui.set({ dialog: 'load' })}>Cargar partida</button>
          <button className="primary" onClick={quitToMenu}>Volver al menú</button>
        </div>
      </div>
    </div>
  );
}
