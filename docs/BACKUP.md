# Backup e ripristino di Sestante

Sestante decide chi può entrare in **tutte** le piattaforme: perderne i dati significa
lasciare tutti fuori. Il backup va quindi tenuto **anche fuori dal server**.

## Cosa viene salvato

`scripts/backup.sh` crea un unico archivio `sestante-<data>-<versione>.tar.gz` con:

| File nell'archivio | Contenuto |
|---|---|
| `database.sql` | dump PostgreSQL completo (utenti, gruppi, MFA, provider, sessioni…) |
| `env` | il `.env` del server: contiene `AUTHENTIK_SECRET_KEY` e `PG_PASS`. **Senza la chiave il dump non basta** (MFA, token e segreti cifrati non sarebbero più leggibili) |
| `data/` | file caricati dalla UI di Authentik |

Configurazione (blueprint, template, immagini, script) non serve: è in git.

L'archivio contiene segreti: va trattato come una password. La cartella sul server è
leggibile solo dal proprietario e dal gruppo della cartella; sul NAS limitarne l'accesso
allo stesso modo.

## Quando

- Ogni notte alle 03:30 (± 5 minuti) tramite il timer systemd `sestante-backup.timer`,
  installato da `scripts/installa.sh` / `scripts/aggiorna.sh` con la funzione
  `installa_backup_systemd` (`scripts/_sestante.sh`). Lo script gira come proprietario del
  repo (`agesci`); senza sudo, `installa.sh`/`aggiorna.sh` stampano il comando che
  l'amministratore deve eseguire. Se il server era spento all'ora prevista, il backup parte
  all'avvio successivo.
- A mano, quando serve: `scripts/backup.sh`.
- In più, `scripts/aggiorna.sh` salva sempre il database (`backups/authentik-*.sql.gz`,
  ultimi 10) prima di ogni aggiornamento.

Sul server gli archivi restano in `backups/` (in `.gitignore`) per 14 giorni. Cartella e
giorni si cambiano in `.env` con `BACKUP_DIR` e `BACKUP_GIORNI` (vedi `.env.template`).

Controlli [admin]:

```bash
systemctl list-timers sestante-backup.timer      # prossima e ultima esecuzione
systemctl status sestante-backup.service         # esito dell'ultima esecuzione
journalctl -u sestante-backup -n 50              # log
ls -lh /opt/sestante/backups/
```

## Copia sul NAS

Il NAS **scarica** gli archivi dal server (pull), non è il server a inviarli: se il server
fosse compromesso, non potrebbe cancellare le copie sul NAS. Si usa un utente dedicato che
può solo leggere la cartella dei backup via rsync.

### Sul server [admin], una volta

```bash
# utente senza password e senza sudo, usato solo dal NAS
sudo adduser --disabled-password --comment "Lettura backup per il NAS" backup-nas

# cartella dei backup: scrive agesci, legge il gruppo backup-nas; il bit setgid (2) fa
# ereditare il gruppo ai nuovi archivi, che backup.sh crea già leggibili dal gruppo
sudo install -d -o agesci -g backup-nas -m 2750 /opt/sestante/backups
sudo chgrp backup-nas /opt/sestante/backups/* 2>/dev/null; sudo chmod g+r /opt/sestante/backups/* 2>/dev/null

# chiave SSH del NAS limitata a rsync in sola lettura su quella cartella (rrsync è nel
# pacchetto rsync di Ubuntu)
sudo install -d -m 700 -o backup-nas -g backup-nas /home/backup-nas/.ssh
echo 'command="/usr/bin/rrsync -ro /opt/sestante/backups/",restrict <CHIAVE-PUBBLICA-DEL-NAS>' \
  | sudo tee /home/backup-nas/.ssh/authorized_keys >/dev/null
sudo chown backup-nas:backup-nas /home/backup-nas/.ssh/authorized_keys
sudo chmod 600 /home/backup-nas/.ssh/authorized_keys
```

