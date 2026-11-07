# Module 4. Azure Backup (~15 min)

🌐 [한국어](../ko/04-azure-backup.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Protect an empty Azure Files share with **Snapshot backup**, then verify **completed backup jobs and recovery points**.

> 📌 This module teaches backup management. It does not write/delete files or **verify restoration of file contents**.

> 🧠 **Key concepts**
> - **Recovery Services vault**: the container managing this lab's backup policies, protected items, and recovery points.
> - **Backup policy**: defines when (schedule) and how long (retention) to back up.
> - **Recovery point**: information used to return to a backup time. This lab's Snapshot backup uses **share snapshots** without moving data into the vault.
> - The **Snapshot tier** keeps snapshots in the storage account; the vault manages policies and recovery points. This differs from Vaulted backup, which copies data into the vault.
> - Do not change shared key or public access settings. Backup requests go to Azure Backup through the management plane. If additional organizational policies block a job, inspect the error and stop.

## 📝 Steps

```bash
source scripts/env.sh
: "${SA:?Deploy Module 0 first}"
```

### 1. Create the vault

```bash
# Only needed the first time in a subscription (instant if Module 0's script already did it)
az provider register -n Microsoft.RecoveryServices --wait

az backup vault create -g $RG -n $VAULT -l $LOCATION -o none

# LRS for the lab. Preserve soft-delete defaults / organizational policy.
az backup vault update -g $RG -n $VAULT \
  --backup-storage-redundancy LocallyRedundant -o none
az backup vault show -g $RG -n $VAULT \
  --query "{Redundancy:properties.redundancySettings.standardTierStorageRedundancy, SoftDelete:properties.securitySettings.softDeleteSettings.softDeleteState}" -o table
```

> 📌 Set redundancy **before registering protected items**. `SoftDelete=AlwaysON` is normal; do not attempt to disable it. Storage account share soft delete and vault soft delete are separate settings. [Soft-delete scope](https://learn.microsoft.com/en-us/azure/backup/secure-by-default)

### 2. Create a backup policy

`infra/backup-policy.json` defines the **Snapshot tier, daily backup at 02:00 UTC, and 7-day retention**. Do not switch to the Vaulted tier in this lab.

CLI policies use `retentionPolicy` for Snapshot and `vaultRetentionPolicy` for Vaulted backup. [Official policy definitions](https://learn.microsoft.com/en-us/azure/backup/manage-afs-backup-cli#create-a-backup-policy)

```bash
az backup policy create -g $RG -v $VAULT -n policy-daily-files \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --policy infra/backup-policy.json -o table
az backup policy show -g $RG -v $VAULT -n policy-daily-files \
  --query "{Schedule:properties.schedulePolicy.scheduleRunFrequency, TimeZone:properties.timeZone, RetentionDays:properties.retentionPolicy.dailySchedule.retentionDuration.count}" -o table
test "$(az backup policy show -g $RG -v $VAULT -n policy-daily-files \
  --query 'properties.vaultRetentionPolicy == `null` && properties.retentionPolicy.dailySchedule.retentionDuration.count == `7`' -o tsv)" = true
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
  --query "[].{Share:properties.friendlyName, State:properties.protectionState, PolicyId:properties.policyId}" -o table
```

You may see `IRPending` before the first backup. After the next step completes, check again for `Protected`.

### 4. On-demand backup

Do not wait for the schedule; create a snapshot of the **empty share** now.

```bash
if [ "$(uname -s)" = Darwin ]; then
  RETAIN_UNTIL=$(date -u -v+7d +%d-%m-%Y)
else
  RETAIN_UNTIL=$(date -u -d '+7 days' +%d-%m-%Y)
fi

JOB=$(az backup protection backup-now -g $RG -v $VAULT \
  --container-name $SA --item-name $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --retain-until "$RETAIN_UNTIL" --query name -o tsv)
: "${JOB:?No backup job ID returned}"

az backup job wait -g $RG -v $VAULT -n $JOB --timeout 1800 -o none
az backup job show -g $RG -v $VAULT -n $JOB --query "{Operation:properties.operation, Status:properties.status}" -o table
test "$(az backup job show -g $RG -v $VAULT -n $JOB --query properties.status -o tsv)" = Completed
```

👉 Status should be **Completed**. (It can take a few minutes.)

### 5. Inspect recovery points

Expect at least one recovery point with a name and creation time.

```bash
az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query "sort_by(@, &properties.recoveryPointTime)[].{Name:name, Time:properties.recoveryPointTime}" -o table
test "$(az backup recoverypoint list -g $RG -v $VAULT -c $SA -i $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query 'length(@)' -o tsv)" -ge 1
az backup item list -g $RG -v $VAULT --backup-management-type AzureStorage \
  --workload-type AzureFileShare \
  --query "[].{Share:properties.friendlyName, State:properties.protectionState, PolicyId:properties.policyId}" -o table
```

👉 You connected **share → backup policy → completed job → recovery point**. An empty share can have recovery points, but this does not prove restoration of file contents.

> 💡 You can inspect **Backup items ▸ Azure Storage (Azure Files)** in vault `rsv-pvtlab` in the portal. Creating/deleting actual files and verifying restored contents is a separate extension requiring identity-based data access.

## ✅ Checklist

- [ ] Share protection state is `Protected`
- [ ] On-demand backup job `Completed`, at least 1 recovery point
- [ ] Shared keys/public access remain disabled and vault soft-delete policy is preserved

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| `MissingSubscriptionRegistration` | Run `az provider register -n Microsoft.RecoveryServices --wait` and retry |
| Backup/restore job is `Failed` | Inspect the errors with `az backup job show -g $RG -v $VAULT -n <job ID> -o json`. Finishing `job wait` alone does not mean success |
| Storage access error when enabling protection | Check Module 0's `networkRuleSet.bypass=AzureServices` and this lab's Snapshot policy definition. Stop and contact your administrator if other policies block it. Do not enable shared keys or public access |
| Redundancy update error | Configure LRS before registering protected items |

➡️ Next: [Cleanup](05-cleanup.md)
