# Sestante — Identity Provider SSO per le piattaforme AGESCI Campania
### Documento di progettazione · Sessione dedicata, propedeutica allo scaffold di Bussola

> Documento di **architettura e progettazione**, non di implementazione.
> Nome del progetto provvisorio: **Sestante** (strumento di navigazione, coerente col filo
> nautico Plancia/Bussola — da confermare o cambiare, §10.1).
> Decisione presa: adottiamo **Authentik** come Identity Provider invece di costruire un
> provider OIDC custom in Django. Questo documento disegna come Authentik si inserisce
> nell'ecosistema AGESCI Campania (Plancia, Bussola, Catello, futuri), non come funziona
> Authentik internamente (per quello, la documentazione ufficiale resta la fonte primaria).

---

## 1. Obiettivo

Un utente che si autentica su una piattaforma (es. Plancia) non deve ripetere il login
passando a un'altra (es. Bussola). Ogni piattaforma mantiene comunque i propri ruoli locali
specifici (PGV/CRP/CSQ in Plancia, ruoli gruppo in Catello, ecc.). Due ruoli sono invece
**globali**, validi automaticamente su ogni piattaforma collegata all'SSO:

- **ADMIN multi-piattaforma** — amministra tutte le piattaforme
- **SEGRETERIA** — ha questo ruolo su tutte le piattaforme

A questi si affianca l'**ADMIN locale**, che resta un ruolo come gli altri gestito dalla
singola piattaforma (scoped solo a quella), non dall'IdP — coerente con la decisione presa
nella sessione precedente.

## 2. Perché Authentik (riepilogo della decisione)

- Stack Python/Django/Celery/PostgreSQL, coerente con l'ecosistema esistente
- Licenza MIT (community edition), utilizzabile liberamente
- Deployment via Docker Compose, footprint contenuto — stesso pattern operativo di
  Plancia/Catello
- Provider OIDC/OAuth2 certificato, con gestione utenti, gruppi, MFA e API di
  amministrazione già pronte — non lo costruiamo, lo configuriamo

## 3. Architettura di deployment

Sestante è un **servizio a sé**, con il proprio `docker-compose` (server + worker + PostgreSQL
+ Redis, come da immagine ufficiale Authentik), esposto su un proprio (sotto)dominio, es.
`auth.agescicampania.org`. Non condivide database né processi con nessuna piattaforma — questo
è il punto centrale della decisione presa nella sessione precedente (§8bis.1 del documento
Bussola): un problema in una piattaforma non deve poter compromettere l'accesso alle altre.

Ogni piattaforma (Plancia, Bussola, Catello, future) resta un progetto Django indipendente,
con il proprio database, che si limita a **fidarsi** dell'identità e dei ruoli globali
dichiarati da Sestante.

## 4. Modello di configurazione in Authentik

