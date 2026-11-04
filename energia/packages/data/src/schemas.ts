import { z } from 'zod';

/** Un valor numérico real debe declarar su fuente o su supuesto. */
export const sourced = z
  .object({ base: z.number(), min: z.number().optional(), max: z.number().optional(), fuente: z.string().optional(), supuesto: z.string().optional() })
  .refine((v) => v.fuente || v.supuesto, { message: 'Falta "fuente" o "supuesto"' })
  .refine((v) => (v.min === undefined || v.min <= v.base) && (v.max === undefined || v.max >= v.base), { message: 'Debe cumplirse min ≤ base ≤ max' });

export const gameSchema = z.object({
  nombre: z.string().min(1),
  version_datos: z.number().int().positive(),
  fecha_inicio: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  pais_inicial: z.string().length(3),
  moneda_contable: z.literal('USD'),
  empresa_inicial: z.object({
    caja_usd: z.number().positive(),
    gastos_fijos_mensuales_usd: z.number().nonnegative(),
    supuesto: z.string().min(1),
  }),
  velocidades: z.array(z.object({ id: z.string(), etiqueta: z.string(), dias_por_segundo: z.number().positive() })).min(1),
  autoguardado: z.object({ cada_meses: z.number().int().positive(), min_segundos_reales: z.number().nonnegative(), ranuras: z.number().int().positive() }),
});

export const layerSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  unidad: z.string(),
  aplica: z.enum(['tierra', 'mar']),
  rango: z.tuple([z.number(), z.number()]),
  rampa: z.array(z.string().regex(/^#[0-9a-fA-F]{6}$/)).min(2),
  tecnologias: z.array(z.string()),
});

const hasSource = (v: { fuente?: string; supuesto?: string }) => !!(v.fuente || v.supuesto);
const srcMsg = { message: 'Falta "fuente" o "supuesto"' };
const src = { fuente: z.string().optional(), supuesto: z.string().optional() };
const prob01 = z.number().min(0).max(1);
const month12 = z.array(z.number().positive()).length(12);
const applicability = z.object({ tecnologias: z.array(z.string()).optional(), mw_min: z.number().optional(), mw_max: z.number().optional() });
const sumsToOne = (keys: string[]) => (v: Record<string, unknown>) => Math.abs(keys.reduce((a, k) => a + (v[k] as number), 0) - 1) < 1e-6;

export const permitSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  grupo: z.string(),
  autoridad: z.string(),
  descripcion: z.string(),
  aplica: applicability,
  requiere: z.object({ estudios: z.array(z.string()), permisos: z.array(z.string()) }),
  costo_fijo_usd: sourced,
  costo_usd_mw: sourced,
  duracion_dias: sourced,
  prob: z.object({ aprobado: prob01, rechazado: prob01, info_adicional: prob01, ...src })
    .refine(hasSource, srcMsg)
    .refine(sumsToOne(['aprobado', 'rechazado', 'info_adicional']), { message: 'Las probabilidades deben sumar 1' }),
  info_adicional: z.object({ retraso_dias: sourced, costo_usd: sourced }),
  reintentable: z.boolean(),
  max_intentos_info: z.number().int().nonnegative(),
  fuente: z.string().optional(),
});

export const ppaChannelSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  descripcion: z.string(),
  precio_usd_mwh: sourced,
  plazo_anos: z.number().int().positive(),
  indexacion_anual: z.number(),
  duracion_dias: sourced,
  prob_exito: prob01,
  costo_usd: sourced,
  mw_min: z.number().nonnegative(),
  mw_max: z.number().positive(),
  requiere_permisos: z.array(z.string()),
  plazo_cod_meses: z.number().int().positive(),
  multa_usd_mw_mes: z.number().nonnegative(),
});

export const lenderSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  tipo: z.enum(['comercial', 'desarrollo']),
  descripcion: z.string(),
  spread: sourced,
  plazo_anos: z.number().int().positive(),
  dscr_ppa: z.number().min(1),
  dscr_merchant: z.number().min(1),
  apalancamiento_max: prob01,
  comision_estructuracion: prob01,
  costo_asesores_usd: sourced,
  diligencia_dias: sourced,
  prob_aprobacion: prob01,
  requiere_ppa: z.boolean(),
  sigma_recurso_max: z.number().positive(),
  monto_min_usd: z.number().nonnegative(),
});

