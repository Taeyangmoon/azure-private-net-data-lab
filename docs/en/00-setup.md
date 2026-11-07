# Module 0. Setup (~10 min)

🌐 [한국어](../ko/00-setup.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Deploy the base infrastructure in one go with Bicep.

| Resource | Name | Notes |
|---|---|---|
| Hub VNet | `vnet-hub` (10.0.0.0/16) | `snet-pe` (for the Private Endpoint), `snet-vm` |
| Spoke VNet | `vnet-spoke` (10.1.0.0/16) | `snet-workload` |
| Test VMs | `vm-hub`, `vm-spoke` | Ubuntu 22.04, no public IP |
| Storage account | `stpvtlab<unique>` | **Shared keys/public access disabled** (the private path is configured in Module 2) |

> 🧠 **What is hub-and-spoke?** A shared-services VNet (hub) in the middle, with workload VNets (spokes) connected to it. Here, the **Private Endpoint lives in the hub and the spoke VM uses it over peering**.

Peering, the Private Endpoint, private DNS, and backup are **deliberately not created**. You'll build them yourself.

Do not change policies to allow shared keys or public access. The lab does not require account key retrieval or SMB mounting.

## 📝 Steps

### 1. Check your login

```bash
az account show -o table
```
If nothing is printed, run `az login --use-device-code`.

### 2. (Optional) Choose region / VM size

```bash
export LOCATION=koreacentral    # default
export VM_SIZE=Standard_B2s_v2  # default. Pick another size on a capacity error
```

### 3. Deploy

```bash
scripts/00-deploy.sh
```

The script: creates the resource group → generates an SSH key → deploys `infra/main.bicep` → checks the storage blocking settings → waits up to 10 minutes for VM initialization and checks `curl`, `nslookup`, and `nc`. Failures are not reported as a completed deployment.

### 4. Load shared variables

```bash
source scripts/env.sh
```
You should see the storage account name, e.g. `SA=stpvtlab...`.

## ✅ Verify

```bash
az resource list -g $RG -o table --query "[].{Name:name, Type:type}"
az storage account show -g $RG -n $SA \
  --query "{SharedKey:allowSharedKeyAccess, PublicAccess:publicNetworkAccess, DefaultAction:networkRuleSet.defaultAction}" -o table
scripts/vm-exec.sh vm-spoke "hostname; nslookup -version"
```

You should see 2 VNets, 2 VMs (+NICs/disks), 1 storage account, 1 NSG, and `hostname` output from the VM.

Storage must show `SharedKey=false`, `PublicAccess=Disabled`, and `DefaultAction=Deny`.

> 💡 The VMs have no public IP, so you don't SSH in. Instead run commands inside a VM with `scripts/vm-exec.sh <vm-name> '<command>'` (uses `az vm run-command` under the hood; 10–20 s per call).

> 📌 The helper uses **Bash with `set -e` and `pipefail`** inside the VM. A failed command stops subsequent commands and returns its guest exit code to your local terminal. Azure's `Enable succeeded` message alone does not mean the command succeeded.

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| `SkuNotAvailable` / capacity error | Set another size (`export VM_SIZE=Standard_B2as_v2`) or region (`export LOCATION=...`) and rerun |
| `AuthorizationFailed` | Check you have Contributor or higher on the subscription |
| Deployment denied by Azure Policy | Inspect the resource and policy condition in the error and contact your administrator. Keep shared keys/public access disabled |

➡️ Next: [Module 1. VNet peering](01-vnet-peering.md)
