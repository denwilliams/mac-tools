#!/usr/bin/env node
// Development-only screenshot capture. Requires playwright-core and a compatible
// Firefox browser; not used by app builds and not a macOS integration check.
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { firefox } = require('playwright-core');

async function main() {
  const directory = path.resolve(__dirname, '../assets/previews');
  const browser = await firefox.launch({
    headless: true,
    ...(process.env.ICON_PREVIEW_BROWSER
      ? { executablePath: process.env.ICON_PREVIEW_BROWSER }
      : {}),
  });
  try {
    for (const [name, width, height] of [['desktop', 1100, 740], ['mobile', 390, 844]]) {
      const page = await browser.newPage({
        viewport: { width, height }, deviceScaleFactor: 1,
        colorScheme: 'light', locale: 'en-US',
      });
      await page.goto(pathToFileURL(path.join(directory, 'index.html')).href);
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map(image => image.decode()));
      });
      const evidence = await page.evaluate(() => ({
        deviceScaleFactor: window.devicePixelRatio,
        overflowing: document.documentElement.scrollWidth > window.innerWidth,
        images: [...document.images].map(image => ({
          width: image.getBoundingClientRect().width,
          height: image.getBoundingClientRect().height,
          naturalWidth: image.naturalWidth,
          naturalHeight: image.naturalHeight,
        })),
      }));
      assert.equal(evidence.deviceScaleFactor, 1);
      assert.equal(evidence.overflowing, false);
      assert.equal(evidence.images.length, 8);
      for (const image of evidence.images) {
        assert.equal(image.width, image.naturalWidth);
        assert.equal(image.height, image.naturalHeight);
      }
      await page.screenshot({ path: path.join(directory, `${name}.png`), fullPage: true, animations: 'disabled' });
      console.log(`${name}: all eight PNGs loaded at native size; no overflow; screenshot saved`);
      await page.close();
    }
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
