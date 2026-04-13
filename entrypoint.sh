#!/bin/sh
set -e

# 1. Start moto server in background
# Uses start_moto_with_smtp.py which monkey-patches CognitoIdpBackend.forgot_password
# to send verification codes via SMTP when SMTP_SERVER env var is set.
python /start_moto_with_smtp.py -H 0.0.0.0 -p 5000 &
MOTO_PID=$!

# 2. Wait for moto to be ready
echo "⏳ Waiting for moto server..."
for i in $(seq 1 30); do
  curl -sf http://localhost:5000/ > /dev/null 2>&1 && break
  [ "$i" -eq 30 ] && { echo "❌ Moto server timeout"; exit 1; }
  sleep 1
done
echo "✅ Moto server ready"

# 3. Run init script to seed resources
/init.sh

# 4. Signal that all resources (Cognito, S3, etc.) are ready
touch /tmp/moto-ready
echo "✅ Init complete, moto-env ready"

# 5. Keep container alive by waiting on moto process
wait $MOTO_PID
