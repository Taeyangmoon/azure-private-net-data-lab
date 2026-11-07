#!/usr/bin/env bash
# 모듈 0: 실습 환경 배포 / Module 0: deploy the lab environment
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh >/dev/null

if ! az account show >/dev/null 2>&1; then
  echo "❌ 먼저 'az login --use-device-code' 를 실행하세요. / Run 'az login --use-device-code' first." >&2
  exit 1
fi

# 모듈 4(Azure Backup)에 필요. 처음 쓰는 구독이면 등록이 필요합니다. / Needed for Module 4; first-time subscriptions must register it.
az provider register -n Microsoft.RecoveryServices --wait >/dev/null

echo "▶ 1/4 리소스 그룹 생성 / Creating resource group: $RG ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" -o none

echo "▶ 2/4 SSH 키 준비 / Preparing SSH key (~/.ssh/lab_key)"
mkdir -p ~/.ssh
[ -f ~/.ssh/lab_key ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/lab_key -q

echo "▶ 3/4 Bicep 배포 / Deploying Bicep (약 3~5분 / ~3-5 min)"
az deployment group create -g "$RG" -n main \
  -f infra/main.bicep \
  -p sshPublicKey="$(cat ~/.ssh/lab_key.pub)" ${VM_SIZE:+vmSize="$VM_SIZE"} \
  --query 'properties.outputs' -o jsonc

SA_NAME=$(az deployment group show -g "$RG" -n main --query properties.outputs.storageAccountName.value -o tsv)
SECURITY_OK=$(az storage account show -g "$RG" -n "$SA_NAME" \
  --query "allowSharedKeyAccess == \`false\` && publicNetworkAccess == 'Disabled' && networkRuleSet.defaultAction == 'Deny'" -o tsv)
if [ "$SECURITY_OK" != true ]; then
  echo "❌ 스토리지 보안 설정을 확인하세요: 공유 키=false, 공용 접근=Disabled, 기본 동작=Deny가 필요합니다." >&2
  echo "❌ Expected storage settings: shared key=false, public access=Disabled, default action=Deny." >&2
  exit 1
fi

echo "▶ 4/4 VM 초기화(cloud-init) 대기 / Waiting for VM cloud-init"
for vm in "$VM_HUB" "$VM_SPOKE"; do
  scripts/vm-exec.sh "$vm" "timeout 600 cloud-init status --wait; command -v curl; command -v nslookup; command -v nc"
done

echo "✅ 완료 / Done. 다음: docs/ko/01-vnet-peering.md (EN: docs/en/01-vnet-peering.md)"
