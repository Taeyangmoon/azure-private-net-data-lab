# Module 4. Azure Backup (~15 min)

🌐 [한국어](../ko/04-azure-backup.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Protect the Azure Files share with **Azure Backup**, then **delete a file by mistake and restore it**.

> 🧠 **Key concepts**
> - **Recovery Services vault**: the container that stores backup data and policies.
> - **Backup policy**: defines when (schedule) and how long (retention) to back up.
> - **Recovery point**: a snapshot at backup time. Azure Files backup is **share-snapshot based**, so it's fast and moves no data.
> - The backup service reaches storage as a **trusted Azure service**. That's why we kept `--bypass AzureServices` in Module 2. Public internet access is still blocked.

## 📝 Steps

```bash
source scripts/env.sh
```

### 1. Create the vault

```bash
az backup vault create -g $RG -n $VAULT -l $LOCATION -o none

# Lab cost/cleanup convenience: LRS redundancy, soft delete off (※ keep it ON in production)
az backup vault backup-properties set -g $RG -n $VAULT \
  --backup-storage-redundancy LocallyRedundant -o none
az backup vault backup-properties set -g $RG -n $VAULT \
  --soft-delete-feature-state Disable -o none
```

> ⚠️ Redundancy (LRS/GRS) can only be changed **before registering any protected item**. With soft delete on, backup data lingers for 14 days after deletion, so you couldn't delete the vault right away during cleanup.

### 2. Create a backup policy

`infra/backup-policy.json` defines **a daily backup at 02:00 UTC, retained for 7 days**.

```bash
az backup policy create -g $RG -v $VAULT -n policy-daily-files \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --policy infra/backup-policy.json -o table
```

### 3. Start protecting the file share

```bash
az backup protection enable-for-azurefileshare -g $RG -v $VAULT \
  --storage-account $SA --azure-file-share $SHARE \
  --policy-name policy-daily-files -o table
```

Takes 1–3 minutes. Check the status:

```bash
az backup item list -g $RG -v $VAULT --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --query "[].{Share:properties.friendlyName, Policy:properties.policyName, Status:properties.protectionStatus}" -o table
```

### 4. On-demand backup

Don't wait for the schedule; back up now. The current files (`budget-2026.txt`, etc.) go into the recovery point.

```bash
JOB=$(az backup protection backup-now -g $RG -v $VAULT \
  --container-name $SA --item-name $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --retain-until $(date -d '+7 days' +%d-%m-%Y) --query name -o tsv)

az backup job wait -g $RG -v $VAULT -n $JOB
az backup job show -g $RG -v $VAULT -n $JOB --query "{Operation:properties.operation, Status:properties.status}" -o table
```

👉 Status should be **Completed**. (It can take a few minutes.)

List the recovery points:

```bash
az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query "[].{Name:name, Time:properties.recoveryPointTime}" -o table
```

### 5. Disaster strikes! Delete a file 💥

```bash
scripts/vm-share.sh "rm /mnt/corpfiles/finance/budget-2026.txt; ls -l /mnt/corpfiles/finance"
```

👉 The `finance` folder is empty. The important budget file is gone!

### 6. Restore ♻️

Pick the latest recovery point and restore **just that file** to its original location.

```bash
RP=$(az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query "[0].name" -o tsv)
echo "Recovery point: $RP"

RJOB=$(az backup restore restore-azurefiles -g $RG -v $VAULT \
  --rp-name $RP --container-name $SA --item-name $SHARE \
  --restore-mode OriginalLocation --resolve-conflict Overwrite \
  --source-file-type File --source-file-path finance/budget-2026.txt \
  --query name -o tsv)

az backup job wait -g $RG -v $VAULT -n $RJOB
```

Verify the result. (Because of the `actimeo=30` mount option it can take up to ~30 s to show up.)

```bash
sleep 30
scripts/vm-share.sh "ls -l /mnt/corpfiles/finance; cat /mnt/corpfiles/finance/budget-2026.txt"
```

👉 If you see `2026 budget - confidential` again, you're done! 🎉

> 💡 **Try it in the portal too**: Azure Portal ▸ Recovery Services vault `rsv-pvtlab` ▸ **Backup items ▸ Azure Storage (Azure Files)** ▸ `corpfiles` ▸ **File Recovery / Restore Share**.

## ✅ Checklist

- [ ] Protected item is healthy (`Healthy`)
- [ ] On-demand backup job `Completed`, at least 1 recovery point
- [ ] Deleted file restored

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| `date -d` error (e.g. macOS) | Works in the Codespace (Linux). Otherwise pass e.g. `--retain-until 31-12-2030` (`d-m-Y`) |
| Storage access error when enabling protection | Check Module 2's `--bypass AzureServices` is applied: `az storage account show -g $RG -n $SA --query networkRuleSet.bypass` |
| `backup-properties set` error | Redundancy can't change once an item is protected. Use a freshly created vault |
| File not visible after restore | Wait 30 s and rerun `scripts/vm-share.sh "ls /mnt/corpfiles/finance"` |

➡️ Next: [Cleanup](05-cleanup.md)
