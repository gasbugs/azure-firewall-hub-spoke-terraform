# 실제 배포 및 통신 검증

검증일: 2026-11-19 (한국 시간). 아래는 당시 배포 환경의 실측 결과이며 다른 구독·시점의 용량이나 배포 성공을 보장하지 않습니다.

## 배포 구성

- 리전: East US
- Azure Firewall Basic 1개, VNet 3개, 양방향 Hub–Spoke 피어링 4개
- VM 2대: Standard_D2s_v7, Ubuntu 24.04.5 LTS (`ubuntu-24_04-lts:server:latest`가 당시 선택한 이미지)
- VM 공인 IP 없음, 기본 외부 연결 비활성화
- 테스트용 SSH DNAT는 관리자 공인 IPv4 한 개(`/32`)에만 허용
- Terraform 1.14.8 / AzureRM 4.81.0

## 실제 통신 결과

| 검사 | App VM | Workload VM |
|---|---|---|
| 8.8.8.8 DNS UDP/TCP 53 | 성공 | 성공 |
| 시스템 DNS로 naver.com 이름 해석 | 성공 | 성공 |
| 반대편 VM으로 ICMP 3회 | 3/3, 손실 0% | 3/3, 손실 0% |
| http://naver.com | HTTP 301 | HTTP 301 |
| http://www.naver.com | HTTP 302 | HTTP 302 |
| http://example.com | Firewall 470 + 거부 응답 | Firewall 470 + 거부 응답 |
| https://naver.com | 연결 실패(HTTP-only 정책) | 연결 실패(HTTP-only 정책) |
| 1.1.1.1 TCP 53 | 차단 | 차단 |
| 반대편 VM의 SSH TCP 22 | 차단 | 차단 |
| 8.8.8.8 ICMP | 실패 예상 / 성공 조건 제외 | 실패 예상 / 성공 조건 제외 |
| 테스트 스크립트 | `RESULT failures=0`, 종료 코드 0 | `RESULT failures=0`, 종료 코드 0 |

HTTP 리다이렉트는 따라가지 않았습니다. HTTPS 홈페이지 전체 로딩을 확인한 결과가 아닙니다. 인터넷 ICMP 대신 VM 간 ICMP를 검증하도록 요구사항을 조정했습니다.

## 실제 라우팅

Azure NIC Effective Routes 조회 결과:

| VM | 대상 경로 | 다음 홉 | 상태 |
|---|---|---|---|
| App | 0.0.0.0/0 | VirtualAppliance 10.0.0.4 | Active |
| App | 10.20.0.0/16 | VirtualAppliance 10.0.0.4 | Active |
| Workload | 0.0.0.0/0 | VirtualAppliance 10.0.0.4 | Active |
| Workload | 10.10.0.0/16 | VirtualAppliance 10.0.0.4 | Active |

양쪽 Hub 피어링은 `Connected`, 전달 트래픽 허용은 `true`였습니다.

## Terraform 확인

- `terraform validate`: 성공
- `terraform test`: 모의 공급자 테스트 2개 통과
- 실제 배포 중 발견한 `AzurePlatformDNS`의 포트 요구사항(`*`)을 코드와 회귀 테스트에 반영
- 최종 `terraform plan -detailed-exitcode`: 종료 코드 0, `No changes`

재현 방법은 [README](README.md#접속-및-통신-테스트)와 [테스트 스크립트](scripts/test-connectivity.sh)를 참고하세요. 실측 원본 로그·Terraform 상태·구독별 입력값·개인키는 저장소에 포함하지 않습니다.
