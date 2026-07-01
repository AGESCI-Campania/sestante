# Blueprints

Cartella prevista per le configurazioni Authentik espresse come Blueprint YAML (Gruppi,
Provider, Application, Property Mapping), versionate invece che create solo a mano in UI.

Nessun blueprint ancora presente: lo schema esatto va verificato contro la documentazione
ufficiale della versione installata (https://docs.goauthentik.io) prima di scriverne uno,
per evitare di fissare in git una sintassi non valida per la release effettivamente in uso.

Primo blueprint da creare in Fase 0: i due gruppi globali `admin-multipiattaforma` e
`segreteria` (vedi CLAUDE.md, task 8).
