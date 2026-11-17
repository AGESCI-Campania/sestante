# CLAUDE.md — Sestante

Riferimento di continuità per Claude Code. Documento di progettazione completo:
`Sestante_Progettazione.md` (nella root del repo) — leggerlo per intero prima di iniziare.

## Cos'è questo progetto

Sestante è l'Identity Provider SSO condiviso per le piattaforme AGESCI Campania (Plancia,
Bussola, Catello, future). **Non è un'app Django custom**: è un deployment configurato di
[Authentik](https://goauthentik.io) (open source, MIT license, Python/Django/Celery/PostgreSQL
sotto il cofano). Il lavoro qui è quasi tutto configurazione (Docker Compose, variabili
d'ambiente, Blueprints/API di Authentik), non scrittura di codice applicativo.

## Decisioni prese (non rimetterle in discussione senza confermare con l'utente)

- Nome: **Sestante**. Dominio: `auth.agescicampania.net` (`agescicampania.org` abbandonato per un
  problema con il registrar, prima della produzione: host, URL ed email sono tutti su `.net`).
- Piattaforma pilota per la prima integrazione OIDC: **Plancia** (ha utenti reali; Catello non
  è mai stato usato in produzione, quindi non è un test realistico).
- Due Gruppi Authentik per i ruoli globali: `admin-multipiattaforma` e `segreteria` — mappati
  nel claim `groups` del token OIDC (di serie nello scope `profile` di Authentik).
- MFA vive solo su Sestante; le piattaforme client non la richiedono più in autonomia una
  volta collegate. Eccezione: con l'accesso via Google/Apple vale la MFA del provider, Sestante non
  chiede il proprio secondo fattore (decisione 2026-11-17).
- Periodo di transizione sulla piattaforma pilota: 60 giorni, con disattivazione del login
  locale subordinata alla verifica che tutti gli utenti attivi abbiano fatto almeno un login
  SSO riuscito (non una scadenza a calendario cieca).
- Amministrazione di Sestante: gruppo ristretto di 2-3 persone fin da subito, mai un solo
  account (bus factor).

## Convenzioni del progetto (stesse di Plancia/Catello/Bussola)

- Licenza MIT, copyright Andrea Bruno — file `LICENSE` già incluso.
- README con badge shields.io.
- `.gitignore` che esclude `.env`, dati/volumi Docker, certificati — **mai committare
  segreti** (client secret dei Provider, `AUTHENTIK_SECRET_KEY`, password PostgreSQL).
- Tutto ciò che è configurazione riproducibile va preferibilmente espresso come codice
  (Blueprints YAML di Authentik, o script idempotenti), non come click manuali in UI non
  documentati — coerente con lo spirito "tutto tracciabile in git" degli altri progetti.

## Deploy e aggiornamento (da 2026-11)

- Server dedicato (Ubuntu 26.04, nessun Virtualmin/Apache) alle piattaforme
  `*.agescicampania.net`, repo clonato in `/opt/sestante`.
- Reverse proxy: Caddy dal repo `AGESCI-Campania/agesci-campania-web-frontend`, rete Docker
  esterna `agesci-proxy` (alias `sestante-server`, in `docker-compose.override.yml`). Le regole
  sono in `docs/INTEGRAZIONE.md` di quel repo.
- `scripts/installa.sh` — prima installazione; `scripts/aggiorna.sh` — aggiornamento (backup DB,
  allineamento `AUTHENTIK_TAG` al default di `docker-compose.yml`, riapplicazione blueprint).
  Entrambi installano/aggiornano la unit systemd `sestante.service` (dopo quella del proxy)
  con `installa_servizio_systemd`; senza sudo stampano il comando per l'amministratore.
  Funzioni condivise in `scripts/_comune.sh` (copia identica di quello del repo frontend) e
  `scripts/_sestante.sh` (elenco blueprint, backup notturno).
- Backup: `scripts/backup.sh` (DB + `.env` + `data/` + `secrets/`), timer systemd `sestante-backup.timer`
  installato da `installa_backup_systemd` in `scripts/_sestante.sh`; procedura in `docs/BACKUP.md`.
- Segreteria regionale: gruppo `gestione-utenti` (crea utenti, assegna solo i ruoli globali, mai
  permessi sugli amministratori), `blueprints/rbac-gestione-utenti.yaml` + timer orario
  `sestante-permessi.timer`; regole e limite noto di Authentik in `docs/GESTIONE-UTENTI.md`.
- Accesso con Google/Apple: `blueprints/source-google.yaml`, `source-apple.yaml` (sorgenti spente
  finché mancano le credenziali in `.env`; chiave Apple in `secrets/`, montata nel worker), flow
  `default-source-authentication` senza MFA di Sestante (accettata quella di Google/Apple, decisione
  dell'utente 2026-11-17), nessuna registrazione automatica (`email_link`); procedura in
  `docs/LOGIN-SOCIAL.md`.
- Nuovo blueprint: aggiungerlo all'elenco `BLUEPRINTS` in `scripts/_sestante.sh`.
- Collegamento di una piattaforma client: `docs/INTEGRAZIONE-SSO.md` è il contratto verso gli
  agenti degli altri repo (endpoint, claim, blueprint Provider, comportamento richiesto); se
  cambia una regola qui, aggiornarlo nello stesso commit.
- Nuova versione di Authentik: riscaricare il compose ufficiale (punto 1 sotto), aggiornare
  `AUTHENTIK_TAG` in `.env.template`, commit e push, poi `scripts/aggiorna.sh` sul server.

## Task operativi — Fase 0 (deploy base, nessuna piattaforma ancora collegata)

Segui l'ordine; verifica sempre la documentazione ufficiale corrente
(`https://docs.goauthentik.io/install-config/`) prima di eseguire un passo, perché versioni e
dettagli di configurazione cambiano.

1. **Non scrivere il docker-compose.yml a mano.** Scaricare quello ufficiale:
   `wget -O docker-compose.yml https://goauthentik.io/docker-compose.yml`
   La documentazione ufficiale raccomanda esplicitamente questo approccio invece di scriverlo
   da zero, e di ripetere il download ad ogni upgrade di versione.
2. Popolare `.env` a partire da `.env.template` (incluso in questo repo) — generare
   `PG_PASS` e `AUTHENTIK_SECRET_KEY` con `openssl rand -base64`, mai valori inventati o
   deboli.
3. Fissare il tag immagine a una versione specifica (mai `:latest`, che è deprecato e non si
   aggiorna più) — verificare l'ultima versione stabile al momento dell'esecuzione.
4. Valutare l'uso delle variabili `AUTHENTIK_BOOTSTRAP_EMAIL` /
   `AUTHENTIK_BOOTSTRAP_PASSWORD` / `AUTHENTIK_BOOTSTRAP_TOKEN` per automatizzare la creazione
   del primo account amministratore invece del flusso manuale via UI — utile per rendere il
   deploy ripetibile.
5. `docker compose pull && docker compose up -d`, poi verificare lo stato di salute dei
   container (postgresql, redis, server, worker).
6. Primo accesso su `/if/flow/initial-setup/`, creazione dell'account amministratore
   nominale (non `akadmin` per l'uso quotidiano — coerente con la decisione "gruppo ristretto
   di 2-3 persone", da creare come account separati, non condivisi).
7. Configurare l'email globale (`AUTHENTIK_EMAIL__*`) per notifiche/recupero accesso.
8. Creare i due Gruppi globali `admin-multipiattaforma` e `segreteria` — **preferibilmente
   come Blueprint YAML** versionato in questo repo (cartella `blueprints/`) invece che a mano
   in UI, verificando lo schema Blueprint corrente nella documentazione ufficiale prima di
   scriverlo (lo schema può differire da versione a versione, non fidarsi di esempi trovati
   altrove senza verificarli contro l'istanza installata).
9. **Non procedere alla Fase 1** (collegamento di Plancia) senza conferma esplicita
   dell'utente: la Fase 0 si considera conclusa quando Sestante è raggiungibile, ha
   amministratori nominali configurati, e i due gruppi globali esistono.

## Cosa NON fare in questa fase

- Non collegare ancora nessuna piattaforma client (Plancia/Bussola/Catello) — è Fase 1,
  successiva e da confermare separatamente.
- Non disattivare il login locale di nessuna piattaforma esistente.
- Non usare l'account `akadmin` di default per l'uso quotidiano dopo il setup iniziale.
