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
      S3_BUCKETS: "my-bucket,another-bucket"
    ports:
      - 5000:5000
    options: >-
      --health-cmd "curl -sf http://localhost:5000/"
      --health-interval 5s
      --health-retries 12
```

## Environment Variables

### Cognito

| Variable | Description | Example |
|---|---|---|
| `COGNITO_POOL_NAME` | User pool name to create | `ci-pool` |
| `COGNITO_USERS` | Comma-separated `username:password` pairs | `alice:Pass1!,bob:Pass2!` |
| `COGNITO_TOTP_ENABLED` | Enable software token MFA for the pool in OPTIONAL mode | `true` |
| `COGNITO_TOTP_REQUIRED` | Enable software token MFA for the pool in REQUIRED mode (`MFA_CONFIGURATION=ON`) | `true` |
| `AWS_REGION` | AWS region (default: `us-east-1`) | `ap-northeast-1` |

Pool ID is deterministic: same region + pool name always produces the same ID (`MOTO_COGNITO_IDP_USER_POOL_ID_STRATEGY=HASH`).

TOTP support is enabled in the image with `MOTO_COGNITO_IDP_USER_POOL_ENABLE_TOTP=true`. To actually trigger MFA flows in tests, you still need to associate and verify a software token for individual users (for example via `AssociateSoftwareToken`, `VerifySoftwareToken`, and `AdminSetUserMFAPreference`). This image now enables the pool-level prerequisite so CI/bootstrap scripts can perform that user-level setup.

### S3

| Variable | Description | Example |
|---|---|---|
| `S3_BUCKETS` | Comma-separated bucket names to pre-create | `uploads,backups` |

## Endpoint

Moto server runs on port `5000`. Use `http://localhost:5000` (or container hostname in Docker networks) as your `endpoint_url`.

## Health Check

`GET http://localhost:5000/` returns `200 OK` when ready.
