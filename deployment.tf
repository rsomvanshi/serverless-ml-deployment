# Variables
variable "username" {}

# Configure the AWS Provider
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-west-2"
}


resource "aws_s3_bucket" "s3_bucket" {
  bucket = "ml-deployment-${var.username}"
  acl    = "private"
}

resource "aws_s3_bucket_object" "model_file" {
  bucket = "${aws_s3_bucket.s3_bucket.id}"
  key    = "SVMModel.pckl"
  source = "SVMModel.pckl"
}

resource "aws_s3_bucket_object" "lambda_package" {
  bucket = "${aws_s3_bucket.s3_bucket.id}"
  key    = "lambda_package.zip"
  source = "lambda_package.zip"
}

resource "aws_lambda_function" "predict" {
  function_name = "predict-${var.username}"

  # The bucket name as created earlier with "aws s3api create-bucket"
  s3_bucket = "${aws_s3_bucket.s3_bucket.id}"
  s3_key    = "lambda_package.zip"
  handler = "lambda_handler.model_handler"
  runtime = "python3.6"
  role = "${aws_iam_role.lambda_role.arn}"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.username}"
  assume_role_policy = <<EOF
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Action": "sts:AssumeRole",
                  "Principal": {
                    "Service": "lambda.amazonaws.com"
                  },
                  "Effect": "Allow",
                  "Sid": ""
                }
              ]
            }
            EOF
}

resource "aws_iam_role_policy" "lambda-policy" {
  name = "lambda-policy-${var.username}"
  role = "${aws_iam_role.lambda_role.id}"
  policy = <<EOF
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Action": [
                    "cloudwatch:*",
                    "logs:*",
                    "s3:*"
                  ],
                  "Effect": "Allow",
                  "Resource": "*"
                }
              ]
            }
            EOF
}

# API GATEWAY

resource "aws_api_gateway_rest_api" "predict" {
  name        = "predict"
  description = "ML Model Prediction"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.predict.id}"
  parent_id   = "${aws_api_gateway_rest_api.predict.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.predict.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

#Each method on an API gateway resource has an integration which specifies where incoming requests are routed. 
#Add the following configuration to specify that requests to this method should be sent to the Lambda function defined earlier

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.predict.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.predict.invoke_arn}"
}

# Unfortunately the proxy resource cannot match an empty path at the root of the API, handling it here.
resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.predict.id}"
  resource_id   = "${aws_api_gateway_rest_api.predict.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.predict.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.predict.invoke_arn}"
}

resource "aws_api_gateway_deployment" "dev" {
  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.predict.id}"
  stage_name  = "dev"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.predict.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.dev.execution_arn}/*/*"
}

# Output API Gateway URL
output "base_url" {
  value = "${aws_api_gateway_deployment.dev.invoke_url}"
}