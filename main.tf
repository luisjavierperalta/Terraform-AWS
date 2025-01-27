# Define AWS provider
provider "aws" {
  region = "us-west-2"
}

# Create DynamoDB Table with on-demand billing mode and encryption
resource "aws_dynamodb_table" "MyTable" {
  name           = "YourTableName"
  hash_key       = "id"
  billing_mode   = "PAY_PER_REQUEST"  # On-demand mode for auto-scaling based on traffic
  attribute {
    name = "id"
    type = "S"
  }

  # Enable encryption using AWS managed keys (default)
  sse_specification {
    enabled  = true
    sse_type = "AES256"
  }

  # Optional: If you plan on querying other attributes, add Global Secondary Indexes (GSIs)
  # global_secondary_index {
  #   name               = "YourIndex"
  #   hash_key           = "secondary_key"
  #   projection_type    = "ALL"
  #   read_capacity      = 5
  #   write_capacity     = 5
  # }
}

# Define IAM Role for Lambda execution
resource "aws_iam_role" "LambdaExecutionRole" {
  name = "LambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect    = "Allow"
      },
    ]
  })
}

# Define Lambda execution policy for DynamoDB access
resource "aws_iam_policy" "LambdaDynamoDBPolicy" {
  name        = "LambdaDynamoDBPolicy"
  description = "Lambda policy to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "dynamodb:PutItem", 
          "dynamodb:GetItem", 
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.MyTable.arn
      },
    ]
  })
}

# Attach IAM policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "LambdaPolicyAttachment" {
  role       = aws_iam_role.LambdaExecutionRole.name
  policy_arn = aws_iam_policy.LambdaDynamoDBPolicy.arn
}

# Create an S3 bucket for Lambda code storage
resource "aws_s3_bucket" "LambdaCodeBucket" {
  bucket = "your-lambda-code-bucket-name"  # Replace with a unique bucket name
  acl    = "private"
}

# Upload Lambda code to S3
resource "aws_s3_bucket_object" "LambdaCode" {
  bucket = aws_s3_bucket.LambdaCodeBucket.bucket
  key    = "path/to/your/lambda/code.zip"  # Replace with actual path in S3
  source = "local/path/to/your/lambda/code.zip"  # Path to the Lambda code on your local machine
  acl    = "private"
}

# Define Lambda function with environment variables and versioning enabled
resource "aws_lambda_function" "MyLambda" {
  function_name = "MyLambdaFunction"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  role          = aws_iam_role.LambdaExecutionRole.arn
  s3_bucket     = aws_s3_bucket.LambdaCodeBucket.bucket
  s3_key        = aws_s3_bucket_object.LambdaCode.key

  # Set environment variables for flexible configuration
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.MyTable.name
      REGION     = "us-west-2"
    }
  }

  memory_size = 128  # Adjust based on function's memory needs
  timeout     = 60   # Adjust based on function's runtime requirements

  # Enable versioning
  publish = true
}

# Optional: Create an API Gateway (if needed)
resource "aws_api_gateway_rest_api" "MyApi" {
  name        = "MyApi"
  description = "API Gateway for MyLambda"
}

resource "aws_api_gateway_resource" "MyApiResource" {
  rest_api_id = aws_api_gateway_rest_api.MyApi.id
  parent_id   = aws_api_gateway_rest_api.MyApi.root_resource_id
  path_part   = "data"
}

resource "aws_api_gateway_method" "MyApiMethod" {
  rest_api_id   = aws_api_gateway_rest_api.MyApi.id
  resource_id   = aws_api_gateway_resource.MyApiResource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "MyApiIntegration" {
  rest_api_id = aws_api_gateway_rest_api.MyApi.id
  resource_id = aws_api_gateway_resource.MyApiResource.id
  http_method = aws_api_gateway_method.MyApiMethod.http_method
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri  = aws_lambda_function.MyLambda.invoke_arn
}

# Optional: Enable CloudWatch Logs for Lambda (if needed for monitoring)
resource "aws_cloudwatch_log_group" "MyLambdaLogGroup" {
  name = "/aws/lambda/${aws_lambda_function.MyLambda.function_name}"
}

resource "aws_cloudwatch_log_stream" "MyLambdaLogStream" {
  log_group_name = aws_cloudwatch_log_group.MyLambdaLogGroup.name
  name           = "LogStream-${aws_lambda_function.MyLambda.function_name}"
}

# Optional: S3 bucket policy to ensure Lambda has permission to access the bucket (if applicable)
resource "aws_s3_bucket_object" "LambdaCode" {
  bucket = "your-lambda-code-bucket-name"  # Replace with the S3 bucket name
  key    = "path/to/your/lambda/code.zip"  # The key inside the S3 bucket
  source = "local/path/to/your/lambda/code.zip"  # Local path to the Lambda code zip file
  acl    = "private"
}
