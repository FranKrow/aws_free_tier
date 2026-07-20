terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}

provider "aws" {
    region = "us-east-1"
}

# DynamoDB Table
resource "aws_dynamodb_table" "main_table" {
    name           = "my-dynamodb-table"
    billing_mode   = "PAY_PER_REQUEST" // Important for the free tier
    hash_key       = "ID"

    attribute {
        name = "ID"
        type = "S"
    }
}

# Queue SQS
resource "aws_sqs_queue" "main_queue" {
    name = "my-sqs-queue"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
    name = "lambda_execution_role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            },
        ]
    })
}

# Basic permissions for Lambda to write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_policy" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Package the Lambda function code
data "archive_file" "lambda_zip" {
    type        = "zip"
    source_file = "lambda_function.py"  # Ensure this file exists in the same directory
    output_path = "lambda_function_payload.zip"
}

# Lambda Function
resource "aws_lambda_function" "my_lambda" {
    filename         = "lambda_function_payload.zip"
    function_name    = "my_lambda_function" // Ensure this matches the function name in your Python file
    role             = aws_iam_role.lambda_role.arn
    handler          = "lambda_function.lambda_handler" // Ensure this matches the function name in your Python file
    runtime          = "python3.9" 

    source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# API Gateway
resource "aws_apigatewayv2_api" "lambda_api" {
    name          = "my-api-gateway-lambda"
    protocol_type = "HTTP"
}

# Default automatic deployment for the API Gateway
resource "aws_apigatewayv2_stage" "default_stage" {
    api_id      = aws_apigatewayv2_api.lambda_api.id
    name        = "$default"
    auto_deploy = true
}

# Integration between API Gateway and Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
    api_id           = aws_apigatewayv2_api.lambda_api.id
    integration_type = "AWS_PROXY"
    integration_uri  = aws_lambda_function.my_lambda.invoke_arn
}

# Generic route for the API Gateway
resource "aws_apigatewayv2_route" "lambda_route" {
    api_id    = aws_apigatewayv2_api.lambda_api.id
    route_key = "ANY /"
    target   = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gateway_permission" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action          = "lambda:InvokeFunction"
    function_name   = aws_lambda_function.my_lambda.function_name
    principal       = "apigateway.amazonaws.com"
    source_arn      = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}

# Output the API Gateway endpoint
output "api_gateway_endpoint" {
    value = aws_apigatewayv2_api.lambda_api.api_endpoint
    description = "The endpoint of the API Gateway that triggers the Lambda function."
}