`<CHIAVE-PUBBLICA-DEL-NAS>` è la riga `ssh-ed25519 AAAA… commento` generata sul NAS.

### Sul NAS

Generare una chiave SSH dedicata (`ssh-keygen -t ed25519 -N "" -f ~/.ssh/sestante_backup`),
metterne la parte pubblica nel comando sopra e pianificare (ogni giorno, dopo le 04:30):

```bash
rsync -a --exclude='.*' -e "ssh -i ~/.ssh/sestante_backup" \
  backup-nas@<server>: /percorso/sul/nas/sestante/
```

- Con `rrsync` il percorso remoto è relativo alla cartella dei backup: `backup-nas@<server>:`
  indica `/opt/sestante/backups/`.
- `--exclude='.*'` salta gli archivi in scrittura (backup.sh li crea con un nome nascosto e
  li rinomina solo a fine scrittura).
- **Senza `--delete`**: il NAS conserva anche gli archivi che il server ha già ruotato. La
  pulizia sul NAS va decisa a parte (es. tenere 30 giornalieri e 12 mensili).
- Prova manuale dal NAS: `ssh -i ~/.ssh/sestante_backup backup-nas@<server>` deve essere
  rifiutato (niente shell), mentre il comando `rsync` sopra deve scaricare i file.
- Se il NAS lo permette, farsi avvisare quando l'archivio più recente è più vecchio di 2
  giorni: è il modo per accorgersi che il backup sul server si è fermato.

Con un NAS Synology: Pannello di controllo → Utilità di pianificazione → attività
pianificata con lo script `rsync` sopra (la chiave in una cartella dell'utente che esegue
l'attività), oppure qualunque strumento che faccia pull via rsync su SSH.

## Ripristino

### Su un server nuovo (o reinstallato)

1. Preparare il server e il frontend come per una prima installazione, creare
   `/opt/sestante` e clonare il repo, **senza** lanciare `scripts/installa.sh`.
2. [agesci] Estrarre l'archivio e rimettere `.env` e `data/`:

   ```bash
   cd /opt/sestante
   mkdir -p /tmp/ripristino && tar -xzf /percorso/sestante-AAAAMMGG-HHMMSS-VERSIONE.tar.gz -C /tmp/ripristino
   cp /tmp/ripristino/env .env && chmod 600 .env
   mkdir -p data && cp -a /tmp/ripristino/data/. data/
   ```

   `AUTHENTIK_TAG` in `.env` è la versione con cui è stato fatto il backup (anche nel nome
   dell'archivio): va ripristinato con quella stessa versione, si aggiorna dopo.
3. Ricaricare il database **prima** di avviare Authentik (altrimenti crea un database vuoto
   con cui il dump va in conflitto):

   ```bash
   docker compose up -d postgresql
   docker compose ps postgresql          # attendere "healthy"
   docker compose exec -T postgresql sh -c 'psql -q -U "$POSTGRES_USER" "$POSTGRES_DB"' < /tmp/ripristino/database.sql
   ```

4. `scripts/installa.sh`: trova il `.env` esistente e non lo rigenera, avvia server e
   worker, riapplica i blueprint, installa unit systemd e timer di backup (eseguire i
   comandi per l'amministratore che stampa). Permessi di `data/` come nelle istruzioni di
   installazione.
5. Verifiche: login di un amministratore con la sua MFA, login SSO da una piattaforma.
6. `rm -rf /tmp/ripristino` (contiene segreti).

### Sullo stesso server (database danneggiato o da riportare indietro)

```bash
cd /opt/sestante
docker compose down
docker volume rm sestante_database          # cancella il database attuale!
```

poi dal punto 2 (`.env` e `data/` solo se vanno ripristinati anche loro).

### Prova di ripristino

Un backup mai ripristinato non è un backup verificato: fare la procedura almeno una volta
(es. su una macchina di prova con Docker, puntando l'host `auth.agescicampania.net` a quella
macchina solo localmente) e ripeterla dopo aggiornamenti importanti di Authentik.
