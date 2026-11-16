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
