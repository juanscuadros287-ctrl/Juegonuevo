import { z } from 'zod';
import type { SimConfig, SimData, CountrySimDef, TechnologyDef, StudyDef, SupplierDef, FindingDef, SupplyDef, ResearchDef, ClientsDef, CompetitorsDef } from '@voltaje/sim';
import {
  countrySchema, gameSchema, layerSchema, studiesFileSchema, suppliersFileSchema, technologySchema, researchFileSchema, clientsFileSchema, competitorsFileSchema,
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

  const simCountries: Record<string, CountrySimDef> = {};
  for (const c of Object.values(countries)) simCountries[c.iso3] = c;

  const simData: SimData = { technologies, studies, findings, suppliers, countries: simCountries, supply, research, clients, competitors };
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
