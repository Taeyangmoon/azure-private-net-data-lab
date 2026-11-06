// Module 0: 허브·스포크 VNet 2개, 테스트 VM 2대, 스토리지 계정
// 일부러 "피어링 / Private Endpoint / 사설 DNS / 백업"은 만들지 않습니다. 실습에서 직접 구성합니다.
targetScope = 'resourceGroup'

param location string = resourceGroup().location
param adminUsername string = 'azureuser'
@secure()
param sshPublicKey string
param vmSize string = 'Standard_B2s'

var hubVnetName = 'vnet-hub'
var spokeVnetName = 'vnet-spoke'
var storageName = 'stpvtlab${uniqueString(resourceGroup().id)}'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-lab'
  location: location
  // 사용자 지정 규칙 없음: 기본 규칙만으로 인터넷 인바운드는 거부, VNet 내부 통신은 허용
}

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: hubVnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'snet-pe'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
      {
        name: 'snet-vm'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: { id: nsg.id }
          // 실습용: 패키지 설치(apt)를 위해 기본 아웃바운드 허용. 운영에서는 NAT Gateway 사용 권장
          defaultOutboundAccess: true
        }
      }
    ]
  }
}

resource spoke 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: spokeVnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.1.0.0/16'] }
    subnets: [
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: '10.1.1.0/24'
          networkSecurityGroup: { id: nsg.id }
          defaultOutboundAccess: true
        }
      }
    ]
  }
}

var vms = [
  { name: 'vm-hub', subnetId: '${hub.id}/subnets/snet-vm' }
  { name: 'vm-spoke', subnetId: '${spoke.id}/subnets/snet-workload' }
]

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for vm in vms: {
  name: 'nic-${vm.name}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: vm.subnetId }
        }
      }
    ]
  }
}]

resource virtualMachines 'Microsoft.Compute/virtualMachines@2024-07-01' = [for (vm, i) in vms: {
  name: vm.name
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vm.name
      adminUsername: adminUsername
      customData: base64(loadTextContent('cloud-init.yaml'))
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nics[i].id }]
    }
  }
}]

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    // 모듈 2에서 차단하기 전까지는 공용 인터넷에서 접근 가능한 상태 (비교용)
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

output storageAccountName string = storage.name
