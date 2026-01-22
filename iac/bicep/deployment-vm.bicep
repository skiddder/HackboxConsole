@description('Name of the virtual machine')
@minLength(3)
@maxLength(15)
param virtualMachineName string

@description('Admin username for the VM')
@minLength(3)
@maxLength(15)
param adminUsername string = 'hackboxuser'

@secure()
@description('Admin password for the VM')
param adminPassword string

@description('Full resource ID of the subnet (e.g., /subscriptions/.../subnets/uservms)')
param virtualNetworkSubnetId string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Size of the virtual machine')
param virtualMachineSize string = 'Standard_D4s_v5'

@description('OS disk type')
param osDiskType string = 'StandardSSD_LRS'

@description('Use Windows 11 BYOL (Bring Your Own License)')
param windowsByol bool = false

@description('User that owns the VM')
param vmOwnerTag string = ''

// Network Interface
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${virtualMachineName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: virtualNetworkSubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    enableAcceleratedNetworking: true
  }
}

// Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: virtualMachineName
  location: location
  tags: {
    HackboxVMOwner: vmOwnerTag
  }
  properties: {
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'microsoftwindowsdesktop'
        offer: 'windows-11'
        sku: 'win11-25h2-pro'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    osProfile: {
      computerName: take(virtualMachineName, 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    licenseType: windowsByol ? 'Windows_Client' : null
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// Outputs
output vmName string = virtualMachine.name
output privateIpAddress string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
