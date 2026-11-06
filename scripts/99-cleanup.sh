#!/usr/bin/env bash
# 정리: 백업 보호 중지 → 자격 증명 모음 삭제 → 리소스 그룹 삭제
# Cleanup: stop protection -> delete vault -> delete resource group
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null

if ! az group exists -n "$RG" | grep -q true; then
  echo "리소스 그룹 $RG 가 없습니다. 이미 정리되었습니다. / Resource group $RG not found. Nothing to do."
  exit 0
fi

if [ -n "$(az backup vault list -g "$RG" --query "[?name=='$VAULT'].name" -o tsv 2>/dev/null)" ]; then
  echo "▶ 1/4 백업 보호 중지 및 백업 데이터 삭제 / Stop protection and delete backup data"
  az backup protection disable -g "$RG" -v "$VAULT" \
    --container-name "$SA" --item-name "$SHARE" \
    --backup-management-type AzureStorage --workload-type AzureFileShare \
    --delete-backup-data true --yes -o none 2>&1 || echo "(이미 중지됨 / already stopped)"

  echo "▶ 2/4 스토리지 계정 등록 해제 / Unregister storage account"
  az backup container unregister -g "$RG" -v "$VAULT" \
    --container-name "$SA" --backup-management-type AzureStorage --yes -o none 2>&1 || true

  echo "▶ 3/4 자격 증명 모음 삭제 / Delete vault"
  az backup vault delete -g "$RG" -n "$VAULT" --yes -o none
else
  echo "▶ 1~3/4 자격 증명 모음 없음 – 건너뜀 / No vault – skipped"
fi

echo "▶ 4/4 리소스 그룹 삭제 / Delete resource group (몇 분 걸림 / takes a few minutes)"
az group delete -n "$RG" --yes --no-wait
echo "✅ 삭제를 요청했습니다 / Deletion requested. 확인 / Verify: az group exists -n $RG"
