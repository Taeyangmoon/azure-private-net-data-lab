# Module 2. Private Endpoint (~20 min)

🌐 [한국어](../ko/02-private-endpoint.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Attach a **Private Endpoint** to a storage account whose public access is already disabled. Compare `nslookup` results and **internet 403 vs. VM 401** responses to understand the private path.

> 🧠 **Key concepts**
> - **Private Endpoint**: a private IP (a NIC) in your VNet. It is the **Private Link** entrance to an Azure service (here, the storage `file` sub-service).
> - **Private DNS zone** `privatelink.file.core.windows.net`: makes `<account>.file.core.windows.net` resolve to the **private IP instead of the public IP**. Without it, VMs keep trying the public IP.
> - **Blocking public access**: Module 0 deploys `publicNetworkAccess=Disabled`. This setting and shared key restrictions stay in place throughout; do not enable public access for comparison.

```mermaid
flowchart LR
  VM["vm-spoke"] -- "① account.file.core.windows.net ?" --> DNS["Private DNS Zone"]
  DNS -- "② 10.0.1.x (private IP)" --> VM
  VM -- "③ via peering" --> PE["Private Endpoint (hub)"] --> SA[("Storage")]
```

## 📝 Steps

```bash
source scripts/env.sh
echo $SA        # if empty, re-check Module 0
: "${SA:?Deploy Module 0 first}"
```

### 1. Before: record the `nslookup` results 📸

**From the VM (spoke):**

```bash
scripts/vm-exec.sh $VM_SPOKE "nslookup $SA.file.core.windows.net"
```

**From the Codespace (internet side):**

```bash
nslookup $SA.file.core.windows.net
```

👉 Both return a **public IP** (e.g. `20.x.x.x`, `52.x.x.x`). Remember this.

> 📌 **Resolving a public IP does not mean public data access is allowed.** Even now the following internet request returns `403 AuthorizationFailure`.

```bash
curl -sS --max-time 30 -i -H "x-ms-version: 2023-11-03" \
  "https://$SA.file.core.windows.net/?comp=list" | grep -iE "^HTTP|x-ms-error-code"
```

### 2. Create the private DNS zone and link it to the VNets

```bash
az network private-dns zone create -g $RG -n $DNS_ZONE -o none

# Link both hub and spoke (the spoke VM must resolve the name)
az network private-dns link vnet create -g $RG -z $DNS_ZONE -n link-hub \
  -v $HUB_VNET -e false -o none
az network private-dns link vnet create -g $RG -z $DNS_ZONE -n link-spoke \
  -v $SPOKE_VNET -e false -o none
```

### 3. Create the Private Endpoint (`snet-pe` in the hub VNet)

```bash
SA_ID=$(az storage account show -g $RG -n $SA --query id -o tsv)

az network private-endpoint create -g $RG -n pe-files \
  --vnet-name $HUB_VNET --subnet snet-pe \
  --private-connection-resource-id $SA_ID \
  --group-id file \
  --connection-name pe-files-conn -o none
```

`--group-id file` targets the **Azure Files** sub-service of the storage account. (Use `blob` for Blob.)

### 4. Attach the endpoint to the DNS zone (auto-registers the A record)

```bash
ZONE_ID=$(az network private-dns zone show -g $RG -n $DNS_ZONE --query id -o tsv)

az network private-endpoint dns-zone-group create -g $RG \
  --endpoint-name pe-files -n default \
  --private-dns-zone $ZONE_ID --zone-name file -o none
```

Check the registered record.

```bash
az network private-dns record-set a list -g $RG -z $DNS_ZONE \
  --query "[].{Name:name, IP:aRecords[0].ipv4Address}" -o table
```

👉 An entry named `$SA` with a `10.0.1.x` private IP should exist.

### 5. After: compare `nslookup` 📸

```bash
scripts/vm-exec.sh $VM_SPOKE "nslookup $SA.file.core.windows.net"
nslookup $SA.file.core.windows.net
```

| Where | Result | Why |
|---|---|---|
| **VM (spoke)** | alias `...privatelink.file.core.windows.net` → **10.0.1.x** (private IP) | The private DNS zone linked to the VNet answers |
| **Codespace (internet)** | still a **public IP** | Outside the linked VNets, public DNS is used |

### 6. Compare internet and VM responses 🔍

Send the same unauthenticated request to check the **access path only**. Public data access has been disabled from the start.

```bash
# From the internet (Codespace)
curl -sS --max-time 30 -i -H "x-ms-version: 2023-11-03" \
  "https://$SA.file.core.windows.net/?comp=list" | grep -iE "^HTTP|x-ms-error-code"
scripts/vm-exec.sh $VM_SPOKE "curl -sS --max-time 30 -i -H 'x-ms-version: 2023-11-03' 'https://$SA.file.core.windows.net/?comp=list' | grep -iE '^HTTP|x-ms-error-code'"
```

| Location | Response | Meaning |
|---|---|---|
| Internet | `403 AuthorizationFailure` | Public data access blocked |
| VM | `401 NoAuthenticationInformation` | Service reached over the private path, but credentials are missing |

> 📌 **401 does not mean reading/writing files succeeded.** Network connectivity and data authentication are separate; file data authentication is outside the basic lab.

### 7. Check SMB port connectivity

```bash
scripts/vm-exec.sh $VM_SPOKE "timeout 5 bash -c '</dev/tcp/$SA.file.core.windows.net/445' && echo '✅ port 445 reachable (private path)'"
```

👉 TCP port 445 is reachable, but you do not attempt an SMB mount or authentication. Shared keys remain disabled by policy.

## ✅ Checklist

- [ ] Before: both VM and Codespace see a public IP
- [ ] After: VM sees `10.0.1.x`, Codespace still sees a public IP
- [ ] Throughout the lab: `curl` from the Codespace returns `403 AuthorizationFailure`
- [ ] After configuring the private path: port 445 from the VM succeeds and `curl` returns `401`

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| VM still resolves to a public IP | Check the DNS zone is linked to the **spoke VNet too** (`az network private-dns link vnet list -g $RG -z $DNS_ZONE -o table`) and the dns-zone-group exists. Retry after 1–2 min |
| Codespace returns 401 | Check Module 0's `publicNetworkAccess=Disabled` and `defaultAction=Deny`. Do not enable public access for comparison |
| Port 445 fails from the VM | Make sure the Module 1 peering is `Connected` |

➡️ Next: [Module 3. Azure Files](03-azure-files.md)
