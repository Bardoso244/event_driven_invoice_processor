import json

def lambda_handler(event, context):
    for record in event['Records']:
        if record['eventName'] == 'INSERT':
            # DynamoDB Streams use a specific format (e.g., {'S': 'value'})
            new_item = record['dynamodb']['NewImage']
            invoice_id = new_item['invoice_id']['S']
            amount = new_item['amount']['N']
            amount = float(amount)  # Convert string to float
            
            print(f"WORKER: Processing new invoice {invoice_id} for amount {amount}")
            """ The example just prints the invoice details, 
            but you could add more complex processing here (e.g., sending notifications, updating other systems, etc.)"""
    
    return {"status": "success"}