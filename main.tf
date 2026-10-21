data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 101), cidrsubnet(var.vpc_cidr, 8, 102)]

  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true
  enable_dns_support     = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = "${local.name}-eks"
  kubernetes_version = var.cluster_version

  endpoint_public_access = true
  # O acesso inicial do criador é habilitado pelo patch do módulo aplicado no
  # workflow. O recurso de acesso do módulo exigiria iam:GetRole, ação negada
  # explicitamente pelo AWS Academy/Vocareum.
  enable_cluster_creator_admin_permissions = false
  enable_irsa                              = false
  create_iam_role                          = false
  iam_role_arn                             = var.lab_role_arn

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    aws-ebs-csi-driver     = {}
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_groups = {
    main = {
      name            = "${local.name}-nodes"
      instance_types  = var.node_instance_types
      capacity_type   = "ON_DEMAND"
      create_iam_role = false
      iam_role_arn    = var.lab_role_arn
      min_size        = var.node_min_size
      desired_size    = var.node_desired_size
      max_size        = var.node_max_size
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }
  }

  node_security_group_additional_rules = {
    ingress_app_from_vpc = {
      description = "Aplicacao recebida pelo NLB privado"
      protocol    = "tcp"
      from_port   = var.app_node_port
      to_port     = var.app_node_port
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }
  }
}
