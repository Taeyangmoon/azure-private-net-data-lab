#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP=$(mktemp -d)
trap 'rm -f "$TMP/az"; rmdir "$TMP"' EXIT

cat > "$TMP/az" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2 $3" = "storage account list" ]; then
  echo sttest
elif [ "$1 $2 $3" = "vm run-command invoke" ]; then
  if [ "${AZ_FAIL:-0}" = 1 ]; then
    echo "Azure authorization failed" >&2
    exit 3
  fi
  if [ "${AZ_MISSING_STATUS:-0}" = 1 ]; then
    echo "Enable succeeded without guest output"
    exit 0
  fi
  while [ "$1" != --scripts ]; do shift; done
  printf 'Enable succeeded:\n[stdout]\n'
  bash -c "$2" || true
  printf '\n[stderr]\n'
else
  echo "Unexpected Azure command: $*" >&2
  exit 1
fi
EOF
chmod +x "$TMP/az"
export PATH="$TMP:$PATH"

expect_status() {
  local expected="$1" actual=0
  shift
  OUTPUT=$("$@" 2>&1) || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    printf 'Expected exit %s, got %s:\n%s\n' "$expected" "$actual" "$OUTPUT" >&2
    exit 1
  fi
}

expect_status 0 "$ROOT/scripts/vm-exec.sh" vm-spoke 'printf "hello\n"'
[[ "$OUTPUT" == *hello* && "$OUTPUT" != *'__PVTLAB_EXIT_'* ]]
expect_status 7 "$ROOT/scripts/vm-exec.sh" vm-spoke 'exit 7'
expect_status 1 "$ROOT/scripts/vm-exec.sh" vm-spoke 'false; echo UNEXPECTED_SUCCESS'
[[ "$OUTPUT" != *UNEXPECTED_SUCCESS* ]]
expect_status 1 "$ROOT/scripts/vm-exec.sh" vm-spoke 'false | cat'
expect_status 3 env AZ_FAIL=1 "$ROOT/scripts/vm-exec.sh" vm-spoke 'true'
expect_status 1 env AZ_MISSING_STATUS=1 "$ROOT/scripts/vm-exec.sh" vm-spoke 'true'
expect_status 1 "$ROOT/scripts/vm-exec.sh" vm-spoke
echo 'VM helper regression tests passed.'