export const countrySchema = z.object({
  iso3: z.string().length(3),
  nombre: z.string(),
  iso_num: z.number().int(),
  moneda: z.object({ codigo: z.string(), nombre: z.string(), usd_por_unidad: z.number().positive() }),
  tipo_cambio: z.object({ deriva_anual: z.number(), volatilidad_anual: z.number().nonnegative(), ...src }).refine(hasSource, srcMsg),
  inflacion_anual: sourced,
  prima_riesgo_pais: sourced,
  regulador: z.string(),
  operador_sistema: z.string(),
  mercado: z.object({
    demanda_anual_twh: sourced,
    pico_mw: sourced,
    precio_spot_medio_usd_mwh: sourced,
    perfil_spot_mensual: month12,
    perfil_spot_fuente: z.string().min(1),
    matriz: z.record(z.union([z.number(), z.string()])),
  }),
  perfil_recurso_mensual: z.record(month12),
  perfil_recurso_fuente: z.string().min(1),
  impuestos: z.object({ renta: sourced, depreciacion_anos: sourced, itbms: sourced, arancel_general_equipos: sourced }),
  incentivos: z.record(z.object({
    descripcion: z.string(),
    arancel_exento: z.boolean(),
    itbms_exento: z.boolean(),
    credito_fiscal_frac_inversion: sourced,
    credito_max_frac_impuesto: prob01,
  })),
  costos: z.object({
    factor_construccion_local: sourced,
    prospeccion_usd: sourced,
    opcion_terreno_usd_ha_ano: sourced,
    arriendo_terreno_usd_ha_ano: sourced,
    seguro_frac_capex_ano: sourced,
  }),
  finanzas: z.object({
    tasa_libre_riesgo: sourced,
    prima_mercado_acciones: sourced,
    beta_renovables: z.number().positive(),
    prima_etapa: z.record(z.number()),
    prima_tecnologia: z.record(z.number()),
    prima_fuente: z.string().min(1),
    prestamistas: z.array(lenderSchema).min(1),
    socio_equity: z.object({ participacion_max: prob01, prima_desarrollo_frac: z.number().nonnegative(), ...src }).refine(hasSource, srcMsg),
    credito_emergencia: z.object({ tasa: z.number().nonnegative(), frac_valor_activos: prob01, ...src }).refine(hasSource, srcMsg),
  }),
  construccion: z.object({
    meses_lluviosos: z.array(z.number().int().min(1).max(12)),
    factor_avance_lluvia: z.number().positive().max(1),
    huelga_prob_mensual: prob01,
    huelga_duracion_dias: sourced,
    clima_extremo_prob_mensual: prob01,
    clima_extremo_dias: sourced,
    ...src,
  }).refine(hasSource, srcMsg),
  quiebra: z.object({ meses_caja_negativa: z.number().int().positive() }),
  permisos: z.array(permitSchema).min(1),
  ppa: z.object({ canales: z.array(ppaChannelSchema).min(1) }),
  notas: z.string().optional(),
});

const milestoneSchema = z.object({
  id: z.string(), nombre: z.string(), fraccion: z.number().positive().max(1),
  requiere_equipos: z.boolean().optional(), sensible_lluvia: z.boolean().optional(),
});

export const technologySchema = z.object({
  id: z.string(),
  nombre: z.string(),
  categoria: z.string(),
  recurso: z.string().optional(),
  modelo_fc: z.enum(['solar_fv', 'eolica', 'fijo']),
  capex_usd_kw: sourced,
  desglose_capex: z.object({ equipos: prob01, epc: prob01, otros: prob01, ...src })
    .refine(hasSource, srcMsg)
    .refine(sumsToOne(['equipos', 'epc', 'otros']), { message: 'El desglose del CAPEX debe sumar 1' }),
  om_fijo_usd_kw_ano: sourced,
  om_variable_usd_mwh: sourced,
  factor_capacidad_ref: sourced,
  vida_util_anos: sourced,
  degradacion_anual: sourced,
  construccion_meses: sourced,
  puesta_en_marcha_dias: sourced,
  emisiones_gco2_kwh: sourced,
  uso_suelo_ha_mw: sourced,
  escala_mw: z.object({ min: z.number().positive(), max: z.number().positive(), tipico: z.number().positive() }),
  sigma_recurso_sitio: z.number().positive().max(0.5),
  variabilidad: z.object({ diaria: z.number().nonnegative(), interanual: z.number().nonnegative(), ...src }).refine(hasSource, srcMsg),
  fallas: z.object({ eventos_ano_por_mw: sourced, fraccion_afectada: sourced, duracion_dias: sourced, costo_reparacion_usd_kw: sourced }),
  mantenimiento: z.object({
    programado_perdida: prob01, preventivo_om_factor: z.number().positive(), preventivo_fallas_factor: z.number().positive(),
    correctivo_om_factor: z.number().positive(), ...src,
  }).refine(hasSource, srcMsg),
  costo_desmantelamiento_frac_capex: sourced,
  estudios_requeridos: z.array(z.string()),
  hitos_construccion: z.array(milestoneSchema).min(1)
    .refine((ms) => Math.abs(ms.reduce((a, m) => a + m.fraccion, 0) - 1) < 1e-6, { message: 'Las fracciones de los hitos deben sumar 1' }),
  riesgos: z.array(z.object({ id: z.string(), nombre: z.string(), descripcion: z.string() })),
  solar: z.object({
    pr: prob01, coef_temp_por_c: z.number(), t_ref_c: z.number(), delta_celda_c: z.number(), ganancia_seguidor: z.number().positive(), ...src,
  }).refine(hasSource, srcMsg).optional(),
  eolica: z.object({
    turbina_mw: z.number().positive(), diametro_rotor_m: z.number().positive(), altura_buje_m: z.number().positive(), cp: prob01,
    v_arranque: z.number().nonnegative(), v_corte: z.number().positive(), weibull_k: z.number().positive(), perdidas: prob01,
    cizalle_alfa: z.number(), ...src,
  }).refine(hasSource, srcMsg).optional(),
  // Fase 4 (opcionales): térmicas y almacenamiento.
  combustible: z.object({ tipo: z.string(), heat_rate_btu_kwh: sourced, precio_usd_mmbtu: sourced.optional() }).optional(),
  almacenamiento: z.object({ eficiencia_ida_vuelta: sourced, horas: sourced, ciclos_vida: sourced.optional() }).optional(),
}).refine((t) => t.modelo_fc !== 'solar_fv' || t.solar, { message: 'modelo_fc solar_fv exige el bloque "solar"' })
  .refine((t) => t.modelo_fc !== 'eolica' || t.eolica, { message: 'modelo_fc eolica exige el bloque "eolica"' });

