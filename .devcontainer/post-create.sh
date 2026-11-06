#!/usr/bin/env bash
# Codespace 생성 후 한 번 실행됩니다. / Runs once after the Codespace is created.
set -e

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends dnsutils jq

az config set core.only_show_errors=true core.collect_telemetry=false
az config set extension.use_dynamic_install=yes_without_prompt

chmod +x scripts/*.sh

echo "✅ 준비 완료 / Ready. 'az login --use-device-code' 로 시작하세요 / to get started."
