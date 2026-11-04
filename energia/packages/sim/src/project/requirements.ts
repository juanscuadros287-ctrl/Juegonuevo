import type { SimContext } from '../core/context';
import type { Applicability, PermitDef, StudyDef } from '../data/types';
import type { Project } from './types';

export function applies(a: Applicability, techId: string, mw: number): boolean {
  if (a.tecnologias && !a.tecnologias.includes(techId)) return false;
  if (a.mw_min !== undefined && mw < a.mw_min) return false;
  if (a.mw_max !== undefined && mw >= a.mw_max) return false;
  return true;
}

type ProjLike = Pick<Project, 'techId' | 'mw' | 'countryCode'>;

export function applicableStudies(ctx: SimContext, p: ProjLike): StudyDef[] {
  return Object.values(ctx.data.studies).filter((s) => applies(s.aplica, p.techId, p.mw));
}

/** Grupos de estudio exigidos por la tecnología que tienen al menos un estudio aplicable. */
export function requiredStudyGroups(ctx: SimContext, p: ProjLike): string[] {
  const tech = ctx.data.technologies[p.techId];
  const groups = new Set(applicableStudies(ctx, p).map((s) => s.grupo));
  return tech.estudios_requeridos.filter((g) => groups.has(g));
}

export function studyGroupDone(ctx: SimContext, p: Project, group: string): boolean {
  return Object.values(p.studies).some((r) => r.status === 'completado' && ctx.data.studies[r.studyId]?.grupo === group);
}

export function studyGroupApplicable(ctx: SimContext, p: ProjLike, group: string): boolean {
  return applicableStudies(ctx, p).some((s) => s.grupo === group);
}

export function applicablePermits(ctx: SimContext, p: ProjLike): PermitDef[] {
  const c = ctx.data.countries[p.countryCode];
  return c ? c.permisos.filter((x) => applies(x.aplica, p.techId, p.mw)) : [];
}

export function permitGroupApplicable(ctx: SimContext, p: ProjLike, group: string): boolean {
  return applicablePermits(ctx, p).some((x) => x.grupo === group);
}

export function permitGroupApproved(ctx: SimContext, p: Project, group: string): boolean {
  const c = ctx.data.countries[p.countryCode];
  return Object.values(p.permits).some((r) => r.status === 'aprobado' && c?.permisos.find((x) => x.id === r.permitId)?.grupo === group);
}

export function openFindings(p: Project) {
  return p.findings.filter((f) => f.status === 'abierto' || f.status === 'en_mitigacion' || f.status === 'fatal');
}

/** Faltantes para encargar un estudio (vacío = se puede). */
export function studyBlockers(ctx: SimContext, p: Project, studyId: string): string[] {
  const s = ctx.data.studies[studyId];
  if (!s) return ['Estudio desconocido.'];
  const out: string[] = [];
  if (!applies(s.aplica, p.techId, p.mw)) out.push('Este estudio no aplica a este proyecto.');
  const rec = p.studies[studyId];
  if (rec?.status === 'en_curso') out.push('El estudio ya está en curso.');
  if (rec?.status === 'completado') out.push('El estudio ya se hizo.');
  for (const g of s.requiere) if (studyGroupApplicable(ctx, p, g) && !studyGroupDone(ctx, p, g)) out.push(`Requiere completar antes: ${groupName(ctx, g)}.`);
  return out;
}

export function groupName(ctx: SimContext, group: string): string {
  const s = Object.values(ctx.data.studies).find((x) => x.grupo === group);
  return s ? s.nombre.replace(/ \(.*\)$/, '') : group;
}

/** Faltantes para solicitar un permiso (vacío = se puede). */
export function permitBlockers(ctx: SimContext, p: Project, permitId: string): string[] {
  const c = ctx.data.countries[p.countryCode];
  const d = c?.permisos.find((x) => x.id === permitId);
  if (!d) return ['Permiso desconocido.'];
  const out: string[] = [];
  if (!applies(d.aplica, p.techId, p.mw)) out.push('Este permiso no aplica a este proyecto.');
  const rec = p.permits[permitId];
  if (rec && (rec.status === 'en_tramite' || rec.status === 'info_adicional')) out.push('El permiso ya está en trámite.');
  if (rec?.status === 'aprobado') out.push('El permiso ya está aprobado.');
  if (rec?.status === 'rechazado' && !d.reintentable) out.push('El permiso fue rechazado y no se puede volver a pedir.');
  for (const g of d.requiere.estudios) if (studyGroupApplicable(ctx, p, g) && !studyGroupDone(ctx, p, g)) out.push(`Requiere el estudio: ${groupName(ctx, g)}.`);
  for (const g of d.requiere.permisos) if (permitGroupApplicable(ctx, p, g) && !permitGroupApproved(ctx, p, g)) out.push(`Requiere el permiso: ${permitGroupName(ctx, p, g)}.`);
  if (openFindings(p).length) out.push('Hay hallazgos sin resolver.');
  return out;
}

export function permitGroupName(ctx: SimContext, p: ProjLike, group: string): string {
  const c = ctx.data.countries[p.countryCode];
  const d = c?.permisos.find((x) => x.grupo === group && applies(x.aplica, p.techId, p.mw)) ?? c?.permisos.find((x) => x.grupo === group);
  return d?.nombre ?? group;
}

/** Faltantes para el cierre financiero. */
export function financingBlockers(ctx: SimContext, p: Project): string[] {
  const out: string[] = [];
  for (const g of requiredStudyGroups(ctx, p)) if (!studyGroupDone(ctx, p, g)) out.push(`Falta el estudio: ${groupName(ctx, g)}.`);
  for (const d of applicablePermits(ctx, p)) if (!permitGroupApproved(ctx, p, d.grupo)) out.push(`Falta el permiso: ${d.nombre}.`);
  if (openFindings(p).length) out.push('Hay hallazgos sin resolver.');
  return [...new Set(out)];
}
