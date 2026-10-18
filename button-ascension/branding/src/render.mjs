// Renders the branding HTML files to PNG at their exact Roblox sizes.
// Usage (from the button-ascension folder):
//   NODE_PATH=$(npm root -g) node branding/src/render.mjs [icon.html ...]
// Needs Playwright with a Chromium browser (npm i -g playwright && npx playwright install chromium).
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const { chromium } = createRequire(import.meta.url)("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, "..");

const jobs = [
	{ file: "icon.html", png: "icon.png", width: 512, height: 512 },
	{ file: "thumbnail.html", png: "thumbnail.png", width: 1920, height: 1080 },
	{ file: "thumbnail-crates.html", png: "thumbnail-crates.png", width: 1920, height: 1080 },
];

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const only = process.argv.slice(2);
for (const job of jobs) {
	if (!fs.existsSync(path.join(here, job.file)) || (only.length > 0 && !only.includes(job.file))) {
		continue;
	}
	const page = await browser.newPage({ viewport: { width: job.width, height: job.height }, deviceScaleFactor: 1 });
	await page.goto("file://" + path.join(here, job.file));
	await page.evaluate(() => document.fonts.ready);
	await page.screenshot({ path: path.join(out, job.png), clip: { x: 0, y: 0, width: job.width, height: job.height } });
	await page.close();
	console.log(`rendered ${job.png} (${job.width}x${job.height})`);
}
await browser.close();
