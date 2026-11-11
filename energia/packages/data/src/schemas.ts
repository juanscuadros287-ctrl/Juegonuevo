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
const applicability = z.object({ tecnologias: z.array(z.string()).optional(), mw_min: z.number().optional(), mw_max: z.number().optional(), excluye: z.array(z.string()).optional() });
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
  // Fase 4
  moneda: z.enum(['USD', 'local']).optional(),
  tecnologias: z.array(z.string()).optional(),
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
  tipo_cambio: z.object({
    deriva_anual: z.number(), volatilidad_anual: z.number().nonnegative(),
    // Fase 4: reversión del tipo de cambio real y shocks (devaluaciones).
    reversion_anual: z.number().min(0).max(1).optional(), shock_prob_anual: prob01.optional(), shock_magnitud: sourced.optional(), ...src,
  }).refine(hasSource, srcMsg),
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
    // Fase 4
    factor_punta: z.number().positive().optional(),
    factor_valle: z.number().positive().optional(),
    moneda_contratos: z.enum(['USD', 'local']).optional(),
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
    fraccion_costos_locales: prob01.optional(),
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
  // ───────── Fase 4 ─────────
  expansion: z.object({ constitucion_usd: sourced, dias: sourced, representante_mensual_usd: sourced }).optional(),
  combustibles: z.record(z.object({ indice: z.string(), factor: z.number().positive(), ...src }).refine(hasSource, srcMsg)).optional(),
  carbono: z.object({ precio_usd_tco2: sourced, crecimiento_anual: z.number().min(-0.2).max(0.3) }).optional(),
  zona: z.object({ nombre: z.string(), lat_min: z.number(), lat_max: z.number(), lon_min: z.number(), lon_max: z.number() }).optional(),
  restricciones: z.object({ tecnologias_prohibidas: z.array(z.string()), motivo: z.string(), ...src }).refine(hasSource, srcMsg).optional(),
  permisos_fuente: z.string().optional(),
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
  modelo_fc: z.enum(['solar_fv', 'eolica', 'fijo', 'geotermia', 'hidro', 'csp', 'termica', 'almacenamiento', 'hidrogeno', 'transmision', 'eficiencia']),
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
  fraccion_inversores: prob01.optional(),
  // Fase 4 (opcionales): térmicas, almacenamiento y modelos nuevos.
  combustible: z.object({ tipo: z.string(), heat_rate_btu_kwh: sourced, precio_usd_mmbtu: sourced.optional() }).optional(),
  almacenamiento: z.object({
    eficiencia_ida_vuelta: sourced, horas: sourced, ciclos_vida: sourced.optional(),
    ciclos_ano_max: z.number().positive().optional(), degradacion_por_ciclo: z.number().nonnegative().max(0.01).optional(),
  }).optional(),
  recurso_tipico: z.number().positive().optional(),
  visual: z.string().optional(),
  sitio: z.object({
    superficie: z.enum(['tierra', 'mar']), recurso_min: z.number().optional(), dist_costa_km_min: z.number().nonnegative().optional(),
    dist_costa_km_max: z.number().positive().optional(), profundidad_max_m: z.number().positive().optional(), profundidad_m_por_km: z.number().positive().optional(),
    flotante_desde_m: z.number().positive().optional(), flotante_capex_extra: z.number().nonnegative().optional(), capex_extra_por_km: z.number().nonnegative().optional(),
    km_ref: z.number().nonnegative().optional(), relieve_min: z.number().min(0).max(1).optional(), agua_indice_min: z.number().nonnegative().optional(),
    agua_dist_costa_km: z.number().nonnegative().optional(), ...src,
  }).refine(hasSource, srcMsg).optional(),
  geotermia: z.object({
    calidad_min_mw_m2: z.number(), calidad_max_mw_m2: z.number(), prob_seco_calidad0: prob01, prob_seco_calidad1: prob01,
    prob_baja_calidad0: prob01, prob_baja_calidad1: prob01, factor_seco_desarrollo: prob01, mw_pozo_calidad0: z.number().positive(),
    mw_pozo_calidad1: z.number().positive(), costo_pozo_usd: sourced, reinyectores_por_productor: z.number().nonnegative(), frac_capex_perforacion: prob01, ...src,
  }).refine(hasSource, srcMsg).refine((g) => g.calidad_max_mw_m2 > g.calidad_min_mw_m2, { message: 'calidad_max debe superar calidad_min' }).optional(),
  hidro: z.object({ fc_min: prob01, fc_max: prob01, exponente: z.number().positive(), regulacion: prob01, lluvia_ref_mm: z.number().positive(), ...src }).refine(hasSource, srcMsg).optional(),
  csp: z.object({ horas_almacenamiento: z.number().nonnegative(), sm_base: z.number().positive(), sm_por_hora: z.number().nonnegative(), eficiencia_relativa: prob01, fc_max: prob01, ...src }).refine(hasSource, srcMsg).optional(),
  termica: z.object({ fc_max: prob01, prima_captura: z.number().positive(), despacho: z.enum(['base', 'media', 'punta']), ...src }).refine(hasSource, srcMsg).optional(),
  hidrogeno: z.object({ kwh_por_kg: sourced, precio_venta_usd_kg: sourced, utilizacion: prob01, agua_usd_kg: z.number().nonnegative(), factor_precio_electricidad: z.number().positive(), ...src }).refine(hasSource, srcMsg).optional(),
  transmision: z.object({
    costo_usd_mw_km: sourced, perdidas_frac_100km: prob01, peaje_usd_mwh: sourced, utilizacion: prob01, interconexion: z.boolean(),
    longitud_min_km: z.number().nonnegative(), longitud_max_km: z.number().positive(), captura_diferencial: prob01, ...src,
  }).refine(hasSource, srcMsg).optional(),
  eficiencia: z.object({ precio_ahorro_usd_mwh: sourced, ahorro_garantizado_frac: prob01, factor_carga: prob01, ...src }).refine(hasSource, srcMsg).optional(),
  riesgo_obra: z.object({ sobrecosto_prob_factor: z.number().positive(), sobrecosto_magnitud_factor: z.number().positive(), retraso_prob_mensual: prob01, retraso_dias: sourced, ...src }).refine(hasSource, srcMsg).optional(),
}).refine((t) => t.modelo_fc !== 'solar_fv' || t.solar, { message: 'modelo_fc solar_fv exige el bloque "solar"' })
  .refine((t) => t.modelo_fc !== 'eolica' || t.eolica, { message: 'modelo_fc eolica exige el bloque "eolica"' })
  .refine((t) => t.modelo_fc !== 'geotermia' || t.geotermia, { message: 'modelo_fc geotermia exige el bloque "geotermia"' })
  .refine((t) => t.modelo_fc !== 'hidro' || t.hidro, { message: 'modelo_fc hidro exige el bloque "hidro"' })
  .refine((t) => t.modelo_fc !== 'csp' || t.csp, { message: 'modelo_fc csp exige el bloque "csp"' })
  .refine((t) => t.modelo_fc !== 'termica' || (t.termica && t.combustible), { message: 'modelo_fc termica exige los bloques "termica" y "combustible"' })
  .refine((t) => t.modelo_fc !== 'almacenamiento' || t.almacenamiento, { message: 'modelo_fc almacenamiento exige el bloque "almacenamiento"' })
  .refine((t) => t.modelo_fc !== 'hidrogeno' || t.hidrogeno, { message: 'modelo_fc hidrogeno exige el bloque "hidrogeno"' })
  .refine((t) => t.modelo_fc !== 'transmision' || t.transmision, { message: 'modelo_fc transmision exige el bloque "transmision"' })
  .refine((t) => t.modelo_fc !== 'eficiencia' || t.eficiencia, { message: 'modelo_fc eficiencia exige el bloque "eficiencia"' });

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
  pozos_exploratorios: z.number().int().positive().optional(),
  hallazgo_pozos_secos: z.string().optional(),
});

