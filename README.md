# Oficina - Infraestrutura Kubernetes

Provisiona com Terraform a VPC, o Amazon EKS, Managed Node Group, Metrics Server, Cluster Autoscaler, NLB privado e API Gateway HTTP.

## Execucao

Configure no GitHub `AWS_ROLE_ARN`, `AWS_REGION` e `TF_STATE_BUCKET`. Pull requests validam e planejam; pushes em `homologacao`, `main` ou `master` aplicam automaticamente o ambiente correspondente.

```bash
terraform init -backend=false
terraform validate
```

O projeto publica no AWS Parameter Store os identificadores consumidos pelos repositórios do banco, da Lambda e da aplicação.

```text
API Gateway -> VPC Link -> NLB privado -> NodePort 30081 -> EKS
```
