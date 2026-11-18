#!/usr/bin/env bash
# Allinea i permessi della segreteria regionale (gruppo gestione-utenti) sui singoli utenti:
# li dà sugli utenti non amministratori, li toglie su amministratori e segreteria stessa.
# Eseguito ogni ora dal timer systemd sestante-permessi.timer e da scripts/aggiorna.sh;
# si può lanciare anche a mano (es. subito dopo un'importazione di utenti).
#
# Uso:  scripts/permessi_gestione_utenti.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_comune.sh

richiedi_comandi docker
docker compose exec -T worker ak shell -c "$(cat scripts/permessi_gestione_utenti.py)" 2>/dev/null \
	| grep -E '^(Permessi|Ruolo|Invitati) ' \
	|| errore "Allineamento permessi gestione-utenti non riuscito: docker compose exec worker ak shell -c \"\$(cat scripts/permessi_gestione_utenti.py)\""
