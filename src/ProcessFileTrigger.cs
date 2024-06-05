using System;
using System.Text.Json;
using System.Threading.Tasks;
using Azure.Storage.Blobs;
using Azure.Identity;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Vbu.Models;

namespace Vbu.ProcessFile
{
    public class ProcessFileTrigger
    {
        private readonly ILogger<ProcessFileTrigger> _logger;

        public ProcessFileTrigger(ILogger<ProcessFileTrigger> log)
        {
            _logger = log;
        }

        [FunctionName("ProcessFileTrigger")]
        public async Task Run([ServiceBusTrigger("%DocumentToBeStoredTopic%", "%DocumentToBeStoredSubscription%", Connection = "ServiceBusConnectionString")]string msg)
        {
            var receivedMessage = JsonSerializer.Deserialize<DocumentProcessingMessage>(msg);

            _logger.LogInformation($@"Start processing file 
                                {receivedMessage.Data} received");

            var blobUri = new Uri(receivedMessage.Uri);
            var blobUriBuilder = new BlobUriBuilder(blobUri);

            string storageConnection = Environment.GetEnvironmentVariable("StorageConnectionString");
            string containerName = Environment.GetEnvironmentVariable("ContainerName");

            var containerClient = new BlobContainerClient(new Uri($"{storageConnection}/{containerName}"), new DefaultAzureCredential());
            var blobClient = containerClient.GetBlobClient(blobUriBuilder.BlobName);

            //File can be downloaded here to be processed using blobClient
            //var fileContent = await blobClient.DownloadContentAsync();
            //var fileTags = await blobClient.GetTagsAsync();

            //Notify external systems via Service Bus
            var message = new DocumentProcessingMessage() {
                SourceSystem = receivedMessage.SourceSystem,
                DestinationSystem = receivedMessage.DestinationSystem,
                InternalId = receivedMessage.InternalId,
                Status = "Processed",
                Reason = "Document successfully processed"
            };

            string topic = Environment.GetEnvironmentVariable("DocumentProcessedTopic");
            await message.SendToServiceBus(topic);

        }
    }
}