Per ogni piattaforma collegata si crea in Authentik una coppia **Provider + Application**
(terminologia Authentik: il Provider definisce la configurazione OAuth2/OIDC — redirect URI,
scope, chiavi di firma; l'Application è ciò che viene assegnato agli utenti/gruppi per
l'accesso):

- `Provider: Plancia` / `Application: Plancia`
- `Provider: Bussola` / `Application: Bussola`
- `Provider: Catello` / `Application: Catello`

**Ruoli globali come Gruppi**: si creano due Gruppi Authentik, es. `admin-multipiattaforma` e
`segreteria`. Authentik include già di serie un claim `groups` nel token (tramite lo scope
`profile`); ogni piattaforma, al login, legge questo claim e riconosce se l'utente appartiene
a uno di quei due gruppi, applicando i permessi corrispondenti **senza bisogno che la
piattaforma stessa gestisca l'assegnazione** — è tutta e sola responsabilità di chi amministra
Sestante.

**Non serve** creare in Authentik un gruppo per ogni ruolo locale (PGV, CRP, CSQ, ADMIN locale
di Plancia, ecc.): quei ruoli restano dati e decisioni della singola piattaforma, come deciso
in precedenza.

## 5. Integrazione lato client (ogni piattaforma)

Le piattaforme usano già `django-allauth`. Si aggiunge il provider OIDC generico di allauth,
puntato all'endpoint di discovery di Sestante
(`https://auth.agescicampania.org/application/o/<slug-piattaforma>/.well-known/openid-configuration`).

Flusso al login:
1. L'utente sceglie "Accedi con SSO AGESCI Campania" sulla piattaforma.
2. Redirect a Sestante; se ha già una sessione valida lì, non rivede alcuna schermata di
   login (autenticazione silenziosa) — è l'esperienza "salto da una piattaforma all'altra"
   richiesta.
3. Al ritorno, la piattaforma riceve l'id_token con i claim `groups` (per i ruoli globali) e
   l'identità (email, codice socio se mappato come attributo).
4. **Provisioning al primo accesso**: se l'utente non esiste ancora localmente, la piattaforma
   lo crea automaticamente, **senza alcun ruolo locale** — chi ha i permessi per farlo
   (segreteria/admin locale) glielo assegna in un secondo momento, esattamente come oggi.
5. Ad ogni login successivo, la piattaforma aggiorna solo lo stato dei ruoli globali dal
   claim `groups`; il ruolo locale non viene mai toccato dal flusso SSO.

**MFA**: si sposta a vivere solo su Sestante. Le piattaforme non richiedono più MFA in
autonomia — altrimenti l'SSO non elimina davvero il re-login, come discusso.

## 6. Il modulo di consultazione cross-piattaforma (in Bussola)

Authentik conosce gli utenti e i **ruoli globali**, ma non sa nulla dei **ruoli locali** di
ciascuna piattaforma — quelli restano nei rispettivi database. Il modulo che Andrea ha chiesto
resta quindi un pannello su misura, non qualcosa che Authentik offre già pronto:

- **Fonte 1 — Authentik**: elenco utenti registrati, stato (attivo/sospeso), appartenenza ai
  gruppi globali (`admin-multipiattaforma`, `segreteria`), tramite l'**API di amministrazione**
  di Authentik (autenticata con un token di servizio dedicato, permessi in sola lettura dove
  possibile).
- **Fonte 2 — ogni piattaforma**: un endpoint interno (`/api/sso/ruoli-locali/`, già previsto
  nel documento Bussola) che riporta i ruoli locali assegnati a ciascun utente su quella
  piattaforma.
- Il modulo in Bussola aggrega le due fonti per dare la vista "utente → ruolo per piattaforma"
  richiesta. Le **azioni di scrittura** (assegnare/revocare un ruolo globale) passano
  dall'API di Authentik, non da uno storage locale in Bussola — Bussola resta un pannello di
  consultazione/comando, non la fonte di verità.

## 7. Migrazione degli utenti esistenti

Plancia e Catello hanno già utenti reali con account `django-allauth` locali (email, MFA,
eventuali social provider collegati). Passare all'SSO richiede una strategia di
riconciliazione, non un semplice switch:

- **Collegamento per email**: al primo login SSO su una piattaforma esistente, se l'email
  restituita da Sestante corrisponde a un account locale già esistente, si collega l'identità
  SSO a quell'account (invece di crearne uno nuovo) — il ruolo locale già assegnato resta
  intatto.
- **Popolamento iniziale di Sestante**: gli utenti vanno comunque creati/importati in Authentik
  prima del rollout (es. da un export delle anagrafiche esistenti) — è un'attività operativa a
  sé, da pianificare quando affrontiamo l'implementazione.
- **Periodo di transizione**: ha senso mantenere il login locale (email+password/MFA) attivo
  in parallelo all'SSO per un periodo, non disattivarlo di colpo, per non bloccare fuori
  nessuno in caso di problemi di configurazione.

## 8. Sicurezza

- Client secret di ogni Provider Authentik trattati come segreti (mai committati — coerente
  con la bonifica già in corso su Bussola).
- Comunicazione Sestante↔piattaforme solo HTTPS.
- Il token di servizio usato dal modulo di Bussola per leggere l'API di Authentik ha permessi
  minimi necessari (sola lettura su utenti/gruppi), non un token amministrativo pieno.
- Backup del database di Sestante trattato con la massima priorità: è la fonte di verità per
  l'accesso a *tutte* le piattaforme.

## 9. Roadmap a fasi

- **Fase 0 — Deploy di Sestante**: docker-compose dedicato, dominio proprio, primo
  amministratore, configurazione base (senza ancora nessuna piattaforma collegata).
- **Fase 1 — Prima integrazione pilota**: una sola piattaforma (da scegliere, §10.3) collegata
  come client OIDC, per validare il pattern end-to-end (login, provisioning, claim dei ruoli
  globali) prima di estenderlo.
- **Fase 2 — Migrazione utenti esistenti** sulla piattaforma pilota, con collegamento per email
  e periodo di transizione (§7).
- **Fase 3 — Estensione alle altre piattaforme**: Catello (mai stato in produzione, quindi
  integrazione diretta senza migrazione utenti) e Bussola nel suo scaffold da zero, che nasce
  quindi già "SSO-ready" invece di dover essere ritoccata.
- **Fase 4 — Modulo di consultazione cross-piattaforma** in Bussola (§6).

## 10. Decisioni prese

1. **Nome definitivo**: **Sestante**.
2. **Dominio**: `auth.agescicampania.org`.
3. **Piattaforma pilota per la Fase 1**: **Plancia** — corretto rispetto alla prima ipotesi:
   Catello non è mai stato usato in produzione, quindi non ha utenti reali su cui validare
   davvero il pattern (login, provisioning, claim dei ruoli globali, migrazione per email).
   Plancia ha utenti reali fin da subito ed è quindi l'unica scelta che verifica il flusso
   sotto condizioni vere. Il rischio si gestisce con il periodo di transizione (§10.4) e
   mantenendo il login locale attivo in parallelo finché l'SSO non è verificato stabile.
4. **Periodo di transizione (§7)**: **60 giorni** dalla migrazione della piattaforma pilota,
   con disattivazione del login locale subordinata alla verifica che tutti gli utenti attivi
   abbiano effettuato almeno un login SSO riuscito — non una scadenza a calendario cieca.
5. **Amministrazione di Sestante**: un **piccolo gruppo ristretto (2-3 persone)** fin da
   subito, non un singolo account — è il punto singolo di fallimento per l'accesso a tutto
   l'ecosistema, va evitato un bus factor di 1 fin dall'inizio.

---

*Documento di riferimento per Claude Code. Decisioni fissate: si procede con la Fase 0
(deploy Sestante) prima di riprendere lo scaffold di Bussola.*
