variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  default     = "rg-malware-insp-solution"
}

variable "location" {
  description = "Azure Region"
  default     = "Switzerland North"
}

variable "function_app_name" {
  description = "Name of the Function App"
  default     = "va-malw-insp-app"
}

variable "storage_account_name" {
  description = "Name of the Storage Account"
  default     = "vastmalwareinsp"
}

variable "storage_doc_container_name" {
  description = "Name of the Storage Container for the documents"
  default     = "va-doc"
}

variable "storage_scan_result_dlq_container_name" {
  description = "Name of the Storage Container for the scan result dlq"
  default     = "va-scan-result-dlq"
}

variable "event_grid_topic_name" {
  description = "Name of the Event Grid Topic"
  default     = "va-malware-scan-events"
}

variable "servicebus_namespace" {
  description = "Name of the ServiceBus Namespace"
  default     = "va-sb-inspection-app"
}

variable "servicebus_topic_doc_processed" {
  description = "Name of the topic for document processed"
  default     = "document-processed"
}

variable "servicebus_topic_doc_rejected" {
  description = "Name of the topic for document rejected"
  default     = "document-rejected"
}

variable "servicebus_topic_doc_tobe_stored" {
  description = "Name of the topic for document to be stored"
  default     = "document-tobe-stored"
}

variable "servicebus_subscription_document_tostore" {
  description = "Name of the subscription for document to be stored"
  default     = "document-sub"
}

variable "app_insights_name" {
  description = "Name of Application Insights"
  default     = "va-inspection-app-insights"
}