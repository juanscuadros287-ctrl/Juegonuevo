import { z } from 'zod';
import type { SimConfig, SimData, CountrySimDef, TechnologyDef, StudyDef, SupplierDef, FindingDef, SupplyDef, ResearchDef, ClientsDef, CompetitorsDef, MarketsDef, PowerDef, WorldDef, TeamDef } from '@voltaje/sim';
import {
  countrySchema, gameSchema, layerSchema, studiesFileSchema, suppliersFileSchema, technologySchema, researchFileSchema, clientsFileSchema, competitorsFileSchema, marketsFileSchema, powerFileSchema, eventsFileSchema, teamFileSchema,
  type CountryDef, type GameYaml, type LayerDef,
} from './schemas';

export interface GameData {
  game: GameYaml;
  layers: LayerDef[];
  countries: Record<string, CountryDef>;
  sim: SimConfig;
  /** Datos que el motor recibe en `SimContext.data`. */
  simData: SimData;
}

export class DataError extends Error {}

function check<T>(schema: z.ZodType<T, z.ZodTypeDef, unknown>, value: unknown, file: string): T {
  const r = schema.safeParse(value);
  if (!r.success) {
    const issues = r.error.issues.map((i) => `  · ${i.path.join('.') || '(raíz)'}: ${i.message}`).join('\n');
    throw new DataError(`Error en ${file}:\n${issues}`);
  }
  return r.data;
}

export interface RawGameData {
  game: unknown;
  layers: unknown;
  countries: Record<string, unknown>;
  technologies?: Record<string, unknown>;
  studies?: unknown;
  suppliers?: unknown;
  /** Fase 3 */
  research?: unknown;
  clients?: unknown;
  competitors?: unknown;
  /** Fase 4 */
  markets?: unknown;
  /** Fase 5 */
  power?: unknown;
  events?: unknown;
  /** Fase 6 */
  team?: unknown;
}

function byId<T extends { id: string }>(items: T[], file: string): Record<string, T> {
  const out: Record<string, T> = {};
  for (const it of items) {
    if (out[it.id]) throw new DataError(`Error en ${file}: id duplicado "${it.id}"`);
    out[it.id] = it;
  }
  return out;
}

