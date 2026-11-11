// Prueba de humo de la UI + capturas. Uso: npm run build && npm run screens
// Levanta `vite preview`, juega un poco (Fase 1: globo y capas; Fase 2: proyecto solar en Coclé)
// y guarda capturas en docs/capturas/. Falla si hay errores de consola.
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/node-tools/node_modules/playwright')); }
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'docs/capturas');
const PORT = Number(process.env.SCREENS_PORT ?? 4173);
// Penonomé (Coclé), en el Arco Seco de Panamá
const SITE = { lat: 8.62, lon: -80.3 };

const server = spawn(process.execPath, [join(ROOT, 'node_modules/vite/bin/vite.js'), 'preview', '--port', String(PORT), '--strictPort'], { cwd: join(ROOT, 'apps/game'), stdio: 'pipe' });
// el servidor muere con el script aunque falle una espera de Playwright
process.on('exit', () => server.kill());
let serverErr = '';
server.stderr.on('data', (d) => (serverErr += d));
await new Promise((res, rej) => {
  server.stdout.on('data', (d) => String(d).includes(String(PORT)) && res());
  server.on('exit', (code) => rej(new Error(`vite preview terminó (${code}): ${serverErr.trim()} — prueba con SCREENS_PORT=otro puerto`)));
});

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const fail = async (m) => { console.error('FALLO:', m); await browser.close(); server.kill(); process.exit(1); };
const errors = [];

// Una sola página para todo el recorrido: cargar el mundo y armar las texturas del globo en CPU (swiftshader)
// es lo más lento. Entre partes se vuelve al menú y se cambia el tamaño de la ventana.
// `?tex=4096&aa=0`: texturas del globo a 4096 px y sin antialias (en el juego real, 8192 px con antialias).
let shared = null;
async function newPage(width, height) {
  if (shared) {
    await toMenu(shared);
    await shared.setViewportSize({ width, height });
    await shared.waitForTimeout(500);
    return shared;
  }
  const page = await browser.newPage({ viewport: { width, height } });
  page.on('pageerror', (e) => errors.push(`[${page.viewportSize().width}] ${e.message}`));
  page.on('console', (m) => m.type() === 'error' && errors.push(`[${page.viewportSize().width}] ${m.text()}`));
  await page.goto(`http://localhost:${PORT}/?tex=4096&aa=0`);
  await page.getByText('Nueva partida').waitFor({ timeout: 30000 });
  await page.waitForTimeout(1200);
  shared = page;
  return page;
}

/** Vuelve al menú principal (cierra ventanas y sale de la partida). */
async function toMenu(page) {
  if (await page.getByText('Nueva partida').isVisible()) return;
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: 'Menú', exact: true }).click();
  page.once('dialog', (d) => d.accept());
  await page.getByRole('button', { name: 'Salir al menú principal' }).click();
  await page.getByText('Nueva partida').waitFor({ timeout: 10000 });
  await page.waitForTimeout(600);
}

const T0 = Date.now();
const shot = async (page, name) => { const t = Date.now(); await page.screenshot({ path: join(OUT, name) }); if (process.env.SCREENS_TIMING) console.log(`${((Date.now() - T0) / 1000).toFixed(1)} s · ${name} (${Date.now() - t} ms)`); };
const speed = async (page, label, ms) => { await page.getByRole('button', { name: label, exact: true }).click(); await page.waitForTimeout(ms); await page.getByRole('button', { name: '❚❚' }).click(); await page.waitForTimeout(300); };
const tab = (page, id) => page.locator(`[data-tab=${id}]`).first().click();

/** Captura la misma pantalla en 1280×800 y vuelve a 1600×960 (sin otra partida). */
async function at1280(page, name, before) {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.waitForTimeout(500);
  if (before) await before();
  await shot(page, name);
  await page.setViewportSize({ width: 1600, height: 960 });
  await page.waitForTimeout(400);
}

