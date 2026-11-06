# Module 1. VNet peering (~15 min)

🌐 [한국어](../ko/01-vnet-peering.md) | **English**  ·  [← Home](../../README.en.md)

## 🎯 Goal

Connect the isolated hub and spoke VNets with **peering** and verify private-IP connectivity.

> 🧠 **What is VNet peering?** It links two VNets directly over the Microsoft backbone. Traffic uses **private IPs and never crosses the internet**. You must create it in **both directions** for it to become `Connected`. The two address spaces **must not overlap** (here 10.0.0.0/16 ↔ 10.1.0.0/16).

## 📝 Steps

```bash
source scripts/env.sh
```

### 1. Before peering: confirm there's no connectivity

Get both VMs' private IPs.

```bash
HUB_IP=$(az vm show -d -g $RG -n $VM_HUB --query privateIps -o tsv)
SPOKE_IP=$(az vm show -d -g $RG -n $VM_SPOKE --query privateIps -o tsv)
echo "hub=$HUB_IP  spoke=$SPOKE_IP"
```

Ping the hub VM from the spoke VM.

```bash
scripts/vm-exec.sh $VM_SPOKE "ping -c 3 -W 2 $HUB_IP"
```

👉 You'll see `100% packet loss` — the VNets aren't connected.

### 2. Create the peering (both directions)

```bash
# spoke → hub
az network vnet peering create -g $RG -n spoke-to-hub \
  --vnet-name $SPOKE_VNET --remote-vnet $HUB_VNET \
  --allow-vnet-access -o none

# hub → spoke
az network vnet peering create -g $RG -n hub-to-spoke \
  --vnet-name $HUB_VNET --remote-vnet $SPOKE_VNET \
  --allow-vnet-access -o none
```

### 3. Check the state

```bash
az network vnet peering list -g $RG --vnet-name $SPOKE_VNET \
  --query "[].{Name:name, State:peeringState, Remote:remoteVirtualNetwork.id}" -o table
```

👉 `State` must be **Connected**. (`Initiated` means the opposite direction is missing.)

### 4. After peering: connectivity test

> ⏱️ Even once `Connected`, route propagation can take **30 s – 1 min**. If the first ping fails, wait a bit and rerun.

```bash
sleep 30
scripts/vm-exec.sh $VM_SPOKE "ping -c 3 -W 2 $HUB_IP"
scripts/vm-exec.sh $VM_HUB   "ping -c 3 -W 2 $SPOKE_IP"
```

👉 Now you get replies with `0% packet loss`. 🎉

### 5. (Optional) See the routing

Once peered, the hub's address range is added automatically to the spoke NIC's effective routes.

```bash
az network nic show-effective-route-table -g $RG -n nic-vm-spoke \
  --query "value[?nextHopType=='VNetPeering' || nextHopType=='VnetLocal'].{Prefix:addressPrefix[0], NextHop:nextHopType}" -o table
```

Look for `10.0.0.0/16` with next hop `VNetPeering`.

## ✅ Checklist

- [ ] 100% loss before peering
- [ ] Both peerings `Connected`
- [ ] Ping works in both directions after peering

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| State is `Initiated` | Make sure you created the other direction (`hub-to-spoke`) |
| Ping still fails after peering | Wait about a minute and retry (route propagation delay). Make sure `HUB_IP`/`SPOKE_IP` aren't empty (`echo $HUB_IP`) |
| `AddressSpaceOverlap` | The VNet address spaces overlap. The lab defaults don't |

➡️ Next: [Module 2. Private Endpoint](02-private-endpoint.md)
