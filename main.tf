# --- PROVIDER CONFIGURATION ---
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

# --- DATABASE ---
resource "aws_dynamodb_table" "url_table" {
  name         = "SwiftLink_URLs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "short_id"

  attribute {
    name = "short_id"
    type = "S"
  }

  tags = {
    Project = "SwiftLink"
  }
}

# --- SECURITY (IAM) ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "swiftlink_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_db_policy" {
  name = "swiftlink_dynamo_access"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
      Effect   = "Allow"
      Resource = aws_dynamodb_table.url_table.arn
    }]
  })
}

# --- BACKEND (LAMBDA) ---
resource "aws_lambda_function" "backend" {
  filename      = "deployment.zip"
  function_name = "SwiftLink_Backend"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "bootstrap"      # Required for provided.al2023
  runtime       = "provided.al2023" # Modern AWS Linux 2023 runtime

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.url_table.name
    }
  }
}

# --- API GATEWAY ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "SwiftLink_API"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_link" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.backend.invoke_arn
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = toset(["POST /shorten", "GET /{id}"])
  
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.lambda_link.id}"
}

resource "aws_lambda_permission" "api_gw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# --- OUTPUTS ---
output "api_url" {
  description = "The public URL for your shortener"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}