/** Nueva partida → celda en Coclé → proyecto solar de 10 MW → primer estudio. */
async function startProject(page, suffix) {
  await page.getByText('Nueva partida').click();
  await page.getByText('Fundar empresa').click();
  await page.waitForTimeout(3500);
  const vp = page.viewportSize();
  await page.evaluate(({ lat, lon }) => window.__voltaje.flyTo(lat, lon, 1.32, 0.1), SITE);
  await page.waitForTimeout(800);
  await page.mouse.click(vp.width / 2, vp.height / 2);
  await page.getByTestId('inspector').waitFor();
  const country = await page.getByTestId('inspector').locator('div').first().textContent();
  if (!country.includes('Panamá')) await fail('la celda elegida no es de Panamá: ' + country);
  await page.getByTestId('develop').click();
  await page.getByTestId('develop-dialog').waitFor();
  await page.getByTestId('mw').fill('10');
  await page.waitForTimeout(900);
  const txt = await page.getByTestId('develop-dialog').textContent();
  if (!txt.includes('TIR del capital')) await fail('la vista previa del sitio no cargó');
  await shot(page, `10-desarrollar${suffix}.png`);
  await at1280(page, `10-desarrollar-1280.png`);
  await page.getByTestId('create-project').click();
  await page.getByTestId('project-window').waitFor({ timeout: 5000 });
  await page.waitForTimeout(400);
  await tab(page, 'estudios');
  await page.waitForTimeout(300);
  await page.getByTestId('study-medicion_solar_satelital').click();
  await page.waitForTimeout(400);
  await page.getByTestId('study-prefactibilidad').click();
  await page.waitForTimeout(500);
  await shot(page, `11-estudios${suffix}.png`);
  await at1280(page, `11-estudios-1280.png`);
}

// SCREENS_ONLY=3 corre solo la parte de la Fase 3 (para iterar más rápido)
const ONLY = process.env.SCREENS_ONLY ?? '';

