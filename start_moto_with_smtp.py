"""
Moto server wrapper with SMTP monkey-patch for forgot_password.

When SMTP_SERVER env var is set, intercepts CognitoIdpBackend.forgot_password
and sends the verification code via SMTP (e.g. to Mailpit) so E2E tests can
retrieve the code without modifying application code.

The code format from moto is "moto-confirmation-code:NNNNNN".
We extract the 6-digit part and send it in the email body.
moto's confirm_forgot_password accepts any code that does NOT start with
"moto-confirmation-code:" as valid, so the extracted digit code works correctly.
"""

import importlib.util
import moto

# motoserver/moto base image installs moto in a way that leaves moto.__file__ = None,
# which causes moto.core.loaders to crash on os.path.abspath(moto.__file__).
# Resolve it before importing any moto submodule.
if moto.__file__ is None:
    spec = importlib.util.find_spec("moto")
    if spec and spec.origin:
        moto.__file__ = spec.origin
    elif spec and spec.submodule_search_locations:
        import os as _os
        moto.__file__ = _os.path.join(list(spec.submodule_search_locations)[0], "__init__.py")

import os
import smtplib
from email.message import EmailMessage
from moto.cognitoidp.models import CognitoIdpBackend

_orig_forgot = CognitoIdpBackend.forgot_password


def _patched_forgot(self, client_id: str, username: str):
    result = _orig_forgot(self, client_id, username)
    confirmation_code = result[0]  # "moto-confirmation-code:NNNNNN" or None

    smtp_host = os.environ.get("SMTP_SERVER", "")
    if smtp_host and confirmation_code:
        # Extract 6-digit code from "moto-confirmation-code:NNNNNN"
        code = confirmation_code.split(":")[-1]
        try:
            msg = EmailMessage()
            msg["From"] = os.environ.get("SMTP_SENDER", "noreply@test.local")
            msg["To"] = username  # username IS the email address in Cognito
            msg["Subject"] = "Your verification code"
            msg.set_content(f"Your verification code is: {code}")
            with smtplib.SMTP(smtp_host, int(os.environ.get("SMTP_PORT", "1025"))) as s:
                s.send_message(msg)
            print(f"[moto-env] Sent verification code to {username} via {smtp_host}")
        except Exception as e:
            print(f"[moto-env] SMTP send failed (non-fatal): {e}")

    return result


CognitoIdpBackend.forgot_password = _patched_forgot

from moto.server import main

main()
