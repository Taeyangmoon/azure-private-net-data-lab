#!/usr/bin/env bash
# 모든 스크립트/실습에서 공통으로 쓰는 변수. 새 터미널을 열 때마다 `source scripts/env.sh` 하세요.
# Common variables. Run `source scripts/env.sh` in every new terminal.

export RG="${RG:-rg-pvtlab}"
export LOCATION="${LOCATION:-koreacentral}"
export HUB_VNET="vnet-hub"
export SPOKE_VNET="vnet-spoke"
export VM_HUB="vm-hub"
export VM_SPOKE="vm-spoke"
export SHARE="corpfiles"
export VAULT="rsv-pvtlab"
export DNS_ZONE="privatelink.file.core.windows.net"

# 스토리지 계정 이름은 배포 시 자동 생성(전역 고유)되므로 리소스 그룹에서 조회합니다.
SA="$(az storage account list -g "$RG" --query '[0].name' -o tsv 2>/dev/null || true)"
export SA

echo "RG=$RG  LOCATION=$LOCATION  SA=${SA:-<아직 없음 / not yet>}"
