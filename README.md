# Oficina — Infraestrutura Kubernetes

Infraestrutura compartilhada da plataforma Oficina na AWS. Este repositório provisiona a rede, o cluster Amazon EKS, os componentes de escalabilidade e a camada de entrada formada por API Gateway, VPC Link e Network Load Balancer privado.

Ele também contém o bootstrap compatível com o AWS Academy/Vocareum Lab. Nesse modo, os workflows usam as credenciais temporárias compartilhadas pela organização, o bucket de state é preparado pela AWS CLI e a `LabRole` preexistente substitui a criação de roles e providers OIDC bloqueada pelo laboratório.

Como o Vocareum também bloqueia `iam:GetRole` para a role `voclabs`, o workflow executa `scripts/patch-eks-module-for-lab.ps1` após cada `terraform init`. O patch desativa a consulta incompatível do módulo EKS `21.26.0` e usa o bootstrap nativo do EKS para conceder acesso inicial ao criador do cluster.  

> Consulte [Execução completa no AWS Lab](docs/EXECUCAO-LAB.md) antes do primeiro deploy. As seções históricas sobre OIDC se aplicam apenas a contas AWS sem as restrições do laboratório.

## Fluxo de branches e promoção

O workflow `.github/workflows/terraform.yml` centraliza validação, deploy e promoção usando o `GITHUB_TOKEN` nativo do GitHub. Em `fase-3`, valida antes de abrir o PR para `homologacao`. Em `homologacao`, abre o PR para `main` somente após o deploy bem-sucedido, na mesma execução:

```text
push em fase-3 → validação → PR para homologacao
merge em homologacao → validação → deploy em homologação → PR para main
merge em main → implantação em produção
```

Os merges são manuais e devem ocorrer somente depois da aprovação e dos checks. Em **Settings → Actions → General → Workflow permissions**, mantenha **Read and write permissions** e **Allow GitHub Actions to create and approve pull requests** habilitados. Nenhum secret adicional é necessário para criar os PRs.

## Links de deploy e documentação

