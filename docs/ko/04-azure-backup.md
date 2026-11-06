# 모듈 4. Azure Backup (약 15분)

🌐 **한국어** | [English](../en/04-azure-backup.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

Azure Files 공유를 **Azure Backup**으로 보호하고, 실수로 **파일을 삭제한 뒤 복원**합니다.

> 🧠 **핵심 개념**
> - **Recovery Services 자격 증명 모음(vault)**: 백업 데이터와 정책을 보관하는 컨테이너.
> - **백업 정책**: 언제(스케줄) 얼마나 오래(보존 기간) 백업할지 정의합니다.
> - **복구 지점**: 백업 시점의 스냅샷. Azure Files 백업은 **공유 스냅샷** 기반이라 빠르고 데이터 이동이 없습니다.
> - 백업 서비스는 **신뢰할 수 있는 Azure 서비스**로 스토리지에 접근합니다. 모듈 2에서 `--bypass AzureServices` 를 둔 이유입니다. 공용 인터넷 접근은 여전히 막혀 있습니다.

## 📝 실습

```bash
source scripts/env.sh
```

### 1. 자격 증명 모음 만들기

```bash
# 구독에서 처음 쓰는 경우에만 필요 (모듈 0 스크립트가 이미 실행했다면 바로 끝남)
az provider register -n Microsoft.RecoveryServices --wait

az backup vault create -g $RG -n $VAULT -l $LOCATION -o none

# 랩 비용·정리 편의: 중복성을 LRS로, 소프트 삭제를 끔 (※ 운영에서는 켜 두세요)
az backup vault backup-properties set -g $RG -n $VAULT \
  --backup-storage-redundancy LocallyRedundant -o none
az backup vault backup-properties set -g $RG -n $VAULT \
  --soft-delete-feature-state Disable -o none
```

> ⚠️ 중복성(LRS/GRS)은 **보호 항목을 등록하기 전**에만 바꿀 수 있습니다. 소프트 삭제를 켜 두면 백업 삭제 후에도 14일간 데이터가 남아 정리 시 자격 증명 모음을 바로 지울 수 없을 수 있습니다. 구독/정책에 따라 `Vault's current Soft Delete State is AlwaysOn. This cannot be modified.` 경고가 나올 수 있는데, 그대로 진행해도 됩니다.

### 2. 백업 정책 만들기

`infra/backup-policy.json` 은 **매일 02:00(UTC)에 백업, 7일 보존** 정책입니다.

```bash
az backup policy create -g $RG -v $VAULT -n policy-daily-files \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --policy infra/backup-policy.json -o table
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
  --query "[].{공유:properties.friendlyName, 정책:properties.policyName, 상태:properties.protectionStatus}" -o table
```

### 4. 즉시 백업 (On-demand)

스케줄까지 기다리지 않고 지금 백업합니다. 이 시점의 파일(`budget-2026.txt` 등)이 복구 지점에 담깁니다.

```bash
JOB=$(az backup protection backup-now -g $RG -v $VAULT \
  --container-name $SA --item-name $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --retain-until $(date -d '+7 days' +%d-%m-%Y) --query name -o tsv)

az backup job wait -g $RG -v $VAULT -n $JOB
az backup job show -g $RG -v $VAULT -n $JOB --query "{작업:properties.operation, 상태:properties.status}" -o table
```

👉 상태가 **Completed** 이면 됩니다. (몇 분 걸릴 수 있습니다)

복구 지점을 확인합니다.

```bash
az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query "[].{이름:name, 시간:properties.recoveryPointTime}" -o table
```

### 5. 사고 발생! 파일 삭제 💥

```bash
scripts/vm-share.sh "rm /mnt/corpfiles/finance/budget-2026.txt; ls -l /mnt/corpfiles/finance"
```

👉 `finance` 폴더가 비었습니다. 중요한 예산안이 사라졌습니다!

### 6. 복원 ♻️

가장 최근 복구 지점을 골라 **그 파일 하나만** 원래 위치로 복원합니다.

```bash
RP=$(az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query "[0].name" -o tsv)
echo "복구 지점: $RP"

RJOB=$(az backup restore restore-azurefiles -g $RG -v $VAULT \
  --rp-name $RP --container-name $SA --item-name $SHARE \
  --restore-mode OriginalLocation --resolve-conflict Overwrite \
  --source-file-type File --source-file-path finance/budget-2026.txt \
  --query name -o tsv)

az backup job wait -g $RG -v $VAULT -n $RJOB
```

복원 결과를 확인합니다. (마운트 옵션 `actimeo=30` 때문에 최대 30초 정도 늦게 보일 수 있습니다)

```bash
sleep 30
scripts/vm-share.sh "ls -l /mnt/corpfiles/finance; cat /mnt/corpfiles/finance/budget-2026.txt"
```

👉 `2026 예산안 - 기밀` 이 다시 보이면 성공! 🎉

> 💡 **포털에서도 해보기**: Azure Portal ▸ Recovery Services 자격 증명 모음 `rsv-pvtlab` ▸ **백업 항목 ▸ Azure Storage (Azure Files)** ▸ `corpfiles` ▸ **파일 복구 / 공유 복구**.

## ✅ 확인 체크리스트

- [ ] 보호 항목 상태가 정상 (`Healthy`)
- [ ] 즉시 백업 작업 `Completed`, 복구 지점 1개 이상
- [ ] 삭제된 파일이 복원됨

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| `MissingSubscriptionRegistration` | `az provider register -n Microsoft.RecoveryServices --wait` 실행 후 재시도 |
| `date -d` 오류 (macOS 등) | Codespace(Linux)에서는 정상입니다. 직접 `--retain-until 31-12-2030` 처럼 `일-월-년` 으로 지정 |
| 보호 설정 시 스토리지 접근 오류 | 모듈 2의 `--bypass AzureServices` 가 적용됐는지 확인: `az storage account show -g $RG -n $SA --query networkRuleSet.bypass` |
| `backup-properties set` 오류 | 이미 보호 항목이 있으면 중복성을 바꿀 수 없습니다. 새로 만든 자격 증명 모음에서 진행 |
| 복원 후에도 파일이 안 보임 | 30초 기다린 뒤 `scripts/vm-share.sh "ls /mnt/corpfiles/finance"` 재실행 |

➡️ 다음: [정리](05-cleanup.md)
