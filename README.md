# 🌐 Hub-Spoke Architecture Setup

This document provides the steps to set up a hub-spoke architecture with various Azure resources using Azure CLI commands.

## 📋 Prerequisites

Install the necessary tooling and prerequisites:

```sh
# Login to Azure
az login

# Upgrade Azure CLI
az upgrade

# Add the required Azure CLI extension
az extension add --name containerapp --upgrade
az extension add --name azure-firewall --upgrade

# Register necessary providers
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

## 🌍 Default Location

Set the default location to `swedencentral`:

```sh
az configure --defaults location=swedencentral
```

Store the subscription in a variable:
```sh
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## 🚀 Running the Script

You can run all the necessary commands by executing the `scripts.sh` file:

```sh
bash scripts.sh
```

## 🏗️ Resource Group

Create a resource group named `rg-hub-spoke-poc`:

```sh
az group create --name rg-hub-spoke-poc
```

## 🌐 Virtual Networks

Create a virtual network for the hub section named `vnet-hub`:

```sh
az network vnet create --resource-group rg-hub-spoke-poc --name vnet-hub --address-prefix 10.0.0.0/16 --subnet-name default --subnet-prefix 10.0.1.0/24
```

Create a virtual network for the spoke section named `vnet-spoke`:

```sh
az network vnet create --resource-group rg-hub-spoke-poc --name vnet-spoke --address-prefix 10.1.0.0/16 --subnet-name default --subnet-prefix 10.1.1.0/24
```

Delegate the `default` subnet of `vnet-spoke` to the `Microsoft.App/environments` service:
```sh
az network vnet subnet update --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name default --delegations Microsoft.App/environments
```

Create a subnet for postgres named `psql-subnet`
```sh 
az network vnet subnet create --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name psql-subnet --address-prefix 10.1.2.0/24
```

Create a subnet for storage account named `sa-subnet`
```sh 
az network vnet subnet create --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name sa-subnet --address-prefix 10.1.3.0/24
az network vnet subnet update --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name sa-subnet --service-endpoints Microsoft.Storage
```

## 🔥 Azure Firewall

Create an Azure Firewall of Standard SKU named `afw-hub`:

```sh
az network firewall create --resource-group rg-hub-spoke-poc --name afw-hub --vnet-name vnet-hub
```

## 📊 Log Analytics Workspace

Create a log analytics workspace named `log-spoke`:

```sh
az monitor log-analytics workspace create --resource-group rg-hub-spoke-poc --workspace-name log-spoke
```

Store the log analytics workspace key in a variable:

```sh
LOGS_KEY=$(az monitor log-analytics workspace get-shared-keys --resource-group rg-hub-spoke-poc --workspace-name log-spoke --query primarySharedKey -o tsv)
```

Store the log analytics workspace id in a variable:

```sh
LOGS_ID=$(az monitor log-analytics workspace show --resource-group rg-hub-spoke-poc --workspace-name log-spoke --query customerId -o tsv)
```

## 🛠️ Container App Environment

Create a container app environment using `vnet-spoke` named `cae-spoke`:

```sh
az containerapp env create --name cae-spoke --resource-group rg-hub-spoke-poc --logs-workspace-id "$LOGS_ID" --logs-workspace-key "$LOGS_KEY" --internal-only true --infrastructure-subnet-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-hub-spoke-poc/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/default"
```

## 📦 Container App

Create a container app using `cae-spoke` which is using a quick start image and is inaccessible externally named `ca-spoke`:

```sh
az containerapp create --name ca-spoke --resource-group rg-hub-spoke-poc --environment cae-spoke --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest --ingress 'internal'
```

## 🗄️ PostgreSQL Server

Create a PostgreSQL server with the lowest SKU which is publicly inaccessible inside `vnet-spoke` and named `psql-spoke`:

```sh
az postgres flexible-server create --resource-group rg-hub-spoke-poc --name psql-spoke --sku-name Standard_B1ms --tier Burstable --admin-user pgadmin --admin-password myS@fePa33word --vnet vnet-spoke --subnet psql-subnet
```

