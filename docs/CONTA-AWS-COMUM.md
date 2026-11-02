# Preparação para uma conta AWS comum

[README](../README.md) · [Execução no laboratório AWS](EXECUCAO-LAB-AWS.md) · [Validação manual](VALIDACAO-E-EXECUCAO-MANUAL.md) · [Instalação das ferramentas](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/main/docs/INSTALACAO-FERRAMENTAS.md)

Este roteiro orienta a preparação de IAM e as alterações necessárias para executar os quatro componentes fora do AWS Academy/Vocareum. O código atual reutiliza `LabRole`, aplica um patch no módulo EKS e autentica os workflows com secrets temporários. Os exemplos de adaptação abaixo precisam ser implementados e validados antes do primeiro deploy na conta comum; esta documentação não altera Terraform ou workflows automaticamente.

## Sequência de preparação

1. Defina conta, região e ambientes, e configure a identidade humana.
2. Prepare o backend S3 e a federação OIDC do GitHub.
3. Crie roles separadas para deploy, cluster, nós, add-ons e funções.
4. Adapte Terraform, bootstrap e workflows para consumir essas roles.
5. Configure acesso Kubernetes para as identidades que executam Helm e kubectl.
6. Valide e implante plataforma → banco → autenticação → API no mesmo ambiente.
7. Reexecute autenticação para ativar Datadog após o secret compartilhado e valide o fluxo de negócio.

## Identidade humana e perfil local

Use uma identidade administrativa da organização para o bootstrap e uma identidade de operação para o uso cotidiano. Configure MFA e prefira sessões federadas; a conta root não deve executar Terraform ou os workflows.

Quando IAM Identity Center estiver disponível, crie/atribua ao usuário um permission set na conta de destino e configure a CLI v2 conforme a [documentação de SSO](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html):

```powershell
aws configure sso --profile oficina-admin
aws sso login --profile oficina-admin
$env:AWS_PROFILE = "oficina-admin"
$env:AWS_REGION = "us-east-1"
$env:AWS_DEFAULT_REGION = "us-east-1"
aws sts get-caller-identity
```

Informe a URL/região do Identity Center e selecione a conta e o permission set atribuídos. Confira o `Account` retornado antes de qualquer plano. Em um terminal que ainda contenha credenciais exportadas do Academy, remova apenas as variáveis daquela sessão para evitar que prevaleçam sobre o perfil:

```powershell
Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
aws sts get-caller-identity
```

Se a organização usa outro provedor federado, obtenha uma sessão pelo mecanismo aprovado por ela. Uma conta sem Identity Center exige preparar essa federação ou acesso temporário equivalente; `aws configure sso` sozinho não cria usuários, permission sets ou atribuições.

## Roles e permissões

Crie as roles pelo IAM ou por um bootstrap Terraform dedicado. Em cada role de serviço, configure a relação de confiança com o principal indicado e associe somente as permissões de sua função. A role de deploy é uma identidade diferente das roles assumidas pelos serviços.

| Role sugerida | Principal de confiança | Permissões necessárias |
| --- | --- | --- |
| `oficina-hom-deploy` | Provider OIDC GitHub, restrito aos repositórios/Environment autorizados | Provisionar os recursos do componente, acessar state e passar somente as roles previstas |
| `oficina-hom-eks-cluster` | `eks.amazonaws.com` | `AmazonEKSClusterPolicy` ou política equivalente documentada pela AWS |
| `oficina-hom-eks-nodes` | `ec2.amazonaws.com` | `AmazonEKSWorkerNodePolicy` e `AmazonEC2ContainerRegistryPullOnly`; CNI com identidade própria |
| `oficina-hom-vpc-cni` | EKS Pod Identity ou IRSA configurado para o ServiceAccount | `AmazonEKS_CNI_Policy` para a rede IPv4 atual |
| `oficina-hom-ebs-csi` | EKS Pod Identity ou IRSA configurado para o controller | Política EBS CSI indicada na documentação do add-on para a versão instalada |
| `oficina-hom-autoscaler` | EKS Pod Identity ou IRSA configurado para `kube-system/cluster-autoscaler` | Leitura de capacidade e alteração dos ASGs do cluster, limitada por tags/recursos |
| `oficina-hom-login` | `lambda.amazonaws.com` | Logs, ENIs na VPC, leitura dos secrets RDS/JWT/Datadog usados pela função |
| `oficina-hom-authorizer` | `lambda.amazonaws.com` | Logs e leitura dos secrets JWT/Datadog usados pela função; sem permissões de ENI |

