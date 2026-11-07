# Module 3. Azure Files (~10 min)

🌐 [한국어](../ko/03-azure-files.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Create an **Azure Files share** while public data access is disabled, then inspect its quota and protocol. Understand that **resource management and file data access are separate**.

> 🧠 **Azure Files** is a managed file share. You configure an SMB share here, but do not mount it or read/write files. TCP 445 connectivity from Module 2 proves network reachability, not successful file authentication.

Do not enable shared keys or create policy exemptions. The `share-rm` management-plane API does not require retrieving account keys in the lab commands.

## 📝 Steps

```bash
source scripts/env.sh
: "${SA:?Deploy Module 0 first}"
```

### 1. Create the file share

Public data access is disabled, so use `share-rm` through the **management plane (ARM)**.

```bash
az storage share-rm create -g $RG --storage-account $SA -n $SHARE \
  --quota 5 --enabled-protocols SMB -o table
```

> 💡 Management vs data plane: creating/configuring resources (management) isn't affected by the firewall; only reading/writing files (data) is subject to the firewall / Private Endpoint.

### 2. Inspect share settings

```bash
az storage share-rm show -g $RG --storage-account $SA -n $SHARE \
  --query "{Name:name, QuotaGiB:shareQuota, Protocols:enabledProtocols}" -o table
```

👉 Expect `corpfiles`, `5` GiB, and `SMB`. This is an **empty share** with no files yet.

### 3. Confirm security settings are unchanged

```bash
az storage account show -g $RG -n $SA \
  --query "{SharedKey:allowSharedKeyAccess, PublicAccess:publicNetworkAccess, DefaultAction:networkRuleSet.defaultAction}" -o table
```

👉 Settings remain `false / Disabled / Deny`. Creating a share did not open data access.

| Operation | Access path | Lab result |
|---|---|---|
| Create share / inspect settings | ARM management plane | Succeeds with your Azure login permissions |
| Internet request to file service | Public data path | Module 2 confirmed 403 |
| VM request to file service | Private Endpoint | Module 2 confirmed private IP / 401 |
| Read/write actual files | Requires data authentication | Omitted from the basic lab |

## ✅ Checklist

- [ ] Share `corpfiles` exists with `5` GiB quota and `SMB` protocol
- [ ] Shared keys and public data access remain disabled
- [ ] Understand management-plane success vs. data-plane restrictions

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| `share-rm create` authorization error | Check Contributor permissions on the resource group and the `$SA` value |
| Policy denies share creation | Inspect the policy condition in the error and contact your administrator. Do not disable shared key / public access restrictions |
| Cannot list files from the internet | Expected: public data access remains blocked |

> 💡 Actual file data operations are a separate extension. [Azure Files REST API with Microsoft Entra ID authentication](https://learn.microsoft.com/en-us/azure/storage/files/authorize-oauth-rest) requires data-plane RBAC roles and permission to assign them.

➡️ Next: [Module 4. Azure Backup](04-azure-backup.md)
