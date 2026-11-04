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
  /** Fase 3: fracción del costo de equipos que corresponde a inversores (si se elige un proveedor de inversores aparte). */
  fraccion_inversores?: number;
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
  /** Fase 3: 'inversores' (solo FV, parte del paquete de equipos) y 'logistica' (flete y aduanas). */
  tipo: 'equipos' | 'epc' | 'inversores' | 'logistica';
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
  /** Fase 3: capacidad que el proveedor asigna a la región (MW/año); su cola alarga plazos y sube precios. */
  capacidad_mw_ano?: number;
  /** Fase 3 (logística): multiplicador del plazo de entrega de los equipos. */
  factor_plazo_entrega?: number;
}

// ───────────────────────────── Fase 3 ─────────────────────────────

/** Índice de materiales (polisilicio, acero, cobre…): proceso log-normal con reversión a la media, mensual. */
export interface MaterialIndexDef {
  id: string;
  nombre: string;
  /** Volatilidad anual del logaritmo del índice. */
  volatilidad_anual: number;
  /** Velocidad de reversión anual hacia 1 (0–1). */
  reversion_anual: number;
  min: number;
  max: number;
}

/** Curva de aprendizaje y exposición a materiales de una tecnología. */
export interface LearningCurveDef {
  tecnologia: string;
  /** Cambio anual del precio de los equipos por aprendizaje (p. ej. −0,035). */
  equipos_anual: number;
  /** Cambio anual del costo de obra (EPC) por aprendizaje. */
  epc_anual: number;
  /** Peso de cada material en el precio de los equipos (el resto no depende de materiales). */
  exposicion: Record<string, number>;
}

export interface SupplyDef {
  materiales: MaterialIndexDef[];
  curvas_aprendizaje: LearningCurveDef[];
  /** Demanda mundial de equipos (índice): alarga plazos y sube precios cuando está alta. */
  demanda_global: { volatilidad_anual: number; reversion_anual: number; min: number; max: number; elasticidad_precio: number; elasticidad_plazo: number };
  /** Prima de precio por cola propia del proveedor: precio × (1 + prima·max(0, cola/capacidad − umbral)). */
  cola: { umbral: number; prima_precio: number; plazo_por_cola: number };
  /** Relación con el proveedor (historial de pedidos). */
  relacion: { descuento_por_pedido: number; descuento_max: number; confiabilidad_por_pedido: number; confiabilidad_max: number; penalidad_retraso: number };
}

export type ResearchBranch = 'tecnologias' | 'estudios' | 'mercados' | 'contratos' | 'eficiencia';

/** Efectos de un nodo de I+D. Las fracciones son cambios relativos (−0,05 = −5 %). Clave '*' = todas las tecnologías. */
export interface ResearchEffects {
  tecnologias?: string[];
  estudios?: string[];
  paises?: string[];
  contratos?: string[];
  capex_frac?: Record<string, number>;
  om_frac?: Record<string, number>;
  fc_frac?: Record<string, number>;
  permisos_tiempo_frac?: number;
  /** Puntos extra en el puntaje técnico de las ofertas. */
  puntaje_tecnico?: number;
}

export interface ResearchNodeDef {
  id: string;
  nombre: string;
  rama: ResearchBranch;
  descripcion: string;
  costo_usd: number;
  /** Duración mínima (meses) con presupuesto suficiente. */
  meses: number;
  requiere: string[];
  /** Disponible desde el inicio (sin costo). */
  inicial?: boolean;
  /** Probabilidad de un contratiempo al terminar (más tiempo y costo). */
  prob_contratiempo: number;
  efectos: ResearchEffects;
  /** Fase en la que el contenido que desbloquea tendrá modelo completo (si es posterior a la actual). */
  fase_modelo?: number;
}

export interface ResearchDef {
  nodos: ResearchNodeDef[];
}

export type ContractKind = 'ppa' | 'potencia' | 'epc' | 'bot';

