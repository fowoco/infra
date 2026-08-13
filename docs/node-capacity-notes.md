# 노드 용량 메모

k3s 단일 노드(`m7i-flex.large`, 2 vCPU / 8GB, `ap-northeast-2c`)의 CPU 여유를
2026-08-13에 재점검한 기록. 나중에 워크로드가 늘거나 트래픽이 붙어서 다시
검토할 때 이 실측치를 기준선으로 쓴다.

## 당시 배경

`kubectl describe node`의 "Allocated resources" 섹션만 보고 CPU가 꽉 찼다고
오판한 적이 있다:

```
Allocated resources:
  Resource   Requests      Limits
  cpu        750m (37%)    2 (100%)
  memory     1228Mi (15%)  3882Mi (49%)
```

`limits` 합계가 노드 용량과 같아서 "확장 여유가 없다"고 결론 내렸는데, 이건
틀린 해석이었다.

## 왜 틀렸는지

- k8s 스케줄러는 파드를 새로 배치할 노드를 고를 때 **`requests`만 본다**.
  `limits`는 스케줄링과 무관하고, kubelet이 런타임에 CFS 쓰로틀링(CPU) /
  OOM kill(메모리) 판단할 때만 쓰인다.
- CPU는 압축 가능한(compressible) 리소스라서, `limits` 총합이 노드 용량을
  넘는 오버커밋은 k8s에서 흔하고 정상적인 운영 방식이다. (메모리는 압축 불가라
  오버커밋하면 위험하지만, 이 노드는 메모리 `limits` 합계가 49%라 그쪽도 여유
  있음.)

## 실측 (2026-08-13)

```
kubectl top nodes
NAME               CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
ip-172-31-45-245   77m          3%       3477Mi          44%

kubectl top pods -n fowoco
ai        2m    882Mi
client    1m    3Mi
postgres  5m    41Mi
server    4m    429Mi
```

전 파드 restarts=0, 실제 CPU 사용량은 노드 전체 기준 3%. `requests` 합계도
650m/2000m(32.5%)로 여유 충분.

## 현재 리소스 설정

| 워크로드 | CPU req | CPU limit | Mem req | Mem limit |
|---|---|---|---|---|
| ai | 100m | 500m | 256Mi | 2Gi |
| server | 300m | 800m | 512Mi | 1Gi |
| postgres | 100m | 500m | 256Mi | 512Mi |
| client | 50m | 200m | 64Mi | 128Mi |

## 언제 다시 검토해야 하는가

- `ai`가 실제로 임베딩/OCR/LibreOffice 렌더링 같은 CPU 바운드 작업을 동시에
  여러 건 처리하기 시작할 때 (지금은 대부분 유휴 상태라 burst 패턴이 실측
  안 됨)
- 실사용자 트래픽이 붙어서 `kubectl top`이 꾸준히 두 자릿수 %를 찍기 시작할 때
- 그 전까지는 **노드 리사이즈도 리밋 재조정도 불필요** — 근거 없이 비용/다운
  타임을 들이지 않는다.
