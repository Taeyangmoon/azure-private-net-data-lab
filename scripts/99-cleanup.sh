#!/usr/bin/env bash
# 정리: 백업 보호 중지 → 자격 증명 모음 삭제 → 리소스 그룹 삭제
# Cleanup: stop protection -> delete vault -> delete resource group
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null

GROUP_EXISTS=$(az group exists -n "$RG")
if [ "$GROUP_EXISTS" = false ]; then
  echo "리소스 그룹 $RG 가 없습니다. 이미 정리되었습니다. / Resource group $RG not found. Nothing to do."
  exit 0
fi
if [ "$GROUP_EXISTS" != true ]; then
  echo "Could not determine whether resource group $RG exists." >&2
  exit 1
fi

VAULT_NAME=$(az backup vault list -g "$RG" --query "[?name=='$VAULT'].name" -o tsv)
if [ -n "$VAULT_NAME" ]; then
  CONTAINER=$(az backup container list -g "$RG" -v "$VAULT" \
    --backup-management-type AzureStorage \
    --query "[?properties.friendlyName=='$SA'].name | [0]" -o tsv)
  if [ -n "$CONTAINER" ]; then
    CONTAINER_STATUS=$(az backup container list -g "$RG" -v "$VAULT" \
      --backup-management-type AzureStorage \
      --query "[?name=='$CONTAINER'].properties.registrationStatus | [0]" -o tsv)
    case "$CONTAINER_STATUS" in
      SoftDeleted)
        echo "▶ 소프트 삭제된 컨테이너 – 보존 정책 유지 / Container already soft deleted; retention preserved"
        ;;
      Registered)
        ITEM=$(az backup item list -g "$RG" -v "$VAULT" \
          --container-name "$CONTAINER" \
          --backup-management-type AzureStorage --workload-type AzureFileShare \
          --query "[?properties.friendlyName=='$SHARE' && properties.isScheduledForDeferredDelete!=\`true\`].name | [0]" -o tsv)
        if [ -n "$ITEM" ]; then
          echo "▶ 1/4 백업 보호 중지 및 백업 데이터 삭제 / Stop protection and delete backup data"
          az backup protection disable -g "$RG" -v "$VAULT" \
            --container-name "$CONTAINER" --item-name "$ITEM" \
            --backup-management-type AzureStorage --workload-type AzureFileShare \
            --delete-backup-data true --yes -o none
        fi

        echo "▶ 2/4 스토리지 계정 등록 해제 / Unregister storage account"
        az backup container unregister -g "$RG" -v "$VAULT" \
          --container-name "$CONTAINER" --backup-management-type AzureStorage --yes -o none
        ;;
      *)
        echo "Unexpected backup container state: $CONTAINER_STATUS. Wait and retry cleanup." >&2
        exit 1
        ;;
    esac
  fi

  echo "▶ 3/4 자격 증명 모음 삭제 / Delete vault"
  az backup vault delete -g "$RG" -n "$VAULT" --yes -o none
else
  echo "▶ 1~3/4 자격 증명 모음 없음 – 건너뜀 / No vault – skipped"
fi

echo "▶ 4/4 리소스 그룹 삭제 / Delete resource group (몇 분 걸림 / takes a few minutes)"
az group delete -n "$RG" --yes
if [ "$(az group exists -n "$RG")" != false ]; then
  echo "Resource group $RG still exists. Cleanup is not complete." >&2
  exit 1
fi
echo "✅ 리소스 그룹 삭제 확인 / Resource group deletion verified: $RG"
