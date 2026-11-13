# TODO — Sestante: Funzionalità Future

Documento di lavoro per le prossime sessioni di sviluppo. Ogni sezione è indipendente e
può essere implementata nell'ordine preferito, salvo i prerequisiti segnalati.

---

## 0. Deploy su nuovo server dedicato (prerequisito di tutto il resto)

**Contesto**: l'istanza su `admin.agescicampania.org` (Virtualmin + Apache, Authentik 2026.5.3)
è stata usata solo per test. Sestante viene reinstallato da zero su un nuovo server dedicato
(Ubuntu 26.04, senza Virtualmin/Apache né altri proxy) alle piattaforme `*.agescicampania.net`
(Sestante, Plancia, nota spese, Tana, …). Il dominio `agescicampania.org` è abbandonato
(problema con il registrar): host, URL ed email passano tutti a `agescicampania.net`.
Nessun dato da migrare: installazione pulita direttamente su **2026.8.5**, nessun percorso di
upgrade intermedio (2026.5.x → 2026.8.x) necessario.

### Task

Reverse proxy: **Caddy** dal repo `AGESCI-Campania/agesci-campania-web-frontend`, rete Docker
condivisa `agesci-proxy` (contratto in `docs/INTEGRAZIONE.md` di quel repo).

- [ ] DNS: puntare `auth.agescicampania.net` al nuovo server
- [ ] Installare per primo il frontend: `/opt/agesci-campania-web-frontend/scripts/installa.sh`
      (crea la rete `agesci-proxy`; `caddy/sites/sestante.caddy` è già presente)
- [ ] `git clone` in `/opt/sestante`, poi `scripts/installa.sh`: genera `.env` con segreti
      nuovi, copia le immagini in `media/`, avvia, attende healthy, applica i blueprint,
      stampa la password iniziale di `akadmin`
- [ ] Compilare `AUTHENTIK_EMAIL__*` in `.env` e `docker compose up -d` — l'account SMTP
      (`auth@agescicampania.org` sulla vecchia istanza) va ricreato su `agescicampania.net`,
      con nuova App Password; mittente `sestante@agescicampania.net`
- [ ] Verificare in Admin → System → Settings che il Base URL sia `https://auth.agescicampania.net`
      e che la UI carichi senza mixed content (header da Caddy accettati: rete privata Docker)
- [ ] Creare gli account amministratore nominali (2-3 persone, non `akadmin`)
- [ ] Controllo visivo del branding: in 2026.8 il CSS personalizzato è gestito con cascade
      layers e lo sfondo dei flow è cambiato — verificare `branding_custom_css` e background;
      verificare anche che i file in `/media` siano serviti (in 2026.x lo storage è sotto `/data`)
- [ ] Test MFA: enrollment e login con TOTP, WebAuthn, codici di backup
- [ ] **Plancia**: `client_id` e `client_secret` del Provider vengono rigenerati con la nuova
      installazione → aggiornare `SOCIAL_SESTANTE_CLIENT_ID/SECRET` nel `.env.prod` di Plancia
- [ ] Test login SSO Plancia → Sestante end-to-end
- [ ] Spegnere i container Sestante sul vecchio server (`docker compose down`) una volta
      validato il nuovo

### Note di versione (2026.5 → 2026.8) rilevanti per noi

- `AUTHENTIK_WEB__BASE_URL` nuova, obbligatoria da 2026.11 — già in `.env.template`
- Header `X-Forwarded-*` accettati solo da proxy fidati (vedi sopra)
- WebAuthn: rimossa l'opzione `prevent_duplicate_devices` (non usata nei nostri blueprint)
- `hash_password` non accetta più la password come argomento posizionale
- `AUTHENTIK_POSTGRESQL__CONN_OPTIONS` deprecata (non usata)
- Per i futuri upgrade: riscaricare il compose ufficiale nel repo (cambia il tag di default),
  commit e push, poi `scripts/aggiorna.sh` sul server (backup DB automatico, niente downgrade).
  Passare all'ultima patch della minor corrente prima di salire alla successiva.

