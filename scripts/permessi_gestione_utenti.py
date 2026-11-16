# Allinea i permessi del ruolo gestione-utenti (segreteria regionale) sui singoli utenti.
# Eseguito dentro il container con `ak shell` da scripts/permessi_gestione_utenti.sh
# (timer orario sestante-permessi.timer e scripts/aggiorna.sh). Vedi blueprints/rbac-gestione-utenti.yaml.
#
# - Utenti gestibili (interni/esterni, senza accesso all'amministrazione): il ruolo riceve
#   vista, modifica e reset password su ciascuno. Copre gli utenti creati dagli amministratori
#   o importati, che non ricevono i permessi iniziali.
# - Tutti gli altri (amministratori, membri di gestione-utenti, chiunque abbia ruoli o accesso
#   all'amministrazione, account di servizio): il ruolo perde quei permessi. Così un utente
#   creato dalla segreteria e poi promosso amministratore esce dalla sua portata.
from authentik.core.models import User, UserTypes
from authentik.rbac.models import Role

PERMESSI = [
    "authentik_core.view_user",
    "authentik_core.change_user",
    "authentik_core.reset_user_password",
]

ruolo = Role.objects.filter(name="gestione-utenti").first()
if ruolo is None:
    print("Ruolo gestione-utenti assente: applicare blueprints/rbac-gestione-utenti.yaml")
else:
    gestibili = esclusi = 0
    for utente in User.objects.all().iterator():
        # is_superuser e i ruoli valgono anche per gli utenti disattivati (has_perm no): un
        # amministratore disattivato resta escluso e la segreteria non può riattivarlo
        escluso = (
            utente.type not in (UserTypes.INTERNAL, UserTypes.EXTERNAL)
            or utente.username == "AnonymousUser"
            or utente.is_superuser
            or utente.all_roles().filter(managed__isnull=True).exists()
            or utente.has_perm("authentik_rbac.access_admin_interface")
        )
        if escluso:
            ruolo.remove_perms(PERMESSI, utente)
            esclusi += 1
        else:
            ruolo.assign_perms(PERMESSI, utente)
            gestibili += 1
    print(f"Permessi gestione-utenti: {gestibili} utenti gestibili, {esclusi} esclusi.")
