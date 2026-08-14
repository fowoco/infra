# Deployment Plan

`client`/`server`/`ai` 세 저장소에 배포 파이프라인(Dockerfile + GitHub Actions)을 PR로 올렸습니다. **머지되면 자동으로 빌드·배포됩니다.** 클러스터 최초 부트스트랩(namespace/secret 생성, 첫 `kubectl apply`)은 `infra` 쪽에서 별도로 진행합니다.

## 현재 상태 (2026-08-06 기준)

| 저장소 | Dockerfile | CI/CD 워크플로우 | 상태 |
|---|---|---|---|
| `client` | 신규 작성 (nginx 기반, `VITE_API_BASE_URL`은 코드 기본값 `/api/v1` 상대경로라 별도 build arg 불필요) | self-heal bootstrap 적용 완료 | **실배포·라이브 확인됨** ([#179](https://github.com/fowoco/client/pull/179) 머지 → [#262](https://github.com/fowoco/client/pull/262)/[#264](https://github.com/fowoco/client/pull/264), [[History]] 참고) |
| `server` | Multi-stage, non-root, healthcheck 포함 (PR #97) | self-heal bootstrap 적용 완료 ([#97](https://github.com/fowoco/server/pull/97), 2026-08-10 머지) | **실배포·라이브 확인됨** (2026-08-10 기준: ai-env 연결, `/app/data` PVC, bootstrap 함수 권한까지 전부 반영, [[History]] 참고) |
| `ai` | 기존 것 그대로 사용 (로컬 빌드 검증 완료) | self-heal bootstrap 적용 완료 ([ai#21](https://github.com/fowoco/ai/issues/21)/[#22](https://github.com/fowoco/ai/pull/22)) | **실배포·라이브 확인됨** |

### client 배포 품질 게이트 (2026-08-05 완료)

`client`는 배포 자체가 되는 것 확인한 뒤, 아래도 추가로 정비함:

| 항목 | 내용 |
|---|---|
| PR CI (`ci.yml`) | `pull_request` 트리거로 lint/test/build 자동 검증 ([client#265](https://github.com/fowoco/client/issues/265)/[#266](https://github.com/fowoco/client/pull/266)). 첫 실행에서 pre-existing flaky 테스트(`LinkRequestPage`, `getByText`→`findByText`)도 잡아서 같이 수정함 |
| Branch protection | `main`에 `verify`(CI) 통과를 required status check로 설정 — 리뷰 승인은 미요구, force-push/삭제는 금지 |
| Resource requests/limits | `k8s/04-client.yaml`에 client 컨테이너 requests 50m cpu/64Mi mem, limits 200m cpu/128Mi mem 추가 (infra [#4](https://github.com/fowoco/infra/issues/4)/[#5](https://github.com/fowoco/infra/pull/5)) — 단일 노드에서 server/ai/postgres와 무제한 경쟁하던 문제 해소 |

`server`/`ai`는 위 세 가지 다 아직 없음 (CI 워크플로우 자체가 없고, branch protection도, resource limits도 미설정).

### server/ai 최초 배포 (2026-08-06 완료)

`ai` PR #22가 머지되면서 계획보다 먼저 실전 배포됨 → client와 동일한 GHCR private 문제 재현·해결. 이 흐름에 이어서 `server`도 같이 진행:

| 항목 | 내용 |
|---|---|
| postgres | `postgres-secret` 수동 생성, `01-postgres.yaml` 적용. `POSTGRES_USER=fowoco_admin`(superuser, 관리용) |
| DB role 분리 | `fowoco_migration`(테이블 소유, Flyway 전용) / `fowoco_runtime`(DML만, `NOSUPERUSER NOBYPASSRLS`) — server의 `docs/database/postgresql-rls-rollout.md`가 명시한 role 분리 그대로 적용. `ALTER DEFAULT PRIVILEGES`로 향후 migration role이 만드는 테이블에 runtime role이 자동으로 DML 권한 받음 |
| server-env | `SPRING_PROFILES_ACTIVE=dev`(TLS·릴리즈 카탈로그 없어서 `prod` 대신), DB 계정 2종, `JWT_SECRET_BASE64`, `CORS_ALLOWED_ORIGINS`, `AI_RUNTIME_*`(엔드포인트는 클러스터 내부 `http://ai:8000/...`), `REFRESH_TOKEN_COOKIE_SECURE=false`(HTTP 전용 도메인이라 필수) |
| GHCR | `ghcr.io/fowoco/server`도 private → Public 전환 (3번째 반복, [[History]] 참고) |
| 버그 2건 | `SERVER_PORT` env var 충돌([[Architecture]] 참고, `enableServiceLinks: false`로 해결) / `AI_RUNTIME_SERVICE_CREDENTIAL` 필수값 누락 |
| 검증 | `client`/`server`/`ai`/`postgres` 전부 `1/1 Running`, `/actuator/health`·`/health` 200, Flyway 30개 테이블 생성, ingress `/api` 경유 signup 스모크 테스트까지 확인 |

**남은 것**: `ai`의 CI/branch protection(`server`엔 이미 있음), `prod` 프로필 전환(TLS+릴리즈 카탈로그 준비 후), SMTP 앱 비밀번호(비밀번호 재설정 메일 발송). **resource limits는 2026-08-06에 셋 다(server/ai/postgres) 완료됨** ([infra#8](https://github.com/fowoco/infra/issues/8)/[#9](https://github.com/fowoco/infra/pull/9)). `server`의 `deploy.yml` self-heal 전환은 2026-08-10 PR #97 머지로 완료.

### server Dockerfile 버그 발견 및 수정

기존 임시 Dockerfile(#31)이 `gradle:8.10-jdk17` 고정 이미지를 사용하고 있었는데, 실제로 로컬에서 빌드해보니 **Spring Boot 4.1.0 플러그인이 Gradle 8.14 이상을 요구**해서 빌드 자체가 실패하는 상태였습니다 (`gradle-wrapper.properties`엔 9.5.1로 지정돼 있음). 고정 이미지 대신 프로젝트의 `./gradlew`를 쓰도록 바꿔서 로컬 빌드 성공까지 확인 후 PR #66에 반영했습니다.

## 워크플로우 구조 (3개 저장소 공통)

main에 push되면: GHCR에 이미지 빌드/푸시(`:latest` + `:<commit sha>`) → 클러스터에 `kubectl set image`로 반영. 최초 배포 시에는 Deployment 자체가 아직 없어서 이 스텝이 실패할 수 있는데(정상), infra 쪽에서 `kubectl apply -f k8s/`로 Deployment를 먼저 만들어두면 그다음부터는 정상 작동합니다.

## 시크릿

애초 계획은 `fowoco` 조직 레벨 시크릿이었으나, 그러려면 `admin:org`라는 넓은 권한이 추가로 필요해서 **저장소별 개별 시크릿으로 변경**했습니다.

| 이름 | 등록 위치 | 비고 |
|---|---|---|
| `KUBE_CONFIG` | `client`/`server`/`ai` 각 저장소에 개별 등록 완료 | AWS EC2 k3s 클러스터의 kubeconfig(base64) |
| `GITHUB_TOKEN` | 자동 제공 | GHCR 푸시용, 별도 등록 불필요 |

GHCR 패키지는 최초 푸시 후 Public으로 전환하면 클러스터에서 `imagePullSecrets` 없이 바로 이미지를 받아올 수 있음 (필수). **`client`/`ai`/`server` 셋 다 2026-08-05~06에 이 전환까지 완료함** — GHCR 패키지가 기본 private 상태라 클러스터가 이미지를 못 당겨오던 것(`ImagePullBackOff`)이 세 저장소 모두에서 실배포 실패의 진짜 원인이었음 ([[History]] 참고). **3/3으로 재현된 패턴이라 새로 생기는 fowoco GHCR 패키지는 기본적으로 이 전환이 필요하다고 가정할 것.**

## 남은 순서 (2026-08-06 기준)

1. ~~팀에서 위 3개 PR 리뷰 후 머지~~ — 완료
2. ~~infra 쪽에서 namespace/secret 생성 + `kubectl apply -f k8s/`로 최초 배포~~ — `client`/`ai`는 워크플로우 자체가 매번 자동으로 처리(self-heal), `server`는 2026-08-06에 infra가 수동으로 처리 완료
3. `client`/`server`/`ai` 전부 실배포·라이브 확인됨. 남은 건:
   - `server`의 `deploy.yml`에도 self-heal bootstrap 적용 — PR #97 머지 후 진행 (지금 건드리면 같은 파일 충돌)
   - `server`/`ai`에 `client`와 동일한 CI 워크플로우/branch protection/resource limits 적용 (전부 아직 없음)
   - `prod` 프로필 전환은 TLS + 릴리즈된 Workflow Catalog 준비 후

## 참고

- [[Architecture]]
- [[Deployment Guide]]
