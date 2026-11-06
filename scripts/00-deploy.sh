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

SA_NAME=$(az storage account list -g "$RG" --query '[0].name' -o tsv)
if [ "$(az storage account show -g "$RG" -n "$SA_NAME" --query allowSharedKeyAccess -o tsv)" = "false" ]; then
  echo "⚠️  이 구독은 스토리지 '공유 키 액세스'가 정책으로 꺼져 있습니다. 모듈 3(SMB 마운트)이 실패합니다." >&2
  echo "⚠️  Shared key access is disabled by policy in this subscription. Module 3 (SMB mount) will fail." >&2
fi

echo "▶ 4/4 VM 초기화(cloud-init) 대기 / Waiting for VM cloud-init"
for vm in "$VM_HUB" "$VM_SPOKE"; do
  scripts/vm-exec.sh "$vm" "cloud-init status --wait" | tail -n 3
done

echo "✅ 완료 / Done. 다음: docs/ko/01-vnet-peering.md (EN: docs/en/01-vnet-peering.md)"