/** Valida los datos crudos (ya parseados de YAML) y arma la configuración del motor. */
export function buildGameData(raw: RawGameData): GameData {
  const game = check(gameSchema, raw.game, 'game.yaml');
  const layers = check(z.array(layerSchema), raw.layers, 'layers.yaml');
  const countries: Record<string, CountryDef> = {};
  for (const [file, value] of Object.entries(raw.countries)) {
    const c = check(countrySchema, value, file);
    countries[c.iso3] = c;
  }
  if (!countries[game.pais_inicial]) throw new DataError(`game.yaml: el país inicial ${game.pais_inicial} no tiene archivo en countries/`);

  const technologies: Record<string, TechnologyDef> = {};
  for (const [file, value] of Object.entries(raw.technologies ?? {})) {
    const t: TechnologyDef = check(technologySchema, value, file);
    technologies[t.id] = t;
  }
  let studies: Record<string, StudyDef> = {};
  let findings: Record<string, FindingDef> = {};
  if (raw.studies !== undefined) {
    const s = check(studiesFileSchema, raw.studies, 'studies.yaml');
    studies = byId<StudyDef>(s.estudios, 'studies.yaml');
    findings = byId<FindingDef>(s.hallazgos, 'studies.yaml');
  }
  let suppliers: Record<string, SupplierDef> = {};
  let supply: SupplyDef | undefined;
  if (raw.suppliers !== undefined) {
    const f = check(suppliersFileSchema, raw.suppliers, 'suppliers.yaml');
    suppliers = byId<SupplierDef>(f.proveedores, 'suppliers.yaml');
    if (f.materiales && f.curvas_aprendizaje && f.demanda_global && f.cola && f.relacion) {
      supply = { materiales: f.materiales, curvas_aprendizaje: f.curvas_aprendizaje, demanda_global: f.demanda_global, cola: f.cola, relacion: f.relacion };
    } else if (f.materiales || f.curvas_aprendizaje || f.demanda_global || f.cola || f.relacion) {
      throw new DataError('Error en suppliers.yaml: la dinámica de precios exige materiales, curvas_aprendizaje, demanda_global, cola y relacion juntos.');
    }
  }
  const research: ResearchDef | undefined = raw.research !== undefined ? check(researchFileSchema, raw.research, 'research.yaml') : undefined;
  const clients: ClientsDef | undefined = raw.clients !== undefined ? check(clientsFileSchema, raw.clients, 'clients.yaml') : undefined;
  const competitors: CompetitorsDef | undefined = raw.competitors !== undefined ? check(competitorsFileSchema, raw.competitors, 'competitors.yaml') : undefined;

  const markets: MarketsDef | undefined = raw.markets !== undefined ? check(marketsFileSchema, raw.markets, 'markets.yaml') : undefined;

  const power: PowerDef | undefined = raw.power !== undefined ? check(powerFileSchema, raw.power, 'power.yaml') as unknown as PowerDef : undefined;
  const world: WorldDef | undefined = raw.events !== undefined ? check(eventsFileSchema, raw.events, 'events.yaml') as unknown as WorldDef : undefined;

  const team: TeamDef | undefined = raw.team !== undefined ? check(teamFileSchema, raw.team, 'team.yaml') as unknown as TeamDef : undefined;

  const simCountries: Record<string, CountrySimDef> = {};
  for (const c of Object.values(countries)) {
    // Inflación de los precios en USD: la local si la moneda está fija al USD; si no, la del USD (paridad de poder de compra).
    const pegged = c.tipo_cambio.volatilidad_anual === 0 && c.tipo_cambio.deriva_anual === 0 && !c.tipo_cambio.shock_prob_anual;
    simCountries[c.iso3] = { ...c, inflacion_usd_anual: pegged ? c.inflacion_anual.base : markets?.inflacion_usd.base ?? 0.025 };
  }

  const simData: SimData = { technologies, studies, findings, suppliers, countries: simCountries, supply, research, clients, competitors, markets, power, world, team };
  checkReferences(simData);

  return {
    game,
    layers,
    countries,
    simData,
    sim: {
      dataVersion: game.version_datos,
      startDate: game.fecha_inicio,
      startCountry: game.pais_inicial,
      company: { cashUsd: game.empresa_inicial.caja_usd, monthlyFixedCostUsd: game.empresa_inicial.gastos_fijos_mensuales_usd },
    },
  };
}

/** Comprueba que las referencias cruzadas entre archivos existan (grupos, hallazgos, tecnologías). */
export function checkReferences(d: SimData) {
  const studyGroups = new Set(Object.values(d.studies).map((s) => s.grupo));
  const techIds = new Set(Object.keys(d.technologies));
  const fail = (msg: string) => { throw new DataError(msg); };
  for (const t of Object.values(d.technologies)) {
    for (const g of t.estudios_requeridos) if (!studyGroups.has(g)) fail(`technologies/${t.id}: estudio requerido "${g}" no existe como grupo en studies.yaml`);
  }
  for (const s of Object.values(d.studies)) {
    for (const g of s.requiere) if (!studyGroups.has(g)) fail(`studies.yaml/${s.id}: requiere grupo inexistente "${g}"`);
    for (const h of s.hallazgos ?? []) if (!d.findings[h]) fail(`studies.yaml/${s.id}: hallazgo inexistente "${h}"`);
    for (const t of s.aplica.tecnologias ?? []) if (techIds.size && !techIds.has(t)) fail(`studies.yaml/${s.id}: tecnología inexistente "${t}"`);
  }
  for (const s of Object.values(d.suppliers)) {
    for (const t of s.tecnologias) if (techIds.size && !techIds.has(t)) fail(`suppliers.yaml/${s.id}: tecnología inexistente "${t}"`);
  }
  for (const c of Object.values(d.countries)) {
    const permitGroups = new Set(c.permisos.map((p) => p.grupo));
    for (const p of c.permisos) {
      for (const g of p.requiere.estudios) if (!studyGroups.has(g) && Object.keys(d.studies).length) fail(`countries/${c.iso3}: permiso ${p.id} requiere estudio inexistente "${g}"`);
      for (const g of p.requiere.permisos) if (!permitGroups.has(g)) fail(`countries/${c.iso3}: permiso ${p.id} requiere permiso inexistente "${g}"`);
    }
    for (const ch of c.ppa.canales) for (const g of ch.requiere_permisos) if (!permitGroups.has(g)) fail(`countries/${c.iso3}: PPA ${ch.id} requiere permiso inexistente "${g}"`);
  }
  checkPhase3References(d);
  checkPhase4References(d);
  checkPhase5References(d);
  checkPhase6References(d);
}

