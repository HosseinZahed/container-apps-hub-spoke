#!/bin/bash

# Set default location
az configure --defaults location=swedencentral

# Store subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create resource group
az group create --name rg-hub-spoke-poc

# Create virtual networks
az network vnet create --resource-group rg-hub-spoke-poc --name vnet-hub --address-prefix 10.0.0.0/16 --subnet-name default --subnet-prefix 10.0.1.0/24
az network vnet create --resource-group rg-hub-spoke-poc --name vnet-spoke --address-prefix 10.1.0.0/16 --subnet-name default --subnet-prefix 10.1.1.0/24

# Delegate subnet
az network vnet subnet update --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name default --delegations Microsoft.App/environments

# Create subnets
az network vnet subnet create --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name psql-subnet --address-prefix 10.1.2.0/24
az network vnet subnet create --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name sa-subnet --address-prefix 10.1.3.0/24
az network vnet subnet update --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --name sa-subnet --service-endpoints Microsoft.Storage

# Create Azure Firewall
az network firewall create --resource-group rg-hub-spoke-poc --name afw-hub --vnet-name vnet-hub

# Create Log Analytics Workspace
az monitor log-analytics workspace create --resource-group rg-hub-spoke-poc --workspace-name log-spoke

# Store Log Analytics Workspace keys
LOGS_KEY=$(az monitor log-analytics workspace get-shared-keys --resource-group rg-hub-spoke-poc --workspace-name log-spoke --query primarySharedKey -o tsv)
LOGS_ID=$(az monitor log-analytics workspace show --resource-group rg-hub-spoke-poc --workspace-name log-spoke --query customerId -o tsv)

# Create Container App Environment
az containerapp env create --name cae-spoke --resource-group rg-hub-spoke-poc --logs-workspace-id "$LOGS_ID" --logs-workspace-key "$LOGS_KEY" --internal-only true --infrastructure-subnet-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-hub-spoke-poc/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/default"

# Create Container App
az containerapp create --name ca-spoke --resource-group rg-hub-spoke-poc --environment cae-spoke --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest --ingress 'internal'

# Create PostgreSQL Server
az postgres flexible-server create --resource-group rg-hub-spoke-poc --name psql-spoke --sku-name Standard_B1ms --tier Burstable --admin-user pgadmin --admin-password myS@fePa33word --vnet vnet-spoke --subnet psql-subnet

# Create Storage Account
az storage account create --name saspoke123456789 --resource-group rg-hub-spoke-poc --sku Standard_LRS --kind StorageV2 --vnet-name vnet-spoke --subnet sa-subnet --public-network-access Disabled

# Create Private Endpoint
az network private-endpoint create --name pe-ca-sa --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --subnet sa-subnet --private-connection-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-hub-spoke-poc/providers/Microsoft.Storage/storageAccounts/saspoke123456789" --group-id blob --connection-name pe-ca-sa-connection

# Create VNet Peering
az network vnet peering create --name hub-to-spoke --resource-group rg-hub-spoke-poc --vnet-name vnet-hub --remote-vnet vnet-spoke --allow-vnet-access
az network vnet peering create --name spoke-to-hub --resource-group rg-hub-spoke-poc --vnet-name vnet-spoke --remote-vnet vnet-hub --allow-vnet-access

# Create DNS Configuration
az network private-dns zone create --resource-group rg-hub-spoke-poc --name contoso.com
az network private-dns record-set a create --resource-group rg-hub-spoke-poc --zone-name contoso.com --name afw-hub
# az network private-dns record-set a add-record --resource-group rg-hub-spoke-poc --zone-name contoso.com --record-set-name afw-hub --ipv4-address <afw-hub-ip-address>
