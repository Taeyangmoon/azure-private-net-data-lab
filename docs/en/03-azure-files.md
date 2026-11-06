# Module 3. Azure Files (~15 min)

🌐 [한국어](../ko/03-azure-files.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Create an **Azure Files share** to act as the corporate file share, and mount it on the spoke VM over the **private path (Private Endpoint)**.

> 🧠 **Azure Files**: a fully managed SMB file share, mounted like a regular network drive on Windows/Linux. SMB uses **port 445**, which is often blocked on internet paths. With a Private Endpoint, traffic stays inside the VNet, so that's not an issue and nothing is exposed to the internet.

## 📝 Steps

```bash
source scripts/env.sh
```

### 1. Create the file share

Because you blocked public access in Module 2, data-plane calls such as `az storage share create` fail from the Codespace. Use `share-rm`, which goes through the **management plane (ARM)**.

```bash
az storage share-rm create -g $RG --storage-account $SA -n $SHARE \
  --quota 5 --enabled-protocols SMB -o table
```

> 💡 Management vs data plane: creating/configuring resources (management) isn't affected by the firewall; only reading/writing files (data) is subject to the firewall / Private Endpoint.

### 2. Configure the mount on the VM

> ⚠️ For simplicity this lab authenticates with the **storage account key**. In production prefer identity-based auth (Microsoft Entra Kerberos).

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

👉 If `df` shows `//stpvtlab....file.core.windows.net/corpfiles` with 5.0G, the mount worked.

> 🧠 Because it's in `/etc/fstab`, the share re-mounts after a reboot. (Each `az vm run-command` call is a fresh session, so `scripts/vm-share.sh` checks the mount and mounts it if needed.)

### 3. Verify it uses the private path 🔍

```bash
scripts/vm-share.sh "grep corpfiles /proc/mounts | tr ',' '\n' | grep -E 'addr=|^//'"
```

👉 `addr=10.0.1.x` — the **Private Endpoint's private IP** from Module 2, not a public IP!

### 4. Create some fake corporate files

```bash
scripts/vm-share.sh "
mkdir -p /mnt/corpfiles/finance /mnt/corpfiles/hr
echo '2026 budget - confidential' > /mnt/corpfiles/finance/budget-2026.txt
echo 'HR policy v1.0'             > /mnt/corpfiles/hr/policy.txt
echo 'Meeting notes 2026-01-05'   > /mnt/corpfiles/meeting-notes.txt
ls -lR /mnt/corpfiles
"
```

### 5. See it from Azure too (management plane)

```bash
az storage share-rm show -g $RG --storage-account $SA -n $SHARE \
  --query "{Name:name, QuotaGiB:shareQuota, Protocols:enabledProtocols}" -o table
```

> 📌 Listing files from the Codespace with `az storage file list` returns **403**. That's expected: public access is blocked. Files are only visible from inside the VNet (the VM). 🔒

## ✅ Checklist

- [ ] The share shows up in `df -h`
- [ ] `addr=` in `/proc/mounts` is `10.0.1.x`
- [ ] 3 sample files were created

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| `mount error(13): Permission denied` | Check the key (`echo ${#KEY}` is normally 88) |
| `mount error(115)` / `Connection timed out` | Confirm the Module 1 peering is `Connected` and DNS resolves to `10.0.1.x` (Module 2) |
| `cifs filesystem not supported` / missing `cifs-utils` | Module 0 cloud-init may not have finished: `scripts/vm-exec.sh $VM_SPOKE "cloud-init status --wait; apt-get install -y cifs-utils"` |
| `share-rm create` fails: shared key access prohibited | An org policy blocks shared keys. Use a personal/test subscription |

➡️ Next: [Module 4. Azure Backup](04-azure-backup.md)
