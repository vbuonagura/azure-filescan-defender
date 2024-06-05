using Azure.Messaging.ServiceBus;
using Azure.Identity;
using System.Text.Json;
using System.Threading.Tasks;
using System;

namespace Vbu.Models
{
    public class DocumentProcessingMessage
    {
        public string Status { get; set; }
        public string SourceSystem { get; set; }
        public string DestinationSystem { get; set; }
        public string InternalId { get; set; }
        public string Uri { get; set; }
        public string Reason { get; set; }

        public async Task SendToServiceBus(string topic)
        {
            string connection = Environment.GetEnvironmentVariable("ServiceBusConnectionString__fullyQualifiedNamespace");
            ServiceBusClient client = new ServiceBusClient(connection, new DefaultAzureCredential());
            ServiceBusSender sender = client.CreateSender(topic);
 
            var serializedMessage = JsonSerializer.Serialize(this);
            var serviceBusMessage = new ServiceBusMessage(serializedMessage);
            serviceBusMessage.ApplicationProperties.Add("sourceSystem", this.SourceSystem);
            serviceBusMessage.ApplicationProperties.Add("destinationSystem", this.DestinationSystem);

            try
            {
                await sender.SendMessageAsync(serviceBusMessage);
            }
            finally
            {
                await sender.DisposeAsync();
                await client.DisposeAsync();
            }
        }
    }
}