// ---------------------------------------------------------------- 1600×960: recorrido completo
if (!ONLY) {
  const page = await newPage(1600, 960);
  await shot(page, '01-menu.png');
  await page.getByText('Nueva partida').click();
  await page.getByText('Fundar empresa').click();
  await page.waitForTimeout(4500);
  await shot(page, '02-panama.png');

  await page.locator('[data-layer=ghi]').click();
  await page.mouse.click(800, 480);
  await page.getByTestId('inspector').waitFor();
  const country = await page.getByTestId('inspector').locator('div').first().textContent();
  if (!country.includes('Panamá')) await fail('la cámara no quedó sobre Panamá: ' + country);
  await page.waitForTimeout(500);
  await shot(page, '03-capa-solar.png');

  await page.locator('[data-layer=viento_tierra]').click();
  for (let i = 0; i < 4; i++) { await page.mouse.move(800, 480); await page.mouse.wheel(0, -300); await page.waitForTimeout(150); }
  await page.waitForTimeout(1200);
  await shot(page, '04-viento-cerca.png');

  const date0 = await page.getByTestId('date').textContent();
  const cash0 = await page.getByTestId('cash').textContent();
  await speed(page, '×8', 3000);
  const date1 = await page.getByTestId('date').textContent();
  const cash1 = await page.getByTestId('cash').textContent();
  if (date0 === date1) await fail('el tiempo no avanzó');
  if (cash0 === cash1) await fail('no se cobraron gastos fijos');
  console.log('Tiempo:', date0, '→', date1, '| caja:', cash0, '→', cash1);

  await page.locator('[data-layer=geotermia]').click();
  await page.mouse.wheel(0, 900);
  await page.waitForTimeout(1200);
  await shot(page, '05-geotermia.png');
  await page.getByRole('button', { name: 'Mapa base' }).click();

  // --- Fase 2: proyecto (en una partida nueva para empezar en 2026)
  await page.getByRole('button', { name: 'Menú', exact: true }).click();
  page.once('dialog', (d) => d.accept());
  await page.getByRole('button', { name: 'Salir al menú principal' }).click();
  await page.waitForTimeout(1200);
  await startProject(page, '');

  // avanzar ~6 meses
  await page.getByTestId('project-window').getByRole('button', { name: '✕' }).first().click();
  await speed(page, '×8', 6500);
  const nProjects = await page.evaluate(() => document.querySelectorAll('[data-nav=projects]').length);
  if (!nProjects) await fail('no está el acceso a Proyectos');

  // el sitio en el globo (de cerca) y clic en el marcador abre el proyecto
  await page.evaluate(({ lat, lon }) => window.__voltaje.flyTo(lat, lon, 1.12, 0.1), SITE);
  await page.waitForTimeout(1500);
  await shot(page, '12-sitio-globo.png');
  const pos = await page.evaluate(() => window.__voltaje.siteScreenPos('P1'));
  if (!pos) await fail('el sitio P1 no está en pantalla');
  await page.mouse.click(pos.x, pos.y);
  await page.getByTestId('project-window').waitFor({ timeout: 3000 });
  await page.waitForTimeout(500);
  await shot(page, '13-proyecto-resumen.png');
  await tab(page, 'estudios'); await page.waitForTimeout(300);
  await shot(page, '14-proyecto-estudios.png');
  await tab(page, 'permisos'); await page.waitForTimeout(300);
  await shot(page, '15-proyecto-permisos.png');
  await tab(page, 'comercial'); await page.waitForTimeout(300);
  await shot(page, '16-proyecto-comercial.png');
  await tab(page, 'construccion'); await page.waitForTimeout(300);
  await shot(page, '17-proyecto-construccion.png');
  await page.getByTestId('select-suppliers').click();
  await page.waitForTimeout(400);
  await tab(page, 'financiacion'); await page.waitForTimeout(700);
  await shot(page, '18-proyecto-financiacion.png');
  await tab(page, 'resumen'); await page.waitForTimeout(200);
  await page.getByTestId('viability').click();
  await page.getByTestId('viability-card').getByText('Prob. de llegar a operación').waitFor({ timeout: 30000 });
  await page.waitForTimeout(300);
  await shot(page, '19-viabilidad.png');

  await page.keyboard.press('Escape');
  await page.keyboard.press('p');
  await page.getByTestId('projects-panel').waitFor();
  await page.waitForTimeout(300);
  await shot(page, '20-proyectos.png');
  await page.keyboard.press('f');
  await page.getByTestId('finance-panel').waitFor();
  await page.waitForTimeout(600);
  await shot(page, '21-finanzas.png');
  await tab(page, 'pyg'); await page.waitForTimeout(300);
  await shot(page, '22-finanzas-pyg.png');
  await page.keyboard.press('e');
  await page.getByTestId('event-log').waitFor();
  const logRows = await page.locator('.log-row').count();
  if (logRows < 3) await fail(`el registro de eventos tiene ${logRows} filas`);
  await shot(page, '23-eventos.png');
  await page.keyboard.press('Escape');

  // 1280×800: pantallas clave del proyecto y finanzas
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.waitForTimeout(500);
  await page.keyboard.press('p');
  await page.locator('[data-project=P1]').click();
  await page.getByTestId('project-window').waitFor();
  await page.waitForTimeout(400);
  await shot(page, '13-proyecto-resumen-1280.png');
  await tab(page, 'permisos'); await page.waitForTimeout(300);
  await shot(page, '15-proyecto-permisos-1280.png');
  await tab(page, 'construccion'); await page.waitForTimeout(300);
  await shot(page, '17-proyecto-construccion-1280.png');
  await page.keyboard.press('f');
  await page.getByTestId('finance-panel').waitFor();
  await page.waitForTimeout(500);
  await shot(page, '21-finanzas-1280.png');
  await page.keyboard.press('Escape');
  await page.setViewportSize({ width: 1600, height: 960 });
  await page.waitForTimeout(400);

  // guardar → salir → continuar (el proyecto debe seguir)
  const dateS = await page.getByTestId('date').textContent();
  await page.getByRole('button', { name: 'Guardar', exact: true }).click();
  await page.locator('form').getByRole('button', { name: 'Guardar' }).click();
  await page.waitForTimeout(500);
  await shot(page, '06-guardar.png');
  // salir al menú y continuar desde la partida guardada (IndexedDB) en lugar de recargar la página: recargar
  // vuelve a armar las texturas del globo en CPU (~15 s)
  await toMenu(page);
  await page.getByText('Continuar').click();
  await page.waitForTimeout(1800);
  const date2 = await page.getByTestId('date').textContent();
  if (date2 !== dateS) await fail(`la carga no restauró la fecha (${date2} ≠ ${dateS})`);
  await page.keyboard.press('p');
  await page.locator('[data-project=P1]').waitFor({ timeout: 3000 });
  console.log('Guardado/carga OK:', date2, '· proyecto P1 restaurado');
}

// ---------------------------------------------------------------- Fase 3: mercado, oferta, I+D, competidores, proveedores
// Semilla 59: hay una licitación de energía de ETESA abierta en enero de 2026 (31 MW, adjudica en mayo).
const SEED = 59;
async function newSeeded(page) {
  await page.getByText('Nueva partida').click();
  await page.locator('form input[type=number]').fill(String(SEED));
  await page.getByText('Fundar empresa').click();
  await page.waitForTimeout(2500);
}
const key = async (page, k, testId) => { await page.keyboard.press(k); await page.getByTestId(testId).waitFor({ timeout: 5000 }).catch(() => fail(`no se abrió ${testId} con la tecla ${k}\n${errors.join('\n')}`)); await page.waitForTimeout(350); };

