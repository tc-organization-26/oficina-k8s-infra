resource "aws_lb" "app" {
  name               = substr("${local.name}-app", 0, 32)
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets
}

resource "aws_lb_target_group" "app" {
  name        = substr("${local.name}-app", 0, 32)
  port        = var.app_node_port
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"
  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "traffic-port"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

locals {
  node_group_asg_names = {
    main = module.eks.eks_managed_node_groups["main"].node_group_autoscaling_group_names[0]
  }
}

resource "aws_autoscaling_attachment" "app" {
  for_each               = local.node_group_asg_names
  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.app.arn
}

resource "aws_security_group" "api_gateway_vpc_link" {
  name_prefix = "${local.name}-apigw-"
  description = "Saida do API Gateway VPC Link para o NLB"
  vpc_id      = module.vpc.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_apigatewayv2_vpc_link" "app" {
  name               = "${local.name}-vpc-link"
  security_group_ids = [aws_security_group.api_gateway_vpc_link.id]
  subnet_ids         = module.vpc.private_subnets
}

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "app" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.app.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.app.id
  payload_format_version = "1.0"
  request_parameters     = { "overwrite:path" = "$request.path" }
}

resource "aws_ssm_parameter" "platform" {
  for_each = {
    "/${var.project_name}/${var.environment}/edge/http-api-id"            = aws_apigatewayv2_api.main.id
    "/${var.project_name}/${var.environment}/edge/http-api-execution-arn" = aws_apigatewayv2_api.main.execution_arn
    "/${var.project_name}/${var.environment}/edge/app-integration-id"     = aws_apigatewayv2_integration.app.id
    "/${var.project_name}/${var.environment}/network/vpc-id"              = module.vpc.vpc_id
    "/${var.project_name}/${var.environment}/network/private-subnet-ids"  = jsonencode(module.vpc.private_subnets)
    "/${var.project_name}/${var.environment}/eks/cluster-name"            = module.eks.cluster_name
    "/${var.project_name}/${var.environment}/eks/node-security-group-id"  = module.eks.node_security_group_id
  }
  name  = each.key
  type  = "String"
  value = each.value
}
