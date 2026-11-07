# 모듈 0. 준비 (약 10분)

🌐 **한국어** | [English](../en/00-setup.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

실습에 사용할 기본 인프라를 Bicep으로 한 번에 배포합니다.

| 리소스 | 이름 | 설명 |
|---|---|---|
| 허브 VNet | `vnet-hub` (10.0.0.0/16) | `snet-pe`(Private Endpoint용), `snet-vm` |
| 스포크 VNet | `vnet-spoke` (10.1.0.0/16) | `snet-workload` |
| 테스트 VM | `vm-hub`, `vm-spoke` | Ubuntu 22.04, 공용 IP 없음 |
| 스토리지 계정 | `stpvtlab<고유값>` | **공유 키·공용 접근 차단** (모듈 2에서 프라이빗 경로 구성) |

> 🧠 **허브-스포크란?** 공용 서비스(허브)를 가운데 두고 워크로드(스포크) VNet을 연결하는 구조입니다. 이 랩에서는 **Private Endpoint를 허브에 두고, 스포크의 VM이 피어링을 통해 사용**합니다.

피어링, Private Endpoint, 프라이빗 DNS, 백업은 **일부러 만들지 않습니다.** 앞으로 직접 구성합니다.

공유 키와 공용 접근을 허용하도록 정책을 바꾸지 않습니다. 실습 중에는 계정 키 조회나 SMB 마운트가 필요하지 않습니다.

## 📝 실습

### 1. 로그인 확인

```bash
az account show -o table
```
아무것도 나오지 않으면 `az login --use-device-code` 를 실행하세요.

### 2. (선택) 리전/VM 크기 지정

```bash
export LOCATION=koreacentral    # 기본값
export VM_SIZE=Standard_B2s_v2  # 기본값. 용량 부족 오류가 나면 다른 크기를 지정
```

### 3. 배포

```bash
scripts/00-deploy.sh
```

스크립트가 하는 일: 리소스 그룹 생성 → SSH 키 생성 → `infra/main.bicep` 배포 → 스토리지 차단 설정 확인 → VM 초기화(최대 10분) 및 `curl`, `nslookup`, `nc` 설치 확인. 실패하면 배포 완료로 표시하지 않습니다.

### 4. 공통 변수 불러오기

```bash
source scripts/env.sh
```
`SA=stpvtlab...` 처럼 스토리지 계정 이름이 보이면 정상입니다.

## ✅ 확인

```bash
az resource list -g $RG -o table --query "[].{Name:name, Type:type}"
az storage account show -g $RG -n $SA \
  --query "{SharedKey:allowSharedKeyAccess, PublicAccess:publicNetworkAccess, DefaultAction:networkRuleSet.defaultAction}" -o table
scripts/vm-exec.sh vm-spoke "hostname; nslookup -version"
```

VNet 2개, VM 2대(+NIC/디스크), 스토리지 계정 1개, NSG 1개가 보이고 VM에서 `hostname` 결과가 나오면 성공입니다.

스토리지 설정은 `SharedKey=false`, `PublicAccess=Disabled`, `DefaultAction=Deny`여야 합니다.

> 💡 VM은 공용 IP가 없어서 SSH로 접속하지 않습니다. 대신 `scripts/vm-exec.sh <VM이름> '<명령>'` 으로 VM 안에서 명령을 실행합니다. (내부적으로 `az vm run-command` 사용, 호출당 10~20초)

> 📌 도우미는 VM에서 **Bash와 `set -e`, `pipefail`** 을 사용합니다. 명령이 실패하면 다음 명령을 실행하지 않고, VM의 종료 코드를 로컬 터미널로 반환합니다. Azure의 `Enable succeeded` 메시지만으로 명령 성공을 판단하지 마세요.

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| `SkuNotAvailable` / 용량 오류 | `export VM_SIZE=Standard_B2as_v2` 처럼 다른 크기, 또는 `export LOCATION=` 으로 다른 리전을 지정하고 다시 실행 |
| 권한 오류 (`AuthorizationFailed`) | 구독에 Contributor 이상 권한이 있는지 확인 |
| 정책(Policy)으로 배포 거부 | 오류의 리소스·정책 조건을 확인하고 관리자에게 문의하세요. 공유 키·공용 접근 제한은 유지하세요 |

➡️ 다음: [모듈 1. VNet 피어링](01-vnet-peering.md)
