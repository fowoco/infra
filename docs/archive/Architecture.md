# Architecture

Docker Compose로 계획했던 초기 구상 대신 **k3s(경량 쿠버네티스) + AWS EC2**로 확정.

```
AWS EC2 (ap-northeast-2, Seoul) — 단일 노드 k3s 클러스터
├── client   (nginx, 정적 SPA)         → Ingress "/"
├── server   (Spring Boot, :8080)      → Ingress "/api"
├── ai       (FastAPI, :8000)          → 클러스터 내부 전용, 외부 노출 안 함
└── postgres (postgres:16-alpine, PVC) → server가 클러스터 내부 DNS로 접근
```

- 이미지 레지스트리: GHCR (`ghcr.io/fowoco/<client|server|ai>`) — 이미지가 private면 클러스터가 pull을 못 함. **client/ai/server 셋 다에서 실제로 겪은 문제 (3/3, [[History]] 참고)** — 전부 Public 전환 완료.
- 배포: 각 앱 저장소의 GitHub Actions가 push → 빌드 → GHCR 푸시 → 클러스터에 자동 반영. `client`/`ai`는 `deploy.yml`이 매번 infra 매니페스트를 자동 `kubectl apply`하는 self-heal 구조 (2026-08-05/06, [[Deployment Plan]] 참고). `server`는 아직 self-heal이 아니라 2026-08-06에 infra 쪽에서 수동으로 최초 부트스트랩함 (PR #97 머지 후 self-heal 전환 예정).
- `client`는 main에 PR 병합 전 CI(lint/test/build)가 필수(branch protection, required status check)로 걸려있음. `server`/`ai`는 아직 없음.
- 도메인: 아직 없음 — `nip.io` 와일드카드 DNS로 데모 (`fowoco.<EC2 퍼블릭 IP>.nip.io`), TLS 미설정이라 `http://`만 동작. ingress가 `/api` → `server`, `/` → `client`로 라우팅해서 **client UI와 server API가 같은 도메인 하나로 다 붙는 상태** (2026-08-06 확인)
- k8s가 Service 이름 기준으로 자동 주입하는 `<SVC이름>_PORT` env var(레거시 Docker links 호환)가 앱 설정과 이름 충돌을 일으킬 수 있음 — 실제로 `server` Service가 Spring Boot의 `server.port`와 충돌해서 부팅 실패했던 사례가 있음 (2026-08-06). 모든 워크로드에 `enableServiceLinks: false` 적용해서 예방.
- AWS 보안그룹(`fowoco-sg`): SSH(22)는 실사용자 없어서 완전히 닫음 (2026-08-06). k3s API(6443)는 GitHub Actions가 직접 써야 해서 `0.0.0.0/0` 유지 — TLS client-cert 인증이 실질적 방어선.

## 왜 이 구조인가

- `server`는 마이크로서비스가 아니라 모듈러 모놀리스로 설계됨 — 배포 단위가 client/server/ai/postgres 4개뿐이라 OpenStack 같은 무거운 오케스트레이션이 불필요.
- Postgres는 매니지드 서비스 대신 클러스터 안에 직접 운영 — AWS 크레딧으로 비용 압박이 없어져서 "전부 우리 인프라 안에서" 원칙을 유지할 수 있게 됨.
- `ai`는 외부 노출 없이 클러스터 내부에서만 `server`가 호출하는 구조 (server의 `AiRuntimeClient`가 `ai`의 내부 API를 호출).

원본 매니페스트는 이 저장소의 `k8s/` 디렉터리 참고.