- [Deployments ativos](https://github.com/tc-organization-26/oficina-k8s-infra/deployments): cada apply bem-sucedido registra a URL real do API Gateway do ambiente.
- [Pipeline Terraform](https://github.com/tc-organization-26/oficina-k8s-infra/actions/workflows/terraform.yml).
- [Pipeline de bootstrap](https://github.com/tc-organization-26/oficina-k8s-infra/actions/workflows/bootstrap.yml).
- Swagger/OpenAPI: este repositório não expõe uma API própria. A documentação pertence à [Oficina API](https://github.com/tc-organization-26/gestao-oficina-tc-1#links-de-deploy-e-documentação-da-api) e fica disponível sob a URL publicada por este repositório.

A URL do API Gateway também pode ser consultada com `terraform output -raw api_gateway_url`. Ela não é fixada no README porque muda entre contas, ambientes e recriações.

## Tecnologias utilizadas

- Terraform e provider AWS;
- Amazon VPC, EKS, EC2, NLB e API Gateway HTTP API;
- AWS Systems Manager Parameter Store, IAM e S3;
- Kubernetes, Metrics Server e Cluster Autoscaler;
- GitHub Actions com credenciais temporárias do AWS Lab.

## Dockerfile

Não se aplica. Este repositório provisiona infraestrutura gerenciada com Terraform e não produz uma aplicação ou imagem de contêiner.

## Responsabilidades deste repositório

- criar o bucket S3 que armazena os states Terraform;
- configurar locking do state por arquivo `.tflock`;
- validar e reutilizar a `LabRole` fornecida pelo ambiente educacional;
- configurar variables do GitHub Actions nos quatro repositórios;
- criar VPC, sub-redes públicas e privadas, Internet Gateway e NAT Gateway;
- criar Amazon EKS e Managed Node Group;
- instalar Metrics Server e Cluster Autoscaler;
- criar o NLB privado usado pela aplicação;
- criar API Gateway HTTP API e VPC Link;
- publicar identificadores compartilhados no AWS Systems Manager Parameter Store.

Este repositório não contém código da API, banco de dados ou código da Lambda.

## Arquitetura provisionada

```text
Internet
  -> API Gateway HTTP API
     -> VPC Link
        -> NLB privado :80
           -> nós do Managed Node Group :30081
              -> Service NodePort da aplicação
                 -> Pods da Oficina API
```

Os nós do EKS ficam em sub-redes privadas. O endpoint do EKS permanece público para permitir a administração e o deploy pelo GitHub Actions. A aplicação é exposta externamente somente pelo API Gateway.

## Recursos principais

| Componente | Implementação |
| --- | --- |
| Rede | VPC em duas Availability Zones |
| Sub-redes | Duas públicas e duas privadas |
| Saída privada | Um NAT Gateway quando `enable_nat_gateway = true` |
| Kubernetes | Amazon EKS |
| Compute | EKS Managed Node Group `ON_DEMAND` |
| Storage add-on | AWS EBS CSI Driver |
| Escala de Pods | Metrics Server + HPA definido no repositório da aplicação |
| Escala de nós | Cluster Autoscaler usando a `LabRole` dos nodes |
| Entrada privada | Network Load Balancer |
| Entrada pública | API Gateway HTTP API + VPC Link |
| Descoberta entre repositórios | AWS Systems Manager Parameter Store |

## Dependências entre os repositórios

Este é o primeiro repositório de infraestrutura a ser aplicado.

```text
bootstrap
  -> oficina-k8s-infra
     -> oficina-db-infra
     -> oficina-auth-lambda
     -> gestao-oficina-tc-1
```

- `oficina-db-infra` lê VPC, sub-redes privadas e Security Group dos nós;
- `oficina-auth-lambda` lê os identificadores do API Gateway e da integração da aplicação;
- `gestao-oficina-tc-1` lê o nome do cluster para executar `kubectl`.

## Bootstrap

O workflow executa `scripts/bootstrap-lab.ps1`. O script prepara o backend S3 pela AWS CLI, valida a `LabRole` fornecida pelo ambiente educacional e configura as Actions Variables dos quatro repositórios. Ele não cria roles IAM nem provider OIDC.

### O que é configurado

- bucket S3 privado para os states;
- criptografia SSE-S3;
- versionamento do bucket;
- bloqueio de acesso público;
- descoberta da `LabRole` preexistente;
- variables dos quatro repositórios.

### Pré-requisitos da primeira execução

1. Criar os quatro repositórios remotos no GitHub.
2. Enviar este código ao repositório `oficina-k8s-infra`.
3. Ter uma sessão válida do AWS Lab.
4. Configurar os três secrets AWS na organização, com acesso aos quatro repositórios.
5. Configurar `GH_ADMIN_TOKEN` neste repositório.

| Secret | Uso |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Access key temporária do Lab |
| `AWS_SECRET_ACCESS_KEY` | Secret key temporária do Lab |
| `AWS_SESSION_TOKEN` | Session token temporário do Lab |
| `GH_ADMIN_TOKEN` | Consulta os repositórios e configura Actions variables nos quatro repositórios |

Os três secrets AWS devem ser Organization secrets com visibilidade para os quatro repositórios. O token do GitHub precisa conseguir ler os repositórios e administrar Actions Variables.

### Execução pelo GitHub Actions

Abra **Actions → Bootstrap AWS e GitHub → Run workflow**.

Entradas:

- `aws_region`: padrão `us-east-1`;
- `state_bucket_name`: opcional; vazio gera `oficina-fiap-tfstate-ACCOUNT_ID`.

Na primeira execução o script:

1. identifica a conta AWS;
2. cria ou reutiliza o bucket de state;
3. aplica versionamento, criptografia e bloqueio de acesso público;
4. consulta a `LabRole` existente;
5. grava `LAB_ROLE_ARN`, `AWS_REGION` e `TF_STATE_BUCKET` nos quatro repositórios.

### Execução local

Pré-requisitos: AWS CLI, PowerShell 7 e GitHub CLI.

```powershell
$env:GH_ADMIN_TOKEN = "token-com-acesso-aos-quatro-repos"
./scripts/bootstrap-lab.ps1 -AwsRegion us-east-1
```

Para escolher o bucket:

```powershell
./scripts/bootstrap-lab.ps1 `
  -AwsRegion us-east-1 `
  -StateBucketName oficina-fiap-tfstate-123456789012
```

### Nova sessão do AWS Lab

Atualize `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` na organização. Todos os workflows usam essas credenciais temporárias. O bootstrap pode ser repetido com segurança para validar o bucket, a role e as variables.

## Terraform da plataforma

### Variáveis

| Variável | Padrão | Descrição |
| --- | --- | --- |
| `aws_region` | `us-east-1` | Região AWS |
| `project_name` | `oficina` | Prefixo dos recursos e parâmetros |
| `environment` | `dev` | Sufixo do ambiente |
| `vpc_cidr` | `10.20.0.0/16` | CIDR da VPC |
| `cluster_version` | `1.34` | Versão do Kubernetes no EKS |
| `node_instance_types` | `["t3.medium"]` | Tipos de instância do node group |
| `node_min_size` | `1` | Quantidade mínima de nós |
| `node_desired_size` | `2` | Quantidade desejada |
| `node_max_size` | `4` | Quantidade máxima |
| `enable_nat_gateway` | `true` | Habilita NAT Gateway |
| `app_node_port` | `30081` | NodePort fixo da aplicação |

O arquivo `terraform.tfvars.example` contém um exemplo para uso local. Não versione `terraform.tfvars` com valores sensíveis ou específicos da conta.

### Outputs

- `cluster_name`
- `vpc_id`
- `private_subnet_ids`
- `api_gateway_url`
- `application_nlb_dns`

### Parâmetros publicados no SSM

Para cada ambiente são criados:

```text
/oficina/ENV/edge/http-api-id
/oficina/ENV/edge/http-api-execution-arn
/oficina/ENV/edge/app-integration-id
/oficina/ENV/network/vpc-id
/oficina/ENV/network/private-subnet-ids
/oficina/ENV/eks/cluster-name
/oficina/ENV/eks/node-security-group-id
```

`ENV` é `hom` para homologação e `prod` para produção.

## Validação local do Terraform

Sem acessar a AWS:

```powershell
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Para planejar manualmente com o backend criado pelo bootstrap:

```powershell
$env:TF_VAR_environment = "hom"
$env:TF_VAR_aws_region = "us-east-1"

terraform init -reconfigure `
  -backend-config="bucket=SEU_BUCKET" `
  -backend-config="key=oficina/k8s/hom.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"

terraform plan
```

## CI/CD

O workflow `.github/workflows/terraform.yml` usa os Organization secrets temporários do AWS Lab. Nenhuma credencial é versionada.

| Evento | Comportamento |
| --- | --- |
| Pull request de `fase-3` para `homologacao` | Apenas formatação e validação; não executa `terraform plan` |
| Pull request de `homologacao` para `main` | Formatação, validação e `terraform plan` de produção |
| Push em `homologacao` | `plan` e `apply` no state `oficina/k8s/hom.tfstate` |
| Push em `main` | `plan` e `apply` no state `oficina/k8s/prod.tfstate` |
| `workflow_dispatch` | Execução manual conforme a branch selecionada |

Variables esperadas, normalmente configuradas pelo bootstrap:

- `LAB_ROLE_ARN`
- `AWS_REGION`
- `TF_STATE_BUCKET`

## Verificação após o apply

```powershell
aws eks update-kubeconfig --name oficina-hom-eks --region us-east-1
kubectl get nodes
kubectl get deployment -n kube-system metrics-server
kubectl get deployment -n kube-system cluster-autoscaler
terraform output api_gateway_url
```

Para produção, substitua `hom` por `prod`.

## Custos e remoção

EKS, EC2, NAT Gateway e NLB podem gerar cobrança enquanto existirem. O `terraform destroy` deste repositório deve ser executado somente depois de remover os recursos dependentes dos outros três repositórios.

Ordem recomendada para destruição:

1. aplicação Kubernetes;
2. Lambda e rotas do API Gateway;
3. RDS;
4. EKS, NLB, API Gateway e VPC;
5. bootstrap, apenas se o state não for mais necessário.

O bucket do bootstrap possui `prevent_destroy` para reduzir o risco de perda acidental dos states.

## Estrutura

```text
.
├── .github/workflows/
│   ├── bootstrap.yml
│   └── terraform.yml
├── bootstrap/
├── scripts/bootstrap.ps1
├── main.tf
├── autoscaling.tf
├── edge.tf
├── variables.tf
├── outputs.tf
└── versions.tf
```