export const studiesFileSchema = z.object({ estudios: z.array(studySchema).min(1), hallazgos: z.array(findingSchema) });

export const supplierSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  tipo: z.enum(['equipos', 'epc', 'inversores', 'logistica']),
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
  capacidad_mw_ano: z.number().positive().optional(),
  factor_plazo_entrega: z.number().positive().optional(),
  ...src,
}).refine((s) => s.tipo !== 'equipos' || s.plazo_entrega_dias, { message: 'Un proveedor de equipos necesita plazo_entrega_dias' })
  .refine((s) => s.tipo !== 'epc' || (s.factor_plazo && s.prob_sobrecosto_hito !== undefined), { message: 'Un EPC necesita factor_plazo y prob_sobrecosto_hito' });

const withSource = <T extends z.ZodRawShape>(shape: T) => z.object({ ...shape, ...src }).refine(hasSource, srcMsg);

export const materialSchema = withSource({
  id: z.string(), nombre: z.string(), volatilidad_anual: z.number().nonnegative().max(1), reversion_anual: prob01,
  min: z.number().positive(), max: z.number().positive(),
});
export const learningSchema = withSource({
  tecnologia: z.string(), equipos_anual: z.number().min(-0.2).max(0.1), epc_anual: z.number().min(-0.2).max(0.1),
  exposicion: z.record(prob01),
});

