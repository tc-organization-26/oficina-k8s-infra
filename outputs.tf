output "cluster_name" { value = module.eks.cluster_name }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnets }
output "api_gateway_url" { value = aws_apigatewayv2_api.main.api_endpoint }
output "application_nlb_dns" { value = aws_lb.app.dns_name }

