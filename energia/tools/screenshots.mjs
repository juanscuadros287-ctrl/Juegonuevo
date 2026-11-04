// Prueba de humo de la UI + capturas. Uso: npm run build && npm run screens
// Levanta `vite preview`, juega un poco y guarda capturas en docs/capturas/.
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'docs/capturas');
const PORT = 4173;

const server = spawn(process.execPath, [join(ROOT, 'node_modules/vite/bin/vite.js'), 'preview', '--port', String(PORT), '--strictPort'], { cwd: join(ROOT, 'apps/game'), stdio: 'pipe' });
await new Promise((res) => server.stdout.on('data', (d) => String(d).includes(String(PORT)) && res()));

const fail = (m) => { console.error('FALLO:', m); server.kill(); process.exit(1); };
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
try {
  const page = await browser.newPage({ viewport: { width: 1600, height: 960 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  await page.goto(`http://localhost:${PORT}/`);
  await page.getByText('Nueva partida').waitFor({ timeout: 30000 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: join(OUT, '01-menu.png') });

  await page.getByText('Nueva partida').click();
  await page.getByText('Fundar empresa').click();
  await page.waitForTimeout(4500);
  await page.screenshot({ path: join(OUT, '02-panama.png') });

  // capa solar y clic sobre Panamá (centro de la pantalla tras el vuelo)
  await page.locator('[data-layer=ghi]').click();
  await page.mouse.click(800, 480);
  await page.getByTestId('inspector').waitFor();
  const country = await page.getByTestId('inspector').locator('div').first().textContent();
  if (!country.includes('Panamá')) fail('la cámara no quedó sobre Panamá: ' + country);
  await page.waitForTimeout(500);
  await page.screenshot({ path: join(OUT, '03-capa-solar.png') });

  await page.locator('[data-layer=viento_tierra]').click();
  for (let i = 0; i < 4; i++) { await page.mouse.move(800, 480); await page.mouse.wheel(0, -300); await page.waitForTimeout(150); }
  await page.waitForTimeout(1200);
  await page.screenshot({ path: join(OUT, '04-viento-cerca.png') });

  // tiempo: ×8 durante 3 s
  const date0 = await page.getByTestId('date').textContent();
  const cash0 = await page.getByTestId('cash').textContent();
  await page.getByRole('button', { name: '×8' }).click();
  await page.waitForTimeout(3000);
  await page.getByRole('button', { name: '❚❚' }).click();
  const date1 = await page.getByTestId('date').textContent();
  const cash1 = await page.getByTestId('cash').textContent();
  if (date0 === date1) fail('el tiempo no avanzó');
  if (cash0 === cash1) fail('no se cobraron gastos fijos');
  console.log('Tiempo:', date0, '→', date1, '| caja:', cash0, '→', cash1);

  await page.locator('[data-layer=geotermia]').click();
  await page.mouse.wheel(0, 900);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: join(OUT, '05-geotermia.png') });

  // guardar → recargar → continuar
  await page.getByRole('button', { name: 'Guardar', exact: true }).click();
  await page.locator('form').getByRole('button', { name: 'Guardar' }).click();
  await page.waitForTimeout(500);
  await page.screenshot({ path: join(OUT, '06-guardar.png') });
  await page.reload();
  await page.getByText('Continuar').click();
  await page.waitForTimeout(1500);
  const date2 = await page.getByTestId('date').textContent();
  if (date2 !== date1) fail(`la carga no restauró la fecha (${date2} ≠ ${date1})`);
  console.log('Guardado/carga OK:', date2);
  if (errors.length) fail('errores en consola:\n' + errors.join('\n'));
  console.log('Capturas en docs/capturas/');
} finally {
  await browser.close();
  server.kill();
}

process.exit(0);