/** Referencias de la Fase 6: roles de los equipos iniciales y objetivos, países del mercado laboral, idiomas con nombres, regiones. */
export function checkPhase6References(d: SimData) {
  const t = d.team;
  if (!t) return;
  const fail = (msg: string) => { throw new DataError(msg); };
  const roles = new Set(t.roles.map((r) => r.id));
  if (roles.size !== t.roles.length) fail('team.yaml: roles duplicados');
  for (const r of t.roles) if (!Object.values(r.areas).some((w) => (w ?? 0) > 0)) fail(`team.yaml/roles.${r.id}: sin áreas`);
  const seeds = [...t.equipo_inicial_jugador, ...Object.values(t.ia.equipo_inicial).flat()];
  for (const s of seeds) if (!roles.has(s!.rol)) fail(`team.yaml: equipo inicial con rol inexistente "${s!.rol}"`);
  for (const [k, o] of Object.entries(t.ia.objetivos)) for (const r of o!.roles) if (!roles.has(r)) fail(`team.yaml/ia.objetivos.${k}: rol inexistente "${r}"`);
  for (const r of t.roles_locales) if (!roles.has(r)) fail(`team.yaml/roles_locales: rol inexistente "${r}"`);
  for (const iso of Object.keys(d.countries)) if (!t.paises[iso]) fail(`team.yaml: falta el mercado laboral de ${iso}`);
  for (const [iso, c] of Object.entries(t.paises)) {
    if (!d.countries[iso] && Object.keys(d.countries).length > 1) fail(`team.yaml/paises: país inexistente "${iso}"`);
    if (!t.nombres[c.idioma]) fail(`team.yaml/paises.${iso}: sin nombres para el idioma "${c.idioma}"`);
  }
  for (const [r, list] of Object.entries(t.oficinas.regiones)) for (const iso of list) if (!d.countries[iso] && Object.keys(d.countries).length > 1) fail(`team.yaml/regiones.${r}: país inexistente "${iso}"`);
  const ids = t.oficinas.niveles.map((l) => l.id).join(',');
  if (ids !== 'representante,oficina,sede') fail('team.yaml/oficinas.niveles: deben ser representante, oficina y sede en ese orden');
  const ext = t.puntaje_externo.base;
  if (!(ext >= 0 && ext < 100)) fail('team.yaml: puntaje_externo fuera de rango');
  for (const [id, e] of Object.entries(t.efectos)) if (id !== 'ofertas_puntaje' && e.base > 1) fail(`team.yaml/efectos.${id}: debe ser ≤ 1 (fracción)`);
}

/** Tipos de modelo 3D (PlantKind de apps/game/src/models/types.ts). */
export const PLANT_KINDS_VISUAL = ['solar_fv', 'csp', 'eolica_tierra', 'eolica_mar', 'geotermica', 'hidro_pasada', 'hidro_embalse', 'hidro_bombeo',
  'biomasa', 'biogas', 'nuclear', 'smr', 'gas', 'carbon', 'petroleo', 'baterias', 'hidrogeno', 'subestacion', 'linea_transmision', 'eficiencia_industrial'];

