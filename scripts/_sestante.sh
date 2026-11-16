# Funzioni specifiche di Sestante condivise da installa.sh e aggiorna.sh — non eseguire direttamente.
# shellcheck shell=bash

# Blueprint applicati esplicitamente, in quest'ordine (percorso relativo a /blueprints nel container).
# Authentik li scopre anche da solo, ma applicarli qui rende gli errori visibili subito.
BLUEPRINTS=(
	local/groups-global.yaml
	local/flow-recovery.yaml
	local/flow-authn-mfa.yaml
	local/brand.yaml
	local/provider-plancia.yaml
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

# Installa (o aggiorna) il backup notturno: sestante-backup.service esegue scripts/backup.sh
# come proprietario del repo (es. agesci), sestante-backup.timer lo lancia ogni notte.
# Persistent=true: se il server era spento all'ora prevista, il backup parte all'avvio.
# Idempotente; senza sudo stampa il comando per l'amministratore, come installa_servizio_systemd.
installa_backup_systemd() {
	local dir utente docker_bin cartella="/etc/systemd/system" tmp nome
	if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
		avviso "systemd non disponibile: salto l'installazione del backup notturno."
		return 0
	fi
	dir="$(pwd -P)"
	utente="$(stat -c %U "$dir")"
	docker_bin="$(command -v docker)"
	tmp="$(mktemp -d)"
	cat > "$tmp/sestante-backup.service" <<UNIT
# Generato da scripts/installa.sh / aggiorna.sh di ${dir} — non modificare a mano.
[Unit]
Description=AGESCI Campania - backup di Sestante
Wants=docker.service
After=docker.service sestante.service

[Service]
Type=oneshot
User=${utente}
WorkingDirectory=${dir}
Environment=PATH=$(dirname "$docker_bin"):/usr/local/bin:/usr/bin:/bin
ExecStart=${dir}/scripts/backup.sh
UNIT
	cat > "$tmp/sestante-backup.timer" <<UNIT
# Generato da scripts/installa.sh / aggiorna.sh di ${dir} — non modificare a mano.
[Unit]
Description=AGESCI Campania - backup notturno di Sestante

[Timer]
OnCalendar=*-*-* 03:30
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
	if cmp -s "$tmp/sestante-backup.service" "$cartella/sestante-backup.service" \
		&& cmp -s "$tmp/sestante-backup.timer" "$cartella/sestante-backup.timer" \
		&& systemctl is-enabled --quiet sestante-backup.timer 2>/dev/null; then
		rm -rf "$tmp"
		info "Backup notturno (sestante-backup.timer) già installato e aggiornato."
		return 0
	fi
	if (( EUID != 0 )) && ! sudo -n true 2>/dev/null; then
		rm -rf "$tmp"
		avviso "Il backup notturno (sestante-backup.timer) va installato o aggiornato da un amministratore:"
		avviso "  sudo bash -c 'cd ${dir} && source scripts/_comune.sh && source scripts/_sestante.sh && installa_backup_systemd'"
		return 0
	fi
	info "Installo il backup notturno (sestante-backup.timer)."
	for nome in sestante-backup.service sestante-backup.timer; do
		come_root install -m 644 "$tmp/$nome" "$cartella/$nome"
	done
	rm -rf "$tmp"
	come_root systemctl daemon-reload
	come_root systemctl enable --now --quiet sestante-backup.timer
}
