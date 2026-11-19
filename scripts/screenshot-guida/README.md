# Screenshot della guida utenti

Rifà le immagini di [`docs/AIUTO-ACCESSO.md`](../../docs/AIUTO-ACCESSO.md)
(`docs/img/aiuto-accesso/`) da un'**istanza di prova locale**, mai dalla produzione: lo script
cambia password e dispositivi MFA di un utente fittizio. Da rifare dopo un aggiornamento di
Authentik o una modifica ai flow, al brand o alle traduzioni.

## 1. Istanza di prova

In una cartella fuori dal repo:

- copiare `docker-compose.yml` e togliere i volumi `/var/run/docker.sock` e `./custom-templates`;
- `.env` con segreti generati al momento, `AUTHENTIK_TAG` uguale alla produzione,
  `AUTHENTIK_WEB__BASE_URL=http://localhost:9100`, `COMPOSE_PORT_HTTP=127.0.0.1:9100`,
  `COMPOSE_PORT_HTTPS=127.0.0.1:9543` e l'email verso mailpit: `AUTHENTIK_EMAIL__HOST=mailpit`,
  `AUTHENTIK_EMAIL__PORT=1025`, `AUTHENTIK_EMAIL__USE_TLS=false`;
- `docker-compose.override.yml` con i volumi di quello del repo (percorsi assoluti verso il repo,
  `custom-templates` montata anche nel server) e senza la rete `agesci-proxy`, più:

  ```yaml
  mailpit:
    image: docker.io/axllent/mailpit:v1.33.1
    ports:
      - 127.0.0.1:9125:8025
  ```

Poi `docker compose -p sestante-prova up -d` e, quando risponde
`http://127.0.0.1:9100/-/health/ready/`, applicare i blueprint con l'elenco `BLUEPRINTS` di
`scripts/_sestante.sh`:

```bash
source /percorso/del/repo/scripts/_sestante.sh
docker compose -p sestante-prova exec -T worker ak apply_blueprint "${BLUEPRINTS[@]}"
```

## 2. Utente e screenshot

```bash
docker compose -p sestante-prova exec -T worker ak shell -c "$(cat prepara_utente.py)"
```

crea (o riporta allo stato iniziale) `mario.rossi@example.org`, invitato da Tana, con un solo
dispositivo TOTP. Va rilanciato prima di ogni giro di screenshot.

Lo script usa Google Chrome installato e due pacchetti npm, in una cartella di lavoro:

```bash
npm i playwright@1.56.1 otplib@12.0.1
cp /percorso/del/repo/scripts/screenshot-guida/screenshot.mjs .
node screenshot.mjs /percorso/del/repo/docs/img/aiuto-accesso
```

Controllare le immagini prima del commit: se cambia una pagina di Authentik, cambiano anche i
testi della guida.

## 3. PDF da distribuire

Dopo ogni modifica alla guida o alle immagini, rifare `docs/AIUTO-ACCESSO.pdf` (stessa cartella
di lavoro, in più i pacchetti `marked@15.0.12 marked-gfm-heading-id@4.1.1`):

```bash
cp /percorso/del/repo/scripts/screenshot-guida/pdf.mjs .
node pdf.mjs /percorso/del/repo
```
