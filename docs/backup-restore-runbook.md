# 백업 복구 런북

DLM 스냅샷(`policy-0564fb7170a2ce515`, 매일 18:00 KST, 7일 보관)으로부터 실제
복구가 되는지 검증한 절차와 결과. 2026-08-13, `fowoco-dev`(`i-0d8eb15ae79a92178`,
`ap-northeast-2c`) EC2에서 실시, 운영 노드는 건드리지 않음.

## 배경

k3s 단일 노드의 루트 EBS 볼륨(`vol-001d68981ae503c1b`) 하나에 `postgres`와
`server-data` PVC가 모두 local-path-provisioner로 얹혀 있다. DLM은 이 볼륨
전체를 스냅샷한다. 스냅샷이 매일 쌓이는 것은 확인했지만, 그 스냅샷에서 실제로
데이터를 복구할 수 있는지는 검증된 적이 없었다.

## 절차

1. 최신 스냅샷으로 임시 볼륨 생성 (운영 볼륨과 같은 AZ)
   ```
   aws ec2 create-volume --availability-zone ap-northeast-2c \
     --snapshot-id <최신 스냅샷 ID> --volume-type gp3 \
     --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=fowoco-restore-drill-temp}]'
   ```
2. `fowoco-dev` 인스턴스에 부착 (운영 노드에는 **절대 부착하지 않음** — 디바이스
   충돌 및 운영 영향 방지)
   ```
   aws ec2 attach-volume --volume-id <vol-id> --instance-id i-0d8eb15ae79a92178 --device /dev/sdf
   ```
3. SSM(`AWS-RunShellScript`)으로 읽기 전용 마운트. Nitro 인스턴스라 디바이스명이
   `/dev/sdf`가 아니라 `/dev/nvme1n1`로 잡히고, 파티션은 `nvme1n1p1`이다 (whole
   disk가 아니라 파티션을 마운트해야 함 — `lsblk`로 먼저 확인).
   ```
   sudo mount -o ro /dev/nvme1n1p1 /mnt/restore-drill
   ```
4. PVC 데이터 디렉터리 확인 (local-path-provisioner 규칙: `<pvc-uid>_<namespace>_<pvc-name>`)
   ```
   /mnt/restore-drill/var/lib/rancher/k3s/storage/pvc-*_fowoco_data-postgres-0
   /mnt/restore-drill/var/lib/rancher/k3s/storage/pvc-*_fowoco_server-data
   ```
5. 검증 후 반드시 정리: `umount` → `detach-volume` → `delete-volume`. 임시
   볼륨을 절대 남겨두지 않는다 (불필요한 과금 + 관리 부채).

## 결과 (2026-08-13 실시분)

- 사용 스냅샷: `snap-01bd2194ed30add68` (2026-08-12 18:20 KST 완료분)
- 복구 볼륨 크기: **30GB** — 운영 볼륨은 현재 100GB로 리사이즈되어 있지만,
  이 스냅샷은 리사이즈 이전에 찍힌 것. **오래된 스냅샷에서 복구하면 리사이즈
  이전 크기로 돌아온다는 뜻** — 필요하면 복구 후 `growpart`/`resize2fs`로
  다시 키워야 한다. 리사이즈 이후 스냅샷부터는 100GB로 복구됨.
- `data-postgres-0`: `PG_VERSION` = `16` (정상), `base/` 하위에 실제 DB OID
  디렉터리(`1`, `4`, `5`, `16384`) 존재, 전체 66M — 정상적인 PostgreSQL 16
  데이터 디렉터리 구조로 확인됨.
- `server-data`: `files/` 하위에 실제 문서 UUID 디렉터리 3건 존재
  (`94800000-...-000000001/2/3`) — 실제 업로드된 파일 데이터로 확인됨.
- 결론: **DLM 백업은 실제로 복구 가능한 상태로 쌓이고 있음.** 절차 자체는
  약 5분 내 완료 가능 (볼륨 생성~마운트~정리 포함).

## 후속 (미실시, 필요시 진행)

- 분기별 정기 리허설 일정화
- 리사이즈 이후 최신 스냅샷으로 재검증 (이번 검증은 리사이즈 이전 스냅샷 기준)
- 실제 postgres 컨테이너로 기동까지 확인하는 전체 복구 드릴 (이번엔 파일시스템
  레벨 데이터 무결성만 확인, DB 엔진 기동 검증은 아직 안 함)
