provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "lambda_role" {
    name   = "HelloWorld_Lambda_Function_Role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
                Effect = "Allow",
                Sid = ""
            }
        ]
    })
}

resource "aws_iam_policy" "iam_policy_for_lambda" {
 
    name         = "aws_iam_policy_for_terraform_aws_lambda_role"
    path         = "/"
    description  = "AWS IAM Policy for managing aws lambda role"
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ]
                Resource = "arn:aws:logs:*:*:*"
                Effect = "Allow"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
    role        = aws_iam_role.lambda_role.name
    policy_arn  = aws_iam_policy.iam_policy_for_lambda.arn
}

data "archive_file" "placeholder" {
    type        = "zip"
    output_path = "${path.module}/dist/placeholder.zip"

    source {
        content = "placeholder"
        filename = "index.php"
    }
}

resource "aws_lambda_function" "terraform_lambda_func" {
    filename                       = "${path.module}/dist/placeholder.zip"
    function_name                  = "HelloWorld_Lambda_Function"
    role                           = aws_iam_role.lambda_role.arn
    handler                        = "index.php"
    runtime                        = "provided.al2"
    depends_on                     = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
    layers                         = [
        "arn:aws:lambda:us-east-1:209497400698:layer:php-81-fpm:27"
    ]
}

resource "aws_lambda_function_url" "function" {
    function_name      = aws_lambda_function.terraform_lambda_func.function_name
    authorization_type = "NONE"
}

resource "aws_apigatewayv2_api" "lambda" {
    name          = "serverless_lambda_gw"
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
    api_id = aws_apigatewayv2_api.lambda.id

    name        = "serverless_lambda_stage"
    auto_deploy = true

    access_log_settings {
        destination_arn = aws_cloudwatch_log_group.api_gw.arn

        format = jsonencode({
            requestId               = "$context.requestId"
            sourceIp                = "$context.identity.sourceIp"
            requestTime             = "$context.requestTime"
            protocol                = "$context.protocol"
            httpMethod              = "$context.httpMethod"
            resourcePath            = "$context.resourcePath"
            routeKey                = "$context.routeKey"
            status                  = "$context.status"
            responseLength          = "$context.responseLength"
            integrationErrorMessage = "$context.integrationErrorMessage"
        })
    }
}

resource "aws_apigatewayv2_integration" "hello_world" {
    api_id = aws_apigatewayv2_api.lambda.id

    integration_uri    = aws_lambda_function.terraform_lambda_func.invoke_arn
    integration_type   = "AWS_PROXY"
    integration_method = "POST" # THIS MUST BE POST
}

resource "aws_apigatewayv2_route" "hello_world" {
    api_id = aws_apigatewayv2_api.lambda.id

    route_key = "ANY /{proxy+}"
    target    = "integrations/${aws_apigatewayv2_integration.hello_world.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
    name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

    retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.terraform_lambda_func.function_name
    principal     = "apigateway.amazonaws.com"

    source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}