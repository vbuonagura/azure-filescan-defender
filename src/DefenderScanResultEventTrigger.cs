// Default URL for triggering event grid function in the local environment.
// http://localhost:7071/runtime/webhooks/EventGrid?functionName={functionname}
using System;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.EventGrid;
using Microsoft.Extensions.Logging;
using Azure;
using Azure.Identity;
using Azure.Messaging.EventGrid;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using System.Text.Json;
using System.Threading.Tasks;
using Vbu.Models;

namespace Vbu.DefenderScanResultEventTrigger
{
    public static class DefenderScanResultEventTrigger
    {
        private const string AntimalwareScanEventType = "Microsoft.Security.MalwareScanningResult";
        private const string MaliciousVerdict = "Malicious";

        [FunctionName("DefenderScanResultEventTrigger")]
        public static async Task RunAsync([EventGridTrigger] EventGridEvent eventGridEvent, ILogger log)
        {
            if (eventGridEvent.EventType != AntimalwareScanEventType)
            {
                log.LogInformation("Event type is not an {0} event, event type:{1}", AntimalwareScanEventType, eventGridEvent.EventType);
                return;
            }

            var storageAccountName = eventGridEvent?.Subject?.Split("/")[^1];
            log.LogInformation("Received new scan result for storage {0}", storageAccountName);
            
            var decodedEventData = JsonDocument.Parse(eventGridEvent.Data).RootElement.ToString();
            var eventData = JsonDocument.Parse(decodedEventData).RootElement;
            var verdict = eventData.GetProperty("scanResultType").GetString();
            var blobUriString = eventData.GetProperty("blobUri").GetString();

            if (blobUriString.Contains("result-dlq")) {
                log.LogInformation("No need to scan DLQ file event");
                return;
            }

            if (verdict == null || blobUriString == null)
            {
                log.LogError("Event data doesn't contain 'verdict' or 'blobUri' fields");
                throw new ArgumentException("Event data doesn't contain 'verdict' or 'blobUri' fields");
            }

            string storageConnection = Environment.GetEnvironmentVariable("StorageConnectionString");
            string containerName = Environment.GetEnvironmentVariable("ContainerName");
            string connection = Environment.GetEnvironmentVariable("ServiceBusConnectionString__fullyQualifiedNamespace");
            
            var blobUri = new Uri(blobUriString);
            var blobUriBuilder = new BlobUriBuilder(blobUri);

            var containerClient = new BlobContainerClient(new Uri($"{storageConnection}/{containerName}"), new DefaultAzureCredential());
            var blobClient = containerClient.GetBlobClient(blobUriBuilder.BlobName);

            Response<BlobProperties> blobProperties = await blobClient.GetPropertiesAsync();
            
            //Reading blob metadata
            var metadata = blobProperties.Value.Metadata;
            if (!metadata.TryGetValue("sourceSystem", out string sourceSystem))
                sourceSystem = "";

            if (!metadata.TryGetValue("destinationSystem", out string destinationSystem))
                destinationSystem = "";

            if (!metadata.TryGetValue("internalId", out string internalId))
                internalId = "";

            if (verdict == MaliciousVerdict) {
                var rejectedMessage = new DocumentProcessingMessage() {
                    SourceSystem = sourceSystem,
                    InternalId = internalId,
                    DestinationSystem = destinationSystem,
                    Status = "Failed",
                    Reason = "Malware Detected. File has been deleted!"
                };

                string rejectedTopic = Environment.GetEnvironmentVariable("DocumentRejectedTopic");
                await rejectedMessage.SendToServiceBus(rejectedTopic);

                await blobClient.DeleteAsync();

                return;
            }            

            var message = new DocumentProcessingMessage() {
                SourceSystem = sourceSystem,
                InternalId = internalId,
                DestinationSystem = destinationSystem,
                Uri = blobUriString,
                Status = "ToBeStored",
                Reason = "No threats detected. File ready to be stored!"
            };

            string topic = Environment.GetEnvironmentVariable("DocumentToBeStoredTopic");
            await message.SendToServiceBus(topic);

            log.LogInformation("File successfully sent");

        }

    }
}