/** Referencias de la Fase 4: combustibles, modelos 3D, países de expansión, permisos por tecnología, hallazgos de pozos. */
export function checkPhase4References(d: SimData) {
  const fail = (msg: string) => { throw new DataError(msg); };
  const fuels = new Set((d.markets?.combustibles ?? []).map((f) => f.id));
  for (const t of Object.values(d.technologies)) {
    if (t.visual && !PLANT_KINDS_VISUAL.includes(t.visual)) fail(`technologies/${t.id}: modelo 3D desconocido "${t.visual}"`);
    if (t.combustible && d.markets && !fuels.has(t.combustible.tipo)) fail(`technologies/${t.id}: combustible "${t.combustible.tipo}" sin índice en markets.yaml`);
  }
  for (const c of Object.values(d.countries)) {
    for (const [tipo, m] of Object.entries(c.combustibles ?? {})) if (d.markets && !fuels.has(m.indice)) fail(`countries/${c.iso3}: combustible ${tipo} usa índice inexistente "${m.indice}"`);
    for (const t of c.restricciones?.tecnologias_prohibidas ?? []) if (!d.technologies[t]) fail(`countries/${c.iso3}: tecnología prohibida inexistente "${t}"`);
    for (const p of c.permisos) for (const t of p.aplica.tecnologias ?? []) if (Object.keys(d.technologies).length && !d.technologies[t]) fail(`countries/${c.iso3}: permiso ${p.id} aplica a tecnología inexistente "${t}"`);
    if (!c.finanzas.prestamistas.some((l) => l.tipo === 'comercial')) fail(`countries/${c.iso3}: falta un prestamista comercial`);
  }
  for (const s of Object.values(d.studies)) if (s.hallazgo_pozos_secos && !d.findings[s.hallazgo_pozos_secos]) fail(`studies.yaml/${s.id}: hallazgo inexistente "${s.hallazgo_pozos_secos}"`);
  for (const c of d.competitors?.empresas ?? []) for (const iso of c.expansion?.paises ?? []) if (!d.countries[iso]) fail(`competitors.yaml/${c.id}: país de expansión sin datos "${iso}"`);
  for (const s of d.competitors?.sitios_candidatos ?? []) if (Object.keys(d.countries).length > 1 && !d.countries[s.pais]) fail(`competitors.yaml: sitio ${s.nombre} en país sin datos "${s.pais}"`);
}

/** Referencias de la Fase 3: árbol de I+D (sin ciclos), clientes, competidores y curvas de precios. */
export function checkPhase3References(d: SimData) {
  const fail = (msg: string) => { throw new DataError(msg); };
  const techIds = new Set(Object.keys(d.technologies));
  if (d.supply) {
    const mats = new Set(d.supply.materiales.map((m) => m.id));
    for (const c of d.supply.curvas_aprendizaje) {
      if (!techIds.has(c.tecnologia)) fail(`suppliers.yaml: curva de aprendizaje de tecnología inexistente "${c.tecnologia}"`);
      for (const m of Object.keys(c.exposicion)) if (!mats.has(m)) fail(`suppliers.yaml: curva ${c.tecnologia} usa material inexistente "${m}"`);
      if (Object.values(c.exposicion).reduce((a, b) => a + b, 0) > 1 + 1e-9) fail(`suppliers.yaml: la exposición a materiales de ${c.tecnologia} suma más de 1`);
    }
  }
  const nodes = new Map((d.research?.nodos ?? []).map((n) => [n.id, n]));
  if (d.research) {
    if (nodes.size !== d.research.nodos.length) fail('research.yaml: hay ids de nodo duplicados');
    for (const n of d.research.nodos) {
      for (const q of n.requiere) if (!nodes.has(q)) fail(`research.yaml/${n.id}: requiere nodo inexistente "${q}"`);
      const later = n.fase_modelo !== undefined;
      for (const t of n.efectos.tecnologias ?? []) if (!techIds.has(t) && !later) fail(`research.yaml/${n.id}: tecnología "${t}" sin modelo: marca fase_modelo`);
      for (const s of n.efectos.estudios ?? []) if (!d.studies[s] && !later) fail(`research.yaml/${n.id}: estudio inexistente "${s}"`);
      for (const c of n.efectos.paises ?? []) if (!d.countries[c] && !later) fail(`research.yaml/${n.id}: país "${c}" sin datos: marca fase_modelo`);
      for (const k of [...Object.keys(n.efectos.capex_frac ?? {}), ...Object.keys(n.efectos.om_frac ?? {}), ...Object.keys(n.efectos.fc_frac ?? {})]) if (k !== '*' && !techIds.has(k) && !later) fail(`research.yaml/${n.id}: efecto sobre tecnología inexistente "${k}"`);
    }
    // Sin ciclos
    const state = new Map<string, number>();
    const visit = (id: string, path: string[]) => {
      if (state.get(id) === 2) return;
      if (state.get(id) === 1) fail(`research.yaml: ciclo de prerrequisitos ${[...path, id].join(' → ')}`);
      state.set(id, 1);
      for (const q of nodes.get(id)!.requiere) visit(q, [...path, id]);
      state.set(id, 2);
    };
    for (const id of nodes.keys()) visit(id, []);
  }
  const contractTypes = new Set((d.research?.nodos ?? []).flatMap((n) => n.efectos.contratos ?? []));
  for (const t of d.clients?.tipos ?? []) {
    if (d.research && !contractTypes.has(t.tipo_contrato)) fail(`clients.yaml/${t.id}: tipo de contrato "${t.tipo_contrato}" que ningún nodo de I+D habilita`);
    if (!t.tecnologias.some((x) => techIds.has(x)) && t.contrato !== 'potencia') fail(`clients.yaml/${t.id}: ninguna tecnología admitida tiene modelo`);
  }
  for (const c of d.competitors?.empresas ?? []) {
    for (const t of c.tecnologias) if (!techIds.has(t)) fail(`competitors.yaml/${c.id}: tecnología inexistente "${t}"`);
    for (const n of c.investigacion.prioridades) if (d.research && !nodes.has(n)) fail(`competitors.yaml/${c.id}: prioridad de I+D inexistente "${n}"`);
    if (c.mw.min > c.mw.max) fail(`competitors.yaml/${c.id}: mw.min > mw.max`);
  }
  for (const s of d.competitors?.sitios_candidatos ?? []) if (!techIds.has(s.tecnologia)) fail(`competitors.yaml: sitio ${s.nombre} con tecnología inexistente "${s.tecnologia}"`);
}

