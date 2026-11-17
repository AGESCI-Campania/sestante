# Accesso con Google e Apple

Nella pagina di login di Sestante possono comparire i pulsanti **Google** e **Apple**: chi ha
già un account Sestante entra con il proprio account Google o Apple invece che con la
password. Configurazione in [`blueprints/source-google.yaml`](../blueprints/source-google.yaml) e
[`blueprints/source-apple.yaml`](../blueprints/source-apple.yaml).

Ogni pulsante compare solo quando le sue credenziali sono in `.env` (e, per Apple, la chiave in
`secrets/`): finché mancano, la sorgente esiste in Authentik ma è spenta.

## Come funziona

- **Nessuna registrazione automatica**: entra solo chi ha già un account Sestante con la
  **stessa email** dell'account Google/Apple (`user_matching_mode: email_link`). Al primo
  accesso i due account vengono collegati; agli sconosciuti compare l'errore "Source is not
  configured for enrollment". Gli account continuano a crearli gli amministratori o la
  segreteria ([GESTIONE-UTENTI.md](GESTIONE-UTENTI.md)).
- **Nessun secondo fattore su Sestante**: con Google/Apple si entra subito dopo il consenso
  del provider (flow `default-source-authentication` di Authentik). Il secondo fattore è quello
  dell'account Google/Apple: Apple lo impone a tutti gli Apple ID, Google solo a chi ha attivato
  la verifica in due passaggi, e Sestante non può verificarlo. Per le piattaforme collegate è
  comunque un accesso via Sestante e non richiedono la loro MFA.
- Collegare l'email è sicuro perché Google e Apple verificano gli indirizzi. Non vale per altri
  provider: non copiare `email_link` su sorgenti che non lo fanno.
- **Email diversa** (es. account Google personale, email AGESCI su Sestante) o Apple con
  **"Nascondi la mia email"** (indirizzo `@privaterelay.appleid.com`): l'email non coincide,
  quindi l'utente entra una volta con password e collega l'account da **Impostazioni →
  Servizi collegati** (*Connected services*). Da lì può anche scollegarlo.

Indirizzo di ritorno (redirect URI) per entrambi i provider:
`https://auth.agescicampania.net/source/oauth/callback/<slug>/`, con slug `google` o `apple`.

## Google

Su [Google Cloud Console](https://console.cloud.google.com), con un account dell'associazione
(non personale: chi lo gestisce deve poterlo passare ad altri):

1. Creare un progetto, es. `Sestante`.
2. **Google Auth Platform → Branding** (*schermata di consenso OAuth*): nome app
   "Piattaforme Regionali Scout Campania", email di assistenza, dominio autorizzato
   `agescicampania.net`, link alla home page e all'informativa privacy.
3. **Audience**: tipo *External*, poi **Pubblica l'app** (*In production*). In stato *Testing*
   possono entrare solo gli utenti di test elencati. Con i soli scope `openid`, `email`,
   `profile` Google non richiede la verifica dell'app.
4. **Clients → Create client**: tipo *Web application*, nome `Sestante`, in *Authorized
   redirect URIs* `https://auth.agescicampania.net/source/oauth/callback/google/`.
5. Copiare **Client ID** e **Client secret** (il secret si vede una sola volta: se perso, se
   ne crea uno nuovo dallo stesso client).

In `.env` sul server, decommentare e compilare (vedi `.env.template`):

```
SOCIAL_GOOGLE_CLIENT_ID=...apps.googleusercontent.com
SOCIAL_GOOGLE_CLIENT_SECRET=...
```

## Apple

Serve un account **Apple Developer Program** a pagamento dell'associazione. Su
[developer.apple.com](https://developer.apple.com/account) → *Certificates, Identifiers &
Profiles*:

1. **Team ID**: in alto a destra nel portale (10 caratteri).
2. **Identifiers → App IDs → +**: tipo *App*, descrizione `Sestante`, Bundle ID esplicito
   `net.agescicampania.sestante`, capability **Sign In with Apple** attiva.
3. **Identifiers → Services IDs → +**: descrizione `Piattaforme Regionali Scout Campania`
   (è il nome mostrato agli utenti), identificativo `net.agescicampania.sestante.web` (deve
   essere diverso da quello dell'App ID). Poi aprirlo, attivare **Sign In with Apple →
   Configure**: App ID primario quello del punto 2, *Domains* `auth.agescicampania.net`,
   *Return URLs* `https://auth.agescicampania.net/source/oauth/callback/apple/`.
4. **Keys → +**: nome `Sestante`, **Sign In with Apple → Configure** con l'App ID del punto 2.
   Annotare il **Key ID** e scaricare il file `.p8` (scaricabile **una sola volta**: se perso,
   si revoca la chiave e se ne crea una nuova).

Sul server, come `agesci`:

```bash
cd /opt/sestante
cp /percorso/AuthKey_XXXXXXXXXX.p8 secrets/apple-signin.p8   # file così com'è, righe BEGIN/END incluse
chmod 600 secrets/apple-signin.p8
```

e in `.env` decommentare e compilare:

```
SOCIAL_APPLE_SERVICES_ID=net.agescicampania.sestante.web
SOCIAL_APPLE_TEAM_ID=XXXXXXXXXX
SOCIAL_APPLE_KEY_ID=XXXXXXXXXX
```

Le email di Sestante (recupero accesso, notifiche) non arrivano agli indirizzi
`@privaterelay.appleid.com` se il mittente non è registrato da Apple. Gli utenti non hanno
quell'indirizzo su Sestante, perché si collegano con l'email vera (vedi sopra), quindi la
registrazione non serve.

## Attivazione sul server

Dopo aver modificato `.env` (ed eventualmente `secrets/`):

```bash
scripts/aggiorna.sh
```

Lo script ricrea i container con le nuove variabili e riapplica i blueprint. Al momento
dell'attivazione Authentik scarica la configurazione OpenID di Google/Apple: se il blueprint
non si applica, l'errore indica l'URL non raggiungibile.

Verifica:

1. Nella pagina di login compaiono i pulsanti attivati.
2. Con un account di prova che ha su Sestante la stessa email dell'account Google/Apple:
   pulsante → consenso del provider → dentro, senza secondo fattore di Sestante.
3. Con un account Google/Apple sconosciuto a Sestante: accesso negato.
4. In Admin → Directory → Federation and Social login la sorgente risulta attiva.

## Disattivare

Commentare (o svuotare) le variabili del provider in `.env` e lanciare `scripts/aggiorna.sh`:
la sorgente torna spenta e il pulsante sparisce. I collegamenti degli utenti restano e
tornano validi se la si riattiva. Per Apple si può anche solo togliere
`secrets/apple-signin.p8`.

Revoca d'urgenza (credenziali compromesse): revocare il client secret su Google Cloud o la
chiave su Apple Developer, poi seguire i passi sopra con le nuove credenziali.
