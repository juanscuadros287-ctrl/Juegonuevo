import { describe, expect, it } from 'vitest';
import { gameData, buildGameData, anchorsSchema, DataError, rawGameData } from '../src';
import anclas from '../resources/anclas.yaml';
import game from '../game.yaml';
import layers from '../layers.yaml';

describe('Datos del juego', () => {
  it('todos los YAML cumplen su esquema', () => {
    expect(gameData.game.pais_inicial).toBe('PAN');
    expect(gameData.countries.PAN.nombre).toBe('Panamá');
    expect(gameData.layers.length).toBeGreaterThanOrEqual(7);
    expect(anchorsSchema.safeParse(anclas).success).toBe(true);
  });

  it('un valor sin fuente ni supuesto es rechazado', () => {
    const bad = structuredClone(gameData.countries.PAN) as any;
    delete bad.inflacion_anual.fuente;
    expect(() => buildGameData({ game, layers, countries: { 'PAN.yaml': bad } })).toThrow(DataError);
  });

  it('el país inicial debe existir', () => {
    expect(() => buildGameData({ game: { ...(game as object), pais_inicial: 'XXX' }, layers, countries: {} })).toThrow(/país inicial/);
  });
});

/** Todos los YAML (claves = nombre del archivo) para pruebas que modifican datos. */
const base = (o: Record<string, unknown>) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k.split('/').pop()!, v]));
const allRaw = () => structuredClone({ ...rawGameData, countries: base(rawGameData.countries), technologies: base(rawGameData.technologies) }) as any;

describe('Datos de la Fase 2', () => {
  const raw = allRaw;

  it('tecnologías, estudios, proveedores y Panamá cargan y se cruzan bien', () => {
    const d = gameData.simData;
    expect(Object.keys(d.technologies)).toEqual(expect.arrayContaining(['eolica_tierra', 'solar_fv']));
    expect(Object.keys(d.technologies).length).toBeGreaterThanOrEqual(20); // Fase 4
    expect(Object.keys(d.studies).length).toBeGreaterThanOrEqual(9);
    expect(Object.values(d.suppliers).filter((s) => s.tipo === 'epc').length).toBeGreaterThanOrEqual(2);
    for (const t of ['solar_fv', 'eolica_tierra']) {
      expect(Object.values(d.suppliers).filter((s) => s.tipo === 'equipos' && s.tecnologias.includes(t)).length).toBeGreaterThanOrEqual(2);
    }
    const p = d.countries.PAN;
    expect(p.impuestos.renta.base).toBe(0.25);
    expect(p.permisos.map((x) => x.autoridad).join(' ')).toMatch(/MiAmbiente.*ETESA|ETESA.*MiAmbiente/);
    expect(p.permisos.some((x) => x.autoridad === 'ASEP')).toBe(true);
    expect(p.ppa.canales.map((c) => c.id)).toEqual(['licitacion_etesa', 'gran_cliente']);
    expect(p.finanzas.prestamistas.map((l) => l.tipo).sort()).toEqual(['comercial', 'desarrollo']);
    expect(buildGameData(raw()).simData.technologies.solar_fv.capex_usd_kw.base).toBe(d.technologies.solar_fv.capex_usd_kw.base);
  });

  it('rangos realistas de CAPEX (IRENA/NREL)', () => {
    const d = gameData.simData.technologies;
    expect(d.solar_fv.capex_usd_kw.base).toBeGreaterThan(600);
    expect(d.solar_fv.capex_usd_kw.base).toBeLessThan(1500);
    expect(d.eolica_tierra.capex_usd_kw.base).toBeGreaterThan(1000);
    expect(d.eolica_tierra.capex_usd_kw.base).toBeLessThan(2200);
  });

  it('rechaza un CAPEX sin fuente', () => {
    const r = raw(); delete r.technologies['solar_fv.yaml'].capex_usd_kw.fuente;
    expect(() => buildGameData(r)).toThrow(/solar_fv.yaml[\s\S]*capex_usd_kw/);
  });

  it('rechaza probabilidades que no suman 1', () => {
    const r = raw(); r.countries['PAN.yaml'].permisos[0].prob.aprobado = 0.5;
    expect(() => buildGameData(r)).toThrow(/sumar 1/);
    const r2 = raw(); r2.studies.estudios[4].resultados.peor = 0.5;
    expect(() => buildGameData(r2)).toThrow(/sumar 1/);
  });

  it('rechaza hitos que no suman 1 y min > base', () => {
    const r = raw(); r.technologies['eolica_tierra.yaml'].hitos_construccion[0].fraccion = 0.5;
    expect(() => buildGameData(r)).toThrow(/hitos/);
    const r2 = raw(); r2.technologies['solar_fv.yaml'].vida_util_anos.min = 50;
    expect(() => buildGameData(r2)).toThrow(/min ≤ base/);
  });

  it('rechaza referencias rotas entre archivos', () => {
    const r = raw(); r.countries['PAN.yaml'].permisos[0].requiere.permisos = ['no_existe'];
    expect(() => buildGameData(r)).toThrow(/no_existe/);
    const r2 = raw(); r2.studies.estudios[4].hallazgos = ['ovni'];
    expect(() => buildGameData(r2)).toThrow(/ovni/);
    const r3 = raw(); r3.technologies['solar_fv.yaml'].estudios_requeridos.push('astrologia');
    expect(() => buildGameData(r3)).toThrow(/astrologia/);
  });
});

