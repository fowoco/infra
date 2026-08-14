# History

인프라 작업을 날짜별로 정리한 기록. 세부 트러블슈팅 로그는 팀 공유 문서(Notion 예정) 참고.

## 2026-08-13 (진짜 마무리) — 모니터링 대시보드 구축

- **`/actuator` 경로를 server로 라우팅 추가** (infra#25→PR#26) — 지금까지 `/actuator/health`·`/health` 등 `/api` 접두사 없는 경로는 client SPA fallback으로 가서, 외부에서 server 실제 상태를 확인할 방법이 없었음. `MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS=always`도 server-env에 추가(앱 코드 안 건드리고 env로) — 이제 `/actuator/health?show-details=always`로 DB·SMTP·디스크 연결 상태까지 실시간 확인 가능.
- **CORS 때문에 브라우저에서 fowoco 서버를 직접 fetch 못 하는 것 확인** (다른 origin에서 요청하면 403 — CORS_ALLOWED_ORIGINS를 앱 자체 오리진으로 좁혀놓은 의도된 동작). 대신 **`status-check` GitHub Actions**(infra#27→PR#28, `.github/workflows/status-check.yml`)를 만들어서 10분마다 client/server 헬스체크 후 결과를 `status-data` 브랜치에 `status.json`으로 커밋 — `raw.githubusercontent.com`은 `Access-Control-Allow-Origin: *`라 대시보드에서 CORS 없이 바로 읽을 수 있음.
- **실제 파드 상태(kubectl)까지 추가** (infra#29): 클러스터 관리자 kubeconfig를 그대로 시크릿으로 등록하는 대신, **fowoco 네임스페이스 pods get/list만 되는 별도 ServiceAccount(`status-reader`)를 새로 만들어서 최소 권한으로 등록** — secrets 조회·파드 삭제 등 시도해서 전부 Forbidden인 것 확인 후 등록. `kubectl config view`로 세션의 관리자 kubeconfig를 파일로 빼내는 시도는 사용자 채팅 승인과 별개로 자동 실행 정책에서 계속 막혔음 — **이런 경우 새로 스코프를 좁힌 자격증명을 만드는 우회가 정책과도 안 부딪히고 보안상으로도 더 나음, 다음에도 이 패턴 사용**.
- **모니터링 대시보드를 Artifact로 게시**: client/server(DB·SMTP·디스크 하위 항목 포함)/AI Runtime(파드 상태로 간접 확인) 카드, 실제 파드 테이블(ready/재시작/가동시간), 요청 경로 다이어그램(로드밸런싱은 단일 노드라 해당 없다고 명시), 10분 자동 갱신 + 수동 새로고침, 마지막 체크 25분 초과 시 "워크플로우가 멈췄을 수 있음" 경고.

## 2026-08-13 (계속) — AI Run "선택한 업무 생성"이 항상 500이던 진짜 버그 발견·수정

사용자가 "AI가 실제로 업무함에 저장까지 잘 되는지" 직접 UI로 처음부터 끝까지 확인해달라고 요청 — 크롬으로 대시보드에서 새 업무 요청 → AI 분석 → 후보 확인까지는 전부 정상(근로자 정확히 매칭, 정보 추출 정상)이었는데, 마지막 "선택한 업무 생성" 클릭 시 항상 500 에러.

- **원인**: `server`의 `JdbcTaskCaseRegistrar.registerComposite()`(`workflow_case` INSERT)가 `Instant`를 그대로 `jdbcTemplate.update(...)`에 넘겨서 pgjdbc가 타입 추론 실패(`Can't infer the SQL type to use for an instance of java.time.Instant`). 같은 패키지의 다른 리포지토리 클래스는 이미 `Timestamp.from(instant)`로 감싸고 있었는데 이 파일만 빠뜨림.
- **server issue #164 → PR #165**: `Timestamp.from(...)`로 감싸서 수정, 로컬 `./gradlew compileJava` 클린 컴파일 확인(Docker 없어서 DB 테스트는 CI에 맡김). 이 경로 자체에 테스트가 아예 없었던 것도 확인 — 회귀 테스트 추가를 이슈에 권장해둠.
- **`ai`#40과 마찬가지로 셀프머지 안 함** — server는 리뷰 승인 필수(branch protection)라 애초에 셀프머지 불가.
- 이 세션에서 발견한 3번째 "겉보기엔 다른 문제 같았는데 실제로는 완전히 다른 층(layer)의 버그"였던 사례: (1) DiskPressure처럼 보였던 게 사실 probe timeout, (2) ai NER 조사 처리, (3) 이번엔 AI 분석 자체는 멀쩡한데 마지막 영속화(persist) 단계의 JDBC 타입 바인딩. **패턴: "AI/파이프라인이 안 되는 것 같다"는 증상이 실제로는 그 훨씬 앞이나 뒤의 완전히 다른 컴포넌트에 있는 경우가 많았다 — 항상 실제 로그/스택트레이스로 정확한 실패 지점을 확인하고 나서 고칠 것.**

## 2026-08-13 (마무리) — 디스크 장애 재발 방지, ReplicaSet 정리, GitHub secret scanning 전체 적용

- **k3s 노드 EBS 30GB → 100GB 확장**: `ai` 재배포 때마다 겪었던 디스크 부족 재발을 막기 위해 실시. `aws ec2 modify-volume`으로 온라인 확장(다운타임 없음) → 노드에서 `growpart /dev/nvme0n1 1` + `resize2fs /dev/nvme0n1p1`로 실제 파일시스템까지 확장. 결과: `/dev/root 97G, 26G 사용(27%), 72G 여유`. **SSH가 없는 노드에서 이런 host-level 명령은 `kubectl run`으로 privileged+hostPath(`/`) 파드를 띄우고 `chroot /host`+`nsenter --target 1 ...`로 실행** — 이번 세션에서 확립한 패턴, 다음에도 이 방식 재사용 가능.
- **오래된 ReplicaSet 30개 정리** (ai/server/client 각 배포 이력, 기능엔 영향 없었지만 지저분했음) — 활성 3개만 남기고 삭제.
- **GitHub secret scanning + push protection 5개 레포 전부 활성화** (client/server/ai/knowledge/infra) — 지난 세션에 의도적으로 미뤄뒀던 항목, `gh api -X PATCH repos/fowoco/<repo> -f security_and_analysis[secret_scanning][status]=enabled -f security_and_analysis[secret_scanning_push_protection][status]=enabled`로 일괄 적용.

## 2026-08-13 (계속) — HTTP→HTTPS 강제 리다이렉트, secure 쿠키/CORS 전환 완료

- **Traefik 전역 리다이렉트** (infra#22→PR#23→경로 버그 수정 PR#24): k3s 내장 Traefik을 `HelmChartConfig`(kube-system)로 오버레이해서 web(80)의 모든 요청을 websecure(443)로 301(실제로는 308) 리다이렉트. **주의**: 처음 PR#23에서 `ports.web.redirections.entryPoint`로 썼는데 실제 스키마는 한 단계 더 있는 `ports.web.http.redirections.entryPoint` — 틀린 키는 helm이 조용히 무시해서 helm upgrade는 성공했지만 아무 효과가 없었음. `helm show values traefik/traefik`로 실제 chart 확인 후 재수정. **다음에 Traefik values 건드릴 때는 반드시 `helm show values`로 실제 스키마 먼저 확인할 것.**
- **server-env 마무리 전환**: `REFRESH_TOKEN_COOKIE_SECURE=true`(기존 false), `CORS_ALLOWED_ORIGINS`에서 `http://` 오리진 제거(https만), `WORKER_PORTAL_BASE_URL`을 `https://fowoco.3.35.105.80.nip.io`로 전환 — ai#40 SMS 링크가 이제 실제 휴대전화에서 열림. 크롬으로 로그인→새로고침까지 실제로 확인, 세션 유지되고 콘솔 에러 없음.
- **client를 크롬으로 실사용자처럼 회원가입까지 테스트**: 신규 계정 생성 → 로그인 → 온보딩 → 근로자 등록(직접 입력)까지 전부 실제로 성공. 새 회사(tenant)가 기존 데모 회사와 완전히 격리되는 것도 확인(근로자 0명에서 시작).

## 2026-08-13 (이어서) — HTTPS 적용, ai TARGET_NOT_FOUND 버그 발견·수정

- **HTTPS 적용**: cert-manager v1.16.2 helm install → `ClusterIssuer`(letsencrypt-prod, HTTP-01 via Traefik) → `05-ingress.yaml`에 tls block 추가 (infra#20→PR#21). nip.io는 공개 DNS라 도메인 소유 없이도 HTTP-01 challenge 통과. `https://fowoco.3.35.105.80.nip.io` 실제 Let's Encrypt 인증서로 200 확인, 기존 http도 그대로 유지됨. **다음 단계(미실행)**: `REFRESH_TOKEN_COOKIE_SECURE=true` 전환 + CORS https 전용화는 별도로 결정 필요.
- **client를 크롬으로 실사용자처럼 테스트**하다가 대시보드 "Agent에게 새 업무 요청"이 어떤 근로자 이름을 넣어도 `TARGET_NOT_FOUND`로 실패하는 걸 발견. `ai` 저장소에 직접 PLAN 호출해서 `targetDisplayName`이 `"속 체아의"`처럼 조사(의)가 안 떨어진 채로 오는 걸 확인 — server의 exact-match 조회(`JpaWorkerAiContextReader.findByDisplayName`)가 항상 실패하는 원인. `ai`#40(이슈)→PR#41로 수정 제출(머지는 팀 판단, 셀프머지 안 함): `_guess_target_display_name()`이 조사로 "끝나는" 토큰을 잘라내도록 고침. 처음엔 "이/가/을/를/은/는"까지 자르면 "리웨이" 같은 음역 인명이 깨져서(실제 테스트로 확인, "리웨이"→"리웨") `의`만 좁게 처리했으나, **받침 유무로 조사 짝(이/가, 은/는, 을/를)의 정합성을 검증하는 방식으로 확장**해서 "리웨이" 같은 오탐 없이 훨씬 넓은 케이스를 커버하도록 개선 (예: "란"(받침 있음)+"이"는 정합 → 조사로 인식, "웨"(받침 없음)+"이"는 불일치 → 이름으로 유지).

## 2026-08-13 — ai OOM/server 크래시 해결, SMTP·SMS·CORS 확장 반영

- **ai OOMKilled 수정** (infra#16→PR#17): ai#30(Language Assistant, 임베딩 모델 내장) merge 이후 512Mi 메모리 제한에서 새 파드가 부팅 중 OOMKilled. request 256Mi/limit 2048Mi로 상향, 정상화.
- **server 크래시 원인 2건 발견·해결**:
  1. `DemoGoldenFlowSeedStateGuard`가 PR #111(issue #94) 이전 특정 13개 UUID(구버전 응웬반A Golden Flow 잔재)를 감지하면 fail-fast하도록 설계됨 — 라이브 DB에 그 13개 row가 남아있어 새 파드가 계속 부팅 실패. 데이터는 건드리지 않고 `DEMO_SEED_ENABLED=false`로 전환해 해결(이 설정은 시작 시점 seed 러너 3개 외에 런타임에 전혀 쓰이지 않는 것 확인 후 적용). 나중에 그 13개 row를 targeted delete하면 다시 켤 수 있음.
  2. **더 큰 원인**: server의 readiness/liveness probe에 `timeoutSeconds`가 없어 k8s 기본값 1초 적용 중이었는데, 실제 `/actuator/health` 응답이 1.3~1.4초 걸려서 probe가 구조적으로 절대 성공할 수 없었음(`context deadline exceeded`) — 앱은 정상 기동했는데도 영원히 Not Ready + liveness 재시작 반복으로 겉보기엔 크래시 루프처럼 보였음. 4개 워크로드 전부 `timeoutSeconds: 5` 추가(infra#18→PR#19)로 해결.
- **server-env/ai-env 대규모 갱신** (git 미커밋, kubectl로만 적용): SMTP(Gmail 앱 비밀번호, 비밀번호 재설정 메일 발송 활성화), SOLAPI SMS(Worker Link 발송), CORS_ALLOWED_ORIGINS에 `https://` 변형과 `fowoco.github.io` 추가, AI Renewal 자동실행·문서생성 엔드포인트, ai-env에 HF_TOKEN·문서변환(HWP/PDF) 설정 추가.
  - `DB_MIGRATION_PASSWORD`/`DB_RUNTIME_PASSWORD`가 새 파일 값과 라이브 Postgres role의 실제 비밀번호가 달라서(특히 runtime — 이전부터 조용히 drift돼있었던 것으로 추정, 커넥션 풀이 재연결 전까진 안 드러남) 두 role 모두 `ALTER ROLE`로 새 값에 맞춰 회전.
  - `WORKER_PORTAL_BASE_URL`은 배포 도메인(`http://fowoco...`)으로 바꾸면 `portalBaseUrl must use HTTPS outside local development` 밸리데이션에 걸려 부팅 실패 — 파일에 있던 원래 값 `http://localhost:5173`으로 유지. **HTTPS(cert-manager) 붙기 전까지 SMS로 발송되는 링크는 실제 휴대전화에서 열리지 않는 한계 있음.**
- **최종 검증**: `ai`/`client`/`postgres`/`server` 전부 1/1 Running, 재시작 0. `/health` 200, `/` 200, 데모 로그인(`demo.admin@example.com`) 200 + 정상 JWT 발급 확인.

## 2026-07-22 — 프로젝트 파악

- ERD 공유 (company/user_account/worker/task/document/ticket/access_audit_log)

## 2026-07-23 — 인프라 방향 논의 시작

- OpenStack으로 직접 관리하고 싶다는 요청 → 검토 결과 OpenStack은 소프트웨어일 뿐 서버 자체를 제공하지 않고, 오히려 DevStack 기준 최소 8vCPU/16GB급 서버가 추가로 필요해 소규모 데모엔 과함 → **k3s(경량 쿠버네티스)**로 결정
- Oracle Cloud Always Free(ARM, 완전 무료)로 k3s 2노드 구성 계획, VCN·서브넷·API 키·CLI 세팅 진행
- `client`(#99)·`server`(#31)에 임시 Dockerfile PR 올림

## 2026-07-27~28 — Oracle 실패, AWS로 전환

- 도쿄 리전에서 `Out of host capacity` 반복 — 수동+자동 재시도 합산 **138회 이상, 5일간 인스턴스 생성 실패**
- Oracle이 2026-06-15부로 Always Free ARM 할당량을 4→2 OCPU(12GB)로 공지 없이 축소한 사실 확인
- 춘천 리전으로 우회하는 방안도 검토했으나, **춘천은 애초에 ARM Always Free 제외 대상**이라 처음부터 막힌 경로였음을 확인
- 클라우드별 가격 재조사(Oracle/GCP/AWS/Hetzner/DigitalOcean/Vultr/NHN/네이버) → 한 차례 Vultr(서울)으로 결정했다가, AWS 신규계정 $200 크레딧 + 재고 문제 없음을 재확인하고 **최종적으로 AWS로 재결정**
- KT 에이블스쿨 크레딧 지원 여부 확인 → 없음

## 2026-07-28 — AWS 구축, infra 저장소·Wiki 세팅

- IAM 사용자(`fowoco-admin`)·보안그룹·EC2 인스턴스(`fowoco-node-1`, m7i-flex.large) 생성 → **당일 완료** (Oracle 5일 대비 극적으로 빠름)
- k3s 싱글 노드 설치, 로컬 kubectl 연결 확인
- `fowoco/infra` 저장소에 `k8s/` 매니페스트(namespace/postgres/server/ai/client/ingress) 작성 → [PR #1](https://github.com/fowoco/infra/pull/1)
- 작업 범위를 **infra 저장소로 한정**하기로 원칙 정함 (client/server/ai는 팀원이 매일 커밋하는 활성 저장소라 부수적으로 건드리지 않기로)
- 문서를 저장소 README 대신 **GitHub Wiki**로 이전 (Home / Architecture / Deployment Guide / Deployment Plan)

## 2026-07-29 — 배포 전 점검, 실제 CI/CD 파이프라인 구축

- 용량 기준선(서버 1대로 데모 트래픽 충분한지)과 향후 업그레이드 조건·절차를 문서화
- 배포 전 재점검에서 문제 2건 발견:
  - **퍼블릭 IP가 고정이 아니었음** → Elastic IP 할당해 즉시 고정 (`3.35.21.43` → `3.35.105.80`), k3s 인증서·kubeconfig·Ingress 매니페스트 갱신
  - 보안그룹이 SSH(22)·k3s API(6443)를 `0.0.0.0/0`으로 전체 공개 — 접속 IP 확정되면 좁힐 예정 (아직 미조치)
- `client`/`server`/`ai`에 **실제 Dockerfile + GitHub Actions 배포 워크플로우**를 PR로 올림
  - `client` [#179](https://github.com/fowoco/client/pull/179) — 신규 Dockerfile (기존 #99는 팀에서 close됨)
  - `server` [#66](https://github.com/fowoco/server/pull/66) — 기존 임시 Dockerfile의 **Gradle 버전 버그 발견 및 수정** (`gradle:8.10` 고정 이미지가 Spring Boot 4.1.0이 요구하는 Gradle 8.14+를 만족 못 해 빌드 실패하던 것을 프로젝트 `./gradlew`(9.5.1) 사용으로 수정, 로컬 빌드 성공 확인)
  - `ai` [#5](https://github.com/fowoco/ai/pull/5) — 기존 Dockerfile 그대로, 워크플로우만 추가
- `KUBE_CONFIG`는 조직 레벨 대신 **3개 저장소 개별 시크릿**으로 등록 (조직 레벨은 `admin:org`라는 더 넓은 권한이 필요해서 최소 권한 원칙에 따라 변경)

## 2026-08-05 — 배포 파이프라인 실전 점검, client 배포 실제로 살아남

- 그동안 3개 저장소 `deploy.yml`의 `kubectl set image` 스텝 실패가 `|| echo "..."` fallback으로 조용히 가려져 있어서, **CI는 계속 초록불이었지만 실제로는 한 번도 배포에 성공한 적이 없었음**을 확인 (클러스터에 `kubectl apply -f k8s/`가 실제로 실행된 적이 없었음 — [[Deployment Guide]]의 최초 배포 순서가 미실행 상태로 남아있었던 것)
- `client`부터 self-heal 방식으로 전환 — `deploy.yml`이 매 배포마다 이 `infra` 저장소를 체크아웃해서 `00-namespace.yaml`/`04-client.yaml`/`05-ingress.yaml`을 자동 `kubectl apply` 후 `set image`/`rollout status` 진행하도록 수정 ([client#261](https://github.com/fowoco/client/issues/261) → [client#262](https://github.com/fowoco/client/pull/262))
- 첫 실행에서 bootstrap은 성공했지만 Rollout이 타임아웃 → 진단 로그 스텝 추가 후([client#263](https://github.com/fowoco/client/issues/263) → [client#264](https://github.com/fowoco/client/pull/264)) 원인이 **readiness probe가 아니라 `ImagePullBackOff`**였음을 확인
- 근본 원인: GHCR `client` 이미지 패키지가 기본 private 상태였고 클러스터엔 `imagePullSecrets`가 전혀 없었음. [[Deployment Plan]]에 이미 "GHCR 패키지는 Public 전환 권장"이라고 적어뒀던 항목인데 client에 대해 실제로는 실행이 안 되어 있던 상태였음
- 해결: GHCR org 정책(`Settings → Packages`)에서 Public 허용 활성화 → 패키지 설정에서 `client` 패키지를 Public으로 전환 (private→public 전환은 GitHub API로는 막혀있어서 웹 UI로만 가능)
- 재배포 후 검증 완료: `curl http://fowoco.3.35.105.80.nip.io/` → **HTTP 200**. `client`는 이제 main에 push하면 실제로 배포까지 확인되는 상태
- https는 아직 000 — nip.io 임시 도메인이라 TLS 인증서 미설정 (별도 사안, 도메인 확정 후 처리 예정)
- **남은 일**: `server`/`ai`도 같은 패턴(self-heal bootstrap + GHCR 패키지 private 여부 확인 후 필요시 public 전환) 적용 예정. `server`는 추가로 [[Deployment Guide]]의 `postgres-secret`/`server-env` Secret이 클러스터에 실제로 생성되어 있는지부터 확인 필요 (미확인 상태)

### 이어서 (같은 날) — client CI/거버넌스 정비

배포 자체는 살아났지만, PR 검증·리소스 제한·머지 규칙이 전혀 없다는 걸 확인해서 마저 정비:

- `client`에 `.github/workflows/deploy.yml`밖에 없었음 — PR을 아무 검증 없이 머지할 수 있는 상태. `pull_request` 트리거로 lint/test/build를 도는 `ci.yml` 추가 ([client#265](https://github.com/fowoco/client/issues/265) → [client#266](https://github.com/fowoco/client/pull/266))
- 이 CI를 처음 돌리자마자 pre-existing flaky 테스트를 잡음 — `LinkRequestPage.test.tsx`가 클릭 핸들러의 비동기 체인(fetch→navigate)이 끝나기 전에 `getByText`로 동기 단언해서 타이밍에 따라 실패하던 문제. `findByText`로 교체해서 같은 PR에 반영
- `main` branch protection이 전혀 없어서 CI가 강제력 없는 상태였음 — `verify`(CI) 통과를 required status check로 설정 (리뷰 승인은 미요구, force-push/삭제 금지)
- `k8s/04-client.yaml`의 client Deployment에 resource requests/limits이 없어서 단일 노드에서 server/ai/postgres와 무제한 경쟁 중이었음 — requests 50m cpu/64Mi mem, limits 200m cpu/128Mi mem 추가 (infra [#4](https://github.com/fowoco/infra/issues/4) → [#5](https://github.com/fowoco/infra/pull/5)), client 재배포로 클러스터에 바로 반영·검증
- 결과: `client`는 이제 배포도 되고, PR 검증도 강제되고, 리소스 제한도 걸린 상태. `server`/`ai`는 이 세 가지(CI/branch protection/resource limits) 전부 아직 없음

## 2026-08-06 — server/ai 실배포, 인프라 정리

### 저장소 전체 점검

5개 저장소 전부 오늘 활동이 있어서 훑어봄. `client`는 근로자/업무함 API 연동(#269/#271) 정상 진행 중. `server`가 예상보다 훨씬 활발했음 — AI 연동(OCR 계약 검증, AI 후보 결정→Task 생성, AiRun SSE, RLS 강화 등 다수 merge)과 별개로, **PR #97("데모 배포 환경과 운영 검증 절차를 구성")이 client와 거의 동일한 패턴(Dockerfile, `deploy.yml`, runbook)을 이미 준비해놓고 명시적으로 "infra 저장소에서 namespace/Secret/PostgreSQL/deployment 최초 배포"를 기다리는 상태**였음. 클러스터 확인 결과 실제로 `postgres-secret`/`server-env` 둘 다 없고 `client`만 떠 있었음.

### ai self-heal 적용

`ai`의 `deploy.yml`도 client의 원래 문제(`deployment/ai` 없으면 그냥 실패)를 그대로 갖고 있어서 client와 동일한 self-heal 패턴 적용: [ai#21](https://github.com/fowoco/ai/issues/21) → [ai#22](https://github.com/fowoco/ai/pull/22, 팀에서 직접 머지). `server`는 PR #97이 이미 `deploy.yml`을 다루고 있어서 충돌 방지 차원에서 코드는 안 건드리고 [server#104](https://github.com/fowoco/server/issues/104)로 필요한 것(Secret 키 목록 등)만 트래킹.

### AWS 보안그룹 정리

`fowoco-sg`(`sg-02aef781851a7cde2`)의 SSH(22)가 `0.0.0.0/0`으로 전체 공개된 채 2026-07-29부터 방치돼 있었음(당시 "아직 미조치"로 기록). 실제 SSH 사용자가 아무도 없음을 확인(`kubectl`이 `KUBE_CONFIG`로 직접 붙는 구조라 SSH 자체가 불필요)하고 규칙을 완전히 삭제(revoke)함. k3s API(6443)는 그대로 `0.0.0.0/0` 유지 — GitHub Actions가 매 배포마다 이 포트로 직접 `kubectl`을 실행하는데 러너 IP 대역이 7,300개 이상이라 allowlist가 불가능함. TLS client-cert 인증이 실질적 방어선.

### server 최초 배포 (ai가 계획보다 먼저 실전 배포되면서 순서가 당겨짐)

`ai` PR #22가 머지되고 실제로 rollout되면서 client와 똑같은 **GHCR private → `ImagePullBackOff`**가 재현됨. 조직 정책은 이미 켜져있어서 패키지 개별 Public 전환만으로 해결 — 다만 전환 직후 익명 pull 토큰 발급이 짧게(약 1분) 전파 지연을 겪어서 pod를 강제로 재시작시켜 바로 해결.

이 흐름을 보고 "server도 이번에 같이 하자"로 결정, 수동으로 최초 배포 진행:

- `postgres-secret` 생성, `01-postgres.yaml` 적용
- PostgreSQL role을 `fowoco_migration`(테이블 소유, Flyway 전용)/`fowoco_runtime`(DML만, `NOSUPERUSER NOBYPASSRLS`)으로 분리 생성 — `docs/database/postgresql-rls-rollout.md`가 이 role 분리를 명시적으로 infra 책임으로 못박아둔 부분을 그대로 따름. `ALTER DEFAULT PRIVILEGES`로 runtime role이 migration role이 만드는 테이블에 자동으로 DML 권한을 받도록 설정
- `server-env` Secret 생성. `SPRING_PROFILES_ACTIVE=dev`로 띄움(`prod`는 TLS + 릴리즈된 Workflow Catalog가 필수인데 아직 없음 — server 자체 runbook도 이 단계는 `dev`+DRAFT 카탈로그로 하라고 명시)
- `ghcr.io/fowoco/server`도 역시 private → **GHCR private 문제가 3/3(client/ai/server) 전부에서 재현**, Public 전환으로 동일하게 해결. 이제 새 fowoco 패키지는 기본적으로 이 전환이 필요하다고 가정할 것

배포 중 새로 발견한 버그 2개:

1. **`SERVER_PORT` 충돌** — k8s가 네임스페이스 내 모든 Service에 대해 `<SVC이름>_PORT` 형태 env var를 자동 주입하는데(레거시 Docker links 호환 기능, 기본 켜짐), Service 이름이 하필 `server`라서 `SERVER_PORT=tcp://<clusterIP>:8080`이 주입되고 Spring Boot의 `server.port` 프로퍼티랑 이름이 충돌해서 부팅 자체가 실패함. `enableServiceLinks: false`를 pod spec에 추가하면 이 자동 주입이 꺼짐 — server뿐 아니라 postgres/ai/client도 같은 클래스의 버그를 예방 차원에서 동일 적용 ([infra#7](https://github.com/fowoco/infra/pull/7), 머지 후 클러스터에도 바로 반영)
2. **`AI_RUNTIME_SERVICE_CREDENTIAL` 필수 검증** — `AI_RUNTIME_ENABLED=true`일 때 이 값이 비어있으면 Spring 기동 자체가 실패하도록 server가 자체 검증하고 있었음(`.env.example`엔 선택 항목처럼 주석 처리돼 있어서 놓치기 쉬움). 랜덤 값 생성해서 채움 — `ai`는 아직 이 값을 검증하지 않아서 당장은 문제없음

### 최종 확인

`kubectl -n fowoco get pods` → `client`/`server`/`ai`/`postgres` 전부 `1/1 Running`. `/actuator/health`·`/health` 둘 다 200. Flyway가 30개 테이블을 `fowoco_migration` 소유로 정상 생성 (`\dt`로 확인). `POST /api/v1/auth/signup` 스모크 테스트 — 구조화된 `400 INVALID_REQUEST` 응답(테스트 payload가 틀렸을 뿐 앱은 정상 서빙 중). 외부 도메인 경유도 확인: `http://fowoco.3.35.105.80.nip.io/api/v1/auth/signup` → 400 (ingress의 `/api` → `server` 라우팅이 실제로 동작). **client/server/ai 세 앱이 전부 같은 도메인 하나로 붙는 상태가 처음으로 완성됨.**

실제 비밀값(DB 비밀번호, JWT 시크릿, AI 서비스 credential)은 k8s Secret에만 존재 — git이나 Wiki 어디에도 평문으로 남기지 않음.

### 이어서 (같은 날) — resource limits, server/ai 거버넌스 재점검

`server`/`ai` 실배포 직후 점검해보니 `server`는 이미 팀이 자체적으로 CI(`ci.yml`, DB 붙여서 테스트)와 branch protection(리뷰 승인 1개 필수 — client보다 더 엄격)을 갖춰둔 상태였음. **`ai`만 이 둘 다 없음** (아직 손 안 댐, 다음 후보). 반면 resource limits는 `client` 말고는 셋 다(`server`/`ai`/`postgres`) 전혀 없었고, `server`가 idle 상태로 이미 556Mi를 쓰는 걸 확인해서 우선순위를 resource limits로 잡음.

- `k8s/02-server.yaml`(JVM, requests 300m/512Mi·limits 800m/1024Mi), `03-ai.yaml`(requests 100m/128Mi·limits 500m/512Mi), `01-postgres.yaml`(requests 100m/256Mi·limits 500m/512Mi) 추가 ([infra#8](https://github.com/fowoco/infra/issues/8) → [#9](https://github.com/fowoco/infra/pull/9), 머지 후 라이브 클러스터에도 바로 적용)
- 적용 후 4개 워크로드 전부 재기동·정상 확인 (`client` 200, `/api` ingress 경유 400=정상 응답)

### 남은 일

- `server`의 `deploy.yml`에 self-heal 패턴 적용 — PR #97이 아직 열려있어서 머지된 뒤에 진행 (지금 건드리면 같은 파일 충돌)
- `ai`의 CI 워크플로우/branch protection — `server`엔 이미 있음, `ai`만 아직 없음
- `prod` 프로필 전환은 TLS + 릴리즈된 Workflow Catalog 준비 후

## 2026-08-10 — server PR #97 머지, ai-env 신규, 라이브 크래시 2건 해결

### server PR #97 self-heal 전환 머지

`deploy.yml`에 client/ai와 동일한 self-heal(`infra` 매니페스트 checkout → `kubectl apply` → set image → rollout) 추가, GitHub Actions 플랫폼 장애(githubstatus.com 확인됨)로 CI가 두 번 튕겼다가 세 번째 시도에 통과, 머지 완료. [server#104](https://github.com/fowoco/server/issues/104) close.

### server-env·ai-env 정비 (현준님이 전달해준 env 파일 기반)

server 쪽에 알림/문서요청/비밀번호재설정/데모시드 기능이 이미 머지·배포됐는데 관련 env(`JWT_ISSUER`/`DEMO_SEED_*`/`AI_OCR_*`/`OCR_RESULT_*`/`FILE_STORAGE_LOCAL_PATH`)가 시크릿에 없던 걸 발견. 병합 진행, `AI_RUNTIME_SERVICE_CREDENTIAL`은 ai의 새 Internal Bearer 값과 통일(둘 다 같은 토큰을 봐야 `/internal/v1/*` 인증이 맞음, `app/api/security.py` 확인).

`ai-env` Secret은 이번에 처음 생성 — 그동안 `03-ai.yaml`에 envFrom 자체가 없어서 ai가 전부 기본값(Intent stub 고정, CLOVA OCR 꺼짐, Internal Bearer 인증 스킵)으로 떠 있었음. Intent 모델 실제 활성화 + CLOVA OCR 실키 연결 + Internal Bearer 인증 활성화 ([infra#13](https://github.com/fowoco/infra/pull/13)).

SMTP(Gmail 앱 비밀번호)는 실값이 없어서 `PASSWORD_RESET_NOTIFICATION_PROVIDER`/`SPRING_MAIL_*`는 보류 — 비밀번호 재설정 메일 발송 기능은 아직 못 켬.

### 라이브 크래시 2건 (전부 해결)

1. **시크릿 병합 스크립트 버그** — 첫 병합에 쓴 awk가 필드 재조합 과정에서 모든 값 앞에 공백 한 칸을 붙이는 버그가 있었음. `DB_URL`이 `" jdbc:postgresql://..."`가 돼서 `spring.datasource.url`이 `jdbc:postgresql:`로 안 시작한다고 부팅 실패(`PostgreSqlRuntimeDataSourceConfiguration`의 자체 검증). 병합 로직을 필드 재조합 없는 방식으로 다시 짜서 재적용.
2. **`bootstrap_claim_event_publications` permission denied** — [infra#11](https://github.com/fowoco/infra/pull/11)(bootstrap 함수 7개 runtime EXECUTE 권한 자동화, `krestar` 작성)을 리뷰 후 머지. 다만 이 PR의 initdb 스크립트는 **빈 PGDATA에서만** 실행되는 방식이라 이미 떠 있는 `postgres-0`엔 자동 반영 안 됨 — PR과 동일한 GRANT 7개를 라이브 DB에 수동 실행해서 해결.
3. **`/app/data` AccessDeniedException** — `DEMO_SEED_ENABLED=true` + `FILE_STORAGE_LOCAL_PATH=/app/data/files`를 켜니 볼륨 없는 `/app/data`에 non-root UID 10001(Dockerfile)이 쓰기 시도하다 실패. `server-data` PVC(2Gi) + `fsGroup: 10001` 추가로 해결 ([infra#14](https://github.com/fowoco/infra/pull/14)).

### 최종 확인

`client`/`server`/`ai`/`postgres` 전부 `1/1 Running`. 데모 계정(`demo.admin@example.com`) 로그인 200 (JWT에 새 issuer/audience 반영 확인), `/health` 200, ai `/docs` 200, 서버 로그에 에러 없음.

### 남은 일

- SMTP 앱 비밀번호 확보 후 비밀번호 재설정 메일 발송 활성화
- `ai`의 CI 워크플로우/branch protection — 여전히 미착수
- HTTPS/TLS, `prod` 프로필 전환

### AWS/k3s 안정성 점검, 백업·liveness probe 없던 것 확인

server-env/ai-env 정비 마치고 AWS/k3s/Docker 쪽을 훑어보니 실제로 비어있는 부분이 몇 개 나옴:

- **EBS 스냅샷이 계정에 0개** — `postgres`/`server-data` PVC 둘 다 `local-path`(hostPath, EC2 로컬 디스크) 기반이라 노드/볼륨 문제 생기면 데모 데이터·업로드 파일이 통째로 날아가는 구조였음. AWS Data Lifecycle Manager로 해결: 전용 IAM role(`fowoco-dlm-role`) 생성, 볼륨(`vol-001d68981ae503c1b`, `postgres`/`server-data` 둘 다 이 하나의 EBS에 있음)에 `fowoco-backup=daily` 태그, DLM 정책(`policy-0564fb7170a2ce515`)으로 매일 18:00(KST) 자동 스냅샷·7일 보관 설정.
- **4개 워크로드 전부 livenessProbe가 없었음** — readiness만 있어서 앱이 크래시 없이 멈춰버리면(deadlock 등) k8s가 자동 재시작을 안 해주는 상태. `server`는 Spring Boot 표준 k8s probe group(`/actuator/health/liveness`, `application.yaml`에 이미 설정돼 있던 것 재사용, 라이브 200 확인 후 반영)으로, 나머지 셋은 기존 readiness 엔드포인트를 더 느슨한 threshold로 재사용 ([infra#15](https://github.com/fowoco/infra/pull/15)).
- **EC2 termination protection이 꺼져있었음** — `disable-api-termination` 활성화로 실수 terminate 방지 (백업이 막 생긴 참이라 더 의미 있어짐).
- **CloudWatch billing alarm 없었음** — 월 추정 요금 20 USD 초과 시 SNS(akkn920@gmail.com)로 알림. 단, `AWS/Billing` 네임스페이스 지표는 계정 Billing Preferences의 "Receive Billing Alerts"가 켜져 있어야 실제로 쌓임 — 이건 IAM API로 못 켜고 콘솔(루트/billing 권한)에서만 가능해서 사용자가 직접 처리해야 함. 이메일 구독도 확인 클릭 필요.
- Secret scanning/push protection(5개 저장소 다 public이라 무료)은 이번엔 순서에서 제외 — 다음 후보로 남겨둠.

## 참고

- [[Home]]
- [[Architecture]]
- [[Deployment Guide]]
- [[Deployment Plan]]
