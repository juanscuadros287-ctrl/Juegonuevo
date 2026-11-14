/**
 * Fase 6: arnés de balance. Juega partidas largas con el JUGADOR controlado por un bot de estrategia simple (los mismos
 * comandos y la misma toma de decisiones que la IA: `decideCompetitor` sobre el estado del jugador) contra las 5 IA, y
 * resume resultados: patrimonio por año, quiebra, MW, países, equipo, TIR de los proyectos y resultados de la IA.
 * Lo usan `balance-*.test.ts` (condiciones) y `npm run balance` (reporte).
 */
import {
  actorView, applyCommand, balanceSheet, decideCompetitor, projectEconomics, siteKey, step, typicalEconomics,
  type CompetitorDef, type GameState, type SimEvent,
} from '../src';
import { isTerminal } from '../src/project/helpers';
import { ctx, data, newGame } from './helpers';

export type Strategy = 'pasivo' | 'solar_conservador' | 'agresivo' | 'diversificado';
export const STRATEGIES: Strategy[] = ['pasivo', 'solar_conservador', 'agresivo', 'diversificado'];

const baseDef = (o: Partial<CompetitorDef>): CompetitorDef => ({
  id: 'bot', nombre: 'Bot', estrategia: 'conservadora', estrategia_aparente: '', descripcion: '', caja_inicial_usd: 1_200_000, gastos_fijos_mensuales_usd: 18_500,
  reputacion_inicial: 25, experiencia_mw_inicial: 0, tecnologias: ['solar_fv'], margen_objetivo: 0.12, tasa_descuento: 0.09, apalancamiento: 0.65, socio: 0.5,
  max_proyectos: 1, mw: { min: 5, max: 15 }, proveedores: 'calidad', prob_ofertar: 0.3, ofertar_epc: false, dias_decision: 14, reserva_meses: 6, vende: 'nunca',
  investigacion: { presupuesto_mensual_usd: 0, prioridades: [] }, ...o,
});

/** Definición de cada estrategia simple del jugador (perfiles comparables a los de la IA). */
export const BOT_DEFS: Record<Exclude<Strategy, 'pasivo'>, CompetitorDef> = {
  solar_conservador: baseDef({
    estrategia: 'conservadora', tecnologias: ['solar_fv'], margen_objetivo: 0.14, tasa_descuento: 0.1, apalancamiento: 0.6, socio: 0.6, max_proyectos: 1, mw: { min: 10, max: 15 },
    proveedores: 'calidad', prob_ofertar: 0.25, reserva_meses: 8, vende: 'listo_para_construir',
  }),
  agresivo: baseDef({
    estrategia: 'agresiva', tecnologias: ['solar_fv', 'eolica_tierra'], margen_objetivo: 0.03, tasa_descuento: 0.075, apalancamiento: 0.8, socio: 0.4, max_proyectos: 2, mw: { min: 20, max: 50 },
    proveedores: 'baratos', prob_ofertar: 0.9, ofertar_epc: true, reserva_meses: 4, vende: 'en_crisis', dias_decision: 10,
  }),
  diversificado: baseDef({
    estrategia: 'fondo', tecnologias: ['solar_fv', 'eolica_tierra'], margen_objetivo: 0.08, tasa_descuento: 0.085, apalancamiento: 0.7, socio: 0.6, max_proyectos: 1, mw: { min: 15, max: 30 },
    proveedores: 'equilibrados', prob_ofertar: 0.5, reserva_meses: 5, vende: 'listo_para_construir',
    investigacion: { presupuesto_mensual_usd: 4_000, prioridades: ['mercado_regional', 'mercado_rep_dominicana', 'mercado_costa_rica', 'mercado_colombia', 'contrato_ppa_corporativo'] },
    expansion: { paises: ['DOM', 'CRI', 'COL'], caja_min_usd: 2_500_000 },
  }),
};

export interface RunResult {
  strategy: Strategy;
  seed: number;
  years: number;
  /** Patrimonio al cierre de cada año (USD). */
  equityByYear: number[];
  cashByYear: number[];
  finalEquityUsd: number;
  initialCashUsd: number;
  bankrupt: boolean;
  bankruptYear?: number;
  operatingMw: number;
  countries: number;
  headcount: number;
  projectIrrs: { techId: string; countryCode: string; irr: number | null }[];
  ai: { name: string; strategy: string; equityMultiple: number; bankrupt: boolean; operatingMw: number; headcount: number }[];
  ms: number;
  /** Suma por categoría contable de toda la partida (diagnóstico). */
  lines: Record<string, number>;
  projects: string[];
}

