## 한눈에 보기

- 클라우드: **AWS ap-northeast-2 (Seoul)**
- 오케스트레이션: **k3s 단일 노드** (EC2 `fowoco-node-1`, m7i-flex.large, 2 vCPU/8GiB)
- 저장소: `client`(React), `server`(Spring Boot), `ai`(FastAPI), `infra`(이 저장소)
- 이미지 레지스트리: GHCR (`ghcr.io/fowoco/*`, Public 필수)
- 도메인: `fowoco.3.35.105.80.nip.io` + cert-manager/Let's Encrypt로 실제 HTTPS 인증서 자동 발급
- **`client`/`server`/`ai` 전부 실배포·라이브 상태**, 셋 다 GitHub Actions self-heal 배포 (push마다 자동 `kubectl apply` + `set image`)

## 아키텍처

```mermaid
flowchart TB
    User["HR 담당자<br/>브라우저"]
    GHA["GitHub Actions<br/>client · server · ai repo"]

    subgraph AWS["AWS ap-northeast-2 · VPC 172.31.0.0/16"]
        subgraph EC2["EC2 fowoco-node-1 (m7i-flex.large)"]
            subgraph K3S["k3s · namespace fowoco"]
                Ingress["Traefik Ingress<br/>HTTPS 80→443, cert-manager"]
                Client["client<br/>React 19 · Vite 8 · nginx"]
                Server["server<br/>Spring Boot 4.1 · Java 17"]
                Ai["ai<br/>FastAPI · Python 3.11<br/>(클러스터 내부 전용)"]
                PG[("postgres<br/>postgres:16-alpine")]
            end
            EBS[("EBS 100GB gp3<br/>local-path PVC")]
        end
        Dev["EC2 fowoco-dev<br/>(SSM 전용, 평소 중지)<br/>트래픽·배포 경로와 무관"]
        DLM["DLM 일일 스냅샷<br/>18:00 KST · 7일 보관"]
    end

    GHCR["ghcr.io/fowoco/*<br/>이미지 레지스트리"]

    User -->|HTTPS| Ingress
    Ingress -->|"/ (정적자산)"| Client
    Ingress -->|"/api, /actuator"| Server
    Client -->|REST fetch| Server
    Server -->|내부호출| Ai
    Server -->|JDBC| PG
    PG -.백업.-> EBS
    EBS -.-> DLM

    GHA -->|build & push| GHCR
    GHCR -->|main 머지 시 자동 pull| EC2
```

## 라우팅

| 경로 | 대상 | 비고 |
|---|---|---|
| `/` | `client` (nginx) | SPA catch-all |
| `/api` | `server` (:8080) | REST API |
| `/actuator` | `server` (:8080) | health/metrics |
| (없음) | `ai` (:8000) | 외부 미노출, `server`만 내부 호출 |

## 배포 파이프라인

```
push to main → GitHub Actions
  → docker build & push (ghcr.io/fowoco/<repo>:latest, :<sha>)
  → kubectl apply -f infra/k8s/*.yaml  (self-heal bootstrap)
  → kubectl set image deployment/<repo> ...
  → rollout status 확인
```

## 백업 / 복구

- EBS 100GB(`vol-001d68981ae503c1b`) 매일 18:00 KST DLM 스냅샷, 7일 보관.
- 2026-08-13 실제 복구 드릴 완료 — PostgreSQL 16 데이터 디렉터리 정상, 문서 파일 확인. 

## 비용

- `m7i-flex.large` 온디맨드 $0.11771/hr. `fowoco-node-1`은 24/7, `fowoco-dev`는 인프라 검증 시에만 기동.

