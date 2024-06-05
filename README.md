# Introduction
This repository contains the code (source + infrastructure) to deploy a serverless antimalware detection solution on Azure as described in the diagram below
![Solution](archi_solution.PNG?raw=true "Solution Architecture")

## Installation
The following are the steps needed to deploy the solution:
- Set the Terraform environment variables as described [here](https://developer.hashicorp.com/terraform/tutorials/azure-get-started/azure-build#set-your-environment-variables)
- Go to "infrastructure" folder
- Run 
```bash
terraform init
```
- Run
```bash
terraform plan
```
- Run 
```bash
terraform apply -auto-approve
```
- Once the infrastructure is deployed, open the Azure tab in VS Code and deploy the code on the function app deployed by Terraform inside the resource group name defined in the variables.tf file

## Test
In order to test the malware detection from Microsoft Defender, go to the Azure Portal, access the va-doc container in the and upload a txt file containing the eicar string
as documented in the <a href="https://www.eicar.org/download-anti-malware-testfile/" target="_blank">official website</a>.
Once uploaded, the file will be deleted after few seconds (by the DefenderScanResultEventTrigger function).