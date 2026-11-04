import { useEffect, useRef, useState } from 'react';
import { gameData } from '@voltaje/data';
import { currentDate, formatDate } from '@voltaje/sim';
import { ui, useUi, type WindowId } from './store';
import { fmtMoney, fmtNum } from './format';
import { riskLevel } from './FinancePanel';

function NavButton({ id, label, keyHint, badge, tone, title }: { id: WindowId; label: string; keyHint: string; badge?: number; tone?: string; title?: string }) {
  const open = useUi((s) => s.window === id || (id === 'projects' && s.window === 'project'));
  return (
    <button className={open ? 'active' : ''} data-nav={id} onClick={() => ui.openWindow(id)} title={`${title ?? label} (${keyHint})`} style={{ position: 'relative' }}>
      {label}
      {!!badge && <span className="nav-badge" style={{ background: tone ?? 'var(--accent)' }}>{badge > 99 ? '99+' : badge}</span>}
    </button>
  );
}

/** Menú desplegable «Más» con las ventanas de consulta (competidores y proveedores). */
function MoreMenu() {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const win = useUi((s) => s.window);
  const active = win === 'competitors' || win === 'suppliers';
  useEffect(() => {
    if (!open) return;
    const off = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false); };
    window.addEventListener('mousedown', off);
    return () => window.removeEventListener('mousedown', off);
  }, [open]);
  const item = (id: WindowId, label: string, key: string, hint: string) => (
    <button className={`menu-item ${win === id ? 'selected' : ''}`} data-nav={id} onClick={() => { setOpen(false); ui.openWindow(id); }}>
      <span>{label}<span className="dim menu-hint">{hint}</span></span><span className="spacer" /><kbd>{key}</kbd>
    </button>
  );
  return (
    <div className="menu-wrap" ref={ref}>
      <button className={active ? 'active' : ''} data-nav="more" onClick={() => setOpen(!open)} title="Competidores y proveedores">
        {win === 'competitors' ? 'Competidores' : win === 'suppliers' ? 'Proveedores' : 'Más'} ▾
      </button>
      {open && (
        <div className="panel menu">
          {item('competitors', 'Competidores', 'R', 'empresas rivales, cuota y plantas')}
          {item('suppliers', 'Proveedores', 'V', 'precios, materiales y plazos')}
        </div>
      )}
    </div>
  );
}

export function TopBar() {
  const game = useUi((s) => s.game);
  const speedId = useUi((s) => s.speedId);
  const unread = useUi((s) => s.unread);
  const fin = useUi((s) => s.views?.finance);
  const projects = useUi((s) => s.views?.projects);
  const biz = useUi((s) => s.views?.business);
  const contractAlerts = useUi((s) => (s.game?.business?.contracts ?? []).filter((k) => k.status === 'sin_proyecto' || ((k.status === 'en_desarrollo') && s.game!.tick > k.codDeadlineTick)).length);
  const researching = useUi((s) => !!s.game?.business?.research.active);
  if (!game) return null;
  const date = currentDate(game);
  const cash = game.company.cashUsd;
  const runway = fin?.bankruptcy.runwayMonths ?? null;
  const risk = fin ? riskLevel(fin) : null;
  const alerts = (projects ?? []).filter((p) => p.active).reduce((a, p) => a + p.warnings.length, 0);
  const active = (projects ?? []).filter((p) => p.active).length;

  return (
    <div className="panel row topbar">
      <div className="brand">{gameData.game.nombre.toUpperCase()}</div>
      <div className="company ellipsis" title={game.company.name}>{game.company.name}</div>
      <div className="row" style={{ gap: 4 }}>
        <NavButton id="projects" label={`Proyectos${active ? ` · ${active}` : ''}`} keyHint="P" badge={alerts} tone="var(--warn)" />
        <NavButton id="market" label="Mercado" keyHint="M" title="Licitaciones y ofertas" badge={biz?.biddableCount} tone="var(--info)" />
        <NavButton id="contracts" label="Contratos" keyHint="C" badge={contractAlerts} tone="var(--warn)" />
        <NavButton id="research" label={researching ? 'I+D ◔' : 'I+D'} keyHint="I" title="Investigación y desarrollo" />
        <NavButton id="finance" label="Finanzas" keyHint="F" />
        <NavButton id="events" label="Eventos" keyHint="E" badge={unread} />
        <MoreMenu />
      </div>
      <div className="spacer" />
      <div className="mono date" data-testid="date">{formatDate(date)}</div>
      <div className="row" style={{ gap: 4 }}>
        <button className={speedId === null ? 'active' : ''} onClick={() => ui.setSpeed(null)} title="Pausa (Espacio)">❚❚</button>
        {gameData.game.velocidades.map((v, i) => (
          <button key={v.id} className={speedId === v.id ? 'active' : ''} onClick={() => ui.setSpeed(v.id)}
            title={`${v.dias_por_segundo} día(s) por segundo (tecla ${i + 1})`}>{v.etiqueta}</button>
        ))}
      </div>
      <div className="spacer" />
      <button className="cash" onClick={() => ui.openWindow('finance')}
        title={`Caja · ${runway === null ? 'la empresa genera caja' : `alcanza para ~${fmtNum(runway, 0)} meses`}${risk ? ` · riesgo de quiebra: ${risk.label.toLowerCase()}` : ''}`}>
        <span className="dim">Caja </span>
        <span className="mono" style={{ fontSize: 15, fontWeight: 700, color: cash < 0 ? 'var(--bad)' : runway !== null && runway < 6 ? 'var(--warn)' : 'var(--good)' }} data-testid="cash">{fmtMoney(cash)}</span>
        {runway !== null && <span className="dim mono" style={{ fontSize: 11 }}> · {fmtNum(runway, 0)} m</span>}
      </button>
      <div className="row" style={{ gap: 4 }}>
        <button onClick={() => ui.set({ dialog: 'save' })} title="Guardar (⌘S)">Guardar</button>
        <button onClick={() => ui.set({ dialog: 'load' })}>Cargar</button>
        <button onClick={() => ui.set({ dialog: 'menu' })}>Menú</button>
      </div>
    </div>
  );
}