export const suppliersFileSchema = z.object({
  fuente_general: z.string().min(1),
  proveedores: z.array(supplierSchema).min(1),
  // Fase 3: dinámica de precios y plazos (opcional: sin ella los precios quedan fijos como en la Fase 2).
  materiales: z.array(materialSchema).optional(),
  curvas_aprendizaje: z.array(learningSchema).optional(),
  demanda_global: withSource({
    volatilidad_anual: z.number().nonnegative(), reversion_anual: prob01, min: z.number().positive(), max: z.number().positive(),
    elasticidad_precio: z.number().nonnegative(), elasticidad_plazo: z.number().nonnegative(),
  }).optional(),
  cola: withSource({ umbral: z.number().nonnegative(), prima_precio: z.number().nonnegative(), plazo_por_cola: z.number().nonnegative() }).optional(),
  relacion: withSource({
    descuento_por_pedido: prob01, descuento_max: prob01, confiabilidad_por_pedido: prob01, confiabilidad_max: prob01, penalidad_retraso: prob01,
  }).optional(),
});

// ───────────── Fase 3: I+D, clientes y competidores ─────────────

const researchEffects = z.object({
  tecnologias: z.array(z.string()).optional(),
  estudios: z.array(z.string()).optional(),
  paises: z.array(z.string().length(3)).optional(),
  contratos: z.array(z.string()).optional(),
  capex_frac: z.record(z.number().min(-0.5).max(0.5)).optional(),
  om_frac: z.record(z.number().min(-0.5).max(0.5)).optional(),
  fc_frac: z.record(z.number().min(-0.5).max(0.5)).optional(),
  permisos_tiempo_frac: z.number().min(-0.5).max(0.5).optional(),
  puntaje_tecnico: z.number().min(0).max(30).optional(),
});

export const researchNodeSchema = withSource({
  id: z.string(),
  nombre: z.string(),
  rama: z.enum(['tecnologias', 'estudios', 'mercados', 'contratos', 'eficiencia']),
  descripcion: z.string(),
  costo_usd: z.number().nonnegative(),
  meses: z.number().positive(),
  requiere: z.array(z.string()),
  inicial: z.boolean().optional(),
  prob_contratiempo: prob01,
  efectos: researchEffects,
  fase_modelo: z.number().int().optional(),
});

export const researchFileSchema = z.object({ supuesto_general: z.string().min(1), nodos: z.array(researchNodeSchema).min(1) });