Repita ou separe as identidades para `prod`, mantendo contratos de cada ambiente. A role dos nós não deve ser a do control plane. A [documentação do cluster](https://docs.aws.amazon.com/eks/latest/userguide/cluster-iam-role.html) e a [documentação dos nós](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html) detalham as policies e trusts correspondentes.

Para as Lambdas, parta de `AWSLambdaBasicExecutionRole`; no login em VPC, inclua as permissões de `AWSLambdaVPCAccessExecutionRole` ou política equivalente. Acrescente `secretsmanager:GetSecretValue` restrito aos ARNs consumidos e `kms:Decrypt` quando os secrets usarem chave gerenciada pelo cliente. A identidade que faz deploy também precisa ler/publicar os parâmetros e secrets usados pelo workflow, além de consultar layers. Consulte [execution roles Lambda](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html) e [permissões de VPC](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html).

Para EBS CSI e Autoscaler, configure a associação entre role e ServiceAccount/add-on: instalar o Pod Identity Agent sozinho não concede permissões. Para Pod Identity, a trust usa `pods.eks.amazonaws.com` com `sts:AssumeRole` e `sts:TagSession`; para IRSA, configure o provider OIDC do cluster e restrinja `sub`/`aud` ao ServiceAccount. O provider do cluster é distinto do provider GitHub. Use os roteiros de [EBS CSI](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) e [Cluster Autoscaler](https://docs.aws.amazon.com/eks/latest/best-practices/cas.html).

### Escopo da role de deploy

As permissões devem cobrir criação, leitura, atualização e remoção dos recursos realmente usados, incluindo os data sources do Terraform. Não há uma única policy mínima universal: ARNs, tags, boundaries e SCPs variam por conta.

| Componente | Famílias de recursos a autorizar |
| --- | --- |
| Plataforma | VPC/EC2, EKS, Auto Scaling, ELBv2, API Gateway, SSM, roles e associações de add-ons |
| Banco | RDS, subnet group, SG/regras, SSM, Secrets Manager e operações necessárias à credencial gerenciada |
| Autenticação | Lambda, layers/permissões de invocação, API Gateway, SG/regras, SSM e Secrets Manager |
| API | Descrever EKS, ler SSM/secrets RDS/JWT, manter secret Datadog e executar operações Kubernetes concedidas separadamente |
| Todos que usam Terraform remoto | Backend S3 nos prefixos do componente; KMS se houver SSE-KMS |

Limite `iam:PassRole` às roles de serviço usadas e aos serviços destinatários. A criação de roles/policies exige permissões IAM adicionais somente onde esse gerenciamento ocorrer; a primeira criação de serviços também pode exigir `iam:CreateServiceLinkedRole`. A publicação/leitura no GHCR e as chaves Datadog continuam tendo credenciais próprias, fora do IAM AWS.

## Backend e bootstrap

Prepare um bucket S3 de nome globalmente único, com versionamento, criptografia e bloqueio de acesso público. Preserve os prefixes atuais: `oficina/k8s/ENV.tfstate`, `oficina/database/ENV.tfstate`, `oficina/auth/ENV.tfstate` e `oficina/observability/ENV.tfstate`. Os workflows usam locking S3 por `use_lockfile=true`.

A role de cada componente precisa de `s3:ListBucket` limitado aos prefixes, leitura/escrita do state e leitura/escrita/exclusão do arquivo `.tflock`. Acrescente acesso KMS se utilizar chave própria. Use [as permissões documentadas do backend S3](https://developer.hashicorp.com/terraform/language/backend/s3#permissions-required) para montar a policy.

O `bootstrap.yml` atual chama `scripts/bootstrap-lab.ps1`, que procura `LabRole` e distribui seu ARN. Adapte esse fluxo para configurar o bucket e os ARNs corretos sem buscar a role educacional.

O diretório `bootstrap/` e `scripts/bootstrap.ps1` contêm uma implementação anterior de S3/OIDC. Eles são referência para a adaptação, não o caminho ativo: a policy antiga usa permissões amplas e subjects com curingas, que devem ser revisados. Se o bucket/provider já existir, importe os recursos no state apropriado ou configure seu reaproveitamento; não aplique um bootstrap novo que tente recriá-los. Preserve o state inicial do bootstrap antes de migrá-lo ao S3.

## Federação GitHub OIDC

Crie ou reutilize no IAM o provider `https://token.actions.githubusercontent.com` com audience `sts.amazonaws.com`. Configure a trust da role de deploy com `sts:AssumeRoleWithWebIdentity` e condições de audience e subject restritas. Siga a [documentação GitHub para AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

Exemplo para um repositório com subject padrão e GitHub Environment `homologacao`; substitua `ACCOUNT_ID`, organização e repositório. Inclua explicitamente os demais repositórios autorizados ou use roles separadas por componente:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:tc-organization-26/oficina-k8s-infra:environment:homologacao"
      }
    }
  }]
}
```

Para produção, use o Environment `producao`. Quando um job usa Environment, o subject padrão contém esse Environment, não `ref:refs/heads/...`; configure as restrições de branch e revisões no próprio Environment. Sem Environment, restrinja o subject à branch necessária. Se os repositórios usam subjects imutáveis ou customizados, ajuste as condições ao formato realmente emitido; o exemplo acima não serve automaticamente para esses tokens. O bootstrap existente já distingue subjects tradicionais e imutáveis.

Nos jobs que acessam AWS, substitua a autenticação pelos secrets de sessão pelo bloco abaixo, preservando as demais permissões necessárias ao job:

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - uses: actions/checkout@v4
  - uses: aws-actions/configure-aws-credentials@v6.3.0
    with:
      role-to-assume: ${{ vars.AWS_ROLE_ARN }}
      aws-region: ${{ vars.AWS_REGION }}
```