export interface ClientTypeDef {
  id: string;
  nombre: string;
  pais: string;
  tipo: 'licitacion_publica' | 'solicitud_privada';
  contrato: ContractKind;
  /** Nodo de I+D (tipo de contrato) necesario para ofertar. */
  tipo_contrato: string;
  descripcion: string;
  nombres_cliente: string[];
  /** Oportunidades por año (media de Poisson). */
  frecuencia_anual: number;
  /** MW (de energía, firmes en potencia, o instalados en EPC). */
  mw: Dist;
  plazo_anos: Dist;
  tecnologias: string[];
  /** Precio de referencia de mercado: USD/MWh (ppa, bot), USD/kW-mes (potencia), USD/kW (epc). */
  precio_referencia: Dist;
  /** Precio máximo aceptable = referencia × factor. */
  precio_reserva_factor: Dist;
  /** Las licitaciones públicas publican el precio tope; los privados lo guardan. */
  publica_precio_tope: boolean;
  plazo_oferta_dias: Dist;
  evaluacion_dias: Dist;
  plazo_cod_meses: Dist;
  garantia_seriedad_usd_mw: number;
  garantia_cumplimiento_usd_mw: number;
  pesos: { precio: number; tecnica: number; experiencia: number; plazo: number };
  experiencia_mw_min: number;
  capital_min_usd: number;
  multa_usd_mw_mes: number;
  meses_max_atraso: number;
  costo_preparacion_usd: Dist;
  ofertantes_externos: { media: number; precio_factor: Dist };
  indexacion_anual: number;
}

export interface ClientsDef {
  tipos: ClientTypeDef[];
  garantias: { comision_anual: number; colateral_frac: number };
  jugador: { reputacion_inicial: number; experiencia_mw_inicial: number };
  /** Potencia firme reconocida por MW instalado (contratos de potencia). */
  potencia_firme_frac: Record<string, number>;
  /** EPC para terceros: anticipo, retención y daños por atraso. */
  epc: { anticipo_frac: number; retencion_frac: number; ld_frac_semana: number; ld_tope_frac: number; contingencia_frac: number };
  /** Meses para asignar un proyecto a un contrato ganado «con proyecto nuevo». */
  meses_asignar_proyecto: number;
}

export type CompetitorStrategy = 'agresiva' | 'conservadora' | 'estatal' | 'especialista' | 'fondo';

export interface CompetitorDef {
  id: string;
  nombre: string;
  estrategia: CompetitorStrategy;
  /** Lo que el mercado percibe (texto público). */
  estrategia_aparente: string;
  descripcion: string;
  caja_inicial_usd: number;
  gastos_fijos_mensuales_usd: number;
  reputacion_inicial: number;
  experiencia_mw_inicial: number;
  tecnologias: string[];
  margen_objetivo: number;
  tasa_descuento: number;
  apalancamiento: number;
  socio: number;
  max_proyectos: number;
  mw: { min: number; max: number };
  proveedores: 'baratos' | 'equilibrados' | 'calidad';
  prob_ofertar: number;
  ofertar_epc: boolean;
  dias_decision: number;
  /** Caja mínima que no arriesga (múltiplo de los gastos fijos mensuales). */
  reserva_meses: number;
  vende: 'nunca' | 'listo_para_construir' | 'en_crisis';
  investigacion: { presupuesto_mensual_usd: number; prioridades: string[] };
}

export interface CandidateSiteDef { nombre: string; pais: string; tecnologia: string; lat: number; lon: number }

export interface CompetitorsDef {
  empresas: CompetitorDef[];
  sitios_candidatos: CandidateSiteDef[];
}

export interface SimData {
  technologies: Record<string, TechnologyDef>;
  studies: Record<string, StudyDef>;
  findings: Record<string, FindingDef>;
  suppliers: Record<string, SupplierDef>;
  countries: Record<string, CountrySimDef>;
  /** Fase 3 (opcionales: sin ellos el motor se comporta como en la Fase 2). */
  supply?: SupplyDef;
  research?: ResearchDef;
  clients?: ClientsDef;
  competitors?: CompetitorsDef;
}
