# 정리 (약 5분)

🌐 **한국어** | [English](../en/05-cleanup.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

과금을 막기 위해 실습 리소스를 모두 삭제합니다.

> ⚠️ **순서가 중요합니다.** 백업 보호 중이면 Azure Backup이 스토리지 계정에 **삭제 잠금**을 걸어 두기 때문에 리소스 그룹이 바로 삭제되지 않습니다. 먼저 **보호 중지 → 자격 증명 모음 삭제** 후 리소스 그룹을 지웁니다.

## 📝 방법 A. 스크립트로 한 번에 (권장)

```bash
scripts/99-cleanup.sh
```

## 📝 방법 B. 단계별로 직접

```bash
source scripts/env.sh

# 1. 보호 중지 + 백업 데이터 삭제
az backup protection disable -g $RG -v $VAULT \
  --container-name $SA --item-name $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --delete-backup-data true --yes

# 2. 스토리지 계정 등록 해제
az backup container unregister -g $RG -v $VAULT \
  --container-name $SA --backup-management-type AzureStorage --yes

# 3. 자격 증명 모음 삭제
az backup vault delete -g $RG -n $VAULT --yes

# 4. 리소스 그룹 전체 삭제 (VNet, VM, Private Endpoint, DNS 영역, 스토리지 포함)
az group delete -n $RG --yes --no-wait
```

## ✅ 확인

몇 분 뒤 `false` 가 나오면 모두 삭제된 것입니다.

```bash
az group exists -n $RG
```

Codespace도 더 쓰지 않는다면 [github.com/codespaces](https://github.com/codespaces) 에서 삭제하세요.

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| 자격 증명 모음 삭제 시 "백업 항목이 있음" | 1·2단계가 끝났는지 확인. 소프트 삭제를 켠 상태였다면 포털에서 소프트 삭제된 항목을 **삭제 취소 후 영구 삭제** 해야 합니다 |
| 리소스 그룹 삭제 시 잠금 오류 | 백업 보호가 남아 있는 경우입니다. 1·2단계를 먼저 완료하세요 |

🎓 수고하셨습니다! 허브·스포크 연결, Private Endpoint로 공용 노출 차단, 그리고 백업/복원까지 마쳤습니다.
