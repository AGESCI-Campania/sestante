# Funzioni specifiche di Sestante condivise da installa.sh e aggiorna.sh — non eseguire direttamente.
# shellcheck shell=bash

# Blueprint applicati esplicitamente, in quest'ordine (percorso relativo a /blueprints nel container).
# Authentik li scopre anche da solo, ma applicarli qui rende gli errori visibili subito.
BLUEPRINTS=(
	local/groups-global.yaml
	local/flow-recovery.yaml
	local/source-google.yaml
	local/source-apple.yaml
	local/flow-authn-mfa.yaml
	local/brand.yaml
	local/scope-avatar.yaml
	local/provider-plancia.yaml
	local/traduzioni.yaml
	local/flow-avatar.yaml
	local/rbac-gestione-utenti.yaml
)

# Applica i blueprint con qualche tentativo: al primo avvio i flow di default
# (referenziati con !Find) vengono creati in background dal worker e possono non esistere ancora.
applica_blueprint() {
	local bp tentativo
	for bp in "${BLUEPRINTS[@]}"; do
		for tentativo in 1 2 3 4 5 6; do
			if docker compose exec -T worker ak apply_blueprint "$bp" >/dev/null 2>&1; then
				info "Blueprint applicato: $bp"
				continue 2
			fi
			avviso "Blueprint $bp non applicabile (tentativo $tentativo/6), riprovo tra 15s."
			sleep 15
		done
		docker compose exec -T worker ak apply_blueprint "$bp" || true
		errore "Blueprint $bp non applicato: vedere l'output sopra."
	done
}

# Impostazione Avatars di Authentik (Admin → System → Settings), che non si può esprimere come
# blueprint: prima l'immagine caricata dall'utente (blueprints/flow-avatar.yaml), poi Gravatar,
# poi le iniziali. Riallineata a ogni installazione/aggiornamento.
AVATAR_MODI="attributes.avatar,gravatar,initials"

imposta_avatar() {
	local esito
	esito="$(docker compose exec -T worker ak shell -c "
from authentik.tenants.models import Tenant
Tenant.objects.filter(schema_name='public').update(avatars='$AVATAR_MODI')
print('Avatars:', Tenant.objects.get(schema_name='public').avatars)
" 2>/dev/null || true)"
	if grep -qx "Avatars: $AVATAR_MODI" <<<"$esito"; then
		info "Impostazione Avatars: $AVATAR_MODI"
	else
		avviso "Impostazione Avatars non applicata: impostarla a mano in Admin → System → Settings ($AVATAR_MODI)."
	fi
}

# Installa (o aggiorna) un'attività periodica: <nome>.service esegue uno script del repo come
# proprietario del repo (es. agesci), <nome>.timer lo lancia secondo OnCalendar.
# Persistent=true: se il server era spento all'ora prevista, parte all'avvio successivo.
# Idempotente; senza sudo stampa il comando per l'amministratore, come installa_servizio_systemd.
#
# Uso:  installa_timer_systemd <nome> <descrizione> <OnCalendar> <script relativo al repo> <funzione>
#       (<funzione> è quella da richiamare nel comando per l'amministratore)
installa_timer_systemd() {
	local nome="$1" descrizione="$2" quando="$3" script="$4" funzione="$5"
	local dir utente docker_bin cartella="/etc/systemd/system" tmp f
	if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
		avviso "systemd non disponibile: salto l'installazione di ${nome}.timer."
		return 0
	fi
	dir="$(pwd -P)"
	utente="$(stat -c %U "$dir")"
	docker_bin="$(command -v docker)"
	tmp="$(mktemp -d)"
	cat > "$tmp/${nome}.service" <<UNIT
# Generato da scripts/installa.sh / aggiorna.sh di ${dir} — non modificare a mano.
[Unit]
Description=AGESCI Campania - ${descrizione}
Wants=docker.service
After=docker.service sestante.service

[Service]
Type=oneshot
User=${utente}
WorkingDirectory=${dir}
Environment=PATH=$(dirname "$docker_bin"):/usr/local/bin:/usr/bin:/bin
ExecStart=${dir}/${script}
UNIT
	cat > "$tmp/${nome}.timer" <<UNIT
# Generato da scripts/installa.sh / aggiorna.sh di ${dir} — non modificare a mano.
[Unit]
Description=AGESCI Campania - ${descrizione} (pianificazione)

[Timer]
OnCalendar=${quando}
RandomizedDelaySec=5min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
	if cmp -s "$tmp/${nome}.service" "$cartella/${nome}.service" \
		&& cmp -s "$tmp/${nome}.timer" "$cartella/${nome}.timer" \
		&& systemctl is-enabled --quiet "${nome}.timer" 2>/dev/null; then
		rm -rf "$tmp"
		info "${nome}.timer già installato e aggiornato."
		return 0
	fi
	if (( EUID != 0 )) && ! sudo -n true 2>/dev/null; then
		rm -rf "$tmp"
		avviso "${nome}.timer (${descrizione}) va installato o aggiornato da un amministratore:"
		avviso "  sudo bash -c 'cd ${dir} && source scripts/_comune.sh && source scripts/_sestante.sh && ${funzione}'"
		return 0
	fi
	info "Installo ${nome}.timer (${descrizione})."
	for f in "${nome}.service" "${nome}.timer"; do
		come_root install -m 644 "$tmp/$f" "$cartella/$f"
	done
	rm -rf "$tmp"
	come_root systemctl daemon-reload
	come_root systemctl enable --now --quiet "${nome}.timer"
}

# Backup notturno di database, .env e data/ (docs/BACKUP.md)
installa_backup_systemd() {
	installa_timer_systemd sestante-backup "backup di Sestante" "*-*-* 03:30" \
		scripts/backup.sh installa_backup_systemd
}

# Permessi della segreteria regionale sui singoli utenti, ogni ora (blueprints/rbac-gestione-utenti.yaml)
installa_permessi_systemd() {
	installa_timer_systemd sestante-permessi "permessi della segreteria su Sestante" hourly \
		scripts/permessi_gestione_utenti.sh installa_permessi_systemd
}
