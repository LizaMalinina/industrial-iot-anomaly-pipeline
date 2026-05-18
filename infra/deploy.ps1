[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [string]$Location = 'westeurope',

    [string]$TemplateFile = (Join-Path $PSScriptRoot 'main.bicep'),

    [string]$ParameterFile = (Join-Path $PSScriptRoot 'parameters.dev.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required to deploy this template.'
}

Write-Host "Validating Azure login context..."
az account show --output none

$resourceGroupExists = az group exists --name $ResourceGroupName --output tsv
if ($resourceGroupExists -ne 'true') {
    Write-Host "Creating resource group $ResourceGroupName in $Location..."
    az group create --name $ResourceGroupName --location $Location --output none | Out-Null
}

$deploymentName = "iiot-infra-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "Deploying $TemplateFile with parameters from $ParameterFile..."
$outputsJson = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroupName `
    --template-file $TemplateFile `
    --parameters "@$ParameterFile" location=$Location `
    --query properties.outputs `
    --output json

Write-Host 'Deployment outputs:'
$outputsJson | ConvertFrom-Json | ConvertTo-Json -Depth 10
