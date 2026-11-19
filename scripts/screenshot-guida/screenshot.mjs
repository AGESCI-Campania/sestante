// Screenshot per docs/AIUTO-ACCESSO.md, presi da un'istanza di prova locale (mai dalla produzione).
// Istruzioni in scripts/screenshot-guida/README.md.
//
// Uso: node screenshot.mjs <cartella-di-uscita>
// Variabili: SESTANTE_URL (default http://localhost:9100), MAILPIT_URL (default http://127.0.0.1:9125)
import { chromium } from 'playwright';
import { authenticator } from 'otplib';

const OUT = process.argv[2];
const URL = process.env.SESTANTE_URL || 'http://localhost:9100';
const MAILPIT = process.env.MAILPIT_URL || 'http://127.0.0.1:9125';
const EMAIL = 'mario.rossi@example.org';
const PASSWORD = 'NuovaPassword-2026!';

const browser = await chromium.launch({ channel: 'chrome' });
const ctx = await browser.newContext({ locale: 'it-IT', viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2 });
const p = await ctx.newPage();

// Contorno rosso sull'elemento da cliccare o compilare, tolto dopo lo screenshot
const evidenzia = (loc, distanza = 3) => loc.evaluate((el, d) => {
	el.style.outline = '3px solid #d62828';
	el.style.outlineOffset = `${d}px`;
}, distanza);
const togliEvidenza = (loc) => loc.evaluate((el) => {
	el.style.outline = '';
});

// Screenshot del solo riquadro di login (senza lo sfondo) o di un elemento dato
async function scatta(nome, elemento = p.locator('.pf-c-login__main')) {
	await p.waitForTimeout(1500);
	await elemento.first().screenshot({ path: `${OUT}/${nome}.png` });
	console.log(nome);
}

async function attendiStage() {
	await p.waitForLoadState('networkidle');
	await p.waitForTimeout(1500);
}

// --- 1. Login con il codice dell'app ---
await p.goto(`${URL}/if/flow/default-authentication-flow/`);
await attendiStage();
await p.fill('#ak-identifier-input', EMAIL);
await p.click('button[type=submit]');
await attendiStage();
await p.locator('#ak-stage-password-input').fill('VecchiaPassword-2026');
await p.click('button[type=submit]');
await attendiStage();
await scatta('01-codice-richiesto');

// --- 2. Recupero con l'email ---
await ctx.clearCookies();
await p.goto(`${URL}/if/flow/default-authentication-flow/`);
await attendiStage();
const linkRecupero = p.getByText('Hai dimenticato il nome utente o la password?');
await evidenzia(linkRecupero);
await scatta('02-password-dimenticata');
await linkRecupero.click();
await attendiStage();
await p.fill('#ak-identifier-input', EMAIL);
await scatta('03-recupero-email');
await fetch(`${MAILPIT}/api/v1/messages`, { method: 'DELETE' });
await p.click('button[type=submit]');
await attendiStage();
await scatta('04-email-inviata');

let messaggio;
for (let i = 0; i < 20 && !messaggio; i++) {
	await p.waitForTimeout(1000);
	messaggio = (await (await fetch(`${MAILPIT}/api/v1/messages`)).json()).messages[0];
}
const html = (await (await fetch(`${MAILPIT}/api/v1/message/${messaggio.ID}`)).json()).HTML;
const link = html.match(/href="([^"]*flow_token=[^"]*)"/)[1].replace(/&amp;/g, '&');
const posta = await ctx.newPage();
await posta.setViewportSize({ width: 700, height: 500 });
await posta.goto(`${MAILPIT}/view/${messaggio.ID}.html`);
await posta.waitForTimeout(1000);
await posta.screenshot({ path: `${OUT}/05-email.png`, fullPage: true });
console.log('05-email');
await posta.close();

