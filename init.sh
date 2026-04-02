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
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH ALLOW_ADMIN_USER_PASSWORD_AUTH \
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

  # ── TOTP enrollment ──────────────────────────────────────────────────
  # COGNITO_TOTP_USERS: comma-separated usernames to enroll in TOTP MFA.
  # Each user must already exist (created via COGNITO_USERS above).
  # Flow: AdminInitiateAuth → AssociateSoftwareToken → VerifySoftwareToken → AdminSetUserMFAPreference
  if [ -n "${COGNITO_TOTP_USERS:-}" ]; then
    OLD_IFS="$IFS"
    IFS=','
    for totp_entry in $COGNITO_TOTP_USERS; do
      TOTP_USERNAME="${totp_entry%%:*}"
      TOTP_PASSWORD="${totp_entry##*:}"
      if [ -z "$TOTP_USERNAME" ] || [ -z "$TOTP_PASSWORD" ]; then
        echo "⚠️  Skipping TOTP enrollment: invalid entry '$totp_entry'"
        continue
      fi

      echo "🔐 Enrolling TOTP for: $TOTP_USERNAME"

      # 1. Get access token via admin auth
      ACCESS_TOKEN=$(aws cognito-idp admin-initiate-auth \
        --endpoint-url "$ENDPOINT" \
        --region "$REGION" \
        --user-pool-id "$POOL_ID" \
        --client-id "$CLIENT_ID" \
        --auth-flow ADMIN_USER_PASSWORD_AUTH \
        --auth-parameters USERNAME="$TOTP_USERNAME",PASSWORD="$TOTP_PASSWORD" \
        --query 'AuthenticationResult.AccessToken' --output text)

      if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "None" ]; then
        echo "❌ Failed to get access token for $TOTP_USERNAME"
        continue
      fi

      # 2. Associate software token → get secret
      SECRET_CODE=$(aws cognito-idp associate-software-token \
        --endpoint-url "$ENDPOINT" \
        --region "$REGION" \
        --access-token "$ACCESS_TOKEN" \
        --query 'SecretCode' --output text)

      if [ -z "$SECRET_CODE" ] || [ "$SECRET_CODE" = "None" ]; then
        echo "❌ Failed to associate software token for $TOTP_USERNAME"
        continue
      fi

      # 3. Generate TOTP code from secret (standard RFC 6238)
      TOTP_CODE=$(python3 -c "
import hmac, hashlib, struct, time, base64
secret = '$SECRET_CODE'
# Pad base32 secret
padded = secret.upper() + '=' * (-len(secret) % 8)
key = base64.b32decode(padded)
counter = int(time.time()) // 30
msg = struct.pack('>Q', counter)
h = hmac.new(key, msg, hashlib.sha1).digest()
offset = h[-1] & 0x0F
code = (struct.unpack('>I', h[offset:offset+4])[0] & 0x7FFFFFFF) % 1000000
print(f'{code:06d}')
")

      # 4. Verify software token
      aws cognito-idp verify-software-token \
        --endpoint-url "$ENDPOINT" \
        --region "$REGION" \
        --access-token "$ACCESS_TOKEN" \
        --user-code "$TOTP_CODE" \
        > /dev/null

      # 5. Enable TOTP as preferred MFA for user
      aws cognito-idp admin-set-user-mfa-preference \
        --endpoint-url "$ENDPOINT" \
        --region "$REGION" \
        --user-pool-id "$POOL_ID" \
        --username "$TOTP_USERNAME" \
        --software-token-mfa-settings Enabled=true,PreferredMfa=true

      echo "✅ TOTP enrolled: $TOTP_USERNAME"
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
      echo "🔧 Creating S3 bucket: $bucket (region=$REGION)"
      if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
          --endpoint-url "$ENDPOINT" \
          --region "$REGION" \
          --bucket "$bucket"
      else
        aws s3api create-bucket \
          --endpoint-url "$ENDPOINT" \
          --region "$REGION" \
          --bucket "$bucket" \
          --create-bucket-configuration "LocationConstraint=$REGION"
      fi
      # Verify bucket exists
      aws s3api head-bucket \
        --endpoint-url "$ENDPOINT" \
        --region "$REGION" \
        --bucket "$bucket"
      echo "✅ S3 bucket created: $bucket"
    fi
  done
  IFS="$OLD_IFS"
fi