const weights = z.object({ precio: z.number().nonnegative(), tecnica: z.number().nonnegative(), experiencia: z.number().nonnegative(), plazo: z.number().nonnegative() })
  .refine((w) => Math.abs(w.precio + w.tecnica + w.experiencia + w.plazo - 1) < 1e-6, { message: 'Los pesos de evaluación deben sumar 1' });

export const clientTypeSchema = withSource({
  id: z.string(),
  nombre: z.string(),
  pais: z.string().length(3),
  tipo: z.enum(['licitacion_publica', 'solicitud_privada']),
  contrato: z.enum(['ppa', 'potencia', 'epc', 'bot']),
  tipo_contrato: z.string(),
  descripcion: z.string(),
  nombres_cliente: z.array(z.string()).min(1),
  frecuencia_anual: z.number().nonnegative(),
  mw: sourced,
  plazo_anos: sourced,
  tecnologias: z.array(z.string()).min(1),
  precio_referencia: sourced,
  precio_reserva_factor: sourced,
  publica_precio_tope: z.boolean(),
  plazo_oferta_dias: sourced,
  evaluacion_dias: sourced,
  plazo_cod_meses: sourced,
  garantia_seriedad_usd_mw: z.number().nonnegative(),
  garantia_cumplimiento_usd_mw: z.number().nonnegative(),
  pesos: weights,
  experiencia_mw_min: z.number().nonnegative(),
  capital_min_usd: z.number().nonnegative(),
  multa_usd_mw_mes: z.number().nonnegative(),
  meses_max_atraso: z.number().nonnegative(),
  costo_preparacion_usd: sourced,
  ofertantes_externos: z.object({ media: z.number().nonnegative(), precio_factor: sourced }),
  indexacion_anual: z.number(),
  moneda: z.enum(['USD', 'local']).optional(),
});

export const clientsFileSchema = z.object({
  tipos: z.array(clientTypeSchema).min(1),
  garantias: withSource({ comision_anual: prob01, colateral_frac: prob01 }),
  jugador: withSource({ reputacion_inicial: z.number().min(0).max(100), experiencia_mw_inicial: z.number().nonnegative() }),
  potencia_firme_frac: z.record(prob01),
  potencia_firme_fuente: z.string().min(1),
  epc: withSource({ anticipo_frac: prob01, retencion_frac: prob01, ld_frac_semana: prob01, ld_tope_frac: prob01, contingencia_frac: prob01 }),
  meses_asignar_proyecto: z.number().positive(),
});

export const competitorSchema = withSource({
  id: z.string(),
  nombre: z.string(),
  estrategia: z.enum(['agresiva', 'conservadora', 'estatal', 'especialista', 'fondo']),
  estrategia_aparente: z.string(),
  descripcion: z.string(),
  caja_inicial_usd: z.number().positive(),
  gastos_fijos_mensuales_usd: z.number().nonnegative(),
  reputacion_inicial: z.number().min(0).max(100),
  experiencia_mw_inicial: z.number().nonnegative(),
  tecnologias: z.array(z.string()).min(1),
  margen_objetivo: z.number().min(-0.2).max(1),
  tasa_descuento: z.number().min(0.02).max(0.3),
  apalancamiento: prob01,
  socio: prob01,
  max_proyectos: z.number().int().nonnegative(),
  mw: z.object({ min: z.number().positive(), max: z.number().positive() }),
  proveedores: z.enum(['baratos', 'equilibrados', 'calidad']),
  prob_ofertar: prob01,
  ofertar_epc: z.boolean(),
  dias_decision: z.number().int().min(1).max(60),
  reserva_meses: z.number().nonnegative(),
  vende: z.enum(['nunca', 'listo_para_construir', 'en_crisis']),
  investigacion: z.object({ presupuesto_mensual_usd: z.number().nonnegative(), prioridades: z.array(z.string()) }),
  expansion: z.object({ paises: z.array(z.string().length(3)), caja_min_usd: z.number().nonnegative() }).optional(),
});

