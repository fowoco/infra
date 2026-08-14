# infra

FOWOCO 배포/인프라 관련 문서는 [ARCHITECTURE.md](./ARCHITECTURE.md)에 정리되어 있습니다 (예전 Wiki는 비우고 이 저장소로 이관했습니다. 과거 기록은 [docs/archive/](./docs/archive/) 참고).

**현재 상태**: `client`/`server`/`ai` 전부 AWS EC2 위 k3s 클러스터에 실제로 배포되어 살아있습니다 (`http://fowoco.3.35.105.80.nip.io/`).

배포 매니페스트 자체는 `k8s/` 디렉터리 참고.
