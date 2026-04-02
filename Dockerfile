FROM motoserver/moto:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    awscli \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY init.sh /init.sh
RUN chmod +x /entrypoint.sh /init.sh

# HASH strategy makes pool ID deterministic (same region+name → same ID)
ENV MOTO_COGNITO_IDP_USER_POOL_ID_STRATEGY=HASH

EXPOSE 5000

ENTRYPOINT ["/entrypoint.sh"]
