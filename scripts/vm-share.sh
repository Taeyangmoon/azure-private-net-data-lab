#!/usr/bin/env bash
# 사용법 / Usage: scripts/vm-share.sh '<bash commands>'
# vm-spoke 에서 파일 공유가 마운트되어 있는지 확인(없으면 마운트)한 뒤 명령을 실행합니다.
# Makes sure the file share is mounted on vm-spoke (mounts it if not), then runs the commands.
set -euo pipefail
DIR="$(dirname "$0")"

"$DIR/vm-exec.sh" vm-spoke "mountpoint -q /mnt/corpfiles || mount /mnt/corpfiles; $*"
