# moto-env

Moto AWS mock server with env-driven initialization for CI.

Starts a [Moto](https://github.com/getmoto/moto) server and seeds AWS resources (Cognito user pools, S3 buckets) from environment variables — no setup scripts needed.

## Usage

```yaml
services:
  aws-mock:
    image: hohsiang/moto-env:latest
    env:
      AWS_REGION: ap-northeast-1
      COGNITO_POOL_NAME: ci-pool
      COGNITO_USERS: "testuser:Password123!"
      COGNITO_TOTP_ENABLED: "true"
      COGNITO_TOTP_USERS: "testuser:Password123!"
      S3_BUCKETS: "my-bucket,another-bucket"
    ports:
      - 5000:5000
    options: >-
      --health-cmd "test -f /tmp/moto-ready"
      --health-interval 5s
      --health-retries 24
```

## Environment Variables

### Cognito

| Variable | Description | Example |
|---|---|---|
| `COGNITO_POOL_NAME` | User pool name to create | `ci-pool` |
| `COGNITO_USERS` | Comma-separated `username:password` pairs | `alice:Pass1!,bob:Pass2!` |
| `COGNITO_TOTP_ENABLED` | Enable software token MFA for the pool in OPTIONAL mode | `true` |
| `COGNITO_TOTP_REQUIRED` | Enable software token MFA for the pool in REQUIRED mode (`MFA_CONFIGURATION=ON`) | `true` |
| `COGNITO_TOTP_USERS` | Comma-separated `username:password` pairs to auto-enroll in TOTP MFA | `admin:Pass1!` |
| `AWS_REGION` | AWS region (default: `us-east-1`) | `ap-northeast-1` |

Pool ID is deterministic: same region + pool name always produces the same ID (`MOTO_COGNITO_IDP_USER_POOL_ID_STRATEGY=HASH`).

TOTP support is enabled in the image with `MOTO_COGNITO_IDP_USER_POOL_ENABLE_TOTP=true`.

#### TOTP user enrollment

To pre-enroll users in TOTP MFA during init, set `COGNITO_TOTP_USERS` with the same `username:password` format as `COGNITO_USERS`. Users listed must already exist (create them via `COGNITO_USERS` first). The init script automatically:

1. Signs in the user (`AdminInitiateAuth`)
2. Associates a software token (`AssociateSoftwareToken`)
3. Generates and verifies a TOTP code (`VerifySoftwareToken`)
4. Enables TOTP as preferred MFA (`AdminSetUserMFAPreference`)

After enrollment, `InitiateAuth` for these users will return a `SOFTWARE_TOKEN_MFA` challenge instead of tokens directly. Moto uses a hardcoded TOTP secret (`asdfasdfasdf`), so test code can generate valid TOTP codes from this known secret.

You must also set `COGNITO_TOTP_ENABLED=true` or `COGNITO_TOTP_REQUIRED=true` to enable MFA at the pool level.

### S3

| Variable | Description | Example |
|---|---|---|
| `S3_BUCKETS` | Comma-separated bucket names to pre-create | `uploads,backups` |

## Endpoint

Moto server runs on port `5000`. Use `http://localhost:5000` (or container hostname in Docker networks) as your `endpoint_url`.

## Health Check

The image writes `/tmp/moto-ready` after all init resources (Cognito pools, S3 buckets, etc.) are fully provisioned. Use `test -f /tmp/moto-ready` as the health check to ensure the container is truly ready — not just that the moto server port is listening.

The Dockerfile includes a default `HEALTHCHECK` directive, but GitHub Actions service containers ignore Dockerfile `HEALTHCHECK`. For CI, pass the health check explicitly via `--health-cmd`.
