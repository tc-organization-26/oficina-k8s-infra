# Execução da infraestrutura no AWS Lab

Este guia descreve o caminho suportado para contas AWS Academy/Vocareum que bloqueiam `iam:CreateOpenIDConnectProvider`, criação de roles IAM e algumas leituras administrativas do S3.

## Arquitetura

```text
GitHub Actions -- credenciais temporárias do Lab --> AWS
    |
    +-- S3 privado: states Terraform
    +-- VPC: sub-redes públicas e privadas, NAT Gateway
    +-- EKS: control plane + managed node group usando LabRole
    +-- Metrics Server + Cluster Autoscaler
    +-- NLB privado + VPC Link
    +-- API Gateway HTTP API
    +-- SSM Parameter Store: descoberta dos recursos
```

O cluster e o node group reutilizam `LabRole`. O IRSA fica desabilitado porque exigiria um provider OIDC IAM. O Cluster Autoscaler obtém credenciais pela role dos nodes; o launch template permite IMDSv2 aos pods com hop limit 2.

## Configuração no GitHub

Crie três **Organization secrets** em `tc-organization-26`, com visibilidade **Selected repositories**, selecionando os quatro repositórios:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
```

Se o plano da organização não disponibilizar Organization secrets para repositórios privados, crie Repository secrets com os mesmos nomes em cada repositório. Atualize os três valores sempre que a sessão do Lab expirar.

Neste repositório, mantenha também:

```text
GH_ADMIN_TOKEN
```

O token precisa ler os quatro repositórios e gravar Actions Variables.

O bootstrap configura estas Repository variables:

```text
AWS_REGION=us-east-1
TF_STATE_BUCKET=oficina-fiap-tfstate-ACCOUNT_ID
LAB_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/LabRole
AWS_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/LabRole
```

`AWS_ROLE_ARN` é mantida apenas para compatibilidade; os workflows do Lab usam `LAB_ROLE_ARN` e os três secrets temporários.

## Promoção automática entre branches

O workflow usa o `GITHUB_TOKEN` fornecido automaticamente pelo GitHub. Em **Settings → Actions → General → Workflow permissions**, selecione **Read and write permissions** e habilite **Allow GitHub Actions to create and approve pull requests**. Não é necessário cadastrar outro secret.

O fluxo de promoção é:

```text
push em fase-3
  -> abre ou atualiza PR de fase-3 para homologacao
  -> merge manual após os checks
  -> abre ou atualiza PR de homologacao para main
  -> merge manual após os checks
```

Se `homologacao` ainda não existir, o workflow a cria a partir de `main`. Proteja `homologacao` e `main` contra push direto e exija Pull Request para merge.

## Bootstrap

O workflow `.github/workflows/bootstrap.yml` executa `scripts/bootstrap-lab.ps1`. Ele:

1. valida as credenciais temporárias;
2. cria ou reutiliza o bucket S3 sem gerenciá-lo como `aws_s3_bucket`;
3. habilita versionamento, criptografia AES-256 e bloqueio de acesso público;
4. consulta a `LabRole` fornecida pelo laboratório;
5. distribui as variables para os quatro repositórios.

Ele não cria OIDC Provider nem roles IAM.

Pelo GitHub: **Actions → Bootstrap AWS e GitHub → Run workflow**, usando a branch que contém esta versão.

Pelo terminal:

```powershell
gh workflow run bootstrap.yml `
  --repo tc-organization-26/oficina-k8s-infra `
  --ref fase-3 `
  -f aws_region=us-east-1 `
  -f state_bucket_name=
```

Confirme o final:

```text
Bootstrap do Lab concluido
```

## Deploy desta infraestrutura

O bootstrap deve terminar antes deste deploy. Execute manualmente:

```powershell
gh workflow run terraform.yml `
  --repo tc-organization-26/oficina-k8s-infra `
  --ref fase-3
```

Liste e acompanhe a execução:

```powershell
gh run list --repo tc-organization-26/oficina-k8s-infra --workflow terraform.yml --limit 3
gh run watch ID --repo tc-organization-26/oficina-k8s-infra --exit-status
```

Em `fase-3` ou `homologacao`, `TF_VAR_environment=hom`. Em `main` ou `master`, o ambiente é `prod`.

## Ordem completa dos quatro repositórios

```text
1. oficina-k8s-infra/bootstrap.yml
2. oficina-k8s-infra/terraform.yml
3. oficina-db-infra/terraform.yml
4. oficina-auth-lambda/cicd.yml
5. gestao-oficina-tc-1/cicd.yml
```

Não execute os passos 2 a 5 em paralelo na primeira implantação.

## Validação

```powershell
$cluster = aws ssm get-parameter `
  --name /oficina/hom/eks/cluster-name `
  --query Parameter.Value `
  --output text

aws eks update-kubeconfig --name $cluster --region us-east-1
kubectl get nodes -o wide
kubectl get pods -A
kubectl get deployment,service,hpa -n oficina
```

Consulte os componentes de entrada:

```powershell
aws apigatewayv2 get-apis --output table
aws elbv2 describe-load-balancers --output table
aws ssm get-parameters-by-path --path /oficina/hom --recursive --output table
```

## Expiração e destruição

Quando o Lab renovar as credenciais, atualize os três Organization secrets antes de qualquer novo workflow. Não coloque esses valores em arquivos do repositório.

Para encerrar definitivamente, destrua na ordem inversa: aplicação, autenticação, banco, EKS/rede e por último o bucket de state. EKS, nodes, NAT Gateway, RDS e NLB geram cobrança enquanto existirem.