export const findingSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  descripcion: z.string(),
  peso: z.number().positive(),
  mitigable: z.boolean(),
  costo_mitigacion_fijo_usd: z.number().nonnegative().optional(),
  costo_mitigacion_usd_mw: z.number().nonnegative().optional(),
  retraso_dias: sourced.optional(),
  prob_exito_mitigacion: prob01.optional(),
});

export const studySchema = z.object({
  id: z.string(),
  nombre: z.string(),
  grupo: z.string(),
  descripcion: z.string(),
  aplica: applicability,
  requiere: z.array(z.string()),
  costo_fijo_usd: sourced,
  costo_usd_mw: sourced,
  duracion_dias: sourced,
  sigma_recurso: z.number().positive().optional(),
  resultados: z.object({ normal: prob01, peor: prob01, bloqueo: prob01, ...src })
    .refine(hasSource, srcMsg)
    .refine(sumsToOne(['normal', 'peor', 'bloqueo']), { message: 'Las probabilidades deben sumar 1' }),
  peor_capex_factor: sourced.optional(),
  peor_descripcion: z.string().optional(),
  hallazgos: z.array(z.string()).optional(),
});

export const studiesFileSchema = z.object({ estudios: z.array(studySchema).min(1), hallazgos: z.array(findingSchema) });

export const supplierSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  tipo: z.enum(['equipos', 'epc']),
  tecnologias: z.array(z.string()).min(1),
  origen: z.string().length(3),
  descripcion: z.string(),
  factor_precio: z.number().positive(),
  calidad: prob01,
  confiabilidad: prob01,
  plazo_entrega_dias: sourced.optional(),
  factor_plazo: z.number().positive().optional(),
  flete_frac: z.number().nonnegative().optional(),
  prob_sobrecosto_hito: prob01.optional(),
}).refine((s) => s.tipo !== 'equipos' || s.plazo_entrega_dias, { message: 'Un proveedor de equipos necesita plazo_entrega_dias' })
  .refine((s) => s.tipo !== 'epc' || (s.factor_plazo && s.prob_sobrecosto_hito !== undefined), { message: 'Un EPC necesita factor_plazo y prob_sobrecosto_hito' });

export const suppliersFileSchema = z.object({ fuente_general: z.string().min(1), proveedores: z.array(supplierSchema).min(1) });

const anchorLand = z.tuple([z.string(), z.number(), z.number(), z.number().nullable(), z.number().nullable(), z.number().nullable()]).rest(z.number());
export const anchorsSchema = z.object({
  radio_defecto_km: z.number().positive(),
  tierra: z.array(anchorLand),
  mar: z.array(z.tuple([z.string(), z.number(), z.number(), z.number()]).rest(z.number())),
  geotermia: z.array(z.tuple([z.string(), z.number(), z.number(), z.number(), z.number()])),
});

export type GameYaml = z.infer<typeof gameSchema>;
export type LayerDef = z.infer<typeof layerSchema>;
export type CountryDef = z.infer<typeof countrySchema>;
export type TechnologyYaml = z.infer<typeof technologySchema>;
export type StudyYaml = z.infer<typeof studySchema>;
export type SupplierYaml = z.infer<typeof supplierSchema>;
