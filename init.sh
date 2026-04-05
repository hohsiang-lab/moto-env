#!/bin/sh
set -e

ENDPOINT="http://localhost:5000"
REGION="${AWS_REGION:-us-east-1}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-local}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-local}"
export AWS_DEFAULT_REGION="$REGION"

# ── Cognito ──────────────────────────────────────────────────────────────
# COGNITO_POOL_NAME: name of the user pool to create (default: ci-pool)
# COGNITO_USERS: comma-separated list of username:password pairs
#   e.g. "alice:Password1!,bob:Password2!"

if [ -n "${COGNITO_POOL_NAME:-}" ]; then
  echo "🔧 Creating Cognito user pool: $COGNITO_POOL_NAME"
  POOL_ID=$(aws cognito-idp create-user-pool \
    --endpoint-url "$ENDPOINT" \
    --region "$REGION" \
    --pool-name "$COGNITO_POOL_NAME" \
    --query 'UserPool.Id' --output text)
  echo "✅ User pool created: $POOL_ID"

  # Create app client (needed for auth flows)
  CLIENT_ID=$(aws cognito-idp create-user-pool-client \
    --endpoint-url "$ENDPOINT" \
    --region "$REGION" \
    --user-pool-id "$POOL_ID" \
    --client-name "ci-client" \
    --no-generate-secret \
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --query 'UserPoolClient.ClientId' --output text)
  echo "✅ App client created: $CLIENT_ID"

  # Optional: enable TOTP MFA at the user pool level.
  # Values:
  # - COGNITO_TOTP_ENABLED=true      -> software token MFA optional
  # - COGNITO_TOTP_REQUIRED=true     -> software token MFA required
  if [ "${COGNITO_TOTP_ENABLED:-}" = "true" ] || [ "${COGNITO_TOTP_REQUIRED:-}" = "true" ]; then
    MFA_CONFIGURATION="OPTIONAL"
    if [ "${COGNITO_TOTP_REQUIRED:-}" = "true" ]; then
      MFA_CONFIGURATION="ON"
    fi

    aws cognito-idp set-user-pool-mfa-config \
      --endpoint-url "$ENDPOINT" \
      --region "$REGION" \
      --user-pool-id "$POOL_ID" \
      --mfa-configuration "$MFA_CONFIGURATION" \
      --software-token-mfa-configuration Enabled=true \
      > /dev/null

    echo "✅ Cognito TOTP enabled for pool: $POOL_ID (mode=$MFA_CONFIGURATION)"
  fi

  # Create users from COGNITO_USERS env
  if [ -n "${COGNITO_USERS:-}" ]; then
    OLD_IFS="$IFS"
    IFS=','
    for entry in $COGNITO_USERS; do
      USERNAME="${entry%%:*}"
      PASSWORD="${entry##*:}"
      if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        aws cognito-idp admin-create-user \
          --endpoint-url "$ENDPOINT" \
          --region "$REGION" \
          --user-pool-id "$POOL_ID" \
          --username "$USERNAME" \
          --temporary-password "$PASSWORD" \
          --message-action SUPPRESS \
          --query 'User.Username' --output text > /dev/null
        # Set permanent password (skip force-change-password state)
        aws cognito-idp admin-set-user-password \
          --endpoint-url "$ENDPOINT" \
          --region "$REGION" \
          --user-pool-id "$POOL_ID" \
          --username "$USERNAME" \
          --password "$PASSWORD" \
          --permanent
        echo "✅ User created: $USERNAME"
      fi
    done
    IFS="$OLD_IFS"
  fi
fi

# ── S3 ───────────────────────────────────────────────────────────────────
# S3_BUCKETS: comma-separated bucket names to pre-create
#   e.g. "my-bucket,another-bucket"

if [ -n "${S3_BUCKETS:-}" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for bucket in $S3_BUCKETS; do
    if [ -n "$bucket" ]; then
      aws s3api create-bucket \
        --endpoint-url "$ENDPOINT" \
        --region "$REGION" \
        --bucket "$bucket" \
        ${REGION:+--create-bucket-configuration LocationConstraint="$REGION"} \
        > /dev/null 2>&1 || true
      echo "✅ S3 bucket created: $bucket"
    fi
  done
  IFS="$OLD_IFS"
fi
