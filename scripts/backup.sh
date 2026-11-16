#!/usr/bin/env bash
# Backup completo di Sestante in un unico archivio: dump del database, .env (contiene
# AUTHENTIK_SECRET_KEY, senza la quale il dump non basta) e data/.
# Eseguito ogni notte dal timer systemd sestante-backup.timer (vedi docs/BACKUP.md);
# si può lanciare anche a mano. Ripristino: docs/BACKUP.md.
#
# Uso:  scripts/backup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_comune.sh

richiedi_comandi docker tar gzip
[[ -f .env ]] || errore ".env mancante: Sestante non è installato in $(pwd -P)."

dest="$(leggi_var BACKUP_DIR)"; dest="${dest:-backups}"
giorni="$(leggi_var BACKUP_GIORNI)"; giorni="${giorni:-14}"
[[ "$giorni" =~ ^[0-9]+$ ]] || errore "BACKUP_GIORNI non valido: $giorni"

# Archivi leggibili dal gruppo della cartella (es. l'utente del NAS che li scarica), non da altri
umask 027
mkdir -p "$dest"

nome="sestante-$(date +%Y%m%d-%H%M%S)-$(leggi_var AUTHENTIK_TAG).tar.gz"
lavoro="$(mktemp -d)"
trap 'rm -rf "$lavoro"' EXIT

info "Dump del database."
docker compose exec -T postgresql sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$lavoro/database.sql"
[[ -s "$lavoro/database.sql" ]] || errore "Dump del database vuoto."
cp .env "$lavoro/env"

info "Creo l'archivio $dest/$nome"
# Scritto con un nome nascosto e rinominato alla fine: chi sincronizza la cartella non vede
# mai un archivio a metà (escludere i file che iniziano con "." dalla sincronizzazione)
tar -czf "$dest/.$nome.parziale" -C "$lavoro" database.sql env -C "$(pwd -P)" data
mv "$dest/.$nome.parziale" "$dest/$nome"

# Rotazione: solo gli archivi di questo script, non quelli di aggiorna.sh
find "$dest" -maxdepth 1 -name 'sestante-*.tar.gz' -mtime "+$giorni" -delete
find "$dest" -maxdepth 1 -name '.sestante-*.parziale' -mmin +120 -delete

info "Backup completato: $dest/$nome ($(du -h "$dest/$nome" | cut -f1))."