---

## 1. Flusso di Auto-Registrazione (Enrollment)

**Obiettivo**: Permettere agli utenti di crearsi un account su Sestante autonomamente,
senza intervento dell'amministratore.

### Decisione preliminare

Prima di implementare, scegliere la modalità:

- **Registrazione libera** — chiunque raggiunga la pagina di login può creare un account.
  Adatto se Sestante è aperto a tutti gli utenti AGESCI Campania.
- **Solo su invito** — l'admin crea un link di invito monouso; solo chi riceve il link può
  registrarsi. Adatto per controllo stretto sugli accessi iniziali.

### Task

- [ ] Creare `blueprints/flow-enrollment.yaml` con la seguente pipeline di stages:
  1. `PromptStage` — chiede username, email, nome completo, password (+ conferma)
  2. `UserWriteStage` — crea l'utente in Authentik
  3. (opzionale) `EmailStage` — invia email di verifica prima del primo accesso
  4. `LoginStage` — accesso automatico al termine della registrazione
- [ ] Collegare l'enrollment flow all'`IdentificationStage` del flow di autenticazione
  principale (campo `enrollment_flow`) → comparirà il link "Crea account" nella pagina
  di login di Sestante
- [ ] Verificare che l'MFA (`flow-authn-mfa.yaml`) scatti correttamente al primo accesso
  post-registrazione (fase di configurazione TOTP/WebAuthn)

### Note tecniche

- Il `UserWriteStage` deve avere `create_users_as_inactive: false` per attivazione
  immediata (o `true` se si vuole moderazione admin)
- Per la modalità su invito usare il modello `authentik_stages_invitation.invitation` nei
  Blueprint e aggiungere un `InvitationStage` prima del `PromptStage`

---

## 2. Importazione Utenti da Plancia

**Obiettivo**: Migrare gli utenti esistenti di Plancia su Sestante, conservando le
password originali senza reset forzato.

### Perché funziona senza reset password

Django (e quindi Plancia) usa PBKDF2-SHA256 come algoritmo di hashing predefinito.
Authentik supporta nativamente gli stessi hash Django — nessuna conversione necessaria.

### Prerequisiti

- Accesso in lettura al database PostgreSQL di Plancia
- Python 3 con libreria `pyyaml` per lo script di conversione

### Task

- [ ] Esportare gli utenti attivi da Plancia con:

  ```sql
  COPY (
    SELECT username, email,
           COALESCE(first_name || ' ' || last_name, username) AS full_name,
           password
    FROM auth_user
    WHERE is_active = TRUE
    ORDER BY date_joined
  ) TO '/tmp/plancia_users.csv' CSV HEADER;
  ```

- [ ] Creare `scripts/plancia_to_blueprint.py` — converte il CSV in Blueprint YAML:

  ```python
  #!/usr/bin/env python3
  """Converte un CSV di utenti Plancia in un Blueprint YAML per Authentik."""
  import csv, sys, yaml

  def convert(csv_path: str) -> dict:
      entries = []
      with open(csv_path) as f:
          for row in csv.DictReader(f):
              entries.append({
                  "model": "authentik_core.user",
                  "state": "present",
                  "identifiers": {"username": row["username"]},
                  "attrs": {
                      "email": row["email"],
                      "name": row["full_name"],
                      "password_hash": row["password"],
                      "type": "internal",
                  },
              })
      return {
          "version": 1,
          "metadata": {"name": "Import utenti Plancia"},
          "entries": entries,
      }

  if __name__ == "__main__":
      print(yaml.dump(convert(sys.argv[1]), allow_unicode=True))
  ```

  Esecuzione: `python3 scripts/plancia_to_blueprint.py /tmp/plancia_users.csv > /tmp/users-import-plancia.yaml`

- [ ] Applicare il blueprint via UI Authentik:
  **System → Blueprints → Import** (o via API: `POST /api/v3/managed/blueprints/`)
- [ ] Verificare che almeno 3-5 utenti campione riescano ad accedere con la password originale