await p.goto(link);
await attendiStage();
await scatta('06-conferma');
await p.click('button[type=submit]');
await attendiStage();
await p.locator('#field-password').fill(PASSWORD);
await p.locator('#field-password_repeat').fill(PASSWORD);
await scatta('07-nuova-password');
await p.click('button[type=submit]');
await p.waitForURL('**/if/user/**');
await attendiStage();
// Chiude l'avviso "Email verificato con successo" in basso
await p.locator('ak-message button[aria-label]').first().click().catch(() => {});
const ingranaggio = p.locator('a[href$="/if/user/#/settings"]').first();
await evidenzia(ingranaggio);
await p.screenshot({ path: `${OUT}/08-dentro.png`, clip: { x: 0, y: 0, width: 1280, height: 300 } });
console.log('08-dentro');

// --- 3. Sostituzione del dispositivo ---
await p.goto(`${URL}/if/user/#/settings;%7B%22page%22%3A%22page-credentials%22%7D`);
await attendiStage();
const mfa = p.locator('ak-user-settings-mfa');
const riga = mfa.locator('tbody input[type=checkbox]').first();
await riga.check();
await evidenzia(p.locator('#page-credentials-tab'), -3);
await evidenzia(mfa.locator('button:has-text("Elimina")'));
await p.waitForTimeout(1500);
await p.screenshot({ path: `${OUT}/09-dispositivi.png`, clip: { x: 0, y: 70, width: 1280, height: 340 } });
console.log('09-dispositivi');
await togliEvidenza(p.locator('#page-credentials-tab'));
await mfa.locator('button:has-text("Elimina")').click();
await p.waitForTimeout(1500);
await scatta('10-conferma-elimina', p.locator('[role=dialog]:visible, dialog[open]'));
await p.locator('[role=dialog]:visible button.pf-m-danger, dialog[open] button.pf-m-danger').last().click();
await p.waitForTimeout(2000);
await togliEvidenza(mfa.locator('button:has-text("Elimina")'));

await mfa.locator('#add-mfa-toggle').click();
await p.waitForTimeout(800);
const voceApp = p.locator('#add-mfa-menu a').filter({ hasText: 'App di autenticazione' });
await evidenzia(voceApp);
await p.waitForTimeout(1000);
await p.screenshot({ path: `${OUT}/11-aggiungi.png`, clip: { x: 0, y: 70, width: 1280, height: 300 } });
console.log('11-aggiungi');
await voceApp.click();
await attendiStage();
await scatta('12-qr');

// Codice valido letto dalla sfida dello stage (stesso piano del flow, non lo fa avanzare)
const sfida = await p.evaluate(async () =>
	(await fetch(`/api/v3/flows/executor/default-authenticator-totp-setup/?query=`, { credentials: 'include' })).json());
const segreto = new URLSearchParams(sfida.config_url.split('?')[1]).get('secret');
await p.locator('#totp-code-input').fill(authenticator.generate(segreto));
await p.click('button[type=submit]');
await p.waitForURL('**/if/user/**');
await attendiStage();

// --- 4. Codici di recupero ---
await p.goto(`${URL}/if/user/#/settings;%7B%22page%22%3A%22page-credentials%22%7D`);
await attendiStage();
await mfa.locator('#add-mfa-toggle').click();
await p.waitForTimeout(800);
await p.locator('#add-mfa-menu a').filter({ hasText: 'Codici di recupero' }).click();
await attendiStage();
await scatta('13-codici-recupero');
await p.click('button[type=submit]');
await p.waitForURL('**/if/user/**');
await attendiStage();
await p.waitForTimeout(1500);
await p.screenshot({ path: `${OUT}/14-dispositivi-dopo.png`, clip: { x: 0, y: 70, width: 1280, height: 330 } });
console.log('14-dispositivi-dopo');

// --- 5. Login con un codice di recupero (scelta del metodo) ---
await ctx.clearCookies();
await p.goto(`${URL}/if/flow/default-authentication-flow/`);
await attendiStage();
await p.fill('#ak-identifier-input', EMAIL);
await p.click('button[type=submit]');
await attendiStage();
await p.locator('#ak-stage-password-input').fill(PASSWORD);
await p.click('button[type=submit]');
await attendiStage();
const voceCodici = p.getByText('Chiavi di recupero');
await evidenzia(voceCodici);
await scatta('15-scegli-metodo');
await voceCodici.click();
await attendiStage();
await scatta('16-inserisci-codice');

await browser.close();
