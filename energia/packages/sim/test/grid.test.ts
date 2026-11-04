import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ResourceGrid, type GridMeta } from '../src';

const dir = join(__dirname, '../../data/generated');
const grid = new ResourceGrid(JSON.parse(readFileSync(join(dir, 'grid.json'), 'utf8')) as GridMeta, readFileSync(join(dir, 'grid.bin')));
const v = (layer: string, lat: number, lon: number) => grid.valueAt(layer, grid.indexOf(lat, lon));

describe('Grilla de recursos', () => {
  it('ubica países correctamente', () => {
    expect(grid.cell(8.75, -80.0).country?.code).toBe('PAN');
    expect(grid.cell(4.6, -74.1).country?.code).toBe('COL');
    expect(grid.cell(48.9, 2.35).country?.code).toBe('FRA');
    expect(grid.cell(0, -30).land).toBe(false);
  });

  it('Panamá tiene celdas suficientes y valores realistas', () => {
    const cells = grid.cellsOfCountry('PAN');
    expect(cells.length).toBeGreaterThan(15);
    for (const i of cells) {
      const ghi = grid.valueAt('ghi', i);
      expect(ghi).toBeGreaterThan(3.8); // Global Solar Atlas: Panamá ≈ 4,2–5,6 kWh/m²/día
      expect(ghi).toBeLessThan(6.0);
    }
  });

  it('órdenes de magnitud coherentes con los atlas', () => {
    expect(v('ghi', 24, 10)).toBeGreaterThan(5.8); // Sahara
    expect(v('ghi', -23.5, -69)).toBeGreaterThan(6.5); // Atacama
    expect(v('ghi', 52.5, 13.4)).toBeLessThan(3.4); // Berlín
    expect(v('viento_tierra', -46, -68)).toBeGreaterThan(9); // Patagonia
    expect(v('viento_tierra', -3, -60)).toBeLessThan(4.5); // Amazonas
    expect(v('viento_mar', 55.5, 3.5)).toBeGreaterThan(9); // Mar del Norte
    expect(v('geotermia', 64.8, -18)).toBeGreaterThan(180); // Islandia
    expect(v('geotermia', 52, 19)).toBeLessThan(80); // Polonia
    expect(v('lluvia', 24, 10)).toBeLessThan(150);
    expect(v('biomasa', -3, -60)).toBeGreaterThan(1800);
    expect(v('biomasa', 24, 10)).toBeLessThan(300);
    expect(v('hidro', -12, -75)).toBeGreaterThan(v('hidro', 52.5, 13.4)); // Andes > llanura alemana
  });

  it('las capas de tierra son cero en el mar y viceversa', () => {
    const sea = grid.indexOf(0, -30);
    expect(grid.valueAt('ghi', sea)).toBe(0);
    expect(grid.valueAt('viento_mar', grid.indexOf(48.9, 2.35))).toBe(0);
  });
});