### Note

- Il Blueprint è idempotente (`state: present`): può essere ri-applicato senza duplicati
- Il file generato contiene hash delle password — **non versionarlo in git**
- Gli utenti importati non avranno MFA configurato; al primo login SSO verranno guidati
  a configurarlo (grazie a `flow-authn-mfa.yaml` già presente)

---

## 3. Sincronizzazione Automatica Nuovi Utenti Plancia → Sestante

**Obiettivo**: Quando un admin crea un utente direttamente in Plancia (non via SSO),
farlo comparire automaticamente anche su Sestante senza intervento manuale.

### Prerequisito comune (entrambe le opzioni)

- [ ] Creare `blueprints/service-account-plancia.yaml` — Service Account Authentik per
  Plancia con token API statico:

  ```yaml
  version: 1
  metadata:
    name: Service Account — Plancia
  entries:
    - model: authentik_core.user
      state: present
      identifiers:
        username: sa-plancia
      attrs:
        name: "Service Account Plancia"
        type: service_account
    - model: authentik_core.token
      state: present
      identifiers:
        identifier: sa-plancia-api-token
      attrs:
        user: !KeyOf sa-plancia
        intent: api
        description: "Token API per sincronizzazione utenti Plancia→Sestante"
  ```

  Dopo l'applicazione, recuperare il token generato da **Directory → Tokens** e
  salvarlo come `SESTANTE_SERVICE_TOKEN` nelle variabili d'ambiente di Plancia.

---

### Opzione A — Signal Django in Plancia (real-time, consigliata)

Richiede una modifica al codice di Plancia. Passare al team Plancia le seguenti
istruzioni da implementare:

**File da creare in Plancia**: `accounts/sestante_sync.py`

```python
"""Sincronizzazione real-time utenti Plancia → Sestante (Authentik)."""
import logging
import requests
from django.conf import settings
from django.contrib.auth import get_user_model
from django.db.models.signals import post_save
from django.dispatch import receiver

logger = logging.getLogger(__name__)
User = get_user_model()

SESTANTE_API = getattr(settings, "SESTANTE_API_URL", "https://auth.agescicampania.net")
SESTANTE_TOKEN = getattr(settings, "SESTANTE_SERVICE_TOKEN", "")


@receiver(post_save, sender=User)
def sync_new_user_to_sestante(sender, instance, created, **kwargs):
    if not created or not SESTANTE_TOKEN:
        return
    try:
        resp = requests.post(
            f"{SESTANTE_API}/api/v3/core/users/",
            headers={"Authorization": f"Bearer {SESTANTE_TOKEN}"},
            json={
                "username": instance.username,
                "email": instance.email,
                "name": instance.get_full_name() or instance.username,
                "type": "internal",
                "is_active": instance.is_active,
            },
            timeout=5,
        )
        if resp.status_code == 201:
            logger.info("Utente %s creato su Sestante.", instance.username)
        elif resp.status_code == 400 and "username" in resp.text:
            logger.debug("Utente %s già esistente su Sestante.", instance.username)
        else:
            logger.warning("Sestante sync: HTTP %s per %s", resp.status_code, instance.username)
    except requests.RequestException as exc:
        logger.error("Impossibile sincronizzare %s su Sestante: %s", instance.username, exc)
```

**Da fare in Plancia**:
- Importare `sestante_sync` in `AppConfig.ready()` dell'app `accounts`
- Aggiungere a `.env.prod`:
  ```
  SESTANTE_API_URL=https://auth.agescicampania.net
  SESTANTE_SERVICE_TOKEN=<token dal blueprint sa-plancia>
  ```

---

### Opzione B — Script di sync batch (nessuna modifica a Plancia)

- [ ] Creare `scripts/sync_plancia_to_sestante.py` — confronta utenti Plancia vs Authentik
  e crea quelli mancanti tramite API; eseguire via cron o GitHub Actions giornalmente

