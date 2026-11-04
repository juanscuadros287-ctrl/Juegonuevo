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
const PORT = 4173;
// Penonomé (Coclé), en el Arco Seco de Panamá
const SITE = { lat: 8.62, lon: -80.3 };

const server = spawn(process.execPath, [join(ROOT, 'node_modules/vite/bin/vite.js'), 'preview', '--port', String(PORT), '--strictPort'], { cwd: join(ROOT, 'apps/game'), stdio: 'pipe' });
await new Promise((res) => server.stdout.on('data', (d) => String(d).includes(String(PORT)) && res()));

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

const shot = (page, name) => page.screenshot({ path: join(OUT, name) });
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

// ---------------------------------------------------------------- 1600×960: recorrido completo
{
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
{
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

if (errors.length) await fail('errores en consola:\n' + errors.join('\n'));
console.log('Capturas en docs/capturas/');
await browser.close();
server.kill();
process.exit(0);
