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

async function newPage(width, height) {
  const page = await browser.newPage({ viewport: { width, height } });
  page.on('pageerror', (e) => errors.push(`[${width}] ${e.message}`));
  page.on('console', (m) => m.type() === 'error' && errors.push(`[${width}] ${m.text()}`));
  await page.goto(`http://localhost:${PORT}/`);
  await page.getByText('Nueva partida').waitFor({ timeout: 30000 });
  await page.waitForTimeout(1200);
  return page;
}

const T0 = Date.now();
const shot = async (page, name) => { const t = Date.now(); await page.screenshot({ path: join(OUT, name) }); if (process.env.SCREENS_TIMING) console.log(`${((Date.now() - T0) / 1000).toFixed(1)} s · ${name} (${Date.now() - t} ms)`); };
const speed = async (page, label, ms) => { await page.getByRole('button', { name: label, exact: true }).click(); await page.waitForTimeout(ms); await page.getByRole('button', { name: '❚❚' }).click(); await page.waitForTimeout(300); };
const tab = (page, id) => page.locator(`[data-tab=${id}]`).first().click();

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
  await page.getByTestId('viability-card').getByText('Probabilidad de llegar a operación').waitFor({ timeout: 30000 });
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

  // guardar → recargar → continuar (el proyecto debe seguir)
  const dateS = await page.getByTestId('date').textContent();
  await page.getByRole('button', { name: 'Guardar', exact: true }).click();
  await page.locator('form').getByRole('button', { name: 'Guardar' }).click();
  await page.waitForTimeout(500);
  await shot(page, '06-guardar.png');
  await page.reload();
  await page.getByText('Continuar').click();
  await page.waitForTimeout(1800);
  const date2 = await page.getByTestId('date').textContent();
  if (date2 !== dateS) await fail(`la carga no restauró la fecha (${date2} ≠ ${dateS})`);
  await page.keyboard.press('p');
  await page.locator('[data-project=P1]').waitFor({ timeout: 3000 });
  console.log('Guardado/carga OK:', date2, '· proyecto P1 restaurado');
  await page.close();
}

// ---------------------------------------------------------------- 1280×800: pantallas clave
if (!ONLY) {
  const page = await newPage(1280, 800);
  await startProject(page, '-1280');
  await page.getByTestId('project-window').getByRole('button', { name: '✕' }).first().click();
  await speed(page, '×8', 4000);
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
  await page.close();
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
async function armBid(page, suffix) {
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
  const rd = await page.getByTestId('research-panel').textContent();
  if (!rd.includes('PPA corporativo')) await fail('la investigación no se inició');

  await armBid(page, '');
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
  await page.close();
}

if (!ONLY || ONLY === '3') {
  const page = await newPage(1280, 800);
  await newSeeded(page);
  await armBid(page, '-1280');
  await page.keyboard.press('Escape');
  await page.keyboard.press('i');
  await page.getByTestId('research-panel').waitFor();
  await page.waitForTimeout(400);
  await shot(page, '35-investigacion-1280.png');
  await page.close();
}

if (errors.length) await fail('errores en consola:\n' + errors.join('\n'));
console.log('Capturas en docs/capturas/');
await browser.close();
server.kill();
process.exit(0);