describe('Datos de la Fase 3', () => {
  const raw = allRaw;

  it('I+D, clientes, competidores y dinámica de proveedores cargan y se cruzan bien', () => {
    const d = gameData.simData;
    expect(d.research!.nodos.length).toBeGreaterThanOrEqual(30);
    for (const r of ['tecnologias', 'estudios', 'mercados', 'contratos', 'eficiencia']) expect(d.research!.nodos.some((n) => n.rama === r)).toBe(true);
    expect(d.research!.nodos.filter((n) => n.inicial).map((n) => n.id).sort()).toEqual(['contrato_ppa_simple', 'est_basicos', 'mercado_panama', 'tec_eolica_tierra', 'tec_solar_fv']);
    expect(d.competitors!.empresas.length).toBeGreaterThanOrEqual(3);
    expect(d.competitors!.empresas.length).toBeLessThanOrEqual(5);
    expect(new Set(d.competitors!.empresas.map((c) => c.estrategia)).size).toBe(d.competitors!.empresas.length);
    expect(d.clients!.tipos.some((t) => t.tipo === 'licitacion_publica')).toBe(true);
    expect(new Set(d.clients!.tipos.map((t) => t.contrato))).toEqual(new Set(['ppa', 'potencia', 'epc', 'bot']));
    expect(d.supply!.materiales.map((m) => m.id).sort()).toEqual(['acero', 'cobre', 'polisilicio']);
    for (const t of ['equipos', 'epc', 'inversores', 'logistica']) expect(Object.values(d.suppliers).some((s) => s.tipo === t)).toBe(true);
    expect(buildGameData(raw()).simData.research!.nodos.length).toBe(d.research!.nodos.length);
  });

  it('rechaza ciclos y prerrequisitos inexistentes en el árbol de I+D', () => {
    const r = raw(); r.research.nodos.find((n: any) => n.id === 'contrato_ppa_corporativo').requiere = ['contrato_potencia'];
    expect(() => buildGameData(r)).toThrow(/ciclo/);
    const r2 = raw(); r2.research.nodos[5].requiere = ['magia'];
    expect(() => buildGameData(r2)).toThrow(/magia/);
  });

  it('rechaza tecnologías sin modelo si el nodo no declara fase_modelo, y nodos sin fuente', () => {
    const r = raw(); delete r.technologies['geotermica.yaml'];
    expect(() => buildGameData(r)).toThrow(/geotermica/);
    const r2 = raw(); delete r2.research.nodos.find((n: any) => n.id === 'ef_permisos').supuesto;
    expect(() => buildGameData(r2)).toThrow(/fuente|supuesto/);
  });

  it('rechaza pesos de evaluación que no suman 1 y tipos de contrato que nadie habilita', () => {
    const r = raw(); r.clients.tipos[0].pesos.precio = 0.9;
    expect(() => buildGameData(r)).toThrow(/sumar 1/);
    const r2 = raw(); r2.clients.tipos[0].tipo_contrato = 'trueque';
    expect(() => buildGameData(r2)).toThrow(/trueque/);
    const r3 = raw(); delete r3.clients.tipos[0].precio_referencia.supuesto;
    expect(() => buildGameData(r3)).toThrow(/precio_referencia/);
  });

  it('rechaza competidores con tecnologías o prioridades inexistentes y curvas con materiales desconocidos', () => {
    const r = raw(); r.competitors.empresas[0].tecnologias = ['fusion'];
    expect(() => buildGameData(r)).toThrow(/fusion/);
    const r2 = raw(); r2.competitors.empresas[0].investigacion.prioridades = ['teletransporte'];
    expect(() => buildGameData(r2)).toThrow(/teletransporte/);
    const r3 = raw(); r3.suppliers.curvas_aprendizaje[0].exposicion = { unobtainium: 0.2 };
    expect(() => buildGameData(r3)).toThrow(/unobtainium/);
    const r4 = raw(); r4.suppliers.proveedores[0].tipo = 'magia';
    expect(() => buildGameData(r4)).toThrow(DataError);
  });
});
