import json
import boto3
import os

# Initialize our AWS clients outside the handler for better performance
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
s3 = boto3.client('s3')

def process_invoice(invoice):
    """Business Logic: Logic that is independent of AWS services."""
    # Example: Check if the invoice is over a certain amount
    is_high_value = float(invoice.get('amount', 0)) > 500
    return {
        "status": "processed",
        "flagged": is_high_value
    }

def lambda_handler(event, context):
    table_name = os.environ.get('DYNAMODB_TABLE') # [cite: 7]
    table = dynamodb.Table(table_name) # [cite: 1]
    
    for record in event['Records']:
        sqs_body = json.loads(record['body'])
        
        # 🛡️ THE ARCHITECT'S SHIELD: Handle the s3:TestEvent
        if 'Service' in sqs_body and sqs_body.get('Event') == 's3:TestEvent':
            print("S3 Test Event detected. Skipping processing.")
            continue 
            
        # Ensure 'Records' exists before proceeding
        if 'Records' not in sqs_body:
            print(f"Unknown message format: {sqs_body}")
            continue

        s3_event = sqs_body['Records'][0]['s3']
        bucket_name = s3_event['bucket']['name']
        file_key = s3_event['object']['key']
        
        # 2. Fetch the actual invoice file from S3
        response = s3.get_object(Bucket=bucket_name, Key=file_key)
        invoice_content = response['Body'].read().decode('utf-8')
        invoice_data = json.loads(invoice_content)
        
        # 3. Process the invoice using our business logic
        result = process_invoice(invoice_data)

        # 4. Save to DynamoDB
        table.put_item(Item={
            'invoice_id': invoice_data['invoice_id'],
            'amount': invoice_data['amount'],
            'status': result['status']
        })
        
        # 4. Notify via SNS if it's high value
        if result['flagged']:
            sns.publish(
                TopicArn = os.environ.get('SNS_TOPIC_ARN'),
                Message=f"High value invoice detected: {invoice_data['invoice_id']}"
            )