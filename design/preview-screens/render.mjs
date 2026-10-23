// Renders the preview screens: each page in this folder as a 1440 by 900 point display at 2x, once
// per variant, into ErstPreview's resources, with the lines of text a screen reader of pixels would
// find on it. Run \`npm install\` here once, then \`node render.mjs [page ...]\`; CHROME overrides the
// browser.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '../../app/Sources/ErstPreview/Screens');
const manifestPath = path.join(out, 'screens.json');
const browserPath = process.env.CHROME ?? '/Applications/Helium.app/Contents/MacOS/Helium';
const pages = process.argv.length > 2
  ? process.argv.slice(2)
  : (await readdir(here)).filter((name) => name.endsWith('.html')).map((name) => name.slice(0, -5));

// Lines as text recognition reads them: words on one baseline join until a gap wider than about
// a space and a half, which splits columns, labels, and buttons apart.
function readLines() {
  const width = innerWidth, height = innerHeight;
  const words = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  for (let node; (node = walker.nextNode());) {
    const element = node.parentElement;
    if (!element || element.closest('svg, style, script, [data-no-text]')) continue;
    if (!element.checkVisibility({ opacityProperty: true, visibilityProperty: true })) continue;
    const size = parseFloat(getComputedStyle(element).fontSize);
    const pattern = /\S+/g;
    for (let match; (match = pattern.exec(node.textContent));) {
      range.setStart(node, match.index);
      range.setEnd(node, match.index + match[0].length);
      const r = range.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) continue;
      const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      if (cx < 0 || cy < 0 || cx > width || cy > height) continue;
      const hit = document.elementFromPoint(cx, cy);
      if (!hit || !(hit === element || element.contains(hit) || hit.contains(element))) continue;
      words.push({ text: match[0], left: r.left, top: r.top, right: r.right, bottom: r.bottom, size });
    }
  }
  const center = (w) => (w.top + w.bottom) / 2;
  words.sort((a, b) => center(a) - center(b));
  const rows = [];
  for (const word of words) {
    const row = rows[rows.length - 1];
    if (row && Math.abs(center(word) - row.center) < 0.3 * Math.min(word.size, row.size)) row.words.push(word);
    else rows.push({ center: center(word), size: word.size, words: [word] });
  }
  const lines = [];
  for (const row of rows) {
    row.words.sort((a, b) => a.left - b.left);
    let line = null;
    for (const word of row.words) {
      const gap = line ? word.left - line.right : Infinity;
      const sameSize = line && Math.max(word.size, line.size) / Math.min(word.size, line.size) < 1.25;
      if (line && sameSize && gap < 0.85 * word.size) {
        line.text += (gap > 0.12 * word.size ? ' ' : '') + word.text;
        line.right = Math.max(line.right, word.right);
        line.top = Math.min(line.top, word.top);
        line.bottom = Math.max(line.bottom, word.bottom);
      } else {
        line = { ...word };
        lines.push(line);
      }
    }
  }
  const round = (value) => Math.round(Math.min(Math.max(value, 0), 1) * 1e5) / 1e5;
  return lines
    .filter((line) => /[\p{L}\p{N}]/u.test(line.text))
    .map((line) => ({
      text: line.text,
      box: [round(line.left / width), round(line.top / height),
        round((line.right - line.left) / width), round((line.bottom - line.top) / height)],
    }));
}

const manifest = existsSync(manifestPath) ? JSON.parse(await readFile(manifestPath, 'utf8')) : {};
const scratch = await mkdtemp(path.join(tmpdir(), 'erst-screens-'));
const browser = await puppeteer.launch({ executablePath: browserPath, headless: true });
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });
  page.on('pageerror', (error) => console.error(error.message));
  for (const name of pages) {
    await page.goto(pathToFileURL(path.join(here, name + '.html')).href, { waitUntil: 'load' });
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.images].map((image) => image.decode().catch(() => {})));
    });
    const count = await page.evaluate(() => window.variants ?? 1);
    const variants = [];
    for (let index = 0; index < count; index++) {
      await page.evaluate((i) => window.variant?.(i), index);
      await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
      const lines = await page.evaluate(readLines);
      const png = path.join(scratch, name + '.png');
      await page.screenshot({ path: png });
      const image = name + '-' + index + '.webp';
      execFileSync('cwebp', ['-quiet', '-q', '90', '-m', '6', '-sharp_yuv', png, '-o', path.join(out, image)]);
      variants.push({ image, lines });
    }
    manifest[name] = variants;
    console.log(name, count, 'variants', variants.map((v) => v.lines.length).join('/'), 'lines');
  }
} finally {
  await browser.close();
  await rm(scratch, { recursive: true, force: true });
}
const ordered = Object.fromEntries(Object.keys(manifest).sort().map((key) => [key, manifest[key]]));
await writeFile(manifestPath, JSON.stringify(ordered) + '\n');
