# 모듈 3. Azure Files (약 10분)

🌐 **한국어** | [English](../en/03-azure-files.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

공용 데이터 접근을 차단한 상태에서 **Azure Files 공유**를 생성하고, 용량·프로토콜을 확인합니다. **리소스 관리와 파일 데이터 접근이 별개**라는 것을 이해합니다.

> 🧠 **Azure Files**: 관리형 파일 공유입니다. 여기서는 SMB 공유를 구성하지만, 실제 SMB 마운트·파일 읽기·쓰기는 수행하지 않습니다. 모듈 2에서 확인한 TCP 445 연결은 네트워크 연결일 뿐, 파일 인증 성공이 아닙니다.

공유 키를 허용하거나 조직 정책 예외를 만들지 않습니다. 관리 영역 API인 `share-rm`을 사용하므로 실습 명령에서 계정 키를 조회할 필요가 없습니다.

## 📝 실습

```bash
source scripts/env.sh
: "${SA:?모듈 0을 먼저 배포하세요}"
```

### 1. 파일 공유 생성

공용 데이터 접근이 차단되어 있으므로 **관리 영역(ARM)** API인 `share-rm`으로 만듭니다.

```bash
az storage share-rm create -g $RG --storage-account $SA -n $SHARE \
  --quota 5 --enabled-protocols SMB -o table
```

> 💡 관리 영역 vs 데이터 영역: 리소스를 만들고 설정하는 것(관리)은 방화벽 영향을 받지 않고, 파일을 읽고 쓰는 것(데이터)만 방화벽/Private Endpoint 대상입니다.

### 2. 공유 설정 확인

```bash
az storage share-rm show -g $RG --storage-account $SA -n $SHARE \
  --query "{Name:name, QuotaGiB:shareQuota, Protocols:enabledProtocols}" -o table
```

👉 이름은 `corpfiles`, 용량은 `5` GiB, 프로토콜은 `SMB`여야 합니다. 아직 파일이 없는 **빈 공유**입니다.

### 3. 보안 설정이 그대로인지 확인

```bash
az storage account show -g $RG -n $SA \
  --query "{SharedKey:allowSharedKeyAccess, PublicAccess:publicNetworkAccess, DefaultAction:networkRuleSet.defaultAction}" -o table
```

👉 `false / Disabled / Deny` 상태가 유지됩니다. 공유를 만들기 위해 데이터 접근을 열지 않았습니다.

| 구분 | 사용 경로 | 이번 실습 결과 |
|---|---|---|
| 공유 생성·설정 조회 | ARM 관리 영역 | Azure 로그인 권한으로 성공 |
| 인터넷에서 파일 서비스 요청 | 공용 데이터 경로 | 모듈 2에서 403 확인 |
| VM에서 파일 서비스 요청 | Private Endpoint | 모듈 2에서 사설 IP·401 확인 |
| 실제 파일 읽기·쓰기 | 데이터 인증 필요 | 기본 실습에서 생략 |

## ✅ 확인 체크리스트

- [ ] 공유 `corpfiles` 생성, 용량 `5` GiB, 프로토콜 `SMB`
- [ ] 공유 키와 공용 데이터 접근은 계속 차단됨
- [ ] 관리 영역 성공과 데이터 영역 접근 제한의 차이를 이해함

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| `share-rm create` 권한 오류 | 리소스 그룹의 Contributor 권한과 `$SA` 값을 확인하세요 |
| 정책으로 공유 생성 거부 | 오류의 정책 조건을 확인하고 관리자에게 문의하세요. 공유 키·공용 접근 제한을 해제하지 마세요 |
| 인터넷에서 파일 목록을 볼 수 없음 | 정상입니다. 공용 데이터 접근은 차단된 상태입니다 |

> 💡 실제 파일 데이터 실습은 별도 확장입니다. [Microsoft Entra ID 인증을 사용하는 Azure Files REST API](https://learn.microsoft.com/en-us/azure/storage/files/authorize-oauth-rest)에는 데이터용 RBAC 역할과 역할 부여 권한이 필요합니다.

➡️ 다음: [모듈 4. Azure Backup](04-azure-backup.md)