## 💾 Storage Account

Create a storage account gen2 which is publicly inaccessible inside `vnet-spoke` and named `saspoke123456789`:

```sh
az storage account create --name saspoke123456789 --resource-group rg-hub-spoke-poc --sku Standard_LRS --kind StorageV2 --vnet-name vnet-spoke --subnet sa-subnet --public-network-access Disabled
```

## 🔒 Private Endpoints

Create a private endpoint between `ca-spoke` and `sa-spoke`:

```sh
az network private-endpoint create --name pe-ca-sa --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --subnet sa-subnet --private-connection-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-hub-spoke-poc/providers/Microsoft.Storage/storageAccounts/saspoke123456789" --group-id blob --connection-name pe-ca-sa-connection
```

## 🔗 VNet Peering

Create VNet peering between `vnet-hub` and `vnet-spoke`:

```sh
az network vnet peering create --name hub-to-spoke --resource-group rg-hub-spoke-poc --vnet-name vnet-hub --remote-vnet vnet-spoke --allow-vnet-access
az network vnet peering create --name spoke-to-hub --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --remote-vnet vnet-hub --allow-vnet-access
```

## 🌐 DNS Configuration

Map the DNS name of `afw-hub` to a custom subdomain name under `contoso.com`:

```sh
az network private-dns zone create --resource-group rg-hub-spoke-poc --name contoso.com
az network private-dns record-set a create --resource-group rg-hub-spoke-poc --zone-name contoso.com --name afw-hub
az network private-dns record-set a add-record --resource-group rg-hub-spoke-poc --zone-name contoso.com --record-set-name afw-hub --ipv4-address <afw-hub-ip-address>
```

## 🌐 Container App Endpoints
### 1️⃣ Single App Deployed to a Container App
#### With Public Ingress:
**Accessibility:** The app is accessible over the internet via a public endpoint.

**Access Methods:**
- **IP Address:** The app can be accessed using its public IP address.
- **FQDN:** The app is accessible via a fully qualified domain name (FQDN) like 
  - myapp.happyhill-70162bb9.canadacentral.azurecontainerapps.io
- **Port:** The app listens on specified ports for HTTP or TCP traffic.

#### Without Public Ingress:
**Accessibility:** The app is only accessible internally within the Azure environment.

**Access Methods:**
- **App Name:** The app can be accessed internally using its name, e.g.
  - http://<APP_NAME>
- **FQDN:** The app is accessible via an internal FQDN within the Azure environment.
- **Port:** The app listens on specified ports for internal HTTP or TCP traffic.

### 🔢 Multiple Apps Deployed to a Container App

#### With Public Ingress:
**Accessibility:** All apps are accessible over the internet via their respective public endpoints.

**Access Methods:**
- **IP Address:** Each app can be accessed using its public IP address.
- **FQDN:** Each app is accessible via its own FQDN, e.g., 
  - app1.happyhill-70162bb9.canadacentral.azurecontainerapps.io
  - app2.happyhill-70162bb9.canadacentral.azurecontainerapps.io
- **Port:** Each app listens on specified ports for HTTP or TCP traffic.

#### Without Public Ingress:
**Accessibility:** All apps are only accessible internally within the Azure environment.

**Access Methods:**
- **App Name:** Each app can be accessed internally using its name, e.g.
  - http://<APP_NAME>
- **FQDN:** Each app is accessible via an internal FQDN within the Azure environment.
- **Port:** Each app listens on specified ports for internal HTTP or TCP traffic.


## 🔗 References

- [Hub-spoke network topology in Azure](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke)
- [Ingress in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Configure Ingress for your app in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to?pivots=azure-cli)
- [Connect applications in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/connect-apps?tabs=bash)
- [Custom VNet configuration in Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/networking?tabs=workload-profiles-env%2Cazure-cli#custom-vnet-configuration)
- [Azure Database for PostgreSQL flexible server networking with Private Link](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking-private-link#private-endpoints)
- [Blue-Green Deployment in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/blue-green-deployment?pivots=azure-cli)
