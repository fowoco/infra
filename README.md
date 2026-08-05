# infra

FOWOCO 배포/인프라 관련 문서는 [Wiki](https://github.com/fowoco/infra/wiki)에 정리되어 있습니다.

- [Home](https://github.com/fowoco/infra/wiki) — 전체 요약, 현재 상태 한눈에 보기
- [Architecture](https://github.com/fowoco/infra/wiki/Architecture) — 전체 구조 (AWS EC2 + k3s)
- [Deployment Guide](https://github.com/fowoco/infra/wiki/Deployment-Guide) — 최초 배포 순서, 필수 환경변수
- [Deployment Plan](https://github.com/fowoco/infra/wiki/Deployment-Plan) — CI/CD 파이프라인 현황 (`client`는 실배포·CI·branch protection·resource limits까지 완료, `server`/`ai`는 아직)
- [History](https://github.com/fowoco/infra/wiki/History) — 날짜별 작업 기록

**현재 상태**: `client`는 AWS EC2 위 k3s 클러스터에 실제로 배포되어 있고 살아있습니다 (`http://fowoco.3.35.105.80.nip.io/`). `server`/`ai`는 같은 패턴 적용 예정, 아직 미완료.

배포 매니페스트 자체는 `k8s/` 디렉터리 참고.
