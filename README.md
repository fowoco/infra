# infra

Docker Compose 대신 **k3s(경량 쿠버네티스) + AWS EC2**로 확정. Docker Compose로 계획했던 초기 구상을 대체함 — 이유는 `k8s/` 매니페스트와 아래 아키텍처 설명 참고.

## 아키텍처

```
AWS EC2 (ap-northeast-2, Seoul) — 단일 노드 k3s 클러스터
├── client   (nginx, 정적 SPA)         → Ingress "/"
├── server   (Spring Boot, :8080)      → Ingress "/api"
├── ai       (FastAPI, :8000)          → 클러스터 내부 전용, 외부 노출 안 함
└── postgres (postgres:16-alpine, PVC) → server가 클러스터 내부 DNS로 접근
```

- 이미지 레지스트리: GHCR (`ghcr.io/fowoco/<client|server|ai>`)
- 배포: 각 앱 저장소의 GitHub Actions가 push → 빌드 → GHCR 푸시 → 클러스터에 자동 반영 (`.github/workflows/deploy.yml`, 각 저장소 참고)
- 도메인: 아직 없음 — `nip.io` 와일드카드 DNS로 데모 (`fowoco.<EC2 퍼블릭 IP>.nip.io`)

## 최초 배포 순서

```bash
kubectl apply -f k8s/00-namespace.yaml

# 아래 두 Secret은 git에 올리지 않는다 — 직접 생성
kubectl -n fowoco create secret generic postgres-secret \
  --from-literal=POSTGRES_DB=fowoco \
  --from-literal=POSTGRES_USER=fowoco \
  --from-literal=POSTGRES_PASSWORD='<비밀번호>'

kubectl -n fowoco create secret generic server-env \
  --from-literal=SPRING_PROFILES_ACTIVE=prod \
  --from-literal=DB_URL='jdbc:postgresql://postgres.fowoco.svc.cluster.local:5432/fowoco' \
  --from-literal=DB_RUNTIME_USERNAME=fowoco \
  --from-literal=DB_RUNTIME_PASSWORD='<postgres-secret과 동일한 비밀번호>' \
  --from-literal=DB_MIGRATION_USERNAME=fowoco \
  --from-literal=DB_MIGRATION_PASSWORD='<postgres-secret과 동일한 비밀번호>' \
  --from-literal=CORS_ALLOWED_ORIGINS='http://fowoco.<EC2 퍼블릭 IP>.nip.io' \
  --from-literal=JWT_ISSUER=fowoco-server \
  --from-literal=JWT_AUDIENCE=fowoco-client \
  --from-literal=JWT_SECRET_BASE64='<openssl rand -base64 32 로 생성>' \
  --from-literal=WORKFLOW_CATALOG_LOCATION='classpath:workflow/catalog-projection.local.json'

kubectl apply -f k8s/
```

## server 필수 환경변수 (prod 프로파일 기준)

`server/src/main/resources/application.yaml`의 `prod` 프로파일을 기준으로 정리. 기본값이 없는 항목은 반드시 넣어야 기동됨.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `DB_URL` | 없음(필수) | `jdbc:postgresql://postgres.fowoco.svc.cluster.local:5432/fowoco` |
| `DB_RUNTIME_USERNAME` / `DB_RUNTIME_PASSWORD` | 없음(필수) | 런타임 쿼리용 DB 계정 |
| `DB_MIGRATION_USERNAME` / `DB_MIGRATION_PASSWORD` | 없음(필수) | Flyway 마이그레이션용 DB 계정 (데모 규모에선 runtime과 동일 계정 재사용해도 무방) |
| `CORS_ALLOWED_ORIGINS` | 없음(필수) | client가 서빙되는 origin |
| `JWT_ISSUER` / `JWT_AUDIENCE` | 없음(필수) | 임의 문자열, client와 값만 맞으면 됨 |
| `JWT_SECRET_BASE64` | 없음(필수) | `openssl rand -base64 32`로 생성 |
| `WORKFLOW_CATALOG_LOCATION` | 없음(필수, default 프로파일에만 기본값 있음) | `classpath:workflow/catalog-projection.local.json` (jar 안에 이미 포함된 리소스) |
| `REFRESH_TOKEN_COOKIE_SECURE` | `true` | HTTPS 아니면 로그인 쿠키가 안 붙을 수 있음 — 데모가 http라면 `false`로 |

## ai 필수 환경변수

없음. 전부 기본값으로 동작 (`ai/app/core/config.py` 기준, LLM 관련 값은 비워두면 템플릿 기반 stub로 동작).

## client 빌드 시 필요한 값

`VITE_API_BASE_URL` — 빌드 타임(Vite) 값. Dockerfile에 `/api/v1` 기본값이 박혀 있어 상대경로로 동작 → 배포 IP/도메인이 바뀌어도 이미지 재빌드 불필요.
