# Deployment Guide

> **`client`/`ai`는 이 섹션이 더 이상 필요 없음** — 둘 다 `deploy.yml`이 매 배포마다 필요한 k8s 매니페스트를 자동으로 `kubectl apply`함 (self-heal, [[History]] 참고). `server`는 아직 self-heal이 아니라서(PR #97 머지 후 전환 예정) 아래 순서가 여전히 유효하고, 실제로 2026-08-06에 이 순서 그대로 최초 배포함 — **아래는 그때 실제로 검증된 순서**.

## 최초 배포 순서 (server 기준, 2026-08-06 검증됨)

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-postgres.yaml   # postgres-secret을 먼저 만든 뒤 적용

kubectl -n fowoco create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=fowoco_admin \
  --from-literal=POSTGRES_PASSWORD='<openssl rand -base64 24로 생성>' \
  --from-literal=POSTGRES_DB=fowoco
```

postgres가 뜨면(`kubectl -n fowoco rollout status statefulset/postgres`), **runtime/migration role을 분리 생성**한다 — server의 `docs/database/postgresql-rls-rollout.md`가 이 분리를 명시적으로 infra 책임으로 정해뒀고, RLS(#34)가 이 분리를 전제로 설계돼 있다:

```bash
kubectl -n fowoco exec -i postgres-0 -- env PGPASSWORD='<admin 비밀번호>' psql -U fowoco_admin -d fowoco <<SQL
CREATE ROLE fowoco_migration WITH LOGIN PASSWORD '<비밀번호>';
CREATE ROLE fowoco_runtime WITH LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE PASSWORD '<비밀번호>';

GRANT ALL ON SCHEMA public TO fowoco_migration;
GRANT USAGE ON SCHEMA public TO fowoco_runtime;

ALTER DEFAULT PRIVILEGES FOR ROLE fowoco_migration IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO fowoco_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE fowoco_migration IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO fowoco_runtime;
SQL
```

`fowoco_migration`으로 Flyway가 테이블을 만들고 소유하게 되고, `ALTER DEFAULT PRIVILEGES` 덕분에 `fowoco_runtime`은 그 테이블들에 자동으로 DML 권한만 받는다 (DDL·`TRUNCATE`·`REFERENCES`·superuser·bypass RLS 전부 없음).

```bash
kubectl -n fowoco create secret generic server-env \
  --from-literal=SPRING_PROFILES_ACTIVE=dev \
  --from-literal=DB_URL='jdbc:postgresql://postgres:5432/fowoco' \
  --from-literal=DB_RUNTIME_USERNAME=fowoco_runtime \
  --from-literal=DB_RUNTIME_PASSWORD='<위에서 만든 runtime 비밀번호>' \
  --from-literal=DB_MIGRATION_USERNAME=fowoco_migration \
  --from-literal=DB_MIGRATION_PASSWORD='<위에서 만든 migration 비밀번호>' \
  --from-literal=JWT_SECRET_BASE64='<openssl rand -base64 32>' \
  --from-literal=CORS_ALLOWED_ORIGINS='http://fowoco.<EC2 퍼블릭 IP>.nip.io' \
  --from-literal=AI_RUNTIME_ENABLED=true \
  --from-literal=AI_RUNTIME_ENDPOINT='http://ai:8000/internal/v1/analyses' \
  --from-literal=AI_RUNTIME_SERVICE_CREDENTIAL='<openssl rand -hex 24>' \
  --from-literal=REFRESH_TOKEN_COOKIE_SECURE=false

kubectl apply -f k8s/02-server.yaml
kubectl -n fowoco rollout status deployment/server --timeout=180s
```

**왜 `prod`가 아니라 `dev`인가**: `prod` 프로필은 `WORKFLOW_CATALOG_LOCATION`이 릴리즈된(`RELEASED`) 카탈로그 프로젝션을 가리켜야 하고 `allow-unreleased: false`라 DRAFT를 못 씀 — 아직 그런 릴리즈가 없음. server 자체 `docs/deployment-runbook.md`도 "임시 HTTP 주소와 DRAFT Catalog는 개발 Smoke에만 사용"이라고 명시하며 이 단계를 `dev`로 상정하고 있음. `dev`는 `WORKFLOW_CATALOG_LOCATION`을 지정 안 해도 jar 안에 번들된 기본 DRAFT 카탈로그를 씀.

## 실제로 두 번 겪은 함정

1. **GHCR private (3/3 재현)** — `client`/`ai`/`server` 전부 최초 push 시 GHCR 패키지가 private로 생성돼서 `ImagePullBackOff`. `github.com/orgs/fowoco/packages/container/<이름>/settings` → Change visibility → Public 으로 전환 (조직 정책이 막혀있으면 `github.com/organizations/fowoco/settings/packages`에서 먼저 켜야 함, 최초 1회만). API로는 이 전환이 아예 막혀있어서 (`PATCH .../packages/container/{name}` 항상 404) 웹 UI로만 가능. 전환 직후 익명 pull 토큰 전파에 짧은 지연(약 1분)이 있을 수 있음 — pod를 강제 재시작(`kubectl delete pod`)하면 바로 해결됨.
2. **`SERVER_PORT` 충돌** — k8s가 네임스페이스의 모든 Service에 대해 `<SVC이름>_PORT` env var를 자동 주입하는데(레거시 Docker links, 기본 켜짐), Service 이름이 `server`라서 `SERVER_PORT=tcp://<IP>:8080`이 주입되고 Spring Boot `server.port`랑 충돌해서 부팅 실패. 모든 워크로드 pod spec에 `enableServiceLinks: false` 추가로 해결 (이미 `k8s/`에 반영됨).

## server 필수 환경변수 (`dev`/`prod` 공통)

`server/src/main/resources/application.yaml` 기준. 기본값이 없는 항목은 반드시 넣어야 기동됨.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `DB_URL` | 없음(필수) | `jdbc:postgresql://postgres:5432/fowoco` (같은 네임스페이스라 짧은 Service 이름으로 충분) |
| `DB_RUNTIME_USERNAME` / `DB_RUNTIME_PASSWORD` | 없음(필수) | 위에서 만든 `fowoco_runtime` 계정 |
| `DB_MIGRATION_USERNAME` / `DB_MIGRATION_PASSWORD` | 없음(필수) | 위에서 만든 `fowoco_migration` 계정 — **runtime과 반드시 분리**, 재사용 금지 (RLS 전제 조건) |
| `CORS_ALLOWED_ORIGINS` | 없음(필수) | client가 서빙되는 origin |
| `JWT_SECRET_BASE64` | 없음(필수) | `openssl rand -base64 32`로 생성 |
| `AI_RUNTIME_ENABLED` | `false` | `true`로 켜면 `AI_RUNTIME_ENDPOINT`/`AI_RUNTIME_SERVICE_CREDENTIAL` 둘 다 사실상 필수가 됨 |
| `AI_RUNTIME_ENDPOINT` | `http://127.0.0.1:8000/...` | 클러스터 내부면 `http://ai:8000/internal/v1/analyses` |
| `AI_RUNTIME_SERVICE_CREDENTIAL` | 없음 | **`AI_RUNTIME_ENABLED=true`면 비어있으면 부팅 자체가 실패함** (`.env.example`엔 선택처럼 보이지만 아님). `ai`는 아직 이 값을 검증하지 않으므로 임의 랜덤 값이면 충분 |
| `REFRESH_TOKEN_COOKIE_SECURE` | `dev`/`prod`는 `true` | HTTPS 아니면 로그인 쿠키가 안 붙음 — 지금처럼 http 데모 도메인이면 `false`로 명시 override 필수 |
| `WORKFLOW_CATALOG_LOCATION` | `dev`는 jar 내장 DRAFT 사용, `prod`는 필수(기본값 없음) | `prod` 전환 전까지는 지정 안 해도 됨 |

## ai 필수 환경변수

없음. 전부 기본값으로 동작 (`ai/app/core/config.py` 기준, LLM 관련 값은 비워두면 템플릿 기반 stub로 동작).

## client 빌드 시 필요한 값

`VITE_API_BASE_URL` — 빌드 타임(Vite) 값. `/api/v1` 기본값으로 상대경로 사용 예정 → 배포 IP/도메인이 바뀌어도 이미지 재빌드 불필요 ([[Deployment Plan]] 참고, 아직 client에 미반영).
