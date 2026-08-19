# FOWOCO Terraform

AWS 리소스(EC2 2대, IAM, DLM 백업 정책, CloudWatch 알람, SNS, Budgets)를 코드로 관리한다.
`k8s/`(클러스터 내부 리소스)와는 관할이 분리되어 있음 — 여기는 클러스터가 **올라갈 자리(AWS 계정 레벨)**만 다룬다.

## 왜 지금 리소스가 이미 다 살아있는데 Terraform이 있나

전부 `aws` CLI로 손으로 만든 뒤에 `terraform import`로 기존 상태를 그대로 state에 끌어왔다.
**아무것도 새로 만들거나 지우지 않았음** — `terraform plan` 결과가 `0 to add, 0 to destroy`인 것으로
검증됨(태그 몇 개 추가되는 것만 diff로 남음). 앞으로의 변경(인스턴스 타입 조정, 알람 임계치 변경 등)은
콘솔/CLI 대신 이 코드를 고치고 PR로 리뷰받은 뒤 적용하는 방식으로 전환하는 게 목적.

## 구성

| 파일 | 내용 |
|---|---|
| `providers.tf` | AWS 프로바이더, 로컬 state 사용(팀 협업 규모로 커지면 S3 백엔드로 전환) |
| `network.tf` | 보안그룹 2개(fowoco-sg, fowoco-dev-sg) — VPC/서브넷은 기본 리소스라 데이터 소스로만 참조 |
| `ec2.tf` | 메인 k3s 노드(fowoco-node-1), 개발용 EC2(fowoco-dev), Elastic IP |
| `iam.tf` | dev 박스 SSM 접속용 역할, DLM 백업용 역할 |
| `monitoring.tf` | DLM 일일 스냅샷 정책, EC2 상태체크 알람, SNS 토픽, 월 지출 Budget |

## 사용법

```bash
terraform init
terraform plan   # 반드시 실행 전에 diff 확인 — 실제 운영 중인 데모 인프라라 무중단이 원칙
terraform apply
```

## 주의사항

- **`*.tfstate`는 git에 올리지 않음**(`.gitignore` 참고) — 실제 리소스 속성이 평문으로 들어있고,
  이게 없으면 다음 `plan`이 다시 처음부터 diff를 다시 계산해야 함. 로컬에서 따로 백업할 것.
- 인스턴스 root volume 태그(`fowoco-backup=daily`)는 DLM 백업 정책이 스냅샷 대상을 찾는
  기준이라 실수로 지우면 안 됨 — `ec2.tf`의 `root_block_device.tags`에 명시적으로 박아뒀음.
- `aws_instance`에 `lifecycle { ignore_changes = [ami, user_data] }`를 걸어둠 — AMI가
  나중에 deprecated돼도 이미 떠서 운영 중인 인스턴스를 `apply`가 재생성하려 들지 않게 하려는 것.
- 시크릿(`server-env`/`ai-env` 등 k8s Secret)은 여기서 다루지 않음 — 그건 여전히 `kubectl`
  라이브 명령으로 관리(레포에 커밋 안 되는 이유는 루트 README 참고).
