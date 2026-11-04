/**
 * Forma de los datos que el motor necesita. @voltaje/data valida los YAML con Zod y produce
 * objetos con exactamente esta forma (más los campos `fuente`/`supuesto`, que el motor ignora).
 * El motor no lee archivos: recibe todo por `SimContext`.
 */

/** Valor con rango. `base` es el valor central; min/max se usan en distribuciones triangulares. */
export interface Dist { base: number; min?: number; max?: number }

/**
 * Modelo físico/económico de la tecnología (ver tech/capacityFactor.ts y tech/models.ts).
 * Fase 4: geotermia, hidro, csp, termica (combustible), almacenamiento, hidrogeno, transmision, eficiencia.
 */
export type FcModel = 'solar_fv' | 'eolica' | 'fijo' | 'geotermia' | 'hidro' | 'csp' | 'termica' | 'almacenamiento' | 'hidrogeno' | 'transmision' | 'eficiencia';

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
  /** Fase 4: térmicas (y biomasa/biogás/nuclear): combustible (id de markets.yaml) y consumo específico. */
  combustible?: { tipo: string; heat_rate_btu_kwh: Dist; precio_usd_mmbtu?: Dist };
  /** Fase 3: fracción del costo de equipos que corresponde a inversores (si se elige un proveedor de inversores aparte). */
  fraccion_inversores?: number;
  /** Fase 4: almacenamiento (baterías, bombeo). */
  almacenamiento?: {
    eficiencia_ida_vuelta: Dist; horas: Dist; ciclos_vida?: Dist;
    /** Ciclos completos por año si el arbitraje es rentable. */
    ciclos_ano_max?: number;
    /** Pérdida de capacidad por ciclo completo (fracción). */
    degradacion_por_ciclo?: number;
  };
  // ───────────────────────── Fase 4 ─────────────────────────
  /** Recurso de un sitio típico bueno (unidad de la capa): referencia del catálogo si no hay grilla y para el mar. */
  recurso_tipico?: number;
  /** Tipo de modelo 3D (PlantKind de apps/game/src/models) que representa a esta tecnología. */
  visual?: string;
  /** Restricciones del sitio. */
  sitio?: TechSiting;
  geotermia?: GeothermalDef;
  hidro?: { fc_min: number; fc_max: number; exponente: number; regulacion: number; lluvia_ref_mm: number };
  csp?: { horas_almacenamiento: number; sm_base: number; sm_por_hora: number; eficiencia_relativa: number; fc_max: number };
  termica?: { fc_max: number; prima_captura: number; despacho: 'base' | 'media' | 'punta' };
  hidrogeno?: { kwh_por_kg: Dist; precio_venta_usd_kg: Dist; utilizacion: number; agua_usd_kg: number; factor_precio_electricidad: number };
  transmision?: { costo_usd_mw_km: Dist; perdidas_frac_100km: number; peaje_usd_mwh: Dist; utilizacion: number; interconexion: boolean; longitud_min_km: number; longitud_max_km: number; captura_diferencial: number };
  eficiencia?: { precio_ahorro_usd_mwh: Dist; ahorro_garantizado_frac: number; factor_carga: number };
  /** Riesgos de obra propios de la tecnología (multiplican los del EPC y del país). */
  riesgo_obra?: { sobrecosto_prob_factor: number; sobrecosto_magnitud_factor: number; retraso_prob_mensual: number; retraso_dias: Dist };
}

export interface TechSiting {
  superficie: 'tierra' | 'mar';
  /** Recurso mínimo de la capa (en su unidad). */
  recurso_min?: number;
  dist_costa_km_min?: number;
  dist_costa_km_max?: number;
  /** Profundidad máxima (m, aproximada desde la distancia a la costa). */
  profundidad_max_m?: number;
  /** Profundidad aproximada = dist_costa_km × este factor (m/km). */
  profundidad_m_por_km?: number;
  /** Profundidad desde la que se usa fundación flotante (+ costo). */
  flotante_desde_m?: number;
  flotante_capex_extra?: number;
  /** CAPEX extra por km de distancia a la costa sobre `km_ref` (cable y logística marina). */
  capex_extra_por_km?: number;
  km_ref?: number;
  relieve_min?: number;
  /** Necesita agua: índice hidro ≥ este valor o a menos de `agua_dist_costa_km` de la costa. */
  agua_indice_min?: number;
  agua_dist_costa_km?: number;
}

