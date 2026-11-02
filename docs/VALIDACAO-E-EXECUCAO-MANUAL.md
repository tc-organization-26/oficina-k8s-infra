# Validação local e execução manual na AWS — oficina-k8s-infra

[README](../README.md) · [Troubleshooting](TROUBLESHOOTING.md) · [AWS](EXECUCAO-AWS.md)

Pré-requisitos: Git e Terraform >= 1.10 (as esteiras fixam 1.15.9). Comece na raiz do repositório. O patch exige PowerShell 7 (`pwsh`).

## O que pode ser executado localmente

Este repositório não fornece um cluster Kubernetes ou PostgreSQL local. A validação abaixo confere o Terraform; `plan` e `apply`, mesmo executados no computador, provisionam AWS. Para desenvolver a aplicação com PostgreSQL local, utilize o [Docker Compose da aplicação](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/EXECUCAO-LOCAL.md), sem aplicar este Terraform.

## Validação sem credenciais AWS

A validação não exige conta AWS. O `init` baixa providers/módulos e precisa de internet se eles ainda não estiverem no cache.

```powershell
terraform fmt -check -recursive
terraform init -backend=false
pwsh ./scripts/patch-eks-module-for-lab.ps1
terraform validate
```

> **Observação:** os comandos AWS abaixo seguem a configuração atual do projeto. Confira as [adaptações educacionais e os pré-requisitos de IAM](EXECUCAO-AWS.md) antes de utilizá-los em outra conta.

## Credenciais para comandos locais que acessam a AWS

`plan`, `apply` e comandos `aws` acessam a conta real; a aplicação dos planos pode criar recursos cobrados. As credenciais do GitHub não configuram automaticamente o seu terminal.

Copie as credenciais da sessão AWS para as variáveis do terminal, sem salvá-las no repositório:

```powershell
$env:AWS_ACCESS_KEY_ID = "ACCESS_KEY_DA_SESSAO"
$env:AWS_SECRET_ACCESS_KEY = "SECRET_KEY_DA_SESSAO"
$env:AWS_SESSION_TOKEN = "SESSION_TOKEN_DA_SESSAO"
$env:AWS_DEFAULT_REGION = "us-east-1"
aws sts get-caller-identity
```

Confira a conta antes do plano. Use o mesmo `project_name`, ambiente, região, bucket e chave de state usados pelo CI/CD; o padrão Terraform `environment=dev` não equivale a `hom`. Não use um state novo para recursos que já estão gerenciados por outro state.

## Aplicação manual na AWS

Execute primeiro o bootstrap deste repositório. O script usa AWS CLI e consulta a LabRole; a sessão deve permitir `iam:GetRole` para essa role.

### Bootstrap pelo terminal

Com AWS CLI, GitHub CLI e PowerShell 7, na raiz:

```powershell
$env:GH_ADMIN_TOKEN = "TOKEN_COM_ACESSO_AOS_QUATRO_REPOS"
pwsh ./scripts/bootstrap-lab.ps1 -AwsRegion us-east-1
```

Para escolher o bucket, acrescente `-StateBucketName NOME_GLOBALMENTE_UNICO`. O token deve ler os quatro repositórios e administrar Actions Variables. O bootstrap prepara S3 e distribui as variables; não grava as credenciais AWS nos secrets do GitHub. Para preparar somente S3 e validar a role, use `-SkipGitHubVariables` e configure as variables depois. O código em `bootstrap/` é legado e não é executado pelo workflow atual.

Informe o bucket real criado pelo bootstrap, sem copiar literalmente `SEU_BUCKET` ou `ACCOUNT_ID`. Execute na raiz. A chave identifica o mesmo state usado pela esteira:

```powershell
$env:TF_VAR_environment = "hom"
$env:TF_VAR_aws_region = "us-east-1"
$env:TF_VAR_lab_role_arn = "arn:aws:iam::ACCOUNT_ID:role/LabRole"

terraform init -reconfigure `
  -backend-config="bucket=SEU_BUCKET" `
  -backend-config="key=oficina/k8s/hom.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"

pwsh ./scripts/patch-eks-module-for-lab.ps1
terraform plan -lock-timeout=5m -out=tfplan
```

Revise o plano, confira se não há outra execução ativa e aplique o plano salvo:

```powershell
terraform apply -lock-timeout=5m tfplan
terraform output
```

Para produção, altere tanto `TF_VAR_environment` quanto a chave do backend para `prod`. Não aplique manualmente em paralelo ao Actions. Não versione credenciais, `terraform.tfvars`, pacote, planos ou state; esses arquivos podem conter informações sensíveis. Consulte a [validação e o encerramento na AWS](EXECUCAO-AWS.md).
