@minLength(5)
@maxLength(50)
@description('Globally unique name for the Azure Container Registry (ACR).')
param acrName string = toLower('acr${uniqueString(resourceGroup().id)}')
@description('The location for all resources.')
param location string = resourceGroup().location // Location for all resources

// git ls-remote --tags https://github.com/qxsch/freerdp-web.git v3.6.1
@description('Git branch to build from (ACR Tasks only supports branches or commit hashes).')
param gitBranch string = 'main'

@description('Memory allocation for Container App. vCPUs are automatically calculated based on Azure Container Apps Consumption tier allowed combinations.')
@allowed([
  '0.5Gi'
  '1.0Gi'
  '1.5Gi'
  '2.0Gi'
  '2.5Gi'
  '3.0Gi'
  '3.5Gi'
  '4.0Gi'
  '6.0Gi'
  '8.0Gi'
])
param containerMemory string = '4.0Gi'

@description('Maximum concurrent HTTP requests per replica before scaling out.')
@minValue(1)
@maxValue(200)
param concurrentRequests int = 20

@description('Minimum number of replicas for the Container App.')
@minValue(0)
@maxValue(30)
param minReplicas int = 1

@description('Maximum number of replicas for the Container App.')
@minValue(1)
@maxValue(30)
param maxReplicas int = 10

// Memory to vCPU mapping based on Azure Container Apps Consumption tier allowed combinations
var memoryToCpuMap = {
  '0.5Gi': '0.25'
  '1.0Gi': '0.5'
  '1.5Gi': '0.75'
  '2.0Gi': '1.0'
  '2.5Gi': '1.25'
  '3.0Gi': '1.5'
  '3.5Gi': '1.75'
  '4.0Gi': '2.0'
  '6.0Gi': '3.0'
  '8.0Gi': '4.0'
}
var containerCpu = memoryToCpuMap[containerMemory]

@description('Image repository name inside ACR.')
var imageRepo = 'freerdpweb-backend'

@description('Image tag (e.g., latest, v3.6.1). Override to build a specific version.')
var imageTag = 'latest'

// ACR Tasks only supports branches, not tags in #ref:context syntax
var sourceLocation = 'https://github.com/qxsch/freerdp-web.git#${gitBranch}:backend'
var imageFullName = '${acr.properties.loginServer}/${imageRepo}:${imageTag}'
// Networking - ACA vnet integration range
var rdpBackendCidr = '10.1.0.0/23'
// Networking - VM range ~1020 adresses
var userVmsCidr = '10.1.252.0/22'


// add a vnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'rdp-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        rdpBackendCidr
        userVmsCidr
      ]
    }
    subnets: [
      {
        name: 'rdpbackend'
        properties: {
          addressPrefix: rdpBackendCidr
          delegations: [
            {
              name: 'containerApps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          serviceEndpoints: [
          ]
        }
      }
      {
        name: 'uservms'
        properties: {
          addressPrefix: userVmsCidr
          delegations: [
          ]
          serviceEndpoints: [
          ]
        }
      }
    ]
  }
}       


resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource buildPushRun 'Microsoft.ContainerRegistry/registries/taskRuns@2019-06-01-preview' = {
  name: 'buildpush-${uniqueString(resourceGroup().id, imageRepo, imageTag)}'
  parent: acr
  location: location
  properties: {
    runRequest: {
      type: 'DockerBuildRequest'
      isArchiveEnabled: true

      // git URL with ref (branch or tag) and context
      sourceLocation: sourceLocation

      // Dockerfile path (differs for branch vs tarball)
      dockerFilePath: 'Dockerfile'
      imageNames: [
        imageFullName
      ]
      isPushEnabled: true
      noCache: false

      // Platform configuration for Linux container
      platform: {
        os: 'Linux'
        architecture: 'amd64'
      }

      // Timeout in seconds (backend build can take a while due to FreeRDP compilation)
      timeout: 3600
    }
  }
}

// Azure Container Apps Environment integrated into the VNet
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'rdp-container-env'
  location: location
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: vnet.properties.subnets[0].id
      internal: false
    }
    zoneRedundant: false
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// User-assigned managed identity for ACR pull
resource acaPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'aca-acr-pull-identity'
  location: location
}

// Role assignment for ACR pull (AcrPull role)
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acaPullIdentity.id, 'acrpull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: acaPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Container App with external ingress, HTTP autoscaling, and configurable resources
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'rdp-gateway-app'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acaPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8765
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: acaPullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'freerdp-web'
          image: imageFullName
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
          env: [
            {
              name: 'SECURITY_ALLOWED_IPV4_CIDRS'
              value: userVmsCidr
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: string(concurrentRequests)
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    buildPushRun
    acrPullRoleAssignment
  ]
}



output acrLoginServer string = acr.properties.loginServer
output imagePushed string = imageFullName
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerCpuAllocated string = containerCpu
output containerMemoryAllocated string = containerMemory
output vmSubnetId string = vnet.properties.subnets[1].id
