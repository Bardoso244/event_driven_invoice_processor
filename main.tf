resource "aws_dynamodb_table" "invoice_table" {
    name           = "${var.project_prefix}-${var.table_name}"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "invoice_id"

    stream_enabled = true
    stream_view_type = "NEW_IMAGE"

    attribute {
        name = "invoice_id"
        type = "S"
    }
  
}

resource "aws_sns_topic" "invoice_alerts" {
    name = "${var.project_prefix}-${var.sns_topic}"
  
}

resource "aws_sns_topic_subscription" "invoice_alerts_subscription" {
    topic_arn = aws_sns_topic.invoice_alerts.arn
    protocol  = "email"
    endpoint  = "${var.email_address}"
    /* Note:  Actual value stored in terraform.tfvars for security reasons. 
    In your implementation, please create a terraform.tfvars to store variables and
    variable definitions in variables.tf, and reference them here.
    */
}

resource "aws_sqs_queue" "invoice_queue" {
    name = "${var.project_prefix}-${var.sqs_queue}"
    visibility_timeout_seconds = 30
    redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.invoice_dead_letter_queue.arn
        maxReceiveCount = 3
    })
}

resource "aws_sqs_queue" "invoice_dead_letter_queue" {
    name = "${var.project_prefix}-${var.dlq}"
    message_retention_seconds = 1209600 # 14 days
  
}

resource "aws_cloudwatch_metric_alarm" "dlq_alarm" {
    alarm_name          = "${var.project_prefix}-${var.dlq_alarm}"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 1
    metric_name         = "ApproximateNumberOfMessagesVisible"
    namespace           = "AWS/SQS"
    period              = 180
    statistic           = "Sum"
    threshold           = 0
    alarm_description = "Alarm when there is at least one message in the invoice dead letter queue"

    dimensions = {
        QueueName = aws_sqs_queue.invoice_dead_letter_queue.name
    }

    alarm_actions = [aws_sns_topic.invoice_alerts.arn]
  
}

resource "aws_s3_bucket" "invoice_uploads" {
    bucket = "${var.project_prefix}-${var.bucket_name}"
    force_destroy = true
}

resource "aws_s3_bucket_notification" "invoice_arrival" {
  bucket = aws_s3_bucket.invoice_uploads.id

  queue {
    queue_arn = aws_sqs_queue.invoice_queue.arn
    events = ["s3:ObjectCreated:*"]
    filter_suffix = ".json"
  }
  depends_on = [ aws_sqs_queue_policy.allow_s3_to_sqs ]
}

data "archive_file" "lambda_receiver_zip" {
    type        = "zip"
    source_file  = "${path.module}/lambda_invoice_receiver.py"
    output_path = "${path.module}/lambda_invoice_receiver.zip"
}

resource "aws_lambda_function" "invoice_receiver" {
    filename      = data.archive_file.lambda_receiver_zip.output_path
    function_name = "${var.project_prefix}-invoice_receiver"
    runtime       = "python3.9"
    handler       = "lambda_invoice_receiver.lambda_handler"
    role          = aws_iam_role.invoice_receiver_role.arn
    source_code_hash = data.archive_file.lambda_receiver_zip.output_base64sha256

    environment {
        variables = {
            DYNAMODB_TABLE = aws_dynamodb_table.invoice_table.name
            SNS_TOPIC_ARN  = aws_sns_topic.invoice_alerts.arn
        }
    }
}

data "archive_file" "lambda_worker_zip" {
    type        = "zip"
    source_file  = "${path.module}/lambda_invoice_worker.py"
    output_path = "${path.module}/lambda_invoice_worker.zip"
}

resource "aws_lambda_function" "invoice_worker" {
    filename      = data.archive_file.lambda_worker_zip.output_path
    function_name = "${var.project_prefix}-invoice_worker"
    runtime       = "python3.9"
    handler       = "lambda_invoice_worker.lambda_handler"
    role          = aws_iam_role.invoice_worker_role.arn
    source_code_hash = data.archive_file.lambda_worker_zip.output_base64sha256

    environment {
        variables = {
            DYNAMODB_TABLE = aws_dynamodb_table.invoice_table.name
            SNS_TOPIC_ARN  = aws_sns_topic.invoice_alerts.arn
        }
    }
  
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
    event_source_arn = aws_sqs_queue.invoice_queue.arn
    function_name    = aws_lambda_function.invoice_receiver.arn
    batch_size = 10
  
}

resource "aws_lambda_event_source_mapping" "dynamodb_trigger" {
    event_source_arn = aws_dynamodb_table.invoice_table.stream_arn
    function_name    = aws_lambda_function.invoice_worker.arn
    starting_position = "LATEST"
}