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
# Run Command reports provisioning success even when the guest command fails.
MARKER="__PVTLAB_EXIT_${RANDOM}_${RANDOM}__"
SCRIPT="exec 2>&1
bash -se -o pipefail <<'$MARKER'
$*
$MARKER
STATUS=\$?
printf '\n$MARKER=%s\n' \"\$STATUS\"
exit \"\$STATUS\""

OUTPUT=$(az vm run-command invoke -g "$RG" -n "$VM" \
  --command-id RunShellScript \
  --scripts "$SCRIPT" \
  --query 'value[0].message' -o tsv)

printf '%s\n' "$OUTPUT" | sed "/^$MARKER=[0-9][0-9]*$/d"
STATUS=$(printf '%s\n' "$OUTPUT" | sed -n "s/^$MARKER=\([0-9][0-9]*\)$/\1/p")
if [[ ! "$STATUS" =~ ^[0-9]+$ ]] || [ "$STATUS" -gt 255 ]; then
  echo "Run Command did not return a guest exit status ($VM). Check the VM agent and command output." >&2
  exit 1
fi
exit "$STATUS"