export const competitorsFileSchema = z.object({
  empresas: z.array(competitorSchema).min(1).max(8),
  sitios_candidatos: z.array(z.object({ nombre: z.string(), pais: z.string().length(3), tecnologia: z.string(), lat: z.number(), lon: z.number() })),
  sitios_fuente: z.string().min(1),
});

// ───────────── Fase 4: combustibles e inflación del USD ─────────────
export const fuelSchema = withSource({
  id: z.string(), nombre: z.string(), precio_usd_mmbtu: sourced, volatilidad_anual: z.number().nonnegative().max(1.5), reversion_anual: prob01,
  min: z.number().positive(), max: z.number().positive(), emisiones_kgco2_mmbtu: z.number().nonnegative(),
});
export const marketsFileSchema = z.object({ inflacion_usd: sourced, combustibles: z.array(fuelSchema).min(1) });

// ───────────── Fase 5: mercado eléctrico, eventos del mundo y seguros ─────────────
const h24 = z.array(z.number().min(-0.01).max(3)).length(24);
const m12 = z.array(z.number().positive().max(3)).length(12);
const ns = z.number().nonnegative();
export const powerClassSchema = z.object({
  nombre: z.string(), tipo: z.enum(['variable_solar', 'variable_eolica', 'base', 'hidro', 'termica']), fc: z.number().positive().max(1),
  disponibilidad: prob01, credito_firme: prob01, combustible: z.string().optional(), heat_rate_btu_kwh: z.number().positive().optional(),
  om_variable_usd_mwh: ns, tecnologias: z.array(z.string()),
});
export const powerCountrySchema = withSource({
  forma_demanda: z.string(), perfil_demanda_mensual: m12.optional(), crecimiento_demanda: z.number().min(-0.05).max(0.15),
  precio_techo_usd_mwh: z.number().positive(), precio_piso_usd_mwh: z.number().min(-500).max(100),
  hidro_embalse_frac: prob01, sigma_hidrologia: z.number().min(0).max(0.6),
  enso: z.object({ nino_hidro: z.number().positive().max(2), nina_hidro: z.number().positive().max(2), nino_demanda: z.number().positive().max(1.5).optional() }).optional(),
  margen_reserva: z.number().min(1).max(2),
  mezcla_termica: z.record(ns).optional(), mezcla_otros: z.record(ns).optional(), parque_mw: z.record(ns).optional(),
  red: z.object({ limite_vre_frac: z.number().positive().max(3) }).optional(),
  capacidad: z.object({ nombre: z.string(), precio_usd_kw_mes: sourced }).optional(),
  servicios: z.object({ nombre: z.string(), requerimiento_frac_demanda: prob01, precio_usd_mw_h: sourced }).optional(),
  elecciones: z.object({ cada_anos: z.number().int().min(2).max(10), proxima: z.number().int().min(2000).max(2100), mes: z.number().int().min(1).max(12) }).optional(),
  riesgos: z.record(prob01).optional(),
});
export const powerFileSchema = z.object({
  formas_demanda: z.record(withSource({ laborable: h24, finde: h24 })),
  formas_recurso: withSource({ solar: h24, eolica: h24 }),
  clases: z.record(z.union([powerClassSchema, z.string()])).refine((r) => typeof r.supuesto === 'string' || typeof r.fuente === 'string', srcMsg)
    .transform((r) => Object.fromEntries(Object.entries(r).filter(([, v]) => typeof v !== 'string')) as Record<string, z.infer<typeof powerClassSchema>>),
  clima: withSource({ prob_nino: prob01, prob_nina: prob01, persistencia: prob01 }),
  valor_agua: withSource({ base: z.number().positive(), exponente: ns, min: ns, max: z.number().positive() }),
  escasez: withSource({ umbral: prob01 }),
  comprador: withSource({ prima_merchant: z.number().min(0).max(0.2), recorte_precio_merchant: z.number().min(0).max(0.5) }),
  ppa_modalidades: z.object({ bloque: withSource({ prima: z.number().min(-0.2).max(0.3), cobertura: prob01 }), financiero: withSource({ prima: z.number().min(-0.2).max(0.3), cobertura: prob01 }) }),
  terminacion_ppa_meses: z.number().nonnegative().max(60),
  credito_firme_tecnologia: z.record(prob01),
  paises: z.record(powerCountrySchema),
});
const eventEffects = z.object({
  combustibles: z.record(z.number().positive().max(5)).optional(), demanda: z.number().positive().max(1.5).optional(),
  capex: z.record(z.number().positive().max(3)).optional(), plazo_entrega: z.number().positive().max(5).optional(),
  plazo_permisos: z.number().positive().max(5).optional(), arancel: z.number().min(0).max(1).optional(),
  tipo_cambio: z.number().min(0).max(0.9).optional(), hidrologia: z.number().positive().max(2).optional(),
  obras_paradas_dias: sourced.optional(),
  danos: z.object({ vulnerabilidad: z.record(prob01), fraccion: sourced, dias: sourced, costo_frac_capex: sourced }).optional(),
  regulacion: z.object({ carbono_usd_t: z.number().min(-100).max(200).optional(), plazo_permisos: z.number().positive().max(3).optional(), credito_fiscal: z.number().min(0).max(5).optional() }).optional(),
  costo_tecnologia: z.record(z.number().positive().max(2)).optional(),
});
export const worldEventSchema = withSource({
  id: z.string(), nombre: z.string(), tipo: z.enum(['economico', 'politico', 'regulatorio', 'conflicto', 'desastre', 'salud', 'tecnologia', 'social']),
  alcance: z.enum(['global', 'pais']), paises: z.array(z.string().length(3)).optional(), amenaza: z.string().optional(),
  prob_anual: prob01, duracion_meses: sourced, efectos: eventEffects, texto: z.string().min(1),
});
export const eventsFileSchema = z.object({
  eventos: z.array(worldEventSchema).min(1),
  gobiernos: z.array(z.object({ id: z.string(), nombre: z.string(), prob: prob01, efectos: z.object({ carbono_usd_t: z.number().optional(), plazo_permisos: z.number().positive().optional(), credito_fiscal: z.number().min(0).optional() }), texto: z.string() })).min(1),
  supuesto_gobiernos: z.string().min(1),
  seguros: withSource({ recargo: z.number().min(1).max(5), tasa_minima: ns, deducible_frac: prob01, espera_dias: z.number().int().nonnegative(), lucro_factor_prima: z.number().min(1).max(5), lucro_dias_max: z.number().int().positive() }),
});

