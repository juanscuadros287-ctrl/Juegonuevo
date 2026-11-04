// Capturas de los modelos 3D. Uso (desde energia/): npm run build && node apps/game/src/models/tools/capturas.mjs [filtro]
// Levanta `vite preview`, abre models.html y guarda imágenes en docs/capturas/modelos/.
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdirSync } from 'node:fs';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../../../../..');
const OUT = join(ROOT, 'docs/capturas/modelos');
const PORT = 4199;
const filter = process.argv[2] ?? '';
mkdirSync(OUT, { recursive: true });

const server = spawn(process.execPath, [join(ROOT, 'node_modules/vite/bin/vite.js'), 'preview', '--port', String(PORT), '--strictPort'], { cwd: join(ROOT, 'apps/game'), stdio: 'pipe' });
await new Promise((res) => server.stdout.on('data', (d) => String(d).includes(String(PORT)) && res()));
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
let failed = false;
try {
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  await page.goto(`http://localhost:${PORT}/models.html`);
  await page.waitForFunction(() => window.__preview && window.__preview.frames() > 2, null, { timeout: 30000 });
  const sw = await page.evaluate(() => window.__preview.sweep());
  console.log('Barrido:', sw.n, 'estados', sw.errors.length ? 'ERRORES: ' + sw.errors.join(' | ') : 'sin errores');
  if (sw.errors.length) failed = true;
  const shot = async (name, params, wait = 900) => {
    if (filter && !name.includes(filter)) return;
    await page.evaluate((p) => window.__preview.set({ ui: false, ...p }), params);
    await page.waitForTimeout(wait);
    await page.screenshot({ path: join(OUT, name + '.png') });
    const st = await page.evaluate(() => window.__preview.stats());
    console.log(name.padEnd(36), JSON.stringify(st));
  };
  for (const stage of ['operacion', 'prospeccion', 'estudios', 'falla', 'abandonado']) await shot(`todas-${stage}`, { mode: 'cuadricula', stage, progress: 0.5, detail: 2, capMul: 1 });
  await shot('todas-construccion-050', { mode: 'cuadricula', stage: 'construccion', progress: 0.5 });
  await shot('todas-detalle1', { mode: 'cuadricula', stage: 'operacion', detail: 1 });
  await shot('todas-detalle0', { mode: 'cuadricula', stage: 'operacion', detail: 0 });
  for (const kind of ['solar_fv', 'eolica_tierra', 'geotermica', 'hidro_embalse']) await shot(`construccion-${kind}`, { mode: 'secuencia', kind, detail: 2 });
  for (const kind of ['solar_fv', 'eolica_tierra', 'nuclear', 'eolica_mar', 'hidro_embalse', 'geotermica']) await shot(`etapas-${kind}`, { mode: 'etapas', kind, progress: 0.5, detail: 2 });
  await shot('globo-operacion', { mode: 'globo', stage: 'operacion', detail: 2 }, 1500);
  if (errors.length) { console.error('ERRORES:', errors); failed = true; }
} finally {
  await browser.close();
  server.kill();
}
process.exit(failed ? 1 : 0);
