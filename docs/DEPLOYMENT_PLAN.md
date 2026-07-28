# 배포 자동화 계획 (추후 진행 예정)

이 문서는 `client`/`server`/`ai` 저장소에 실제로 반영되기 **전 단계의 계획**입니다. 각 저장소는 소유 팀원과 협의 후 별도로 반영합니다. `infra` 저장소는 이 계획을 관리하는 용도로만 사용합니다.

## 현재 상태 (2026-07-28 기준)

| 저장소 | Dockerfile | CI/CD 워크플로우 |
|---|---|---|
| `client` | 임시 버전이 PR로 대기 중 ([#99](https://github.com/fowoco/client/pull/99), 미머지) | 없음 |
| `server` | 임시 버전 머지됨 ([#31](https://github.com/fowoco/server/pull/31)) — "TEMP" 표시된 상태, 정식화 필요 | 있음 (`ci.yml`, 테스트만 — 배포는 없음) |
| `ai` | 팀원이 이미 추가함 (`python:3.12-slim` 기반) | 없음 |

## 진행 예정 작업

### 1. client — Dockerfile에 빌드 인자 추가 필요
`VITE_API_BASE_URL`을 빌드 타임에 상대경로(`/api/v1`)로 기본 설정해서, 배포 IP/도메인이 바뀌어도 이미지를 다시 안 만들어도 되게 개선 예정.

```dockerfile
ARG VITE_API_BASE_URL=/api/v1
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN npm run build
```

### 2. 세 저장소 공통 — `.github/workflows/deploy.yml` 초안

main에 push되면 이미지를 빌드해 GHCR에 올리고, 클러스터에 반영하는 워크플로우. 아래는 참고용 초안이며, 실제로는 각 저장소에 맞게 이미지 이름/컨테이너 이름만 바꿔서 넣으면 됨.

```yaml
name: deploy
on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/fowoco/<저장소명>:latest
            ghcr.io/fowoco/<저장소명>:${{ github.sha }}

      - name: Set up kubectl
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > ~/.kube/config

      - name: Rollout
        run: |
          kubectl -n fowoco set image deployment/<컨테이너명> \
            <컨테이너명>=ghcr.io/fowoco/<저장소명>:${{ github.sha }}
```

### 3. 필요한 시크릿 (조직 레벨, `fowoco` org secrets)

| 이름 | 용도 | 비고 |
|---|---|---|
| `KUBE_CONFIG` | 클러스터 접근용 kubeconfig(base64) | AWS EC2 k3s 클러스터의 kubeconfig — 아직 org secret으로 등록 안 됨 |
| `GITHUB_TOKEN` | GHCR 푸시 | 자동 제공, 별도 등록 불필요 |

GHCR 패키지는 최초 푸시 후 Public으로 전환하면 클러스터에서 `imagePullSecrets` 없이 바로 이미지를 받아올 수 있음 (권장).

### 4. 실행 순서 (합의되면)

1. 팀 리뷰 후 각 저장소에 위 워크플로우 추가
2. `KUBE_CONFIG` org secret 등록
3. `client`는 Dockerfile 빌드 인자 반영 (PR #99에 추가 커밋 또는 신규 PR)
4. push 한 번으로 자동 빌드·배포 확인
