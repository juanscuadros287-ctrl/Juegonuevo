/**
 * Forma de los datos que el motor necesita. @voltaje/data valida los YAML con Zod y produce
 * objetos con exactamente esta forma (más los campos `fuente`/`supuesto`, que el motor ignora).
 * El motor no lee archivos: recibe todo por `SimContext`.
 */

/** Valor con rango. `base` es el valor central; min/max se usan en distribuciones triangulares. */
export interface Dist { base: number; min?: number; max?: number }

export type FcModel = 'solar_fv' | 'eolica' | 'fijo';

export interface Milestone { id: string; nombre: string; fraccion: number; requiere_equipos?: boolean; sensible_lluvia?: boolean }

export interface TechRisk { id: string; nombre: string; descripcion: string }

export interface TechnologyDef {
  id: string;
  nombre: string;
  categoria: string;
  /** Capa de la grilla que define el recurso (ghi, viento_tierra…). Ausente = sin recurso de grilla. */
  recurso?: string;
  modelo_fc: FcModel;
  capex_usd_kw: Dist;
  /** Reparto del CAPEX: equipos (sujeto a arancel y proveedor), obra/EPC (sujeto a costo local), resto. */
  desglose_capex: { equipos: number; epc: number; otros: number };
  om_fijo_usd_kw_ano: Dist;
  om_variable_usd_mwh: Dist;
  factor_capacidad_ref: Dist;
  vida_util_anos: Dist;
  degradacion_anual: Dist;
  construccion_meses: Dist;
  puesta_en_marcha_dias: Dist;
  emisiones_gco2_kwh: Dist;
  uso_suelo_ha_mw: Dist;
  escala_mw: { min: number; max: number; tipico: number };
  /** Incertidumbre del recurso real frente al valor de la celda (desv. estándar relativa). */
  sigma_recurso_sitio: number;
  /** Variación diaria e interanual de la producción (desv. estándar relativa). */
  variabilidad: { diaria: number; interanual: number };
  fallas: {
    eventos_ano_por_mw: Dist;
    fraccion_afectada: Dist;
    duracion_dias: Dist;
    /** Costo por kW AFECTADO (fracción_afectada × potencia). */
    costo_reparacion_usd_kw: Dist;
  };
  mantenimiento: {
    /** Pérdida de disponibilidad por mantenimiento programado (fracción del año). */
    programado_perdida: number;
    /** Con política preventiva: multiplicador de O&M fijo y de la tasa de fallas. */
    preventivo_om_factor: number;
    preventivo_fallas_factor: number;
    correctivo_om_factor: number;
  };
  costo_desmantelamiento_frac_capex: Dist;
  estudios_requeridos: string[];
  hitos_construccion: Milestone[];
  riesgos: TechRisk[];
  solar?: { pr: number; coef_temp_por_c: number; t_ref_c: number; delta_celda_c: number; ganancia_seguidor: number };
  eolica?: {
    turbina_mw: number; diametro_rotor_m: number; altura_buje_m: number; cp: number;
    v_arranque: number; v_corte: number; weibull_k: number; perdidas: number; cizalle_alfa: number;
  };
  /** Fase 4: térmicas. */
  combustible?: { tipo: string; heat_rate_btu_kwh: Dist; precio_usd_mmbtu?: Dist };
  /** Fase 4: almacenamiento. */
  almacenamiento?: { eficiencia_ida_vuelta: Dist; horas: Dist; ciclos_vida?: Dist };
}

export type StudyOutcome = 'normal' | 'peor' | 'bloqueo';

export interface Applicability { tecnologias?: string[]; mw_min?: number; mw_max?: number }

export interface FindingDef {
  id: string;
  nombre: string;
  descripcion: string;
  peso: number;
  mitigable: boolean;
  costo_mitigacion_fijo_usd?: number;
  costo_mitigacion_usd_mw?: number;
  retraso_dias?: Dist;
  prob_exito_mitigacion?: number;
}

export interface StudyDef {
  id: string;
  nombre: string;
  grupo: string;
  descripcion: string;
  aplica: Applicability;
  /** Grupos de estudios que deben estar completos antes. */
  requiere: string[];
  costo_fijo_usd: Dist;
  costo_usd_mw: Dist;
  duracion_dias: Dist;
  /** Si es medición de recurso: incertidumbre residual (σ relativa) tras el estudio. */
  sigma_recurso?: number;
  /** Probabilidades de resultado (suman 1). En medición de recurso «peor» se deriva de la medición. */
  resultados: { normal: number; peor: number; bloqueo: number };
  /** Efecto de un resultado «peor» sobre el CAPEX (multiplicador, triangular). */
  peor_capex_factor?: Dist;
  peor_descripcion?: string;
  hallazgos?: string[];
}

