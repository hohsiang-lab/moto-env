FROM motoserver/moto:latest

RUN apk add --no-cache aws-cli curl

COPY entrypoint.sh /entrypoint.sh
COPY init.sh /init.sh
RUN chmod +x /entrypoint.sh /init.sh

# HASH strategy makes pool ID deterministic (same region+name → same ID)
ENV MOTO_COGNITO_IDP_USER_POOL_ID_STRATEGY=HASH

# Enable Cognito TOTP support in Moto.
# Without this, AssociateSoftwareToken / VerifySoftwareToken flows are unavailable.
ENV MOTO_COGNITO_IDP_USER_POOL_ENABLE_TOTP=true

EXPOSE 5000

HEALTHCHECK --interval=5s --timeout=3s --retries=24 \
  CMD test -f /tmp/moto-ready || exit 1

ENTRYPOINT ["/entrypoint.sh"]
