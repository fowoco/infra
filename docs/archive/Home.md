# FOWOCO Infra Wiki

FOWOCO 배포/인프라 관련 문서 모음.

- [[Architecture]] — 전체 구조 (AWS EC2 + k3s, 서비스 구성)
- [[Deployment Guide]] — 최초 배포 순서, 필수 환경변수
- [[Deployment Plan]] — CI/CD 파이프라인. `client`/`server`/`ai` 셋 다 실배포 완료. CI·branch protection·resource limits는 `client`만 완료, `server`/`ai`는 아직
- [[History]] — 날짜별 작업 기록 (Oracle 실패 → AWS 전환 → 배포 파이프라인 구축 → client 실배포 확인까지)

## 한눈에 보기

- 클라우드: **AWS** (ap-northeast-2, Seoul) — Oracle Cloud Free Tier가 5일간 재고 부족으로 실패해서 전환함 ([[History]] 참고)
- 오케스트레이션: k3s 단일 노드
- 저장소: `client`(React), `server`(Spring Boot), `ai`(FastAPI), `knowledge`(Python 라이브러리), `infra`(이 저장소)
- 이미지 레지스트리: GHCR (`ghcr.io/fowoco/*`) — 패키지가 private면 클러스터가 pull 못 함, 반드시 Public이어야 함. **client/ai/server 셋 다에서 실제로 겪음 (3/3) — 새 패키지는 기본적으로 이 전환이 필요하다고 가정할 것**
- **`client`/`server`/`ai` 전부 2026-08-06 기준 실제로 살아있음**: `http://fowoco.3.35.105.80.nip.io/` → HTTP 200, `/api/v1/...`도 같은 도메인에서 server로 라우팅됨(ingress `/api` prefix), `ai`는 클러스터 내부에서 server가 정상 호출 가능. Postgres는 `fowoco_migration`/`fowoco_runtime` role 분리로 30개 테이블 생성 완료

세부 트러블슈팅 배경은 팀 공유 문서(Notion)에도 업데이트할 예정.
