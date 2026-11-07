# 정리 (약 5분)

🌐 **한국어** | [English](../en/05-cleanup.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

과금을 막기 위해 실습 리소스를 모두 삭제합니다.

> ⚠️ **순서가 중요합니다.** 백업 보호 중이면 Azure Backup이 스토리지 계정에 **삭제 잠금**을 걸어 두기 때문에 리소스 그룹이 바로 삭제되지 않습니다. 먼저 **보호 중지 → 자격 증명 모음 삭제** 후 리소스 그룹을 지웁니다.

> 📌 **실습 전용 리소스 그룹만 삭제하세요.** `$RG` 안의 모든 리소스가 삭제됩니다. 조직 정책이나 자격 증명 모음의 소프트 삭제를 비활성화하지 않습니다.

## 📝 방법 A. 스크립트로 한 번에 (권장)

```bash
scripts/99-cleanup.sh
```

스크립트는 등록된 보호 항목이 있는지 확인한 뒤 순서대로 삭제하며, 실패를 "이미 중지됨"으로 숨기지 않습니다. 리소스 그룹 삭제가 끝나고 `az group exists`가 `false`인지 확인한 뒤에만 완료를 출력합니다. 오류가 나면 남은 리소스는 계속 과금될 수 있으므로 아래 문제 해결을 확인하세요.

이미 소프트 삭제된 항목·컨테이너는 다시 삭제하지 않고 보존 정책을 유지합니다. Azure가 일시적 오류를 반환했다면 잠시 기다린 뒤 스크립트를 다시 실행하면 현재 상태부터 재개합니다.

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

`false`이면 활성 리소스 그룹 삭제가 완료된 것입니다.

```bash
az group exists -n $RG
```

Azure의 Secure by Default 설정에 따라 삭제된 자격 증명 모음이 **소프트 삭제 상태로 보존**될 수 있습니다. 활성 리소스 그룹 삭제와 즉시 영구 삭제는 다릅니다. 보존 정책은 변경하지 않으며, [기본 소프트 삭제 기간과 비용](https://learn.microsoft.com/en-us/azure/backup/secure-by-default)을 확인하세요.

Codespace도 더 쓰지 않는다면 [github.com/codespaces](https://github.com/codespaces) 에서 삭제하세요.

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| 자격 증명 모음 삭제 시 "백업 항목이 있음" | 보호 중지·등록 해제 완료 여부를 확인하세요. 정책이 작업을 거부하면 오류를 확인하고 관리자에게 문의하세요. 소프트 삭제나 불변성 정책을 끄지 마세요 |
| 리소스 그룹 삭제 시 잠금 오류 | 백업 보호가 남아 있는 경우입니다. 1·2단계를 먼저 완료하세요 |
| `CloudInternalError` 등 일시적 Azure 오류 | 1~2분 기다린 뒤 스크립트를 다시 실행하세요. 오류가 계속되면 관리자 또는 Microsoft 지원에 문의하고 남은 리소스를 확인하세요 |

🎓 수고하셨습니다! 허브·스포크 연결, 프라이빗 경로와 공용 접근 차단 확인, 공유 구성과 백업·복구 지점 확인을 마쳤습니다.
