# 모듈 1. VNet 피어링 (약 15분)

🌐 **한국어** | [English](../en/01-vnet-peering.md)  ·  [← 처음으로](../../README.md)

## 🎯 목표

서로 격리된 허브·스포크 VNet을 **피어링**으로 연결하고, 사설 IP로 통신이 되는지 확인합니다.

> 🧠 **VNet 피어링이란?** 두 VNet을 Microsoft 백본 네트워크로 직접 연결합니다. 인터넷을 거치지 않고 **사설 IP로 통신**하며, **양방향 모두** 만들어야 `Connected` 상태가 됩니다. 두 VNet의 주소 공간은 **겹치면 안 됩니다** (여기서는 10.0.0.0/16 ↔ 10.1.0.0/16).

## 📝 실습

```bash
source scripts/env.sh
```

### 1. 피어링 전: 통신이 안 되는지 확인

두 VM의 사설 IP를 조회합니다.

```bash
HUB_IP=$(az vm show -d -g $RG -n $VM_HUB --query privateIps -o tsv)
SPOKE_IP=$(az vm show -d -g $RG -n $VM_SPOKE --query privateIps -o tsv)
echo "hub=$HUB_IP  spoke=$SPOKE_IP"
```

스포크 VM에서 허브 VM으로 ping을 보냅니다.

```bash
scripts/vm-exec.sh $VM_SPOKE "ping -c 3 -W 2 $HUB_IP"
```

👉 `100% packet loss` 가 나옵니다. VNet이 서로 연결되어 있지 않기 때문입니다.

이 단계의 종료 코드 `1`은 예상된 ping 실패입니다. 이후의 피어링 후 테스트는 종료 코드 `0`이어야 합니다.

### 2. 피어링 생성 (양방향)

```bash
# 스포크 → 허브
az network vnet peering create -g $RG -n spoke-to-hub \
  --vnet-name $SPOKE_VNET --remote-vnet $HUB_VNET \
  --allow-vnet-access -o none

# 허브 → 스포크
az network vnet peering create -g $RG -n hub-to-spoke \
  --vnet-name $HUB_VNET --remote-vnet $SPOKE_VNET \
  --allow-vnet-access -o none
```

### 3. 상태 확인

```bash
az network vnet peering list -g $RG --vnet-name $SPOKE_VNET \
  --query "[].{Name:name, State:peeringState, Remote:remoteVirtualNetwork.id}" -o table
```

👉 `State`가 **Connected** 여야 합니다. (`Initiated` 이면 반대 방향 피어링이 없는 것입니다)

### 4. 피어링 후: 연결 테스트

> ⏱️ 피어링이 `Connected` 가 된 뒤에도 경로 전파에 **30초~1분** 걸릴 수 있습니다. 첫 ping이 실패하면 잠시 후 다시 실행하세요.

```bash
sleep 30
scripts/vm-exec.sh $VM_SPOKE "ping -c 3 -W 2 $HUB_IP"
scripts/vm-exec.sh $VM_HUB   "ping -c 3 -W 2 $SPOKE_IP"
```

👉 이번에는 `0% packet loss` 로 응답이 옵니다. 🎉

### 5. (선택) 라우팅 눈으로 확인

피어링이 만들어지면 스포크 NIC의 유효 경로에 허브 주소 대역이 자동으로 추가됩니다.

```bash
az network nic show-effective-route-table -g $RG -n nic-vm-spoke \
  --query "value[?nextHopType=='VNetPeering' || nextHopType=='VnetLocal'].{Prefix:addressPrefix[0], NextHop:nextHopType}" -o table
```

다음 홉이 `VNetPeering` 인 `10.0.0.0/16` 이 보이면 됩니다.

## ✅ 확인 체크리스트

- [ ] 피어링 전 ping 100% 손실
- [ ] 양쪽 피어링 상태 `Connected`
- [ ] 피어링 후 양방향 ping 성공

## 🛠️ 문제 해결

| 증상 | 해결 |
|---|---|
| 상태가 `Initiated` | 반대 방향(`hub-to-spoke`)을 만들었는지 확인 |
| 피어링 후에도 ping 실패 | 1분 정도 기다린 뒤 재시도 (경로 전파 지연). `HUB_IP`/`SPOKE_IP` 변수가 비어 있지 않은지 확인 (`echo $HUB_IP`) |
| `AddressSpaceOverlap` | 두 VNet 주소 공간이 겹치는 경우. 이 랩 기본값은 겹치지 않습니다 |

➡️ 다음: [모듈 2. Private Endpoint](02-private-endpoint.md)
