# Utente fittizio per gli screenshot della guida, come un invitato da Tana che ha perso il telefono:
# password nota, un solo dispositivo TOTP (di cui nessuno ha il segreto), nessun altro metodo.
# Si può rilanciare: riporta sempre l'utente a questo stato.
# Eseguito con `ak shell -c "$(cat prepara_utente.py)"` sull'istanza di prova, MAI in produzione.
from authentik.core.models import Token, User
from authentik.stages.authenticator_static.models import StaticDevice
from authentik.stages.authenticator_totp.models import TOTPDevice
from authentik.stages.authenticator_webauthn.models import WebAuthnDevice

utente, _ = User.objects.update_or_create(
    username="mario.rossi@example.org",
    defaults={
        "email": "mario.rossi@example.org",
        "name": "Mario Rossi",
        "path": "utenti/invitati",
        "attributes": {"piattaforme_consentite": ["tana"]},
        "is_active": True,
    },
)
utente.set_password("VecchiaPassword-2026")
utente.save()
for modello in (TOTPDevice, StaticDevice, WebAuthnDevice):
    modello.objects.filter(user=utente).delete()
Token.objects.filter(user=utente).delete()
TOTPDevice.objects.create(user=utente, name="App di autenticazione", confirmed=True)
print("Utente pronto:", utente.username)
