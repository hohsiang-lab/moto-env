FROM motoserver/moto:latest

RUN apk add --no-cache aws-cli curl

COPY entrypoint.sh /entrypoint.sh
COPY init.sh /init.sh
COPY start_moto_with_smtp.py /start_moto_with_smtp.py
RUN chmod +x /entrypoint.sh /init.sh

# HASH strategy makes pool ID and client ID deterministic (same inputs → same IDs)
ENV MOTO_COGNITO_IDP_USER_POOL_ID_STRATEGY=HASH
ENV MOTO_COGNITO_IDP_USER_POOL_CLIENT_ID_STRATEGY=HASH

# Enable Cognito TOTP support in Moto.
# Without this, AssociateSoftwareToken / VerifySoftwareToken flows are unavailable.
ENV MOTO_COGNITO_IDP_USER_POOL_ENABLE_TOTP=true

# Fix: USER_ID_FOR_SRP should be user.username (email), not user.id (UUID sub).
# Moto bug: InitiateAuth returns USER_ID_FOR_SRP=user.id, but RespondToAuthChallenge
# uses that value as USERNAME for lookup — fails because users are keyed by username.
# amazon-cognito-identity-js sends USER_ID_FOR_SRP back as USERNAME in the challenge
# response, so moto must return the actual username here, not the internal UUID.
RUN python3 -c "\
import moto.cognitoidp.models as m, inspect; \
f = inspect.getfile(m.CognitoIdpBackend); \
src = open(f).read(); \
patched = src.replace('\"USER_ID_FOR_SRP\": user.id,', '\"USER_ID_FOR_SRP\": user.username,'); \
assert patched != src, 'Patch not found!'; \
open(f, 'w').write(patched); \
print('✅ USER_ID_FOR_SRP patch applied') \
"

EXPOSE 5000

HEALTHCHECK --interval=5s --timeout=3s --retries=24 \
  CMD test -f /tmp/moto-ready || exit 1

ENTRYPOINT ["/entrypoint.sh"]
