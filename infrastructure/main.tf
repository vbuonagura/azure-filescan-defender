data "azurerm_client_config" "current" {}

resource "null_resource" "build_package" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    working_dir   = "../src"
    command       = "dotnet publish -o zip-package"
  }
}

resource "null_resource" "compress_package" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    working_dir   = "../src"
    command       = "Compress-Archive ./zip-package/* package.zip -Force"
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [
    null_resource.build_package
  ]
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  depends_on = [
    null_resource.compress_package
  ]
}

# Storage Account for Documents
resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  identity {
    type = "SystemAssigned"
  }

}

# Storage Container - va-doc
resource "azurerm_storage_container" "va_doc_container" {
  name                  = var.storage_doc_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# Storage Container - va-scan-result-dlq
resource "azurerm_storage_container" "va_scan_result_dlq_container" {
  name                  = var.storage_scan_result_dlq_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# Service Bus Namespace
resource "azurerm_servicebus_namespace" "servicebus" {
  name                = var.servicebus_namespace
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
}

# Service Bus Topic - Document Processed
resource "azurerm_servicebus_topic" "document_processed_topic" {
  name                = var.servicebus_topic_doc_processed
  namespace_id      = azurerm_servicebus_namespace.servicebus.id
}

# Service Bus Subscription - Sub to Document Processed Topic
resource "azurerm_servicebus_subscription" "document_processed_subscription" {
  name                       = "app-sub"
  topic_id                   = azurerm_servicebus_topic.document_processed_topic.id
  max_delivery_count         = 5
  auto_delete_on_idle        = "PT5M"
}

# Service Bus Topic - Document Rejected
resource "azurerm_servicebus_topic" "document_rejected_topic" {
  name                = var.servicebus_topic_doc_rejected
  namespace_id      = azurerm_servicebus_namespace.servicebus.id
}

# Service Bus Subscription - Sub to Document Rejected Topic
resource "azurerm_servicebus_subscription" "document_rejected_subscription" {
  name                       = "app-sub"
  topic_id                   = azurerm_servicebus_topic.document_rejected_topic.id
  max_delivery_count         = 5
  auto_delete_on_idle        = "PT5M"
}

# Service Bus Topic - Document To Be Stored
resource "azurerm_servicebus_topic" "document_to_be_stored_topic" {
  name                = var.servicebus_topic_doc_tobe_stored
  namespace_id        = azurerm_servicebus_namespace.servicebus.id
}

# Service Bus Subscription - Sub to Document To Be Stored Topic
resource "azurerm_servicebus_subscription" "document_tobe_stored_subscription" {
  name                       = var.servicebus_subscription_document_tostore
  topic_id                   = azurerm_servicebus_topic.document_to_be_stored_topic.id
  max_delivery_count         = 5
  auto_delete_on_idle        = "PT5M"
}

# Application Insights
resource "azurerm_application_insights" "app_insights" {
  name                = var.app_insights_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  application_type    = "web"
}

resource "random_id" "storage_account_app" {
  byte_length = 8
}

# Storage Account for Function App
resource "azurerm_storage_account" "storage_app" {
  name                     = "sta${lower(random_id.storage_account_app.hex)}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# App Service Plan
resource "azurerm_service_plan" "service_plan" {
  name                = "va-inspectionapp-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Windows"
  sku_name            = "Y1"
}

# Windows Function App
resource "azurerm_windows_function_app" "function_app" {
  name                          = var.function_app_name
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  service_plan_id               = azurerm_service_plan.service_plan.id
  storage_account_name          = azurerm_storage_account.storage_app.name
  storage_account_access_key    = azurerm_storage_account.storage_app.primary_access_key
  zip_deploy_file               = "../src/package.zip"
  https_only                    = true

  site_config {
    application_stack {
      dotnet_version = "v4.0"
    }
  }

  app_settings = {
    "ContainerName"                                             = var.storage_doc_container_name,
    "DocumentProcessedTopic"                                    = var.servicebus_topic_doc_processed,
    "DocumentRejectedTopic"                                     = var.servicebus_topic_doc_rejected,
    "DocumentToBeStoredSubscription"                            = var.servicebus_subscription_document_tostore,
    "DocumentToBeStoredTopic"                                   = var.servicebus_topic_doc_tobe_stored,
    "ServiceBusConnectionString__fullyQualifiedNamespace"       = "${azurerm_servicebus_namespace.servicebus.name}.servicebus.windows.net",
    "StorageConnectionString"                                   = "https://${var.storage_account_name}.blob.core.windows.net",
    "APPINSIGHTS_INSTRUMENTATIONKEY"                            = azurerm_application_insights.app_insights.instrumentation_key,
    "FUNCTIONS_WORKER_RUNTIME"                                  = "dotnet",
    "WEBSITE_RUN_FROM_PACKAGE"                                  = 1
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_storage_account.storage,
    azurerm_servicebus_namespace.servicebus
  ]
}

# Assign roles for Storage Account
resource "azurerm_role_assignment" "storage_account_role_assignment" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"  
  principal_id         = azurerm_windows_function_app.function_app.identity[0].principal_id
}

# Assign roles for Service Bus
resource "azurerm_role_assignment" "service_bus_receiver_role_assignment" {
  scope                = azurerm_servicebus_namespace.servicebus.id
  role_definition_name = "Azure Service Bus Data Receiver"  
  principal_id         = azurerm_windows_function_app.function_app.identity[0].principal_id
}

resource "azurerm_role_assignment" "service_bus_sender_role_assignment" {
  scope                = azurerm_servicebus_namespace.servicebus.id
  role_definition_name = "Azure Service Bus Data Sender"  
  principal_id         = azurerm_windows_function_app.function_app.identity[0].principal_id
}

# Event Grid Topic
resource "azurerm_eventgrid_topic" "event_grid_topic" {
  name                = var.event_grid_topic_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# Event Grid Topic Subscription for Azure Function
resource "azurerm_eventgrid_event_subscription" "function_app_subscription" {
  name                  = "response-to-microsoft-defender"
  scope                 = azurerm_eventgrid_topic.event_grid_topic.id
  included_event_types  = [
    "Microsoft.Security.MalwareScanningResult"
  ]
  
  azure_function_endpoint {
    function_id             = "${azurerm_windows_function_app.function_app.id}/functions/DefenderScanResultEventTrigger"
    max_events_per_batch    = 1
  }

  storage_blob_dead_letter_destination {
    storage_account_id  = azurerm_storage_account.storage.id
    storage_blob_container_name = azurerm_storage_container.va_scan_result_dlq_container.name
  }

  retry_policy {
    max_delivery_attempts    = 3
    event_time_to_live       = 5
  }
}

#Microsoft Defender
resource "azapi_update_resource" "enable_defender" {
  name        = "current"
  type        = "Microsoft.Security/DefenderForStorageSettings@2022-12-01-preview"
  parent_id   = azurerm_storage_account.storage.id

  body = jsonencode({
    properties = { 
        isEnabled = true, 
        malwareScanning = { 
            onUpload = { 
                isEnabled = true, 
                capGBPerMonth = 10 
            }, 
            scanResultsEventGridTopicResourceId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg.name}/providers/Microsoft.EventGrid/topics/${azurerm_eventgrid_topic.event_grid_topic.name}" 
        }, 
        sensitiveDataDiscovery = { 
            isEnabled = true 
        }, 
        overrideSubscriptionLevelSettings = true 
    } 
  })

  depends_on = [
    azurerm_storage_account.storage,
    azurerm_eventgrid_topic.event_grid_topic
  ]
}