Cadastre `AWS_ROLE_ARN` por Environment/repositório e mantenha `AWS_REGION` e `TF_STATE_BUCKET`. A variável `AWS_ROLE_ARN` já é escrita pelo script educacional, mas os workflows atuais não a usam para assumir uma role; somente cadastrá-la não ativa OIDC. Remova dos jobs migrados os parâmetros `aws-access-key-id`, `aws-secret-access-key` e `aws-session-token`.

## Alterações no Terraform e no acesso EKS

| Arquivo | Adaptação necessária |
| --- | --- |
| `main.tf` da plataforma | Separar ARN do cluster e ARN dos nós; substituir `var.lab_role_arn` pelos respectivos valores, ou habilitar criação de roles pelo módulo com policies apropriadas |
| `variables.tf` e workflow da plataforma | Declarar e fornecer os novos inputs; remover a obrigatoriedade de `lab_role_arn` na configuração migrada |
| Módulo EKS e workflow | Retirar a chamada de `patch-eks-module-for-lab.ps1` e trabalhar com o módulo original |
| `main.tf`/`autoscaling.tf` | Configurar roles/associações de VPC CNI, EBS CSI e Cluster Autoscaler |
| `terraform/main.tf` da autenticação | Separar `role` das funções login e authorizer e declarar os inputs/recursos correspondentes |
| Workflows de autenticação/plataforma | Substituir `TF_VAR_lab_role_arn` pelos inputs novos; usar OIDC para deploy |
| Workflows de banco/API e bootstrap | Migrar autenticação AWS e revisar permissões do componente |

