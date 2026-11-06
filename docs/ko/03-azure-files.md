# 모듈 3. Azure Files (약 15분)

🌐 **한국어** | [English](../en/03-azure-files.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

사내 파일 공유로 쓸 **Azure Files 공유**를 만들고, 스포크 VM에서 **프라이빗 경로(Private Endpoint)** 로 마운트합니다.

> 🧠 **Azure Files**: 완전 관리형 SMB 파일 공유입니다. Windows/Linux에서 일반 네트워크 드라이브처럼 마운트합니다. SMB는 **445 포트**를 쓰는데, 인터넷 구간에서는 막힌 경우가 많습니다. Private Endpoint를 쓰면 VNet 내부 경로만 이용하므로 이런 문제가 없고 인터넷에 노출되지도 않습니다.

> ⚠️ **전제 조건**: 이 모듈은 스토리지 **계정 키(공유 키) 액세스가 허용**된 구독이 필요합니다. 조직 정책이 `allowSharedKeyAccess=false` 를 강제하면 마운트가 `mount error(13): Permission denied` (`STATUS_ACCESS_DENIED`) 로 실패합니다. 모듈 0 배포 스크립트가 이 경우 경고를 출력하며, `az storage account show -g $RG -n $SA --query allowSharedKeyAccess` 로도 확인할 수 있습니다. 정책이 막는 구독이라면 개인/테스트 구독을 사용하세요.

## 📝 실습

```bash
source scripts/env.sh
```

### 1. 파일 공유 생성

모듈 2에서 공용 접근을 막았기 때문에 Codespace에서 데이터 영역(`az storage share create`)은 실패합니다. 대신 **관리 영역(ARM)** API인 `share-rm` 으로 만듭니다.

```bash
az storage share-rm create -g $RG --storage-account $SA -n $SHARE \
  --quota 5 --enabled-protocols SMB -o table
```

> 💡 관리 영역 vs 데이터 영역: 리소스를 만들고 설정하는 것(관리)은 방화벽 영향을 받지 않고, 파일을 읽고 쓰는 것(데이터)만 방화벽/Private Endpoint 대상입니다.

### 2. VM에 마운트 설정

> ⚠️ 랩 단순화를 위해 **스토리지 계정 키**로 인증합니다. 운영에서는 ID 기반 인증(Microsoft Entra Kerberos)을 권장합니다.

```bash
KEY=$(az storage account keys list -g $RG -n $SA --query '[0].value' -o tsv)

scripts/vm-exec.sh $VM_SPOKE "
set -e
mkdir -p /mnt/corpfiles /etc/smbcredentials
printf 'username=$SA\npassword=$KEY\n' > /etc/smbcredentials/$SA.cred
chmod 600 /etc/smbcredentials/$SA.cred
grep -q corpfiles /etc/fstab || echo '//$SA.file.core.windows.net/$SHARE /mnt/corpfiles cifs nofail,credentials=/etc/smbcredentials/$SA.cred,dir_mode=0777,file_mode=0777,serverino,nosharesock,actimeo=30,vers=3.1.1 0 0' >> /etc/fstab
systemctl daemon-reload
mount /mnt/corpfiles
df -h /mnt/corpfiles
"
```

👉 `df` 결과에 `//stpvtlab....file.core.windows.net/corpfiles` 가 5.0G로 보이면 마운트 성공입니다.

> 🧠 `/etc/fstab` 에 등록했기 때문에 VM이 재부팅되어도 자동으로 마운트됩니다. (`az vm run-command` 는 호출마다 새 세션이라, 이후 `scripts/vm-share.sh` 가 마운트 여부를 확인하고 필요하면 마운트합니다.)

### 3. 프라이빗 경로로 연결되었는지 확인 🔍

```bash
scripts/vm-share.sh "grep corpfiles /proc/mounts | tr ',' '\n' | grep -E 'addr=|^//'"
```

👉 `addr=10.0.1.x` — 모듈 2에서 만든 **Private Endpoint의 사설 IP**입니다. 공용 IP가 아닙니다!

### 4. 사내 파일 흉내 내기

```bash
scripts/vm-share.sh "
mkdir -p /mnt/corpfiles/finance /mnt/corpfiles/hr
echo '2026 예산안 - 기밀' > /mnt/corpfiles/finance/budget-2026.txt
echo '인사 규정 v1.0'     > /mnt/corpfiles/hr/policy.txt
echo '회의록 2026-01-05'   > /mnt/corpfiles/meeting-notes.txt
ls -lR /mnt/corpfiles
"
```

### 5. Azure에서도 보이는지 확인 (관리 영역)

```bash
az storage share-rm show -g $RG --storage-account $SA -n $SHARE \
  --query "{이름:name, 용량GiB:shareQuota, 프로토콜:enabledProtocols}" -o table
```

> 📌 Codespace에서 `az storage file list` 로 파일 목록을 보려고 하면 **403** 이 납니다. 공용 접근을 차단했으니 정상입니다. 파일은 VNet 안(VM)에서만 보입니다. 🔒

## ✅ 확인 체크리스트

- [ ] `df -h` 에 공유가 마운트되어 있음
- [ ] `/proc/mounts` 의 `addr=` 가 `10.0.1.x`
- [ ] 샘플 파일 3개가 생성됨

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| `mount error(13): Permission denied` | 키 길이 확인 (`echo ${#KEY}` 가 88이면 정상). 그래도 실패하면 `allowSharedKeyAccess` 가 `false` 인지 확인 (위 전제 조건) |
| `mount error(115)` / `Connection timed out` | 모듈 1 피어링 `Connected`, 모듈 2 DNS 해석이 `10.0.1.x` 인지 확인 |
| `mount error: cifs filesystem not supported` / `cifs-utils` 없음 | 모듈 0의 cloud-init이 끝나지 않았을 수 있습니다. `scripts/vm-exec.sh $VM_SPOKE "cloud-init status --wait; apt-get install -y cifs-utils"` |
| `share-rm create` 실패: 키 접근 금지 정책 | 조직 정책이 공유 키를 막는 경우입니다. 개인/테스트 구독 사용 |

➡️ 다음: [모듈 4. Azure Backup](04-azure-backup.md)
