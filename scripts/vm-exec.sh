#!/usr/bin/env bash
# 사용법 / Usage: scripts/vm-exec.sh <vm-name> '<bash commands>'
# Bastion/공용 IP 없이 `az vm run-command` 로 VM 안에서 명령을 실행합니다. (root 권한)
# Runs commands inside a VM via `az vm run-command` – no Bastion or public IP needed. (as root)
set -euo pipefail
source "$(dirname "$0")/env.sh" >/dev/null

if [ $# -lt 2 ]; then
  echo "Usage: $0 <vm-name> '<bash commands>'" >&2
  exit 1
fi

VM="$1"; shift
az vm run-command invoke -g "$RG" -n "$VM" \
  --command-id RunShellScript \
  --scripts "$*" \
  --query 'value[0].message' -o tsv
