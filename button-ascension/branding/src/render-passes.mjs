// Renders a 512x512 image for every game pass and OP crate into branding/passes/.
// Usage (from the button-ascension folder):
//   NODE_PATH=$(npm root -g) node branding/src/render-passes.mjs
// Needs Playwright with a Chromium browser (npm i -g playwright && npx playwright install chromium).
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const { chromium } = createRequire(import.meta.url)("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, "..", "passes");
fs.mkdirSync(out, { recursive: true });

const keys = [
	"auto_clicker",
	"op_auto_clicker",
	"double_sparks",
	"triple_sparks",
	"double_gems",
	"lucky",
	"super_luck",
	"fast_crates",
	"vip",
	"op_crate",
	"mega_op_crate",
	"ultra_op_crate",
	"rainbow_chest",
];

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const page = await browser.newPage({ viewport: { width: 512, height: 512 }, deviceScaleFactor: 1 });
for (const key of keys) {
	await page.goto("file://" + path.join(here, "pass-icon.html") + "#" + key);
	await page.reload();
	await page.evaluate(() => document.fonts.ready);
	await page.screenshot({ path: path.join(out, `${key}.png`), clip: { x: 0, y: 0, width: 512, height: 512 } });
	console.log(`rendered passes/${key}.png`);
}
await browser.close();
