# Gestione utenti da parte della segreteria regionale

La segreteria regionale crea gli utenti di Sestante e assegna loro i **ruoli globali** delle
piattaforme, senza poter toccare gli amministratori né darsi permessi maggiori. Configurazione
in [`blueprints/rbac-gestione-utenti.yaml`](../blueprints/rbac-gestione-utenti.yaml) e
[`scripts/permessi_gestione_utenti.py`](../scripts/permessi_gestione_utenti.py).

Il gruppo `gestione-utenti` (chi gestisce gli utenti in Sestante) è distinto dal ruolo globale
`segreteria` (ciò che una persona è sulle piattaforme): una persona può avere l'uno, l'altro o
entrambi.

## Cosa può fare un membro di `gestione-utenti`

| Azione | Su chi |
|---|---|
| Entrare nell'amministrazione di Sestante, vedere utenti e gruppi | tutti |
| Creare utenti | — |
| Modificare, disattivare, reimpostare la password / inviare il link di recupero | utenti **non** amministratori |
| Aggiungere o togliere persone dai ruoli globali | solo `admin-multipiattaforma` e `segreteria` |

Non può: modificare amministratori, membri di `gestione-utenti` (sé stesso compreso), account
di servizio o chiunque abbia accesso all'amministrazione; assegnare ruoli RBAC; aggiungere
persone ad `authentik Admins` o a `gestione-utenti` dall'interfaccia; cambiare la
configurazione di Sestante.

## Come funziona

- Permessi globali del ruolo `gestione-utenti`: accesso all'amministrazione, vista e creazione
  utenti, vista gruppi.
- Permessi sui singoli utenti (vista, modifica, reset password):
  - gli utenti creati dalla segreteria li ricevono subito (permessi iniziali);
  - per tutti gli altri utenti non amministratori — creati dagli amministratori, importati —
    li assegna `scripts/permessi_gestione_utenti.sh`, **ogni ora** (timer
    `sestante-permessi.timer`) e a ogni `scripts/aggiorna.sh`. Dopo un'importazione di
    utenti si può lanciarlo subito a mano;
  - lo stesso script li **toglie** a chi diventa amministratore o entra in `gestione-utenti`
    (finestra massima di un'ora: per una promozione urgente lanciarlo a mano).
- Ogni creazione, modifica o eliminazione di utenti e gruppi fatta da un membro di
  `gestione-utenti` genera una **notifica** (email e campanella) al gruppo `authentik Admins`.

## Limite noto di Authentik (2026.8)

Chi può creare o modificare un utente può, usando direttamente le API, inserirlo in
**qualunque gruppo non superuser**: il controllo di Authentik blocca solo i gruppi che danno lo
stato di superuser. Un membro di `gestione-utenti` non può quindi diventare amministratore, ma
potrebbe per esempio creare un nuovo membro di `gestione-utenti` o mettere un utente in un
gruppo non previsto. Contromisure: la notifica sopra (un abuso si vede subito), i gruppi di
default con ruoli ampi (`authentik Read-only`, `authentik Agent-Users`) rimossi, nessun
permesso della segreteria su chi ha accesso all'amministrazione.

**Regola per gli amministratori**: non creare gruppi con ruoli RBAC oltre a quelli previsti; se
servono, valutare prima l'effetto di questo limite.

## Operazioni per gli amministratori

- **Aggiungere una persona alla segreteria**: utente nominale (non condiviso) → gruppo
  `gestione-utenti`. Lo fa solo un amministratore. Al primo accesso configura la MFA.
- **Nuovo ruolo globale** (nuovo gruppo che le piattaforme leggono dal claim `groups`): in
  `blueprints/rbac-gestione-utenti.yaml` aggiungere il gruppo con le due voci `permissions`
  come per `segreteria`, poi commit, push e `scripts/aggiorna.sh`.
- **Utenti invitati da una piattaforma** (path `utenti/invitati`, attributo
  `piattaforme_consentite`): entrano solo nella piattaforma che li ha invitati. Per allargare
  l'accesso la segreteria toglie l'attributo (o aggiunge lo slug di un'altra piattaforma) e solo
  dopo assegna eventuali ruoli globali. Vedi [INVITI-PIATTAFORME.md](INVITI-PIATTAFORME.md).
- **Utente che non riesce ad accedere** (password dimenticata, telefono con l'app dei codici
  perso): mandargli [AIUTO-ACCESSO.md](AIUTO-ACCESSO.md). Con il link di recupero via email
  entra senza secondo fattore e poi sostituisce da solo il dispositivo nelle impostazioni.
  Serve un intervento solo se non può più leggere la sua email. In quel caso, dopo aver
  verificato l'identità per un altro canale (telefono, di persona; mai fidarsi della sola email
  o di un messaggio), la segreteria corregge l'email dell'utente e gli manda il link di recupero.
  Eliminare i dispositivi MFA di un utente spetta solo agli amministratori, perché il ruolo
  `gestione-utenti` non ha permessi sui dispositivi.
- **Verifica a mano dei permessi**: [agesci] `cd /opt/sestante && scripts/permessi_gestione_utenti.sh`
  stampa quanti utenti sono gestibili dalla segreteria e quanti esclusi, e quanti invitati
  dalle piattaforme hanno gruppi o ruoli non previsti.
- **Stato del timer**: `systemctl list-timers sestante-permessi.timer`,
  `journalctl -u sestante-permessi -n 20`.