/** Referencias de la Fase 5: cada país tiene mercado eléctrico, formas de demanda y clases existentes; eventos con países y amenazas válidos. */
export function checkPhase5References(d: SimData) {
  const fail = (msg: string) => { throw new DataError(msg); };
  const p = d.power;
  if (p) {
    for (const iso of Object.keys(d.countries)) if (!p.paises[iso]) fail(`power.yaml: falta el mercado eléctrico de ${iso}`);
    for (const [iso, c] of Object.entries(p.paises)) {
      if (!d.countries[iso]) fail(`power.yaml: país inexistente "${iso}"`);
      if (!p.formas_demanda[c.forma_demanda]) fail(`power.yaml/${iso}: forma de demanda inexistente "${c.forma_demanda}"`);
      for (const k of [...Object.keys(c.mezcla_termica ?? {}), ...Object.keys(c.mezcla_otros ?? {}), ...Object.keys(c.parque_mw ?? {})]) if (!p.clases[k]) fail(`power.yaml/${iso}: clase inexistente "${k}"`);
    }
    for (const [id, k] of Object.entries(p.clases)) for (const t of k.tecnologias) if (Object.keys(d.technologies).length && !d.technologies[t]) fail(`power.yaml/clases.${id}: tecnología inexistente "${t}"`);
    for (const t of Object.keys(p.credito_firme_tecnologia)) if (Object.keys(d.technologies).length && !d.technologies[t]) fail(`power.yaml/credito_firme_tecnologia: tecnología inexistente "${t}"`);
  }
  const w = d.world;
  if (w) {
    const fuels = new Set((d.markets?.combustibles ?? []).map((f) => f.id));
    const ids = new Set<string>();
    for (const e of w.eventos) {
      if (ids.has(e.id)) fail(`events.yaml: id duplicado "${e.id}"`);
      ids.add(e.id);
      for (const iso of e.paises ?? []) if (!d.countries[iso]) fail(`events.yaml/${e.id}: país inexistente "${iso}"`);
      for (const f of Object.keys(e.efectos.combustibles ?? {})) if (fuels.size && !fuels.has(f)) fail(`events.yaml/${e.id}: combustible inexistente "${f}"`);
      for (const t of [...Object.keys(e.efectos.capex ?? {}), ...Object.keys(e.efectos.costo_tecnologia ?? {})]) if (t !== 'todas' && Object.keys(d.technologies).length && !d.technologies[t]) fail(`events.yaml/${e.id}: tecnología inexistente "${t}"`);
      if (e.amenaza && p && !Object.values(p.paises).some((c) => c.riesgos?.[e.amenaza!] !== undefined)) fail(`events.yaml/${e.id}: ningún país tiene la amenaza "${e.amenaza}"`);
    }
    const sum = w.gobiernos.reduce((a, g) => a + g.prob, 0);
    if (Math.abs(sum - 1) > 1e-6) fail('events.yaml: las probabilidades de los gobiernos deben sumar 1');
  }
}
