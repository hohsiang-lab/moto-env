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
| `AWS_REGION` | AWS region (default: `us-east-1`) | `ap-northeast-1` |

Pool ID is deterministic: same region + pool name always produces the same ID (`MOTO_COGNITO_IDP_USER_POOL_ID_STRATEGY=HASH`).

### S3

| Variable | Description | Example |
|---|---|---|
| `S3_BUCKETS` | Comma-separated bucket names to pre-create | `uploads,backups` |

## Endpoint

Moto server runs on port `5000`. Use `http://localhost:5000` (or container hostname in Docker networks) as your `endpoint_url`.

## Health Check

`GET http://localhost:5000/` returns `200 OK` when ready.
