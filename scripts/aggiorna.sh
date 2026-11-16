#!/usr/bin/env bash
# Aggiorna Sestante: scarica l'ultima versione da git, fa il backup del database, allinea la
# versione di Authentik a quella fissata in docker-compose.yml e riapplica i blueprint.
#
# Per salire di versione: aggiornare il compose ufficiale nel repo (vedi CLAUDE.md), commit e
# push, poi eseguire questo script sul server. Authentik non supporta il downgrade.
#
# Uso:  scripts/aggiorna.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_comune.sh

richiedi_comandi docker git gzip
[[ -f .env ]] || errore ".env mancante: eseguire prima scripts/installa.sh"
docker network inspect "$RETE_PROXY" >/dev/null 2>&1 || errore "Rete $RETE_PROXY mancante."

# git pull può modificare questo stesso script: dopo il pull si riparte con la versione nuova
if [[ "${1:-}" != "--dopo-pull" ]]; then
	richiedi_albero_pulito
	info "Scarico gli aggiornamenti da git."
	git pull --ff-only
	exec "$0" --dopo-pull
fi
source scripts/_sestante.sh

controlla_var_nuove

# --- Versione ---
attuale="$(leggi_var AUTHENTIK_TAG)"
richiesta="$(sed -n 's/.*AUTHENTIK_TAG:-\([0-9.]*\)}.*/\1/p' docker-compose.yml | head -n 1)"
[[ -n "$richiesta" ]] || errore "Versione di default non trovata in docker-compose.yml."
if [[ "$attuale" != "$richiesta" ]]; then
	if [[ "$(printf '%s\n%s\n' "$attuale" "$richiesta" | sort -V | head -n 1)" != "$attuale" ]]; then
		errore "docker-compose.yml chiede $richiesta, più vecchia della $attuale installata: downgrade non supportato."
	fi
	info "Aggiornamento Authentik $attuale → $richiesta"
else
	info "Authentik resta alla $attuale (aggiorno configurazione e blueprint)."
fi

# --- Backup ---
mkdir -p backups
backup="backups/authentik-$(date +%Y%m%d-%H%M%S)-$attuale.sql.gz"
info "Backup del database in $backup"
docker compose exec -T postgresql sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "$backup"
[[ -s "$backup" ]] || errore "Backup vuoto: aggiornamento interrotto."
# Tengo gli ultimi 10 backup
find backups -name 'authentik-*.sql.gz' | sort -r | tail -n +11 | xargs rm -f

# --- Aggiornamento ---
imposta_var AUTHENTIK_TAG "$richiesta"
docker compose pull
docker compose up -d
attendi_salute 600 postgresql server worker

applica_blueprint

# Idempotente: installa la unit se manca, la aggiorna se è cambiata
installa_servizio_systemd sestante "$UNIT_PROXY"
installa_backup_systemd

cat <<EOF

Aggiornamento completato (Authentik $richiesta). Backup: $backup
Se qualcosa non va: docker compose logs server worker
Ripristino (solo in emergenza, versione precedente $attuale):
  AUTHENTIK_TAG=$attuale in .env, docker compose down, ricreare il DB e
  gunzip -c $backup | docker compose exec -T postgresql psql -U \$PG_USER \$PG_DB
EOF
