terraform {
  required_providers {
    aws = {
        source  = "hashicorp/aws"
        version = "~> 3.58.0"
    }
    random = {
        source  = "hashicorp/random"
        version = "~> 3.1.0"
    }
    archive = {
        source  = "hashicorp/archive"
        version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
    region  = var.aws_region
    profile = "default" 
}

data "archive_file" "LaRE_AWS" {
    type = "zip"

    source_dir  = "${path.module}/src"
    output_path = "${path.module}/LaRE_AWS.zip"
}

resource "aws_lambda_function" "LaRE" {
    function_name   = "LaRE"
    filename        = "${path.module}/LaRE_AWS.zip"

    runtime = "python3.9"
    handler = "LaRE.handler"

    source_code_hash = data.archive_file.LaRE_AWS.output_base64sha256

    role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "LaRE" {
    name = "/aws/lambda/${aws_lambda_function.LaRE.function_name}"

    retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
    name = "serverless_lambda"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action  = "sts:AssumeRole"
            Effect  = "Allow"
            Sid     = ""
            Principal = {
                Service = "lambda.amazonaws.com"
            }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
    role        = aws_iam_role.lambda_exec.name
    policy_arn  = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_apigatewayv2_api" "lambda" {
    name            = "serverless_lambda_gw"
    protocol_type   = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
    api_id      = aws_apigatewayv2_api.lambda.id
    name        = "serverless_lambda_stage"
    auto_deploy = true
}

resource "aws_apigatewayv2_integration" "LaRE" {
    api_id = aws_apigatewayv2_api.lambda.id

    integration_uri     = aws_lambda_function.LaRE.invoke_arn
    integration_type    = "AWS_PROXY"
    integration_method  = "POST"
}

resource "aws_apigatewayv2_route" "LaRE" {
    api_id = aws_apigatewayv2_api.lambda.id

    route_key   = "ANY /LaRE"
    target      = "integrations/${aws_apigatewayv2_integration.LaRE.id}"
}

resource "aws_lambda_permission" "api_gw" {
    statement_id    = "AllowExecutionFromAPIGateway"
    action          = "lambda:InvokeFunction"
    function_name   = aws_lambda_function.LaRE.function_name
    principal       = "apigateway.amazonaws.com"
    source_arn      = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}