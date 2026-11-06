# 모듈 0. 준비 (약 10분)

🌐 **한국어** | [English](../en/00-setup.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

실습에 사용할 기본 인프라를 Bicep으로 한 번에 배포합니다.

| 리소스 | 이름 | 설명 |
|---|---|---|
| 허브 VNet | `vnet-hub` (10.0.0.0/16) | `snet-pe`(Private Endpoint용), `snet-vm` |
| 스포크 VNet | `vnet-spoke` (10.1.0.0/16) | `snet-workload` |
| 테스트 VM | `vm-hub`, `vm-spoke` | Ubuntu 22.04, 공용 IP 없음 |
| 스토리지 계정 | `stpvtlab<고유값>` | 아직 **공용 인터넷에서 접근 가능** (모듈 2에서 비교/차단) |

> 🧠 **허브-스포크란?** 공용 서비스(허브)를 가운데 두고 워크로드(스포크) VNet을 연결하는 구조입니다. 이 랩에서는 **Private Endpoint를 허브에 두고, 스포크의 VM이 피어링을 통해 사용**합니다.

피어링, Private Endpoint, 프라이빗 DNS, 백업은 **일부러 만들지 않습니다.** 앞으로 직접 구성합니다.

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

스크립트가 하는 일: 리소스 그룹 생성 → SSH 키 생성 → `infra/main.bicep` 배포 → VM 초기화(`cifs-utils`, `dnsutils` 설치) 대기.

### 4. 공통 변수 불러오기

```bash
source scripts/env.sh
```
`SA=stpvtlab...` 처럼 스토리지 계정 이름이 보이면 정상입니다.

## ✅ 확인

```bash
az resource list -g $RG -o table --query "[].{이름:name, 종류:type}"
scripts/vm-exec.sh vm-spoke "hostname; nslookup -version"
```

VNet 2개, VM 2대(+NIC/디스크), 스토리지 계정 1개, NSG 1개가 보이고 VM에서 `hostname` 결과가 나오면 성공입니다.

> 💡 VM은 공용 IP가 없어서 SSH로 접속하지 않습니다. 대신 `scripts/vm-exec.sh <VM이름> '<명령>'` 으로 VM 안에서 명령을 실행합니다. (내부적으로 `az vm run-command` 사용, 호출당 10~20초)

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| `SkuNotAvailable` / 용량 오류 | `export VM_SIZE=Standard_B2as_v2` 처럼 다른 크기, 또는 `export LOCATION=` 으로 다른 리전을 지정하고 다시 실행 |
| 권한 오류 (`AuthorizationFailed`) | 구독에 Contributor 이상 권한이 있는지 확인 |
| 정책(Policy)으로 배포 거부 | 조직 정책이 막는 경우입니다. 개인/테스트 구독을 사용하세요 |

➡️ 다음: [모듈 1. VNet 피어링](01-vnet-peering.md)
