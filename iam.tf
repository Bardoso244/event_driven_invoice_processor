data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

  }
}

resource "aws_iam_role" "invoice_receiver_role" {
  name               = "invoice_receiver_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "invoice_receiver_policy" {
  name   = "invoice_receiver_policy"
  role   = aws_iam_role.invoice_receiver_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [ "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes" ]
        Effect = "Allow"
        Resource = aws_sqs_queue.invoice_queue.arn
      },
      {
        
        Action = ["dynamodb:PutItem"]
        Effect = "Allow"
        Resource = aws_dynamodb_table.invoice_table.arn
      },
      {
        Action = ["sns:Publish"]
        Effect = "Allow"
        Resource = aws_sns_topic.invoice_alerts.arn
      },
      {
        
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "s3:GetObject"
        ]
        Effect = "Allow"
        Resource = "${aws_s3_bucket.invoice_uploads.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "invoice_worker_role" {
  name               = "invoice_worker_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  
}

resource "aws_iam_role_policy" "invoice_worker_policy" {
  name   = "invoice_worker_policy"
  role   = aws_iam_role.invoice_worker_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [ 
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        
        ]
        Effect = "Allow"
        Resource = "${aws_dynamodb_table.invoice_table.arn}/stream/*"
      },
      {
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "allow_s3_to_sqs" {
  queue_url = aws_sqs_queue.invoice_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {Service = "s3.amazonaws.com"}
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.invoice_queue.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.invoice_uploads.arn
          }
        }
      }
    ]
  })
  
}

resource "aws_sns_topic_policy" "cloudwatch_to_sns" {
  arn = aws_sns_topic.invoice_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.invoice_alerts.arn
      }
    ]
  })
  
}