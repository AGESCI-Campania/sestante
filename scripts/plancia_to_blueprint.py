#!/usr/bin/env python3
"""Converte un CSV di utenti Plancia in un Blueprint YAML per Authentik.

Utilizzo:
    python3 scripts/plancia_to_blueprint.py /tmp/plancia_users.csv > /tmp/users-import-plancia.yaml

Il CSV deve avere le colonne: username, email, full_name, password
(prodotto dalla query SQL di esportazione da accounts_user di Plancia).

ATTENZIONE: il file generato contiene hash delle password — non versionarlo in git.
"""
import csv
import re
import sys
import yaml

_email_re = re.compile(r"^[^@]+@[^@]+\.[^@]+$")


def convert(csv_path: str) -> dict:
    entries = []
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            if not row["username"] or not _email_re.match(row["email"]):
                continue
            attrs: dict = {
                "email": row["email"],
                "name": row["full_name"],
                "type": "internal",
                "is_active": True,
            }
            if not row["password"].startswith("!"):
                attrs["password"] = row["password"]
            entries.append({
                "model": "authentik_core.user",
                "state": "present",
                "identifiers": {"username": row["username"]},
                "attrs": attrs,
            })
    return {
        "version": 1,
        "metadata": {"name": "Import utenti Plancia"},
        "entries": entries,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Uso: {sys.argv[0]} <percorso_csv>", file=sys.stderr)
        sys.exit(1)
    print(yaml.dump(convert(sys.argv[1]), allow_unicode=True, default_flow_style=False))