function occupied(state: GameState): Set<string> {
  const s = new Set<string>();
  const add = (ps: GameState['projects']) => { for (const p of ps) if (!isTerminal(p)) s.add(siteKey(p.site.lat, p.site.lon)); };
  add(state.projects);
  for (const c of state.competitors) add(c.projects);
  return s;
}

/** Comandos del bot del jugador (null = pasivo). */
export function botCommands(state: GameState, def: CompetitorDef | null) {
  if (!def || state.finance.bankrupt) return [];
  return decideCompetitor(state, ctx, { def: { ...def, gastos_fijos_mensuales_usd: state.company.monthlyFixedCostUsd }, occupiedSites: occupied(state) });
}

export function runStrategy(strategy: Strategy, seed: number, years: number): RunResult {
  const t0 = performance.now();
  const s = newGame(seed);
  const def = strategy === 'pasivo' ? null : BOT_DEFS[strategy];
  const res: RunResult = { strategy, seed, years, equityByYear: [], cashByYear: [], finalEquityUsd: 0, initialCashUsd: s.company.cashUsd, bankrupt: false, operatingMw: 0, countries: 1, headcount: 0, projectIrrs: [], ai: [], ms: 0, lines: {}, projects: [] };
  const irrSeen = new Set<string>();
  for (let d = 0; d < Math.round(years * 365.25); d++) {
    const cmds = def && s.tick % def.dias_decision === 0 ? botCommands(s, def) : [];
    const ev: SimEvent[] = step(s, cmds, ctx);
    for (const e of ev) {
      if (e.type === 'projectOperational' && !irrSeen.has(e.projectId)) {
        irrSeen.add(e.projectId);
        const p = s.projects.find((x) => x.id === e.projectId);
        if (p) res.projectIrrs.push({ techId: p.techId, countryCode: p.countryCode, irr: projectEconomics(s, ctx, p).model.irrEquity });
      }
      if (e.type === 'bankruptcy' && !res.bankrupt) { res.bankrupt = true; res.bankruptYear = s.tick / 365.25; }
    }
    if (s.tick % 365 === 0) { res.equityByYear.push(balanceSheet(s).equityUsd); res.cashByYear.push(s.company.cashUsd); }
    if (s.finance.bankrupt) {
      // La partida terminó para el jugador: el mundo no sigue (el resultado es la quiebra).
      res.bankrupt = true; res.bankruptYear ??= s.tick / 365.25;
      break;
    }
  }
  res.finalEquityUsd = s.finance.bankrupt ? Math.min(0, balanceSheet(s).equityUsd) : balanceSheet(s).equityUsd;
  res.operatingMw = s.projects.filter((p) => p.operation && !isTerminal(p)).reduce((a, p) => a + p.mw, 0);
  res.countries = 1 + Object.values(s.business.presence ?? {}).filter((p) => p.status === 'activa').length;
  res.headcount = s.business.team?.employees.length ?? 0;
  res.ai = s.competitors.map((c) => {
    const d = data.competitors!.empresas.find((x) => x.id === c.defId)!;
    return { name: c.name, strategy: d.estrategia, equityMultiple: balanceSheet(actorView(s, c)).equityUsd / d.caja_inicial_usd, bankrupt: c.status === 'quebrada',
      operatingMw: c.projects.filter((p) => p.operation && !isTerminal(p)).reduce((a, p) => a + p.mw, 0), headcount: c.business.team?.employees.length ?? 0 };
  });
  for (const st of s.finance.statements) for (const [k, v] of Object.entries(st.lines)) res.lines[k] = (res.lines[k] ?? 0) + v;
  res.projects = s.projects.map((p) => `${p.techId}:${p.mw}:${p.stage}`);
  res.ms = performance.now() - t0;
  void applyCommand;
  return res;
}

/** TIR del capital de proyectos típicos (catálogo, sitio típico del país) para el reporte. */
export function typicalIrrTable(techs: string[], countries: string[]) {
  const s = newGame(1, undefined, false);
  step(s, [], ctx);
  const rows: { techId: string; countryCode: string; irr: number | null; lcoe: number }[] = [];
  for (const t of techs) for (const c of countries) {
    const e = typicalEconomics(s, ctx, t, c);
    if (e) rows.push({ techId: t, countryCode: c, irr: e.irrEquity, lcoe: e.lcoeUsdMwh });
  }
  return rows;
}

export const fmtM = (v: number) => `${(v / 1e6).toFixed(2)} M`;