/** Abre el mercado, elige la primera oportunidad en la que se puede ofertar y arma la oferta. */
async function armBid(page, suffix = '') {
  await key(page, 'm', 'market-panel');
  const row = page.locator('[data-opp]', { hasText: 'Puedes ofertar' }).first();
  await row.waitFor({ timeout: 5000 }).catch(() => fail('no hay oportunidades en las que se pueda ofertar'));
  await row.click();
  await page.waitForTimeout(300);
  if (!suffix) await shot(page, '30-mercado.png');
  await page.getByTestId('open-bid').click();
  await page.getByTestId('bid-dialog').waitFor();
  await page.waitForFunction(() => !document.querySelector('[data-testid=bid-price]')?.textContent?.includes('—'), null, { timeout: 15000 });
  // margen bajo para competir en precio
  await page.getByTestId('bid-margin').fill('0.03');
  await page.waitForTimeout(700);
  await shot(page, `31-oferta${suffix}.png`);
}

if (!ONLY || ONLY === '3') {
  const page = await newPage(1600, 960);
  await newSeeded(page);
  // I+D: presupuesto y primera investigación
  await key(page, 'i', 'research-panel');
  await page.locator('[data-budget="100000"]').click();
  await page.locator('[data-node=contrato_ppa_corporativo]').click();
  await page.waitForTimeout(250);
  await page.getByTestId('research-start').click();
  await page.waitForTimeout(500);
  // la segunda queda en cola y seguirá en curso al llegar a la adjudicación
  await page.locator('[data-node=contrato_epc]').click();
  await page.waitForTimeout(250);
  await page.getByTestId('research-start').click();
  await page.waitForTimeout(400);
  const rd = await page.getByTestId('research-panel').textContent();
  if (!rd.includes('PPA corporativo')) await fail('la investigación no se inició');

  await armBid(page, '');
  // el mismo diálogo en 1280×800 (sin otra partida: solo se cambia el tamaño de la ventana)
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.waitForTimeout(700);
  await shot(page, '31-oferta-1280.png');
  await page.setViewportSize({ width: 1600, height: 960 });
  await page.waitForTimeout(500);
  await page.getByTestId('bid-dialog').getByRole('button', { name: 'Presentar oferta' }).click();
  await page.getByTestId('bid-dialog').getByRole('button', { name: 'Confirmar' }).click();
  await page.waitForTimeout(700);
  const card = await page.getByTestId('opp-card').textContent();
  if (!card.includes('Tu oferta')) await fail('la oferta no quedó presentada: ' + card.slice(0, 200));
  await shot(page, '32-oferta-enviada.png');

  // avanzar hasta la adjudicación (mayo de 2026)
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: '×8', exact: true }).click();
  await page.waitForFunction(() => /(mayo|junio|julio) de 2026/.test(document.querySelector('[data-testid=date]')?.textContent ?? ''), null, { timeout: 30000 });
  await page.waitForTimeout(1500);
  await page.getByRole('button', { name: '❚❚' }).click();
  await page.waitForTimeout(300);
  await key(page, 'm', 'market-panel');
  await page.locator('[data-tab=mias]').click();
  await page.locator('[data-mybid]').first().waitFor();
  const st = await page.locator('[data-mybid]').first().textContent();
  if (/Presentada/.test(st)) await fail('la oferta sigue sin adjudicar: ' + st);
  if (!(await page.getByTestId('ranking').isVisible())) await page.locator('[data-mybid]').first().click();
  await page.getByTestId('ranking').waitFor({ timeout: 3000 });
  await page.waitForTimeout(300);
  await shot(page, '33-resultado.png');
  console.log('Licitación:', st.replace(/\s+/g, ' ').slice(0, 120));

  await key(page, 'c', 'contracts-panel');
  await shot(page, '34-contratos.png');
  await key(page, 'i', 'research-panel');
  await shot(page, '35-investigacion.png');
  await key(page, 'r', 'competitors-panel');
  await page.waitForTimeout(300);
  await shot(page, '36-competidores.png');
  await key(page, 'v', 'suppliers-panel');
  await shot(page, '37-proveedores.png');
  await page.locator('[data-tab=precios]').click();
  await page.waitForTimeout(500);
  await shot(page, '38-proveedores-precios.png');
  await page.keyboard.press('Escape');
  const rivals = await page.evaluate(() => window.__voltaje.rivalSites());
  console.log('Plantas visibles de competidores:', rivals.length);
  if (rivals.length) {
    await page.evaluate(() => window.__voltaje.flyTo(8.4, -80.2, 1.22, 0.1));
    await page.waitForTimeout(1200);
    await shot(page, '39-rivales-globo.png');
  }
  await page.setViewportSize({ width: 1280, height: 800 });
  await key(page, 'i', 'research-panel');
  await page.waitForTimeout(400);
  await shot(page, '35-investigacion-1280.png');
}