Para recuperar o módulo original após uso do patch, prepare uma cópia de trabalho limpa e execute `terraform init` com os lockfiles versionados. Não faça mudanças manuais permanentes em `.terraform/modules`.

Configure EKS Access Entries para a role que executa Terraform/Helm na plataforma e para a role que aplica os manifests da API. O módulo deve habilitar autenticação por API e declarar as entradas/associações. O exemplo abaixo é um desenho de adaptação ao módulo adotado; `var.platform_deploy_role_arn` é um input novo:

```hcl
# Dentro de module "eks", após definir as roles de cluster e nós:
authentication_mode = "API_AND_CONFIG_MAP"
access_entries = {
  platform_deploy = {
    principal_arn = var.platform_deploy_role_arn
    policy_associations = {
      platform_admin = {
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = { type = "cluster" }
      }
    }
  }
}
```

A plataforma instala charts e recursos de escopo de cluster; a role de deploy precisa desse alcance para o fluxo atual. Se a API usar outra role, acrescente sua entrada e as permissões Kubernetes exigidas pelo deploy/Datadog, ou separe as etapas para reduzir seu escopo. Use ARNs IAM permanentes das roles, não ARNs temporários `assumed-role`. Planeje também o acesso da identidade humana que fará diagnóstico. Confira o [modelo de acesso EKS](https://docs.aws.amazon.com/eks/latest/userguide/cluster-auth.html).

`aws eks update-kubeconfig` configura o cliente, mas não concede acesso ao cluster. Mantenha um caminho de administração validado antes de retirar o acesso do criador. Se optar por endpoint EKS privado, os runners precisam alcançar a VPC; os runners GitHub-hosted atuais dependem do endpoint administrativo público.

## Implantar e verificar

Depois de implementar as adaptações, execute `terraform fmt -check -recursive`, `terraform init` no backend correto, `terraform validate` e revise o plano de cada componente. Uma migração de ambiente existente pode alterar roles, acesso e recursos: trate o plano como migração, não como nova instalação sem estado.

Em uma instalação nova, conclua bootstrap e depois plataforma, banco, autenticação e API. Mantenha SSM, nomes e states no mesmo `hom` ou `prod`. No terminal autenticado:

```powershell
aws sts get-caller-identity
$cluster = aws ssm get-parameter --name /oficina/hom/eks/cluster-name --query Parameter.Value --output text
aws eks update-kubeconfig --name $cluster --region us-east-1
kubectl get nodes
kubectl get pods -n kube-system
kubectl get deployment,pods,service,hpa -n oficina
```

Repita as verificações de identidade/acesso na esteira OIDC: sucesso no perfil humano não comprova acesso da role do GitHub. Verifique logs do Autoscaler e add-ons, rollout da API, readiness, login e o [fluxo completo de negócio](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/main/docs/VALIDACAO-FLUXO.md). A integração Datadog, as credenciais GHCR e a ordem de remoção continuam seguindo os guias atuais dos componentes.

## Critérios para considerar a adaptação concluída

- Nenhum bootstrap, input obrigatório, workflow ou recurso depende de `LabRole` na configuração migrada.
- Cluster, nós, workloads e Lambdas usam roles com trusts e policies próprios.
- OIDC funciona somente para os repositórios/ambientes autorizados.
- Terraform/Helm e kubectl funcionam com as identidades reais de deploy.
- Todos os componentes usam o backend e os contratos SSM do ambiente correto.
- Readiness e roteiro de atendimento passam, e os agentes/add-ons têm as permissões necessárias.

Esses critérios descrevem a validação a executar na conta de destino. O projeto atual permanece configurado para o ambiente educacional até que as adaptações de código sejam realizadas.
