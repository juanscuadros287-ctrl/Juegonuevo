import { z } from 'zod';
import type { SimConfig, SimData, CountrySimDef, TechnologyDef, StudyDef, SupplierDef, FindingDef } from '@voltaje/sim';
import {
  countrySchema, gameSchema, layerSchema, studiesFileSchema, suppliersFileSchema, technologySchema,
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
  if (raw.suppliers !== undefined) suppliers = byId<SupplierDef>(check(suppliersFileSchema, raw.suppliers, 'suppliers.yaml').proveedores, 'suppliers.yaml');

  const simCountries: Record<string, CountrySimDef> = {};
  for (const c of Object.values(countries)) simCountries[c.iso3] = c;

  const simData: SimData = { technologies, studies, findings, suppliers, countries: simCountries };
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
}