```python
#!/usr/bin/env python3
"""Sync batch: crea su Sestante gli utenti Plancia che non esistono ancora."""
import os, csv, subprocess, json, requests

SESTANTE = os.environ["SESTANTE_API_URL"]
TOKEN = os.environ["SESTANTE_SERVICE_TOKEN"]
PLANCIA_DB_URL = os.environ["PLANCIA_DATABASE_URL"]

headers = {"Authorization": f"Bearer {TOKEN}"}

# Recupera utenti esistenti su Sestante
existing = {u["username"] for u in requests.get(
    f"{SESTANTE}/api/v3/core/users/?page_size=10000", headers=headers
).json()["results"]}

# Legge utenti da Plancia (richiede accesso DB)
# Adattare in base all'ambiente di deploy (psql, pg_dump, etc.)
result = subprocess.run(
    ["psql", PLANCIA_DB_URL, "-c",
     "COPY (SELECT username,email,first_name,last_name FROM auth_user WHERE is_active) TO STDOUT CSV HEADER"],
    capture_output=True, text=True, check=True
)
for row in csv.DictReader(result.stdout.splitlines()):
    if row["username"] in existing:
        continue
    resp = requests.post(f"{SESTANTE}/api/v3/core/users/", headers=headers, json={
        "username": row["username"],
        "email": row["email"],
        "name": f"{row['first_name']} {row['last_name']}".strip() or row["username"],
        "type": "internal",
    })
    print(f"{'OK' if resp.status_code == 201 else 'ERR'} {row['username']}")
```

---

### Opzione C — SCIM (futuro, quando Plancia sarà aggiornata)

Authentik espone un SCIM Provider che può ricevere eventi di provisioning standard.
Quando Plancia sarà pronta, configurare il SCIM endpoint e registrarlo in Plancia come
SCIM client per una sincronizzazione bidirezionale automatica senza codice custom.

---

## 4. Login Social (Apple / Google / Microsoft)

**Obiettivo**: Permettere agli utenti di accedere a Sestante con i propri account
Google, Microsoft o Apple, senza creare una password separata.

Le redirect URI per tutti i provider seguono il pattern:
`https://auth.agescicampania.net/source/oauth/callback/<slug>/`

---

### 4a. Google

