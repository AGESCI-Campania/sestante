# Inviti creati dalle piattaforme

Una piattaforma collegata (per esempio Tana) può far creare un account Sestante a una persona
nuova a cui ha dato un ruolo locale, senza passare dalla segreteria regionale. Il responsabile
assegna il ruolo sulla piattaforma, la piattaforma chiede a Sestante un **invito** per quell'email
e manda alla persona il link. La persona sceglie la password, configura il secondo fattore e,
al primo accesso SSO, la piattaforma la riconosce per email.

**L'account creato così vale solo per la piattaforma che ha invitato.** Configurazione in
[`blueprints/inviti-piattaforme.yaml`](../blueprints/inviti-piattaforme.yaml); l'account di
servizio di ogni piattaforma è nel suo `blueprints/provider-<slug>.yaml`. Contratto verso le
piattaforme: [INTEGRAZIONE-SSO.md § 10](INTEGRAZIONE-SSO.md#10-inviti-dalla-piattaforma-facoltativo).

## Come funziona

- Ogni piattaforma che invita ha un **account di servizio** `svc-<slug>` con il **suo** ruolo
  RBAC `inviti-<slug>`. Il ruolo dà solo questi permessi: creare inviti, vedere e revocare quelli
  della piattaforma, vedere il flusso di iscrizione. Non dà nessun permesso su utenti o gruppi: un
  token rubato non crea utenti, non dà ruoli globali e non legge l'anagrafica. Serve un ruolo per
  piattaforma perché Authentik dà i permessi sugli inviti creati al ruolo, non all'account. Con un
  ruolo condiviso una piattaforma vedrebbe e revocherebbe gli inviti delle altre.
- La persona invitata apre `https://auth.agescicampania.net/if/flow/sestante-iscrizione-invito/?itoken=…`
  e il flusso fa questi passi:
  1. controlla l'invito: deve esistere, non essere scaduto, essere stato creato per questo flusso
     e avere una scadenza entro 31 giorni;
  2. lo rifiuta se in `fixed_data` c'è una chiave diversa da `email`, `username`, `name` e
     `attributes.invito`, o se non l'ha creato un account di servizio attivo con
     `attributes.piattaforma` e il ruolo `inviti-<piattaforma>` corrispondente;
  3. se esiste già un account con quell'email o quello username (maiuscole e minuscole sono
     indifferenti), mostra «Hai già un account Sestante…» e si ferma. Così non nascono doppioni;
  4. chiede nome, password e ripetizione della password, con le regole di Authentik per il
     cambio password. L'email arriva dall'invito, si vede ma non si cambia;
  5. ripete il controllo dei punti 1-3 e crea l'utente nel path `utenti/invitati`, senza gruppi;
  6. fa configurare subito il secondo fattore (app o passkey) e completa l'accesso a Sestante.
- La **piattaforma consentita** la ricava Sestante da `attributes.piattaforma` dell'account che
  ha creato l'invito, mai dai dati dell'invito. Sul nuovo utente la scrive in
  `attributes.piattaforme_consentite` (es. `["tana"]`). In `attributes.invito` resta la traccia
  di chi ha chiesto l'invito, come l'ha passata la piattaforma.
- La policy `sestante-accesso-piattaforme`, legata a **ogni applicazione**, fa entrare chi ha
  `piattaforme_consentite` solo nelle piattaforme elencate. Nelle altre l'utente riceve il diniego
  di Sestante, quindi la piattaforma non crea nessun account. Per chi non ha l'attributo non
  cambia niente.
- L'invito **non è monouso**: vale fino alla scadenza. Se la persona chiude la pagina a metà
  può riaprire il link. Dopo la creazione dell'account il controllo del punto 3 blocca ogni
  riuso. Gli inviti scaduti li cancella Authentik.
- Gli inviti non li spedisce Sestante: l'email la manda la piattaforma, con il suo testo.

## Controlli per gli amministratori

- **Notifica** (email e campanella ad `authentik Admins`) per ogni invito creato.
- **Controllo orario** (`scripts/permessi_gestione_utenti.sh`, timer `sestante-permessi.timer`):
  un utente con `piattaforme_consentite` che risulta in un gruppo o con un ruolo genera un
  avviso (evento `configuration_warning`, notificato dalla regola di default di Authentik).
  L'avviso si ripete ogni ora finché il caso non è risolto.
- Gli invitati si trovano in Directory → Users, path `utenti/invitati`.

## Operazioni

### Allargare l'accesso di un invitato

Per esempio quando la persona diventa anche capo in Plancia. Lo fa la segreteria
(`gestione-utenti`) o un amministratore: utente → modifica → Attributi → togliere
`piattaforme_consentite`, oppure aggiungere lo slug di un'altra piattaforma alla lista. Solo
dopo, se serve, si assegna un ruolo globale: l'avviso orario segnala gli invitati ancora limitati
che hanno gruppi.

### Abilitare gli inviti per una nuova piattaforma

1. In `blueprints/provider-<slug>.yaml` aggiungere l'account di servizio e il token, come in
   `provider-tana.yaml` (modello in INTEGRAZIONE-SSO.md § 10.1): ruolo `inviti-<slug>` con i
   permessi iniziali e la vista del flusso; `svc-<slug>` con `attributes.piattaforma: <slug>`
   uguale allo slug dell'applicazione e quel ruolo; il token `svc-<slug>-inviti`.
2. Commit, push e `scripts/aggiorna.sh` sul server.
3. Copiare la chiave da <https://auth.agescicampania.net/if/admin/#/core/tokens>, token
   `svc-<slug>-inviti`, pulsante di copia del token, e metterla nel `.env` della piattaforma come
   `SESTANTE_INVITI_TOKEN`. La chiave non va mai in un repo.

Il binding di `sestante-accesso-piattaforme` all'applicazione va messo in **ogni**
`provider-<slug>.yaml`, anche se la piattaforma non invita. Senza binding gli invitati delle
altre piattaforme ci entrerebbero.

### Ruotare il token di una piattaforma

Directory → Tokens and App passwords → `svc-<slug>-inviti` → eliminare. Poi lanciare
`scripts/aggiorna.sh`, che lo ricrea con una chiave nuova, e copiare la chiave nel `.env` della
piattaforma come sopra. Fino a quel momento la piattaforma non può creare inviti; quelli già
spediti restano validi.

### Revocare gli inviti aperti

Directory → Invitations, filtrare per `created_by` = `svc-<slug>` ed eliminare. Per bloccare
subito tutti gli inviti di una piattaforma, anche quelli non ancora usati, basta disattivare
`svc-<slug>`: il controllo del flusso rifiuta gli inviti degli account disattivati.

## Regole per gli amministratori

- `sestante-invito` deve restare l'**unico** invitation stage di Sestante. Un invito senza
  flusso varrebbe anche in un altro flusso con un invitation stage, saltando i controlli.
- Non creare inviti a mano per `sestante-iscrizione-invito`: senza un account di servizio di
  piattaforma come autore vengono rifiutati. Per creare un account a mano si usa Directory →
  Users, come sempre.
- Non assegnare i ruoli `inviti-<slug>` a persone o gruppi: vanno solo al rispettivo account
  `svc-<slug>`. Un ruolo, un account.