/** Geotermia: pozos exploratorios y de producción; el recurso es el flujo de calor (mW/m²). */
export interface GeothermalDef {
  /** Flujo de calor para el que la calidad del reservorio es 0 y 1 (interpolación lineal). */
  calidad_min_mw_m2: number;
  calidad_max_mw_m2: number;
  /** Probabilidad de pozo seco de exploración con calidad 0 y 1. */
  prob_seco_calidad0: number;
  prob_seco_calidad1: number;
  /** Probabilidad de pozo de baja entalpía (productivo pero pobre) con calidad 0 y 1. */
  prob_baja_calidad0: number;
  prob_baja_calidad1: number;
  /** Pozos de desarrollo: la tasa de pozos secos es esta fracción de la de exploración. */
  factor_seco_desarrollo: number;
  /** MW por pozo productor con calidad 0 y 1. */
  mw_pozo_calidad0: number;
  mw_pozo_calidad1: number;
  costo_pozo_usd: Dist;
  /** Pozos reinyectores por productor. */
  reinyectores_por_productor: number;
  /** Fracción del CAPEX que es perforación (escala con el número de pozos). */
  frac_capex_perforacion: number;
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
  /** Fase 4 (geotermia): pozos exploratorios que perfora el estudio (pueden salir secos o de baja entalpía). */
  pozos_exploratorios?: number;
  /** Hallazgo que se abre si todos los pozos exploratorios salen secos. */
  hallazgo_pozos_secos?: string;
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
  /** Fase 4: moneda del contrato (por defecto la del mercado del país, USD si no se indica). */
  moneda?: 'USD' | 'local';
  /** Fase 4: tecnologías admitidas (ausente = todas). */
  tecnologias?: string[];
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
  moneda: { codigo: string; usd_por_unidad: number; nombre?: string };
  /**
   * Fase 4: deriva real anual (tendencia del tipo de cambio real), volatilidad anual, reversión a la media y shocks
   * (devaluaciones: probabilidad anual y magnitud). Volatilidad 0 y deriva 0 = moneda fija al USD.
   */
  tipo_cambio: { deriva_anual: number; volatilidad_anual: number; reversion_anual?: number; shock_prob_anual?: number; shock_magnitud?: Dist };
  regulador?: string;
  operador_sistema?: string;
  mercado: {
    precio_spot_medio_usd_mwh: Dist;
    /** 12 multiplicadores (ene–dic) del precio spot medio. */
    perfil_spot_mensual: number[];
    demanda_anual_twh?: Dist;
    pico_mw?: Dist;
    matriz?: Record<string, number | string>;
    /** Fase 4: precio de las horas punta y valle respecto del medio (arbitraje de almacenamiento). */
    factor_punta?: number;
    factor_valle?: number;
    /** Moneda de los contratos de energía del país (por defecto USD). */
    moneda_contratos?: 'USD' | 'local';
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
    /** Fase 4: fracción de los costos de operación pagados en moneda local (expuestos al tipo de cambio). */
    fraccion_costos_locales?: number;
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
  // ───────────────────────── Fase 4 ─────────────────────────
  /** Inflación de los precios en USD (derivada al cargar: la local si la moneda está fija al USD, si no la de EE. UU.). */
  inflacion_usd_anual?: number;
  /** Costo de abrir presencia (constitución + representante legal). Ausente = no se puede abrir. */
  expansion?: { constitucion_usd: Dist; dias: Dist; representante_mensual_usd: Dist };
  /** Combustible por tipo de tecnología: índice de markets.yaml y factor del precio local. */
  combustibles?: Record<string, { indice: string; factor: number }>;
  /** Precio del carbono (USD/tCO2) y su crecimiento anual. */
  carbono?: { precio_usd_tco2: Dist; crecimiento_anual: number };
  /** Zona habilitada (p. ej. Texas/ERCOT dentro de EE. UU.). */
  zona?: { nombre: string; lat_min: number; lat_max: number; lon_min: number; lon_max: number };
  /** Tecnologías no permitidas por ley o política. */
  restricciones?: { tecnologias_prohibidas: string[]; motivo: string };
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
  /** Fase 4: moneda del contrato (por defecto la del mercado del país). */
  moneda?: 'USD' | 'local';
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
  /** Fase 4: países a los que se expande cuando los tiene investigados y le sobra caja. */
  expansion?: { paises: string[]; caja_min_usd: number };
}

export interface CandidateSiteDef { nombre: string; pais: string; tecnologia: string; lat: number; lon: number }

export interface CompetitorsDef {
  empresas: CompetitorDef[];
  sitios_candidatos: CandidateSiteDef[];
}

/** Fase 4: índices de combustibles y macro (markets.yaml). */
export interface FuelDef {
  id: string;
  nombre: string;
  /** Precio de referencia al inicio (USD/MMBtu). */
  precio_usd_mmbtu: Dist;
  volatilidad_anual: number;
  reversion_anual: number;
  min: number;
  max: number;
  /** Emisiones de combustión (kg CO2/MMBtu). */
  emisiones_kgco2_mmbtu: number;
}

export interface MarketsDef {
  inflacion_usd: Dist;
  combustibles: FuelDef[];
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
  /** Fase 4 (opcional): combustibles e inflación del USD. */
  markets?: MarketsDef;
}
