# Cleanup (~5 min)

🌐 [한국어](../ko/05-cleanup.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Delete all lab resources to stop charges.

> ⚠️ **Order matters.** While backup protection is active, Azure Backup places a **delete lock** on the storage account, so the resource group can't be deleted right away. First **stop protection → delete the vault**, then delete the resource group.

## 📝 Option A. One script (recommended)

```bash
scripts/99-cleanup.sh
```

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

After a few minutes, `false` means everything is gone.

```bash
az group exists -n $RG
```

If you're done with the Codespace too, delete it at [github.com/codespaces](https://github.com/codespaces).

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| Vault deletion says "backup items exist" | Make sure steps 1–2 finished. If soft delete was on, **undelete then permanently delete** the soft-deleted items in the portal |
| Lock error deleting the resource group | Backup protection still exists. Complete steps 1–2 first |

🎓 Well done! You connected hub and spoke, blocked public exposure with a Private Endpoint, and backed up and restored your data.
