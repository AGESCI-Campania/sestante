// PDF di docs/AIUTO-ACCESSO.md (con le immagini di docs/img/aiuto-accesso/), da distribuire agli utenti.
// Istruzioni in scripts/screenshot-guida/README.md.
//
// Uso: node pdf.mjs <percorso-del-repo>   → scrive docs/AIUTO-ACCESSO.pdf
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { chromium } from 'playwright';
import { marked } from 'marked';
import { gfmHeadingId } from 'marked-gfm-heading-id';

const REPO = process.argv[2];
const DOCS = `${REPO}/docs`;

marked.use(gfmHeadingId());
const corpo = marked.parse(readFileSync(`${DOCS}/AIUTO-ACCESSO.md`, 'utf8'));
const logo = pathToFileURL(`${REPO}/resources/logo.png`).href;

const html = `<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<base href="${pathToFileURL(`${DOCS}/`).href}">
<style>
	body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; font-size: 10.5pt;
		line-height: 1.45; color: #1d1d1f; }
	.logo { display: block; width: 2.6cm; margin: 0 auto 0.4cm; }
	h1 { color: #622599; text-align: center; font-size: 22pt; margin: 0 0 0.5cm; }
	h2 { color: #622599; font-size: 14pt; border-bottom: 2px solid #7a1e99; padding-bottom: 3px;
		margin-top: 0.9cm; break-after: avoid; }
	a { color: #7a1e99; text-decoration: none; }
	img { display: block; max-width: 100%; max-height: 6.2cm; margin: 0.25cm auto;
		border: 1px solid #ddd; border-radius: 4px; }
	p, li { orphans: 3; widows: 3; }
	p:has(img), li:has(img) { break-inside: avoid; }
	strong { color: #000; }
</style>
</head>
<body>
<img class="logo" src="${logo}" alt="">
${corpo}
</body>
</html>`;

const browser = await chromium.launch({ channel: 'chrome' });
const p = await browser.newPage();
// Da file e non con setContent: una pagina about:blank non può caricare immagini file://
const cartella = mkdtempSync(`${tmpdir()}/guida-`);
writeFileSync(`${cartella}/guida.html`, html);
await p.goto(pathToFileURL(`${cartella}/guida.html`).href, { waitUntil: 'load' });
await p.pdf({
	path: `${DOCS}/AIUTO-ACCESSO.pdf`,
	format: 'A4',
	margin: { top: '1.6cm', bottom: '1.6cm', left: '1.8cm', right: '1.8cm' },
	displayHeaderFooter: true,
	headerTemplate: '<span></span>',
	footerTemplate: `<div style="font-size:8pt;color:#888;width:100%;text-align:center;">
		Piattaforme Regionali Scout Campania · Non riesco ad accedere · pagina
		<span class="pageNumber"></span> di <span class="totalPages"></span></div>`,
});
await browser.close();
rmSync(cartella, { recursive: true });
console.log(`${DOCS}/AIUTO-ACCESSO.pdf`);