const anchorLand = z.tuple([z.string(), z.number(), z.number(), z.number().nullable(), z.number().nullable(), z.number().nullable()]).rest(z.number());
export const anchorsSchema = z.object({
  radio_defecto_km: z.number().positive(),
  tierra: z.array(anchorLand),
  mar: z.array(z.tuple([z.string(), z.number(), z.number(), z.number()]).rest(z.number())),
  geotermia: z.array(z.tuple([z.string(), z.number(), z.number(), z.number(), z.number()])),
});

// ───────────────────────── Fase 6: equipo, reputación y oficinas ─────────────────────────
const nn6 = z.number().nonnegative();
const teamMember = z.object({ rol: z.string(), habilidad: z.number().min(0).max(100), experiencia: nn6 });
const officeLevel = withSource({
  id: z.enum(['representante', 'oficina', 'sede']), nombre: z.string(), capacidad_personal: z.number().int().positive(), costo_inicial_usd: nn6, costo_mensual_usd: nn6,
  dias: z.number().int().nonnegative(), costo_desarrollo_frac: z.number().min(-0.5).max(0), reputacion_gobierno_mes: nn6, invitaciones_privadas: z.boolean(),
  costo_desarrollo_vecinos_frac: z.number().min(-0.5).max(0).optional(),
});
const repDelta = z.object({ gobierno: z.number().optional(), comunidad: z.number().optional(), clientes: z.number().optional() });
const aiStrategies = ['agresiva', 'conservadora', 'estatal', 'fondo', 'especialista'] as const;
const teamAreas = z.enum(['permisos', 'social', 'recurso', 'obra', 'finanzas', 'ofertas', 'mercado', 'operacion']);
export const teamFileSchema = z.object({
  puntaje_externo: sourced,
  pesos_equipo: z.array(z.number().min(0).max(1)).min(1),
  experiencia_anos_plena: z.number().positive(),
  roles: z.array(withSource({ id: z.string(), nombre: z.string(), areas: z.record(teamAreas, z.number().min(0).max(1)), capacidad: z.number().int().positive(), factor_salario: z.number().positive() })).min(8),
  /** k de cada efecto: fracciones ≤ 1, salvo el puntaje técnico (puntos ≤ 20). */
  efectos: z.record(sourced.refine((v) => v.base >= 0 && v.base <= 20, { message: 'Efecto fuera de rango' })),
  permisos_sociales: z.array(z.string()),
  factor_fuera_pais: sourced, factor_fuera_pais_region: sourced, roles_locales: z.array(z.string()), factor_sin_idioma: sourced, factor_sin_idioma_local: sourced,
  mercado_laboral: z.object({
    candidatos_por_pais: sourced, vigencia_dias: sourced, habilidad: sourced, experiencia_anos: sourced, reclutamiento_frac_anual: sourced, oferta_minima_frac: sourced,
    rotacion_base_mensual: sourced, rotacion_moral_baja: sourced, moral_inercia: sourced, moral_salario: sourced, moral_sobrecarga: sourced,
    capacitacion_costo_usd: sourced, capacitacion_dias: sourced, capacitacion_ganancia: sourced, aumento_anual_experiencia: sourced,
  }),
  paises: z.record(withSource({
    salario_usd: z.number().positive(), cargas: z.number().min(0).max(1.5), indemnizacion_meses_ano: nn6, indemnizacion_min_meses: nn6, indemnizacion_max_meses: nn6,
    idioma: z.string(), ingles: z.number().min(0).max(1), oficina_indice: z.number().positive(),
  })),
  otras_lenguas: z.record(z.record(z.number().min(0).max(1))).optional(),
  nombres: z.record(z.object({ nombres: z.array(z.string()).min(3), apellidos: z.array(z.string()).min(3) })),
  oficinas: z.object({
    niveles: z.array(officeLevel).length(3),
    requisitos_sede: withSource({ personal_min: z.number().int().nonnegative() }),
    regiones: z.record(z.array(z.string().length(3))),
  }),
  reputacion: z.object({
    inicial_pais_nuevo: sourced, reversion_mensual: sourced, neutro: sourced,
    causas: z.record(repDelta), supuesto: z.string().min(1),
    efectos: z.object({ social_aprobacion: sourced, conflicto: sourced, banca_desarrollo_spread: sourced, invitacion_prob_mes: sourced }),
    inversion_social: z.object({ usd_por_punto: sourced, tope_anual_puntos: sourced }),
  }),
  riesgos_obra: z.object({ conflicto_mensual: sourced, conflicto_dias: sourced, conflicto_costo_frac: sourced, accidente_mensual: sourced, accidente_dias: sourced, accidente_costo_frac: sourced }),
  equipo_inicial_jugador: z.array(teamMember),
  ia: z.object({
    equipo_inicial: z.record(z.enum(aiStrategies), z.array(teamMember)),
    objetivos: z.record(z.enum(aiStrategies), z.object({ roles: z.array(z.string()).min(1), por_proyectos: z.number().positive(), max: z.number().int().positive() })),
    supuesto: z.string().min(1),
  }),
});

export type GameYaml = z.infer<typeof gameSchema>;
export type LayerDef = z.infer<typeof layerSchema>;
export type CountryDef = z.infer<typeof countrySchema>;
export type TechnologyYaml = z.infer<typeof technologySchema>;
export type StudyYaml = z.infer<typeof studySchema>;
export type SupplierYaml = z.infer<typeof supplierSchema>;
