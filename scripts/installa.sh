#!/usr/bin/env bash
# Prima installazione di Sestante (Authentik) sul server.
# Prerequisito: agesci-campania-web-frontend già installato (rete agesci-proxy esistente).
#
# Uso:  scripts/installa.sh
#       AUTHENTIK_BOOTSTRAP_EMAIL=x@y scripts/installa.sh   (senza domande)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_comune.sh
source scripts/_sestante.sh

richiedi_comandi docker git openssl
docker network inspect "$RETE_PROXY" >/dev/null 2>&1 \
	|| errore "Rete $RETE_PROXY mancante: installare prima agesci-campania-web-frontend."

# --- .env ---
password_bootstrap=""
if [[ -f .env ]]; then
	info ".env già presente, non lo modifico."
else
	info "Creo .env da .env.template con segreti nuovi."
	cp .env.template .env
	chmod 600 .env
	imposta_var PG_PASS "$(openssl rand -base64 36 | tr -d '\n')"
	imposta_var AUTHENTIK_SECRET_KEY "$(openssl rand -base64 60 | tr -d '\n')"

	email="${AUTHENTIK_BOOTSTRAP_EMAIL:-}"
	[[ -n "$email" ]] || read -rp "Email dell'account akadmin iniziale: " email
	[[ -n "$email" ]] || errore "Email akadmin obbligatoria."
	password_bootstrap="$(openssl rand -base64 24 | tr -d '\n')"
	imposta_var AUTHENTIK_BOOTSTRAP_EMAIL "$email"
	imposta_var AUTHENTIK_BOOTSTRAP_PASSWORD "$password_bootstrap"
fi
for v in PG_PASS AUTHENTIK_SECRET_KEY AUTHENTIK_TAG AUTHENTIK_WEB__BASE_URL; do
	[[ -n "$(leggi_var "$v")" ]] || errore "$v vuota in .env."
done
controlla_var_nuove

# --- Cartelle e risorse ---
mkdir -p data certs custom-templates
copia_media

# --- Avvio ---
docker compose pull
docker compose up -d
# start_period di Authentik 2026.8 = 120s; primo avvio con migrazioni più lungo
attendi_salute 600 postgresql server worker

applica_blueprint

# La password bootstrap serve solo al primo avvio: non lasciarla in chiaro in .env
if [[ -n "$password_bootstrap" ]]; then
	imposta_var AUTHENTIK_BOOTSTRAP_PASSWORD ""
fi

email_mancanti=()
for v in AUTHENTIK_EMAIL__HOST AUTHENTIK_EMAIL__USERNAME AUTHENTIK_EMAIL__PASSWORD; do
	[[ -n "$(leggi_var "$v")" ]] || email_mancanti+=("$v")
done

cat <<EOF

Sestante è attivo (rete $RETE_PROXY, alias sestante-server:9000).
EOF
if [[ -n "$password_bootstrap" ]]; then
	cat <<EOF

  Account iniziale:  akadmin  /  $password_bootstrap
  (mostrata solo ora e rimossa da .env: annotarla e cambiarla al primo accesso)
EOF
fi
if (( ${#email_mancanti[@]} )); then
	avviso "Email non configurata (${email_mancanti[*]}): compilare .env e 'docker compose up -d'."
fi
cat <<EOF

Passi successivi:
  1. In agesci-campania-web-frontend deve esistere caddy/sites/sestante.caddy
     (poi /opt/agesci-campania-web-frontend/scripts/aggiorna.sh)
  2. https://auth.agescicampania.org — login come akadmin, creare gli amministratori
     nominali (2-3 persone, nel gruppo admin), poi non usare più akadmin
  3. Provider Plancia: copiare client_id e client_secret nuovi nel .env.prod di Plancia
     (Applications → Providers → Plancia AGESCI Campania)
  4. Verifiche: branding, MFA (TOTP/WebAuthn/codici backup), login SSO da Plancia
EOF