**Prerequisiti** — completare sul [Google Cloud Console](https://console.cloud.google.com):

- [ ] Creare o scegliere un progetto Google Cloud
- [ ] Abilitare l'API "Google Identity" (OAuth 2.0)
- [ ] Creare credenziali: **OAuth 2.0 Client ID** (tipo: "Web Application")
- [ ] In "Authorized redirect URIs" aggiungere:
  `https://auth.agescicampania.net/source/oauth/callback/google/`
- [ ] Scaricare/copiare **Client ID** e **Client Secret**
- [ ] Aggiungere a `.env`: `SOCIAL_GOOGLE_CLIENT_ID=...` e `SOCIAL_GOOGLE_CLIENT_SECRET=...`

**Task Authentik**:

- [ ] Creare `blueprints/source-google.yaml`:

  ```yaml
  version: 1
  metadata:
    name: Source — Google OAuth
  entries:
    - model: authentik_sources_oauth.oauthsource
      state: present
      identifiers:
        slug: google
      attrs:
        name: "Google"
        provider_type: google
        consumer_key: !Env SOCIAL_GOOGLE_CLIENT_ID
        consumer_secret: !Env SOCIAL_GOOGLE_CLIENT_SECRET
        enabled: true
        authentication_flow: !Find [authentik_flows.flow, [slug, default-source-authentication]]
        enrollment_flow: !Find [authentik_flows.flow, [slug, default-source-enrollment]]
  ```

---

### 4b. Microsoft (Entra ID / Azure AD)

**Prerequisiti** — completare su [portal.azure.com](https://portal.azure.com) → Entra ID → App registrations:

- [ ] **New registration**:
  - Name: "Sestante SSO"
  - Supported account types: "Accounts in any organizational directory and personal Microsoft accounts"
    (o "single tenant" se solo account aziendali AGESCI)
  - Redirect URI: `https://auth.agescicampania.net/source/oauth/callback/entra-id/`
- [ ] Annotare **Application (client) ID** e **Directory (tenant) ID**
- [ ] In **Certificates & Secrets** → New client secret → copiare subito il valore
  (mostrato una sola volta)
- [ ] In **API permissions** aggiungere (Delegated): `email`, `profile`, `openid`, `User.Read`
- [ ] Aggiungere a `.env`:
  ```
  SOCIAL_MICROSOFT_CLIENT_ID=...
  SOCIAL_MICROSOFT_CLIENT_SECRET=...
  SOCIAL_MICROSOFT_TENANT_ID=...   # o "common" per multi-tenant
  ```

**Task Authentik**:

- [ ] Creare `blueprints/source-microsoft.yaml`:

  ```yaml
  version: 1
  metadata:
    name: Source — Microsoft Entra ID
  entries:
    - model: authentik_sources_oauth.oauthsource
      state: present
      identifiers:
        slug: entra-id
      attrs:
        name: "Microsoft"
        provider_type: azure-ad
        consumer_key: !Env SOCIAL_MICROSOFT_CLIENT_ID
        consumer_secret: !Env SOCIAL_MICROSOFT_CLIENT_SECRET
        # Per single-tenant sostituire "common" con il tenant ID
        oidc_well_known_url: "https://login.microsoftonline.com/!Env SOCIAL_MICROSOFT_TENANT_ID/v2.0/.well-known/openid-configuration"
        enabled: true
        authentication_flow: !Find [authentik_flows.flow, [slug, default-source-authentication]]
        enrollment_flow: !Find [authentik_flows.flow, [slug, default-source-enrollment]]
  ```

  > Nota: verificare la sintassi `!Env` nel OIDC URL sul campo stringa nella versione installata;
  > in alternativa, inserire il tenant ID direttamente nella stringa URL.

---

### 4c. Apple

**Prerequisiti** — completare su [developer.apple.com](https://developer.apple.com):

- [ ] **Creare App ID**:
  - Identifier: es. `net.agescicampania.sestante`
  - Abilitare capability: "Sign In with Apple"
- [ ] **Creare Services ID** (stesso nome dell'App ID):
  - Abilitare "Sign In with Apple"
  - Configurare "Return URLs": `https://auth.agescicampania.net/source/oauth/callback/apple/`
- [ ] **Creare Key**:
  - Abilitare "Sign in with Apple" e selezionare l'App ID
  - Scaricare il file `.p8` (solo una volta)
  - Annotare **Key ID**
- [ ] Annotare **Team ID** (visibile nell'header del portale developer)
- [ ] Aggiungere a `.env`:
  ```
  SOCIAL_APPLE_SERVICES_ID=net.agescicampania.sestante     # Services ID
  SOCIAL_APPLE_TEAM_ID=XXXXXXXXXX
  SOCIAL_APPLE_KEY_ID=XXXXXXXXXX
  # Contenuto del file .p8 (su una riga, senza header/footer)
  SOCIAL_APPLE_PRIVATE_KEY=...
  ```

**Task Authentik**:

- [ ] Creare `blueprints/source-apple.yaml`:

  ```yaml
  version: 1
  metadata:
    name: Source — Apple
  entries:
    - model: authentik_sources_oauth.oauthsource
      state: present
      identifiers:
        slug: apple
      attrs:
        name: "Apple"
        provider_type: apple
        # consumer_key format: services_id;team_id;key_id
        consumer_key: !Format "%s;%s;%s" [!Env SOCIAL_APPLE_SERVICES_ID, !Env SOCIAL_APPLE_TEAM_ID, !Env SOCIAL_APPLE_KEY_ID]
        consumer_secret: !Env SOCIAL_APPLE_PRIVATE_KEY
        enabled: true
        authentication_flow: !Find [authentik_flows.flow, [slug, default-source-authentication]]
        enrollment_flow: !Find [authentik_flows.flow, [slug, default-source-enrollment]]
  ```

  > Nota: Apple richiede un dominio reale e registrato (no `.local`, no IP). Testare solo
  > con `auth.agescicampania.net` live su HTTPS.

---

## 5. Branding — Piattaforme Regionali Scout Campania

**Obiettivo**: Personalizzare la UI di Sestante con il brand AGESCI Campania e usare
`resources/background.jpeg` come sfondo della pagina di login.

### Prerequisiti da preparare

- [ ] **Logo SVG** dell'organizzazione/piattaforme (viewBox ritagliata stretta, no padding
  eccessivo) — salvare in `resources/logo.svg`
- [ ] **Favicon** PNG 32×32 px — salvare in `resources/favicon.png`
- [ ] **Colori brand** principali (esadecimale) — da concordare con il team

### Step 1 — Rendere il background accessibile al server

Il `docker-compose.yml` attuale non espone un volume `/media` persistente. Aggiornare
`docker-compose.override.yml` per:
1. Montare una cartella `./media` persistente (per avatar, icone caricate via UI, ecc.)
2. Copiare il background nell'area media accessibile via HTTP

```yaml
# docker-compose.override.yml (aggiungere alle sezioni esistenti)
services:
  server:
    volumes:
      - ./blueprints:/blueprints/local
      - ./media:/media                           # aggiunto
  worker:
    volumes:
      - ./blueprints:/blueprints/local
      - ./media:/media                           # aggiunto
```

Poi copiare il background:
```bash
mkdir -p media
cp resources/background.jpeg media/background.jpeg
cp resources/logo.svg media/logo.svg          # quando disponibile
cp resources/favicon.png media/favicon.png    # quando disponibile
```

Dopo `docker compose up -d`, i file saranno raggiungibili a:
- `https://auth.agescicampania.net/media/background.jpeg`
- `https://auth.agescicampania.net/media/logo.svg`

### Step 2 — Blueprint brand

- [ ] Creare `blueprints/brand.yaml`:

  ```yaml
  version: 1
  metadata:
    name: Brand — Piattaforme Regionali Scout Campania
  entries:
    - model: authentik_brands.brand
      state: present
      identifiers:
        domain: auth.agescicampania.net
      attrs:
        title: "Piattaforme Regionali Scout Campania"
        logo: /media/logo.svg
        favicon: /media/favicon.png
        default_locale: it
        flow_background: /media/background.jpeg
        # Colori: impostare tramite custom_css (vedi sotto) o lasciare default
  ```

  > Verificare il model name esatto per la versione installata: potrebbe essere
  > `authentik_brands.brand` o `authentik_tenants.tenant`. Controllare via
  > `docker compose exec server ak shell -c "from authentik_brands.models import Brand; print(Brand)"`.

### Step 3 — CSS personalizzato (opzionale)

Nel campo **Custom CSS** del Brand (via UI o aggiunto all'attrs del Blueprint):

```css
/* Colori brand AGESCI Campania — sostituire con i valori reali */
:root {
  --ak-accent: #1a5276;          /* colore primario (es. blu scuro) */
  --pf-global--primary-color--100: #1a5276;
}

/* Assicura che il background copra tutto lo schermo */
.pf-c-login {
  background-size: cover;
  background-position: center;
}
```

### Note

- Il background JPEG è già presente in `resources/background.jpeg` — nessuna risorsa da
  creare, solo da copiare nella cartella `media/`
- Logo e favicon sono le uniche risorse grafiche ancora da produrre prima di
  completare il branding

---

## Ordine di esecuzione consigliato

0. **Deploy su nuovo server** (sezione 0) — prerequisito per tutto il resto
1. **Branding** (Step 1 + docker-compose) — impatto zero sui flussi esistenti
2. **Enrollment flow** — dopo aver deciso libero vs su invito
3. **Import utenti Plancia** — coordinare con Plancia per accesso al DB
4. **Service Account** (prerequisito per Opzione A sync)
5. **Social login** — dopo aver ottenuto tutte le credenziali dai portali
6. **Sync automatico** — dopo che import e social login sono stabili