export interface PermitDef {
  id: string;
  nombre: string;
  grupo: string;
  autoridad: string;
  descripcion: string;
  aplica: Applicability;
  requiere: { estudios: string[]; permisos: string[] };
  costo_fijo_usd: Dist;
  costo_usd_mw: Dist;
  duracion_dias: Dist;
  prob: { aprobado: number; rechazado: number; info_adicional: number };
  info_adicional: { retraso_dias: Dist; costo_usd: Dist };
  reintentable: boolean;
  max_intentos_info: number;
}

export interface PpaChannelDef {
  id: string;
  nombre: string;
  descripcion: string;
  precio_usd_mwh: Dist;
  plazo_anos: number;
  indexacion_anual: number;
  duracion_dias: Dist;
  prob_exito: number;
  costo_usd: Dist;
  mw_min: number;
  mw_max: number;
  requiere_permisos: string[];
  plazo_cod_meses: number;
  multa_usd_mw_mes: number;
}

export interface LenderDef {
  id: string;
  nombre: string;
  tipo: 'comercial' | 'desarrollo';
  descripcion: string;
  spread: Dist;
  plazo_anos: number;
  dscr_ppa: number;
  dscr_merchant: number;
  apalancamiento_max: number;
  comision_estructuracion: number;
  costo_asesores_usd: Dist;
  diligencia_dias: Dist;
  prob_aprobacion: number;
  requiere_ppa: boolean;
  sigma_recurso_max: number;
  monto_min_usd: number;
}

export interface CountrySimDef {
  iso3: string;
  nombre: string;
  inflacion_anual: Dist;
  prima_riesgo_pais: Dist;
  moneda: { codigo: string; usd_por_unidad: number };
  tipo_cambio: { deriva_anual: number; volatilidad_anual: number };
  mercado: {
    precio_spot_medio_usd_mwh: Dist;
    /** 12 multiplicadores (ene–dic) del precio spot medio. */
    perfil_spot_mensual: number[];
  };
  /** 12 multiplicadores (ene–dic) del recurso por capa (ghi, viento_tierra…). */
  perfil_recurso_mensual: Record<string, number[]>;
  impuestos: { renta: Dist; depreciacion_anos: Dist; itbms: Dist; arancel_general_equipos: Dist };
  incentivos: Record<string, { arancel_exento: boolean; itbms_exento: boolean; credito_fiscal_frac_inversion: Dist; credito_max_frac_impuesto: number; descripcion: string }>;
  costos: {
    factor_construccion_local: Dist;
    prospeccion_usd: Dist;
    opcion_terreno_usd_ha_ano: Dist;
    arriendo_terreno_usd_ha_ano: Dist;
    seguro_frac_capex_ano: Dist;
  };
  finanzas: {
    tasa_libre_riesgo: Dist;
    prima_mercado_acciones: Dist;
    beta_renovables: number;
    prima_etapa: Record<string, number>;
    prima_tecnologia: Record<string, number>;
    prestamistas: LenderDef[];
    socio_equity: { participacion_max: number; prima_desarrollo_frac: number };
    credito_emergencia: { tasa: number; frac_valor_activos: number };
  };
  construccion: {
    meses_lluviosos: number[];
    factor_avance_lluvia: number;
    huelga_prob_mensual: number;
    huelga_duracion_dias: Dist;
    clima_extremo_prob_mensual: number;
    clima_extremo_dias: Dist;
  };
  quiebra: { meses_caja_negativa: number };
  permisos: PermitDef[];
  ppa: { canales: PpaChannelDef[] };
}

export interface SupplierDef {
  id: string;
  nombre: string;
  tipo: 'equipos' | 'epc';
  tecnologias: string[];
  origen: string;
  descripcion: string;
  /** Multiplicador del costo de su parte del CAPEX. */
  factor_precio: number;
  /** 0–1: menor calidad ⇒ más sobrecostos (EPC) o defectos en puesta en marcha (equipos). */
  calidad: number;
  /** 0–1: menor confiabilidad ⇒ más retrasos de entrega/obra y más fallas en operación. */
  confiabilidad: number;
  /** Equipos: días de entrega. EPC: multiplicador del plazo de obra. */
  plazo_entrega_dias?: Dist;
  factor_plazo?: number;
  flete_frac?: number;
  /** EPC: probabilidad de sobrecosto por hito. */
  prob_sobrecosto_hito?: number;
}

export interface SimData {
  technologies: Record<string, TechnologyDef>;
  studies: Record<string, StudyDef>;
  findings: Record<string, FindingDef>;
  suppliers: Record<string, SupplierDef>;
  countries: Record<string, CountrySimDef>;
}
