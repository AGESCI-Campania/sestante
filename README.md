# Sestante

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Powered by Authentik](https://img.shields.io/badge/powered%20by-Authentik-fb5607.svg)
![Docker Compose](https://img.shields.io/badge/deploy-Docker%20Compose-2496ED.svg)
![Status](https://img.shields.io/badge/status-in%20configurazione-yellow.svg)

Identity Provider SSO condiviso per le piattaforme AGESCI Campania (Plancia, Bussola, Catello
e future). Basato su [Authentik](https://goauthentik.io) (open source, MIT).

Questo repository contiene la configurazione di deployment (Docker Compose, variabili
d'ambiente, Blueprints) — non è un'applicazione Django custom.

## Documentazione

- `Sestante_Progettazione.md` — documento di progettazione completo (architettura, modello
  dei ruoli, roadmap, decisioni prese)
- `CLAUDE.md` — riferimento operativo per la continuità con Claude Code
- [`docs/INTEGRAZIONE-SSO.md`](docs/INTEGRAZIONE-SSO.md) — **come collegare una piattaforma a
  Sestante** (da dare agli agenti degli altri repo:
  <https://raw.githubusercontent.com/AGESCI-Campania/sestante/main/docs/INTEGRAZIONE-SSO.md>)
- [`docs/BACKUP.md`](docs/BACKUP.md) — backup notturno, copia su NAS, ripristino

## Installazione e aggiornamento

Prerequisito: [agesci-campania-web-frontend](https://github.com/AGESCI-Campania/agesci-campania-web-frontend)
installato sul server (reverse proxy Caddy e rete `agesci-proxy`).

```bash
git clone https://github.com/AGESCI-Campania/sestante.git /opt/sestante
/opt/sestante/scripts/installa.sh    # prima installazione
/opt/sestante/scripts/aggiorna.sh    # aggiornamenti successivi
```

## Stato

Istanza di test validata (Plancia collegata via OIDC); reinstallazione pulita su server
dedicato in preparazione (vedi `TODO.md`, sezione 0).

## Piattaforme collegate

| Piattaforma | Stato |
|---|---|
| Plancia | Non ancora collegata (pilota previsto) |
| Bussola | Non ancora collegata (nascerà SSO-ready) |
| Catello | Non ancora collegata |

## Licenza

MIT © Andrea Bruno
