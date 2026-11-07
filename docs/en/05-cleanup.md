# Cleanup (~5 min)

🌐 [한국어](../ko/05-cleanup.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Delete all lab resources to stop charges.

> ⚠️ **Order matters.** While backup protection is active, Azure Backup places a **delete lock** on the storage account, so the resource group can't be deleted right away. First **stop protection → delete the vault**, then delete the resource group.

> 📌 **Delete only a dedicated lab resource group.** Everything inside `$RG` is deleted. Do not disable organizational policies or vault soft delete.

## 📝 Option A. One script (recommended)

```bash
scripts/99-cleanup.sh
```

The script checks for registered protected items, deletes in order, and does not hide failures as "already stopped." It reports completion only after resource group deletion finishes and `az group exists` returns `false`. If an error occurs, remaining resources may still incur charges; see troubleshooting below.

Already soft-deleted items/containers are not deleted again; retention policies are preserved. If Azure returns a transient error, wait briefly and rerun the script to resume from the current state.

## 📝 Option B. Step by step

```bash
source scripts/env.sh

# 1. Stop protection + delete backup data
az backup protection disable -g $RG -v $VAULT \
  --container-name $SA --item-name $SHARE \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --delete-backup-data true --yes

# 2. Unregister the storage account
az backup container unregister -g $RG -v $VAULT \
  --container-name $SA --backup-management-type AzureStorage --yes

# 3. Delete the vault
az backup vault delete -g $RG -n $VAULT --yes

# 4. Delete the whole resource group (VNets, VMs, Private Endpoint, DNS zone, storage)
az group delete -n $RG --yes --no-wait
```

## ✅ Verify

`false` confirms deletion of the active resource group.

```bash
az group exists -n $RG
```

With Azure Secure by Default, deleted vaults may remain in a **soft-deleted state**. Removing the active resource group is not the same as immediate permanent deletion. Preserve retention policies; review the [default soft-delete period and pricing](https://learn.microsoft.com/en-us/azure/backup/secure-by-default).

If you're done with the Codespace too, delete it at [github.com/codespaces](https://github.com/codespaces).

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| Vault deletion says "backup items exist" | Check protection was stopped and the container unregistered. If policy denies an operation, inspect the error and contact your administrator. Do not disable soft delete or immutability policies |
| Lock error deleting the resource group | Backup protection still exists. Complete steps 1–2 first |
| Transient Azure error such as `CloudInternalError` | Wait 1–2 minutes and rerun the script. If it persists, contact your administrator or Microsoft support and inspect remaining resources |

🎓 Well done! You connected hub and spoke, verified private access and public blocking, configured a share, and inspected backup jobs and recovery points.
