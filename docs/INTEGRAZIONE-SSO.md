# Integrazione di una piattaforma con Sestante (SSO AGESCI Campania)

Istruzioni per chi sviluppa una piattaforma che usa il login SSO di Sestante
(`https://auth.agescicampania.net`), **in particolare per gli agenti Claude Code che lavorano
nei repository delle singole piattaforme** (Plancia, Bussola, Catello, nota spese, Tana,
future). Valgono allo stesso modo per una piattaforma nuova e per una già esistente che viene
reinstallata o collegata ex novo. Leggere per intero prima di toccare login, account utente,
ruoli o MFA del progetto.

Sorgente: `docs/INTEGRAZIONE-SSO.md` nel repo
[`AGESCI-Campania/sestante`](https://github.com/AGESCI-Campania/sestante).
Versione sempre aggiornata, leggibile senza autenticazione:
<https://raw.githubusercontent.com/AGESCI-Campania/sestante/main/docs/INTEGRAZIONE-SSO.md>

Va letto **insieme** a `docs/INTEGRAZIONE.md` del repo `agesci-campania-web-frontend`
(reverse proxy, rete Docker, header, script di installazione), pubblico:
<https://raw.githubusercontent.com/AGESCI-Campania/agesci-campania-web-frontend/main/docs/INTEGRAZIONE.md>

---

## 1. Cos'è Sestante e cosa decide

Sestante è un'istanza di [Authentik](https://docs.goauthentik.io) usata come Identity
Provider OIDC unico. Ogni piattaforma resta un progetto indipendente con il proprio database
e **si fida** di identità, MFA e ruoli globali dichiarati da Sestante.

Decisioni già prese (non rimetterle in discussione senza l'utente):

- **Ruoli globali** = gruppi Authentik `admin-multipiattaforma` e `segreteria`, arrivano nel
  claim `groups`. Li assegna solo chi amministra Sestante.
- **Ruoli locali** (es. PGV, CRP, CSQ, admin locale…) restano dati della piattaforma: Sestante
  non li conosce e il flusso SSO non li modifica mai.
- **MFA solo su Sestante**: la piattaforma non richiede di nuovo la MFA a chi entra via SSO.
- **Provisioning al primo accesso**: utente sconosciuto → creato in automatico, senza ruoli
  locali (salvo quelli derivati dai ruoli globali); un utente esistente con la stessa email
  viene **collegato**, non duplicato.
- **Transizione**: login locale e SSO convivono. Il login locale di una piattaforma con utenti
  reali si disattiva solo dopo conferma esplicita dell'utente, verificato che tutti gli
  utenti attivi abbiano fatto almeno un login SSO riuscito. Un agente non lo disattiva mai di
  propria iniziativa.

## 2. Chi fa cosa

| Cosa | Dove | Chi |
|---|---|---|
| Provider OIDC + Application in Authentik | `blueprints/provider-<slug>.yaml` nel repo `sestante` | **l'utente** (l'agente della piattaforma prepara il contenuto, § 4) |
| Client ID / secret | generati da Authentik all'applicazione del blueprint | l'utente li copia nel `.env` della piattaforma |
| Codice di login, mappatura ruoli, provisioning | repo della piattaforma | agente della piattaforma |
| Blocco Caddy, rete, header proxy | `docs/INTEGRAZIONE.md` del frontend | come da quel documento |

Regole per l'agente della piattaforma:

- **Non modificare il repo `sestante`** e non creare Provider/Application a mano in UI o via
  API: preparare il blueprint (§ 4) e consegnarlo all'utente.
- **Mai committare** client secret o altri segreti: vanno nel `.env` della piattaforma
  (escluso da git) e in `.env.template` solo come chiave vuota con un commento.
- Non introdurre gestione di password/MFA per gli utenti SSO, né gruppi Authentik per i ruoli
  locali.

## 3. Endpoint

Ogni piattaforma ha un'Application con uno **slug** (es. `plancia`, `bussola`); l'issuer è
per-applicazione:

| Cosa | URL |
|---|---|
| Issuer | `https://auth.agescicampania.net/application/o/<slug>/` |
| Discovery | `https://auth.agescicampania.net/application/o/<slug>/.well-known/openid-configuration` |
| Authorization | `https://auth.agescicampania.net/application/o/authorize/` |
| Token | `https://auth.agescicampania.net/application/o/token/` |
| Userinfo | `https://auth.agescicampania.net/application/o/userinfo/` |
| JWKS | `https://auth.agescicampania.net/application/o/<slug>/jwks/` |
| Logout (RP-initiated) | `https://auth.agescicampania.net/application/o/<slug>/end-session/` |

- Configurare la libreria OIDC con la **discovery** (issuer), non con URL scritti a mano.
- Usare sempre l'URL pubblico `https://auth.agescicampania.net`, anche dal backend che gira
  sullo stesso server: l'alias Docker `sestante-server:9000` darebbe un issuer diverso e la
  validazione dei token fallirebbe. La piattaforma non va collegata alla rete di Sestante.
- Prima di dare per buono un endpoint, verificarlo sulla discovery dell'istanza reale.

## 4. Blueprint da preparare per l'utente

Dati che servono (chiederli all'utente se non ovvi):

- **slug** e nome visualizzato della piattaforma;
- **redirect URI** esatte (match `strict`), una per ogni dominio di produzione — ricavarle
  dalla libreria effettivamente installata (vedi § 6.1), non a memoria;
- **launch URL**: pagina che avvia il login SSO, usata dal dashboard di Sestante;
- tipo di client: `confidential` (app web con backend, il caso normale) oppure `public` + PKCE
  (SPA o app mobile senza backend);
- eventuali claim extra oltre a `openid profile email`: in particolare se la piattaforma
  mostra la foto dell'utente, lo scope `avatar` (§ 5.1), da aggiungere a `property_mappings`
  con `!Find [authentik_providers_oauth2.scopemapping, [name, "Sestante: avatar"]]`.

Modello (stesso schema del blueprint già validato sull'istanza; l'utente lo salva come
`blueprints/provider-<slug>.yaml` e lo aggiunge a `BLUEPRINTS` in `scripts/_sestante.sh`):

```yaml
version: 1
metadata:
  name: Sestante - Provider <Nome>

entries:
  - model: authentik_providers_oauth2.oauth2provider
    id: provider-<slug>
    identifiers:
      name: <Nome> AGESCI Campania
    attrs:
      name: <Nome> AGESCI Campania
      authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
      invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
      client_type: confidential
      grant_types:
        - authorization_code
      sub_mode: hashed_user_id
      redirect_uris:
        - url: "https://<sottodominio>.agescicampania.net/<percorso-callback>"
          matching_mode: strict
      property_mappings:
        - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: OpenID 'openid'"]]
        - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: OpenID 'profile'"]]
        - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: OpenID 'email'"]]
      # client_id e client_secret sono generati da Authentik: l'utente li recupera da
      # Applications → Providers → <Nome> AGESCI Campania e li mette nel .env della piattaforma.

  - model: authentik_core.application
    identifiers:
      slug: <slug>
    attrs:
      name: <Nome>
      slug: <slug>
      provider: !Find [authentik_providers_oauth2.oauth2provider, [name, <Nome> AGESCI Campania]]
      policy_engine_mode: any
      meta_launch_url: "https://<sottodominio>.agescicampania.net/<percorso-avvio-login>"
```

`implicit-consent` = nessuna schermata "autorizza l'app": è voluto, sono piattaforme interne.

Ambiente di sviluppo: **non** aggiungere redirect URI `localhost` al Provider di produzione;
se serve provare l'SSO in locale chiedere all'utente (Provider di sviluppo separato o istanza
Authentik locale).

## 5. Claim ricevuti

Con gli scope `openid profile email`:

| Claim | Uso |
|---|---|
| `sub` | identificativo stabile **solo per questa piattaforma** (`sub_mode: hashed_user_id`: lo stesso utente ha `sub` diversi su piattaforme diverse). Chiave dell'account social collegato. |
| `email`, `email_verified` | collegamento agli account esistenti, contatto |
| `name`, `given_name`, `preferred_username`, `nickname` | anagrafica di base |
| `groups` | lista dei **nomi** dei gruppi Authentik dell'utente |

- Considerare solo i gruppi noti (`admin-multipiattaforma`, `segreteria`) e ignorare gli
  altri: l'utente può appartenere anche a gruppi interni di Authentik.
- Leggere i claim dalla risposta `userinfo`, con l'`id_token` come riserva.
- Verificare i claim effettivi con un login di prova (es. stampando i dati dell'account
  social in shell) prima di scrivere logica che ne dipende; in particolare il valore di
  `email_verified` se la libreria lo richiede per il collegamento per email.

### 5.1 Immagine del profilo (scope `avatar`, facoltativo)

Su Sestante l'utente può caricare la propria immagine del profilo. Per riceverla la
piattaforma chiede anche lo scope `avatar`, e il Provider deve avere la mappatura
`Sestante: avatar` (`blueprints/scope-avatar.yaml`).

| Claim `picture` nella risposta `userinfo` | Significato |
|---|---|
| `data:image/<tipo>;base64,…` (JPG, PNG, WebP o GIF, al massimo 512 KB decodificati) | immagine caricata su Sestante |
| URL `https://…` (oggi Gravatar) | nessuna immagine caricata, ma esiste un Gravatar per la sua email (arriva dallo scope `profile`) |
| assente, o un percorso relativo (`/static/…`, l'emblema predefinito di Sestante) | nessuna immagine: usare l'avatar predefinito della piattaforma |

- Il data-URI c'è **solo** nella risposta `userinfo`, mai nell'`id_token` (sarebbe troppo grande).
  Se manca la risposta `userinfo`, o si sta leggendo l'`id_token` come riserva, l'immagine
  **non** va considerata rimossa: si lascia quella che c'è.
- Non mostrare il data-URI direttamente nelle pagine e non tenerlo nel database: decodificarlo
  una volta e salvarlo come file (§ 6, punto 7).

## 6. Comportamento richiesto alla piattaforma

1. Pulsante "**Accedi con SSO AGESCI Campania**" nella pagina di login (affiancato al login
   locale durante la transizione).
2. **Primo login SSO**:
   - esiste un utente locale con la stessa email (confronto case-insensitive) → collegarlo;
   - altrimenti → crearlo, con ruolo locale minimo/nessuno, più quanto derivato dai ruoli
     globali.
3. **Ogni login SSO**: ricalcolare **solo** i ruoli globali da `groups`. Se un ruolo globale
   non c'è più nel claim, va revocato (riportando l'utente al ruolo di default della
   piattaforma). I ruoli locali non si toccano.
4. **MFA**: non chiederla a chi è entrato via Sestante **in questa sessione**. Il criterio deve
   essere il metodo di autenticazione della sessione corrente, **non** "l'utente ha un account
   Sestante collegato": altrimenti un utente collegato che entra con password locale salta la
   MFA. Chi usa il login locale resta soggetto alle regole MFA della piattaforma.
5. **Logout**: il logout locale chiude solo la sessione della piattaforma (la sessione su
   Sestante resta, è il senso dell'SSO). Un logout globale via `end-session` si implementa solo
   se l'utente lo chiede.
6. **Utenti senza email** o con email duplicata: rifiutare il login con un messaggio chiaro,
   non creare account parziali.
7. **Immagine del profilo** (solo se la piattaforma mostra foto degli utenti e chiede lo scope
   `avatar`): a ogni login SSO allineare la foto locale a `picture` di `userinfo` (§ 5.1).
   - data-URI → controllare il tipo (solo `image/jpeg|png|webp|gif`) e la dimensione, decodificare
     e salvarla come file della piattaforma; riscriverla solo se è cambiata (confronto di un hash
     salvato insieme alla foto).
   - URL `https://…` → scaricarla (timeout breve, stessi controlli) oppure ignorarla: scelta della piattaforma.
   - assente o percorso relativo → rimuovere la foto **solo se era arrivata da Sestante**; una foto caricata
     dall'utente sulla piattaforma resta. Serve quindi ricordare l'origine della foto.
   - Se l'utente cambia la foto sulla piattaforma, vale fino al login SSO successivo in cui
     Sestante ne invia una diversa da quella già salvata. Meglio però rimandare l'utente a
     Sestante (`https://auth.agescicampania.net/if/user/#/settings`) e togliere il caricamento
     locale per chi entra via SSO.
   - L'allineamento avviene solo al login: una foto cambiata su Sestante appare sulla
     piattaforma al login SSO successivo.
   - Un errore nella foto (formato, dimensione, decodifica) non deve mai bloccare il login:
     registrarlo nel log e proseguire.

### 6.1 Django + django-allauth (caso standard dell'ecosistema)

- `INSTALLED_APPS`: `allauth.socialaccount` e `allauth.socialaccount.providers.openid_connect`.
- Provider id **`sestante`** (stesso nome su tutte le piattaforme):

```python
SOCIALACCOUNT_PROVIDERS = {
    "openid_connect": {
        "SERVERS": [
            {
                "id": "sestante",
                "name": "SSO AGESCI Campania",
                "server_url": "https://auth.agescicampania.net/application/o/<slug>/",
                "APP": {
                    "client_id": env.str("SOCIAL_SESTANTE_CLIENT_ID", default=""),
                    "secret": env.str("SOCIAL_SESTANTE_CLIENT_SECRET", default=""),
                },
                "SCOPE": ["openid", "profile", "email"],  # + "avatar" se serve la foto (§ 5.1)
            }
        ]
    },
}
SOCIALACCOUNT_EMAIL_AUTHENTICATION = True
SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT = True
SOCIALACCOUNT_ADAPTER = "<app>.adapters.<Nome>SocialAccountAdapter"
```

- Variabili in `.env.template`: `SOCIAL_SESTANTE_CLIENT_ID=` e `SOCIAL_SESTANTE_CLIENT_SECRET=`
  (vuote, con commento su dove recuperarle).
- **Callback**: con allauth recenti è `/accounts/oidc/sestante/login/callback/`, con versioni
  più vecchie `/accounts/openid_connect/sestante/login/callback/`. Verificarlo sulla versione
  installata (`reverse("openid_connect_callback", kwargs={"provider_id": "sestante"})` in
  `manage.py shell`, o l'elenco URL) prima di comunicarlo all'utente per il blueprint. Il
  launch URL è il corrispondente `/accounts/oidc/sestante/login/?next=/`.
- Adapter: `is_auto_signup_allowed` vero solo per `provider == "sestante"` (gli altri social
  login, se presenti, restano solo collegamento a utenti esistenti); `pre_social_login` per il
  collegamento per email e la sincronizzazione dei ruoli globali; `populate_user` per i ruoli
  del nuovo utente. Con allauth ≥ 65.11 `extra_data` è `{"userinfo": {...}, "id_token": {...}}`.
- Foto (scope `avatar`): leggere `extra_data["userinfo"]["picture"]` in `pre_social_login`
  (utenti esistenti) e dopo la creazione dei nuovi (es. segnale `social_account_added` o
  `save_user`). Allauth salva `extra_data` nel database a ogni login, quindi va tolto il
  data-URI (`pop("picture")`, solo se inizia con `data:`) **dopo** averlo letto e **prima**
  del salvataggio, altrimenti ogni account si porta dietro fino a ~700 KB di testo. Tenere
  `picture` quando è un URL.
- MFA con `allauth.mfa`: in un `MFAAdapter` personalizzato, `is_mfa_enabled` restituisce
  `False` solo durante il login in corso se tra i metodi della sessione
  (`request.session["account_authentication_methods"]`) c'è
  `{"method": "socialaccount", "provider": "sestante"}`; eventuali middleware che forzano
  l'attivazione della MFA devono usare lo stesso criterio (§ 6 punto 4).
- Impostazioni proxy (`SECURE_PROXY_SSL_HEADER`, `CSRF_TRUSTED_ORIGINS`, …) come da
  `docs/INTEGRAZIONE.md` del frontend § 2.5: se sono sbagliate allauth genera callback
  `http://` e Sestante le rifiuta (`redirect_uri` non corrispondente).

Implementazione di riferimento già funzionante: Plancia, `apps/accounts/adapters.py` e
`apps/accounts/middleware.py` nel repo
[`AGESCI-Campania/plancia`](https://github.com/AGESCI-Campania/plancia). Prenderla
come esempio, adattando nomi di ruoli e modelli; per la MFA seguire § 6 punto 4, non la
verifica sull'esistenza dell'account collegato.

### 6.2 Altri stack

Usare una libreria OIDC certificata/matura con discovery, flusso **authorization code**
(con PKCE se il client è pubblico, consigliato comunque), `state` e `nonce`, validazione di
firma, `iss` e `aud` dell'`id_token`. Niente implicit flow, niente password grant.

## 7. Installazione sul server

Ogni piattaforma, anche quelle esistenti reinstallate da zero, segue la stessa sequenza:

1. Procedura del frontend (`docs/INTEGRAZIONE.md` § 4): DNS, clone in `/opt/<repo>`,
   `scripts/installa.sh`, blocco `caddy/sites/<progetto>.caddy`.
2. L'utente aggiunge/aggiorna `blueprints/provider-<slug>.yaml` in `sestante` e lancia
   `scripts/aggiorna.sh` di Sestante.
3. L'utente copia client id e secret nel `.env` della piattaforma. Si trovano in
   <https://auth.agescicampania.net/if/admin/#/core/providers> → `<Nome> AGESCI Campania` →
   modifica. Le istruzioni di installazione della piattaforma devono indicare questo passo
   (con quel percorso e i nomi delle variabili); `installa.sh` della piattaforma deve
   elencarli tra i passi manuali residui se sono vuoti, e l'app deve avviarsi anche senza
   (pulsante SSO nascosto o disabilitato), non andare in errore.
4. Login SSO di prova end-to-end, con un utente nuovo e uno già esistente (collegamento per
   email), uno nel gruppo `segreteria` e uno senza gruppi.

Sestante **non** è una dipendenza d'avvio della piattaforma (niente `After=sestante.service`
nella unit systemd): serve solo a runtime, al momento del login.

## 8. Checklist per l'agente della piattaforma

- [ ] provider OIDC con id `sestante`, discovery su `https://auth.agescicampania.net/application/o/<slug>/`
- [ ] client id/secret solo da variabili d'ambiente, chiavi vuote in `.env.template`
- [ ] callback verificata sulla libreria installata e comunicata all'utente con il blueprint (§ 4)
- [ ] collegamento per email degli utenti esistenti, provisioning dei nuovi
- [ ] sincronizzazione dei soli ruoli globali da `groups`, con revoca; ruoli locali intatti
- [ ] nessuna MFA ripetuta per le sessioni SSO, MFA invariata per il login locale
- [ ] se la piattaforma mostra foto degli utenti: scope `avatar` e allineamento della foto (§ 6, punto 7)
- [ ] login locale ancora attivo (transizione)
- [ ] header proxy e impostazioni HTTPS conformi a `INTEGRAZIONE.md` del frontend
- [ ] nessun riferimento residuo a `agescicampania.org` (issuer, redirect, email)
- [ ] guida utente della piattaforma aggiornata (come si entra con SSO, cosa cambia per la MFA)

## 9. Registro applicazioni

| Piattaforma | Slug | Redirect URI | Blueprint | Stato |
|---|---|---|---|---|
| Plancia | `plancia` | `https://plancia.agescicampania.net/accounts/oidc/sestante/login/callback/` | `provider-plancia.yaml` | blueprint pronto, piattaforma da reinstallare sul nuovo server |

Aggiornare la tabella (nel repo `sestante`) a ogni nuova piattaforma collegata.