// ---------------------------------------------------------------- Fase 4: países, catálogo, combustibles, otras tecnologías, líneas
// Atajo de prueba (como en las pruebas del motor): se edita la partida guardada para tener I+D de tecnologías y mercados
// y caja suficiente; el resto se juega con la UI.
const P4_NODES = ['tec_baterias', 'est_geofisica', 'tec_geotermica', 'tec_transmision', 'mercado_regional', 'tec_interconexion', 'mercado_costa_rica', 'mercado_colombia',
  'tec_hidro_pasada', 'tec_biomasa', 'contrato_potencia', 'tec_gas', 'est_batimetria', 'tec_eolica_marina', 'tec_eficiencia'];
/** Abre «Desarrollar» en el centro de la pantalla tras volar a (lat, lon) y elige la tecnología. */
async function developAt(page, lat, lon, techId, mw) {
  await page.evaluate(({ lat, lon }) => window.__voltaje.flyTo(lat, lon, 1.3, 0.1), { lat, lon });
  await page.waitForTimeout(700);
  // la celda se elige con el gancho (un clic en el centro podría caer sobre una planta rival)
  await page.evaluate(({ lat, lon }) => window.__voltaje.select(lat, lon), { lat, lon });
  await page.getByTestId('inspector').waitFor();
  await page.getByTestId('develop').click();
  await page.getByTestId('develop-dialog').waitFor();
  await page.locator(`[data-tech=${techId}]`).click();
  if (mw) await page.getByTestId('mw').fill(String(mw));
  await page.waitForTimeout(250);
}
async function waitPreview(page) {
  await page.getByTestId('site-preview').waitFor({ timeout: 15000 }).catch(async () => fail('sin vista previa: ' + (await page.getByTestId('develop-dialog').textContent()).slice(0, 400)));
  await page.waitForTimeout(700);
}
async function createAndClose(page) {
  await page.getByTestId('create-project').click();
  await page.getByTestId('project-window').waitFor({ timeout: 5000 }).catch(() => fail('el proyecto no se creó'));
  await page.waitForTimeout(300);
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
}

