# 모듈 4. Azure Backup (약 15분)

🌐 **한국어** | [English](../en/04-azure-backup.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

빈 Azure Files 공유를 **Snapshot 백업**으로 보호하고, **백업 작업 완료와 복구 지점 생성**을 확인합니다.

> 📌 이 모듈은 백업 관리 절차를 배우는 실습입니다. 파일을 쓰거나 삭제하지 않으며 **파일 내용 복원 성공을 검증하는 실습은 아닙니다.**

> 🧠 **핵심 개념**
> - **Recovery Services 자격 증명 모음(vault)**: 이 실습의 백업 정책·보호 항목·복구 지점을 관리하는 컨테이너.
> - **백업 정책**: 언제(스케줄) 얼마나 오래(보존 기간) 백업할지 정의합니다.
> - **복구 지점**: 백업 시점으로 돌아가기 위한 정보. 이 실습의 Snapshot 백업은 **공유 스냅샷** 기반이며 데이터를 모음으로 이동하지 않습니다.
> - **Snapshot 계층**은 스토리지에 스냅샷을 남기고, 자격 증명 모음은 정책과 복구 지점을 관리합니다. 데이터를 모음에 복사하는 Vaulted 백업과는 다릅니다.
> - 스토리지의 공유 키·공용 접근 설정을 바꾸지 않습니다. 백업 요청은 관리 영역으로 Azure Backup에 전달하며, 추가 조직 정책이 작업을 막으면 오류를 확인하고 중지합니다.

## 📝 실습

```bash
source scripts/env.sh
: "${SA:?모듈 0을 먼저 배포하세요}"
```

### 1. 자격 증명 모음 만들기

```bash
# 구독에서 처음 쓰는 경우에만 필요 (모듈 0 스크립트가 이미 실행했다면 바로 끝남)
az provider register -n Microsoft.RecoveryServices --wait

az backup vault create -g $RG -n $VAULT -l $LOCATION -o none

# 실습용 중복성은 LRS. 소프트 삭제는 기본 설정·조직 정책을 유지합니다.
az backup vault update -g $RG -n $VAULT \
  --backup-storage-redundancy LocallyRedundant -o none
az backup vault show -g $RG -n $VAULT \
  --query "{Redundancy:properties.redundancySettings.standardTierStorageRedundancy, SoftDelete:properties.securitySettings.softDeleteSettings.softDeleteState}" -o table
```

> 📌 중복성은 **보호 항목을 등록하기 전**에 설정합니다. `SoftDelete=AlwaysON`이어도 정상이며, 비활성화를 시도하지 않습니다. 스토리지의 공유 소프트 삭제와 자격 증명 모음의 소프트 삭제는 별개입니다. [소프트 삭제 범위](https://learn.microsoft.com/en-us/azure/backup/secure-by-default)

### 2. 백업 정책 만들기

`infra/backup-policy.json`은 **Snapshot 계층, 매일 02:00(UTC) 백업, 7일 보존** 정책입니다. 실습에서는 Vaulted 계층으로 바꾸지 않습니다.

CLI 정책에서 Snapshot은 `retentionPolicy`, Vaulted는 `vaultRetentionPolicy`를 사용합니다. [공식 정책 정의](https://learn.microsoft.com/en-us/azure/backup/manage-afs-backup-cli#create-a-backup-policy)

```bash
az backup policy create -g $RG -v $VAULT -n policy-daily-files \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --policy infra/backup-policy.json -o table
az backup policy show -g $RG -v $VAULT -n policy-daily-files \
  --query "{Schedule:properties.schedulePolicy.scheduleRunFrequency, TimeZone:properties.timeZone, RetentionDays:properties.retentionPolicy.dailySchedule.retentionDuration.count}" -o table
test "$(az backup policy show -g $RG -v $VAULT -n policy-daily-files \
  --query 'properties.vaultRetentionPolicy == `null` && properties.retentionPolicy.dailySchedule.retentionDuration.count == `7`' -o tsv)" = true
```

### 3. 파일 공유 보호 시작

```bash
az backup protection enable-for-azurefileshare -g $RG -v $VAULT \
  --storage-account $SA --azure-file-share $SHARE \
  --policy-name policy-daily-files -o table
```

1~3분 걸립니다. 상태를 확인합니다.

```bash
az backup item list -g $RG -v $VAULT --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --query "[].{Share:properties.friendlyName, State:properties.protectionState, PolicyId:properties.policyId}" -o table
```

첫 백업 전에는 `IRPending`이 보일 수 있습니다. 다음 단계의 백업이 완료되면 `Protected`인지 다시 확인합니다.

### 4. 즉시 백업 (On-demand)

스케줄까지 기다리지 않고 지금 **빈 공유의 스냅샷**을 만듭니다.

```bash
if [ "$(uname -s)" = Darwin ]; then
  RETAIN_UNTIL=$(date -u -v+7d +%d-%m-%Y)
else
  RETAIN_UNTIL=$(date -u -d '+7 days' +%d-%m-%Y)
fi

JOB=$(az backup protection backup-now -g $RG -v $VAULT \
  --container-name $SA --item-name $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --retain-until "$RETAIN_UNTIL" --query name -o tsv)
: "${JOB:?백업 작업 ID가 없습니다}"

az backup job wait -g $RG -v $VAULT -n $JOB --timeout 1800 -o none
az backup job show -g $RG -v $VAULT -n $JOB --query "{Operation:properties.operation, Status:properties.status}" -o table
test "$(az backup job show -g $RG -v $VAULT -n $JOB --query properties.status -o tsv)" = Completed
```

👉 상태가 **Completed** 이면 됩니다. (몇 분 걸릴 수 있습니다)

### 5. 복구 지점 확인

이름과 생성 시간이 있는 복구 지점이 1개 이상 있어야 합니다.

```bash
az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query "sort_by(@, &properties.recoveryPointTime)[].{Name:name, Time:properties.recoveryPointTime}" -o table
test "$(az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query 'length(@)' -o tsv)" -ge 1
az backup item list -g $RG -v $VAULT --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --query "[].{Share:properties.friendlyName, State:properties.protectionState, PolicyId:properties.policyId}" -o table
```

👉 **공유 → 백업 정책 → 완료된 작업 → 복구 지점**의 연결을 확인했습니다. 빈 공유에도 복구 지점을 만들 수 있지만, 이 결과가 파일 내용 복원을 입증하지는 않습니다.

> 💡 포털에서 자격 증명 모음 `rsv-pvtlab`의 **백업 항목 ▸ Azure Storage (Azure Files)**를 살펴볼 수 있습니다. 실제 파일 생성·삭제·내용 복원은 ID 기반 데이터 접근을 추가하는 별도 확장 실습입니다.

## ✅ 확인 체크리스트

- [ ] 공유의 보호 상태가 `Protected`
- [ ] 즉시 백업 작업 `Completed`, 복구 지점 1개 이상
- [ ] 공유 키·공용 접근 차단과 모음의 소프트 삭제 정책을 유지함

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| `MissingSubscriptionRegistration` | `az provider register -n Microsoft.RecoveryServices --wait` 실행 후 재시도 |
| 백업/복원 작업이 `Failed` | `az backup job show -g $RG -v $VAULT -n <작업 ID> -o json`으로 오류를 확인하세요. `job wait`가 끝났다는 것만으로 성공을 판단하지 마세요 |
| 보호 설정 시 스토리지 접근 오류 | 모듈 0의 `networkRuleSet.bypass=AzureServices`와 이 실습의 Snapshot 정책 정의를 확인하세요. 다른 조직 정책이 막으면 중지하고 관리자에게 문의하세요. 공유 키나 공용 접근을 켜지 마세요 |
| 중복성 변경 오류 | 보호 항목 등록 전에 LRS를 설정해야 합니다 |

➡️ 다음: [정리](05-cleanup.md)
