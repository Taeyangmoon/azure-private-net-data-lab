#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP=$(mktemp -d)
trap 'rm -f "$TMP/az" "$TMP/calls" "$TMP/deleted"; rmdir "$TMP"' EXIT
export CALLS="$TMP/calls" DELETED="$TMP/deleted"

cat > "$TMP/az" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2 ${3:-}" in
  "storage account list") echo sttest ;;
  "group exists "*)
    if [ "$SCENARIO" = query-failure ]; then exit 3; fi
    if [ "$SCENARIO" = absent ] || [ -f "$DELETED" ]; then
      echo false
    else
      echo true
    fi
    ;;
  "backup vault list") echo rsv-pvtlab ;;
  "backup container list")
    if [[ "$*" == *registrationStatus* ]]; then
      case "$SCENARIO" in
        soft-deleted-container) echo SoftDeleted ;;
        unknown-state) echo Registering ;;
        *) echo Registered ;;
      esac
    elif [ "$SCENARIO" != no-container ]; then
      echo 'storagecontainer;rg;sttest'
    fi
    ;;
  "backup item list")
    if [ "$SCENARIO" != soft-deleted-item ] || [[ "$*" != *isScheduledForDeferredDelete* ]]; then
      echo 'azurefileshare;test'
    fi
    ;;
  "backup protection disable")
    if [ "$SCENARIO" = protection-failure ]; then
      echo "Cannot delete protected backup data" >&2
      exit 9
    fi
    ;;
  "backup container unregister") ;;
  "backup vault delete")
    if [ "$SCENARIO" = vault-failure ]; then exit 7; fi
    ;;
  "group delete "*) touch "$DELETED" ;;
  *) echo "Unexpected Azure command: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$TMP/az"
export PATH="$TMP:$PATH"

check_cleanup() {
  local expected="$2" actual=0
  export SCENARIO="$1"
  : > "$CALLS"
  rm -f "$DELETED"
  OUTPUT=$("$ROOT/scripts/99-cleanup.sh" 2>&1) || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    printf '%s: expected exit %s, got %s:\n%s\n' "$SCENARIO" "$expected" "$actual" "$OUTPUT" >&2
    exit 1
  fi
}

check_cleanup absent 0
! grep -q 'group delete' "$CALLS"
check_cleanup query-failure 3
! grep -q 'group delete' "$CALLS"
check_cleanup protection-failure 9
! grep -q 'container unregister\|vault delete\|group delete' "$CALLS"
check_cleanup vault-failure 7
! grep -q 'group delete' "$CALLS"
check_cleanup no-container 0
! grep -q 'protection disable\|container unregister' "$CALLS"
test -f "$DELETED"
check_cleanup soft-deleted-container 0
! grep -q 'protection disable\|container unregister' "$CALLS"
test -f "$DELETED"
check_cleanup soft-deleted-item 0
! grep -q 'protection disable' "$CALLS"
grep -q 'container unregister' "$CALLS"
test -f "$DELETED"
check_cleanup unknown-state 1
! grep -q 'protection disable\|container unregister\|vault delete\|group delete' "$CALLS"
check_cleanup normal 0
grep -q 'protection disable' "$CALLS"
grep -q 'container unregister' "$CALLS"
test -f "$DELETED"
[[ "$OUTPUT" == *'deletion verified'* ]]
echo 'Cleanup regression tests passed.'
