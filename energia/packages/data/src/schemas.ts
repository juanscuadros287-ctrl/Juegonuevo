import { z } from 'zod';

/** Un valor numérico real debe declarar su fuente o su supuesto. */
export const sourced = z
  .object({ base: z.number(), min: z.number().optional(), max: z.number().optional(), fuente: z.string().optional(), supuesto: z.string().optional() })
  .refine((v) => v.fuente || v.supuesto, { message: 'Falta "fuente" o "supuesto"' });

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

export const countrySchema = z.object({
  iso3: z.string().length(3),
  nombre: z.string(),
  iso_num: z.number().int(),
  moneda: z.object({ codigo: z.string(), nombre: z.string(), usd_por_unidad: z.number().positive() }),
  inflacion_anual: sourced,
  prima_riesgo_pais: sourced,
  regulador: z.string(),
  operador_sistema: z.string(),
  mercado: z.object({
    demanda_anual_twh: sourced,
    pico_mw: sourced,
    precio_spot_medio_usd_mwh: sourced,
    matriz: z.record(z.union([z.number(), z.string()])),
  }),
  notas: z.string().optional(),
});

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