if (!ONLY || ONLY === '4') {
  const page = await newPage(1600, 960);
  await page.getByText('Nueva partida').click();
  await page.getByText('Fundar empresa').click();
  await page.waitForTimeout(2500);
  const text = await page.evaluate(() => window.__voltaje.saveText());
  const file = JSON.parse(text);
  file.state.business.research.completed.push(...P4_NODES.filter((n) => !file.state.business.research.completed.includes(n)));
  file.state.company.cashUsd = 40e6;
  await page.evaluate((t) => window.__voltaje.loadText(t), JSON.stringify(file));
  await page.waitForTimeout(2500);
  // unos meses para que haya historial de tipo de cambio y combustibles
  await speed(page, '×8', 4500);

  await key(page, 'x', 'countries-panel');
  await page.locator('[data-country=CRI]').waitFor();
  await shot(page, '40-paises.png');
  await page.locator('[data-country=CRI]').click();
  await page.getByTestId('country-sheet').waitFor({ timeout: 5000 }).catch(() => fail('no se abrió la ficha de Costa Rica'));
  await page.getByTestId('permit-tech').selectOption('hidro_pasada');
  await page.waitForTimeout(500);
  await shot(page, '41-ficha-pais.png');
  await page.getByTestId('permit-graph').scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  await shot(page, '42-permisos-grafo.png');
  await page.getByTestId('presence-card').scrollIntoViewIfNeeded();
  await page.getByTestId('open-presence').click();
  await page.getByTestId('presence-card').getByRole('button', { name: 'Confirmar' }).click();
  await page.waitForTimeout(800);
  const pc = await page.getByTestId('presence-card').textContent();
  if (!/trámite/.test(pc)) await fail('la presencia no quedó en trámite: ' + pc.slice(0, 200));
  await shot(page, '43-presencia.png');
  await at1280(page, '41-ficha-pais-1280.png');

  await key(page, 't', 'catalog-panel');
  await page.locator('[data-tech=geotermica]').first().waitFor({ timeout: 20000 }).catch(() => fail('el catálogo no cargó'));
  await page.locator('[data-tech=geotermica]').first().click();
  await page.waitForTimeout(400);
  await shot(page, '44-catalogo.png');
  await at1280(page, '44-catalogo-1280.png');
  await page.locator('[data-tab=lcoe]').click();
  await page.getByTestId('catalog-country').selectOption('CHL');
  await page.waitForTimeout(600);
  await shot(page, '45-catalogo-lcoe.png');

  await key(page, 'x', 'countries-panel');
  await page.locator('[data-tab=combustibles]').click();
  await page.getByTestId('fuels').waitFor();
  await page.waitForTimeout(500);
  await shot(page, '46-combustibles.png');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);

  // baterías cerca de la ciudad de Panamá
  await developAt(page, 9.05, -79.45, 'baterias', 40);
  await waitPreview(page);
  await shot(page, '47-desarrollar-baterias.png');
  await at1280(page, '47-desarrollar-baterias-1280.png');
  await createAndClose(page);
  // geotermia en el volcán Barú (Chiriquí)
  await developAt(page, 8.8, -82.55, 'geotermica', 20);
  await waitPreview(page);
  await shot(page, '48-desarrollar-geotermia.png');
  if (await page.getByTestId('create-project').isEnabled()) await createAndClose(page); else { console.log('Geotermia no disponible en el sitio de prueba'); await page.keyboard.press('Escape'); }

  // línea de transmisión Coclé → ciudad de Panamá con el punto final elegido en el globo
  await developAt(page, SITE.lat, SITE.lon, 'linea_transmision', 300);
  await page.getByTestId('pick-route').click();
  await page.getByTestId('route-banner').waitFor();
  await page.waitForTimeout(400);
  const end = await page.evaluate(() => window.__voltaje.geoScreenPos(9.0, -79.55));
  if (!end) await fail('el extremo de la línea no está en pantalla');
  await page.mouse.click(end.x, end.y);
  await waitPreview(page);
  await shot(page, '49-linea.png');
  await createAndClose(page);

  // más tecnologías (comandos directos) para ver modelos variados en el globo
  for (const c of [
    { techId: 'hidro_pasada', mw: 20, lat: 8.85, lon: -82.15 }, { techId: 'gas_natural', mw: 300, lat: 9.3, lon: -79.9 },
    { techId: 'biomasa', mw: 25, lat: 8.0, lon: -80.6 }, { techId: 'eolica_tierra', mw: 50, lat: 8.5, lon: -80.75 },
    { techId: 'eolica_marina', mw: 300, lat: 7.6, lon: -79.7 },
  ]) await page.evaluate((cmd) => window.__voltaje.command({ type: 'createProject', ...cmd }), c);
  await page.waitForTimeout(800);
  await page.keyboard.press('Escape');
  await page.evaluate(() => window.__voltaje.flyTo(8.75, -80.0, 1.16, 0.1));
  await page.waitForTimeout(1500);
  await shot(page, '50-linea-globo.png');
  await page.evaluate(() => window.__voltaje.flyTo(8.6, -80.9, 1.28, 0.1));
  await page.waitForTimeout(1500);
  await shot(page, '51-modelos-globo.png');
  await page.evaluate(() => window.__voltaje.flyTo(8.8, -82.4, 1.09, 0.1));
  await page.waitForTimeout(1500);
  await shot(page, '53-modelos-cerca.png');
  await page.evaluate(() => window.__voltaje.flyTo(5, -82, 2.4, 0.1));
  await page.waitForTimeout(1500);
  await shot(page, '52-paises-globo.png');
  const n = await page.evaluate(() => document.querySelector('[data-nav=projects]')?.textContent);
  console.log('Fase 4:', n);
}


if (errors.length) await fail('errores en consola:\n' + errors.join('\n'));
console.log('Capturas en docs/capturas/');
await browser.close();
server.kill();
process.exit(0);
