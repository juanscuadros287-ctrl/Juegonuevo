import { useEffect, useState, type ReactNode } from 'react';
import type { ProjectStage } from '@voltaje/sim';
import { STAGE_COLORS } from '../globe/siteVisual';

/** Ventana grande centrada (proyectos, finanzas, eventos, detalle). */
export function Window({ title, subtitle, onClose, width = 1100, children, actions, testId }: {
  title: ReactNode; subtitle?: ReactNode; onClose: () => void; width?: number; children: ReactNode; actions?: ReactNode; testId?: string;
}) {
  return (
    <div className="window-wrap">
      <div className="panel window" style={{ width: `min(${width}px, calc(100vw - 24px))` }} data-testid={testId}>
        <div className="window-head">
          <div style={{ minWidth: 0 }}>
            <div className="window-title">{title}</div>
            {subtitle && <div className="dim window-sub">{subtitle}</div>}
          </div>
          <span className="spacer" />
          {actions}
          <button onClick={onClose} title="Cerrar (Esc)">✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function Tabs<T extends string>({ tabs, value, onChange }: { tabs: { id: T; label: ReactNode; badge?: ReactNode }[]; value: T; onChange: (t: T) => void }) {
  return (
    <div className="tabs" role="tablist">
      {tabs.map((t) => (
        <button key={t.id} role="tab" data-tab={t.id} className={value === t.id ? 'tab active' : 'tab'} onClick={() => onChange(t.id)}>
          {t.label}{t.badge}
        </button>
      ))}
    </div>
  );
}

/** Indicador grande (KPI). */
export function Stat({ label, value, hint, tone }: { label: ReactNode; value: ReactNode; hint?: ReactNode; tone?: 'good' | 'bad' | 'warn' }) {
  return (
    <div className="stat">
      <div className="stat-label">{label}</div>
      <div className="stat-value mono" style={{ color: tone ? `var(--${tone})` : undefined }}>{value}</div>
      {hint && <div className="stat-hint dim">{hint}</div>}
    </div>
  );
}

export function Bar({ value, color = 'var(--accent)', height = 6 }: { value: number; color?: string; height?: number }) {
  return (
    <div className="bar" style={{ height }}>
      <div style={{ width: `${Math.max(0, Math.min(1, value)) * 100}%`, background: color }} />
    </div>
  );
}

export function StageBadge({ stage, label }: { stage: ProjectStage; label: string }) {
  const c = STAGE_COLORS[stage];
  return <span className="badge" style={{ color: c, border: `1px solid ${c}`, whiteSpace: 'nowrap' }}>{label}</span>;
}

export function Pill({ children, tone }: { children: ReactNode; tone: 'good' | 'bad' | 'warn' | 'info' | 'dim' }) {
  const c = tone === 'dim' ? 'var(--text-dim)' : `var(--${tone})`;
  return <span className="badge" style={{ color: c, border: `1px solid ${c}`, whiteSpace: 'nowrap' }}>{children}</span>;
}

/** Botón que pide confirmación en línea (segundo clic) en lugar de un diálogo del navegador. */
export function ConfirmButton({ children, confirm, onConfirm, className = '', disabled, title }: {
  children: ReactNode; confirm: ReactNode; onConfirm: () => void; className?: string; disabled?: boolean; title?: string;
}) {
  const [armed, setArmed] = useState(false);
  useEffect(() => { if (!armed) return; const t = setTimeout(() => setArmed(false), 5000); return () => clearTimeout(t); }, [armed]);
  if (!armed) return <button className={className} disabled={disabled} title={title} onClick={() => setArmed(true)}>{children}</button>;
  return (
    <span className="row confirm" style={{ gap: 6 }}>
      <span className="dim" style={{ fontSize: 12 }}>{confirm}</span>
      <button className="danger" onClick={() => { setArmed(false); onConfirm(); }}>Confirmar</button>
      <button onClick={() => setArmed(false)}>Cancelar</button>
    </span>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty dim">{children}</div>;
}

/** Sección con título dentro de una pestaña. */
export function Section({ title, children, right }: { title: ReactNode; children: ReactNode; right?: ReactNode }) {
  return (
    <section className="section">
      <div className="row section-head"><h3>{title}</h3><span className="spacer" />{right}</div>
      {children}
    </section>
  );
}
