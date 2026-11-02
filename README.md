# Oficina — Infraestrutura Kubernetes

Terraform da plataforma AWS: VPC, EKS, Metrics Server, Cluster Autoscaler, NLB privado, VPC Link e API Gateway. Inclui o bootstrap do backend S3 e das variáveis do GitHub para os quatro repositórios. É a primeira infraestrutura a ser implantada.

## Responsabilidades deste repositório

- preparar o bucket S3 dos states e distribuir as variáveis GitHub dos quatro repositórios pelo bootstrap;
- provisionar VPC, sub-redes públicas e privadas, Internet Gateway e NAT Gateway;
- criar o EKS e seu Managed Node Group usando a role configurada;
- instalar Metrics Server e Cluster Autoscaler;
- criar NLB privado, VPC Link e API Gateway HTTP API;
- publicar no SSM os identificadores consumidos pelo banco, pela autenticação e pela aplicação.

## Índice da documentação

| Assunto | Documento |
| --- | --- |
| Validação e execução pelo terminal | [Validação local e execução manual](docs/VALIDACAO-E-EXECUCAO-MANUAL.md) |
| Checklist GitHub, dependências, deploy e encerramento | [Execução na AWS](docs/EXECUCAO-AWS.md) |
| Tecnologias, ferramentas, versões e fontes | [Tecnologias e versões](docs/VERSOES.md) |
| Diagnóstico por assunto e recuperação | [Troubleshooting](docs/TROUBLESHOOTING.md) |

## Repositórios da solução

| Repositório | Responsabilidade |
| --- | --- |
| [gestao-oficina-tc-1](https://github.com/tc-organization-26/gestao-oficina-tc-1#readme) | API Java, migrations, Docker Compose e deploy da aplicação |
| [oficina-k8s-infra](https://github.com/tc-organization-26/oficina-k8s-infra#readme) | Bootstrap, rede, EKS, escalabilidade e entrada HTTP |
| [oficina-db-infra](https://github.com/tc-organization-26/oficina-db-infra#readme) | RDS PostgreSQL privado, backups e credencial gerenciada |
| [oficina-auth-lambda](https://github.com/tc-organization-26/oficina-auth-lambda#readme) | Login por CPF, JWT e rotas protegidas do Gateway |

## Execução e deploy

### Validação local e execução manual

Consulte o [guia de validação local e execução manual](docs/VALIDACAO-E-EXECUCAO-MANUAL.md) para validar o Terraform e executar bootstrap, plan e apply pelo terminal. A validação exige Terraform compatível e PowerShell para o patch do módulo EKS; o primeiro init pode baixar providers e módulos.

Este repositório não cria um cluster Kubernetes local. Executar plan/apply no computador continua acessando a AWS e exige o mesmo backend e ambiente da esteira.

### Deploy e execução na AWS

Prepare o [checklist de acessos e configurações](docs/EXECUCAO-AWS.md#checklist-inicial) e conclua as dependências na [ordem de implantação](docs/EXECUCAO-AWS.md#ordem-da-primeira-implantação). Faça o merge para `homologacao` para disparar o deploy em `hom` e aguarde a conclusão. Para produção, use `main` após validar homologação. **Run workflow é uma alternativa ou reexecução**, não um passo obrigatório após o merge.

> O código contém adaptações educacionais de IAM e credenciais. Confira a observação do guia AWS antes de utilizá-lo em outra conta.

Na primeira instalação, execute manualmente `bootstrap.yml` antes do deploy da plataforma. Ele prepara S3 e registra as variáveis `AWS_REGION`, `TF_STATE_BUCKET` e `LAB_ROLE_ARN`; não distribui os secrets AWS, JWT, GHCR ou Datadog. Depois da plataforma, implante banco, autenticação e aplicação em sequência.

## Arquitetura

```mermaid
flowchart TB
    cliente["Internet"] --> gateway["API Gateway HTTP API"]
    subgraph vpc["VPC · duas zonas de disponibilidade"]
        subgraph publicas["Sub-redes públicas"]
            nat["NAT Gateway · saída para internet"]
        end
        subgraph privadas["Sub-redes privadas"]
            link["VPC Link"] --> nlb["NLB interno · TCP 80"]
            subgraph eks["Amazon EKS"]
                nodes["Managed Node Group · NodePort 30081"]
                app["Service e Pods da API · outro repositório"]
                metrics["Metrics Server"]
                autoscaler["Cluster Autoscaler"]
                nodes --> app
                metrics -.->|Métricas para o HPA da API| app
                autoscaler -.->|Escala de nós| nodes
            end
            nlb --> nodes
        end
        nodes -->|Saída dos workloads| nat
    end
    gateway --> link
    actions["GitHub Actions / Terraform"] -.->|Deploy pelo endpoint público do EKS| eks
    actions -.-> state["S3 · backend dos states e locking"]
    actions -.-> ssm["SSM · publica rede, cluster e entrada HTTP"]
```

Consulte os [recursos principais](#recursos-principais) deste componente. A [arquitetura integrada da aplicação](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/ARQUITETURA-SOLUCAO.md) reúne os quatro projetos e suas sequências.

## Arquitetura provisionada

Os nós do EKS ficam em sub-redes privadas. O endpoint do EKS permanece público para permitir a administração e o deploy pelo GitHub Actions. A aplicação é exposta externamente somente pelo API Gateway.

O Gateway, o VPC Link e a integração HTTP da aplicação são criados aqui. As rotas públicas de login/saúde e as rotas protegidas pelo Authorizer são criadas pelo repositório de autenticação. A [visão integrada de componentes](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/ARQUITETURA-SOLUCAO.md#diagrama-de-componentes-da-aplicação) inclui banco, autenticação e monitoramento.

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

## Acesso à API

Este repositório provisiona infraestrutura e não expõe uma API de negócio própria. A documentação e as requisições da aplicação consumidora estão disponíveis em:

- [Swagger local da Oficina API](http://localhost:8081/swagger-ui/index.html), após iniciar a aplicação.
- [Collection Insomnia da Oficina API](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/src/main/docs/insomnia/collection.yaml).
- [Collection Insomnia do login por CPF](https://github.com/tc-organization-26/oficina-auth-lambda/blob/HEAD/docs/insomnia/collection.json).

## Infraestrutura e integração entre os repositórios

Este Terraform cria rede, cluster e integração HTTP. A autenticação acrescenta as rotas públicas e protegidas ao Gateway; a aplicação publica o Service NodePort `30081` e os Pods.

Os parâmetros ficam sob `/oficina/ENV/network`, `/oficina/ENV/eks` e `/oficina/ENV/edge`. A plataforma usa `oficina/k8s/hom.tfstate` ou `oficina/k8s/prod.tfstate`; os demais componentes mantêm seus próprios states. Consulte as [variáveis, outputs e contratos SSM](#terraform-da-plataforma).

## Estrutura do repositório

| Arquivo ou diretório | Responsabilidade |
| --- | --- |
| [main.tf](main.tf) | VPC, EKS, add-ons e Managed Node Group |
| [edge.tf](edge.tf) | NLB, VPC Link, Gateway, integração e parâmetros SSM |
| [autoscaling.tf](autoscaling.tf) | Releases Helm do Metrics Server e Cluster Autoscaler |
| [variables.tf](variables.tf), [versions.tf](versions.tf) e [outputs.tf](outputs.tf) | Entradas, providers e dados publicados pelo Terraform |
| [terraform.tfvars.example](terraform.tfvars.example) | Exemplo inicial para aplicação pelo terminal |
| [scripts/bootstrap-lab.ps1](scripts/bootstrap-lab.ps1) | Bootstrap atual de S3, role preexistente e variáveis GitHub |
| [scripts/patch-eks-module-for-lab.ps1](scripts/patch-eks-module-for-lab.ps1) | Adaptação do módulo EKS ao ambiente educacional |
| [.github/workflows](.github/workflows) | Bootstrap manual, validação, deploy e promoção |
| [bootstrap/](bootstrap) e [scripts/bootstrap.ps1](scripts/bootstrap.ps1) | Implementação anterior de bootstrap/OIDC, fora do workflow atual |

## Terraform da plataforma

### Variáveis

| Variável | Padrão | Descrição |
| --- | --- | --- |
| `aws_region` | `us-east-1` | Região AWS |
| `lab_role_arn` | Obrigatória, sem padrão | ARN da LabRole preexistente |
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

O arquivo `terraform.tfvars.example` contém valores iniciais; informe também `lab_role_arn` e escolha explicitamente o ambiente ao aplicar. Não versione `terraform.tfvars` com valores sensíveis ou específicos da conta.

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

## Validação após o deploy

Confirme os nós EKS, os workloads de escalabilidade e os parâmetros SSM conforme o [roteiro de validação](docs/EXECUCAO-AWS.md#validar-a-plataforma). Os outputs incluem `cluster_name`, `vpc_id`, `private_subnet_ids`, `api_gateway_url` e `application_nlb_dns`.

O Gateway pode ainda não responder às rotas da aplicação: elas dependem dos deploys da autenticação e da API. Para diagnóstico, consulte [EKS e acesso](docs/TROUBLESHOOTING.md#eks-nós-e-acesso-kubernetes) ou [rede, NLB e Gateway](docs/TROUBLESHOOTING.md#rede-nlb-e-api-gateway).

## Observabilidade

Metrics Server fornece métricas ao HPA da API, e Cluster Autoscaler ajusta a capacidade dos nós. Datadog Operator/Agent, dashboards e alertas são instalados pelo deploy da aplicação, não por este Terraform. Consulte a [observabilidade da Oficina API](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/OBSERVABILIDADE.md) para a coleta integrada.

## Encerramento

Remova a plataforma depois da aplicação/observabilidade, autenticação e RDS, conforme o [encerramento](docs/EXECUCAO-AWS.md#encerramento). Preserve os states até concluir as dependências. O bucket foi criado pelo bootstrap via AWS CLI e não é destruído pelo Terraform da plataforma.

## Workflow

- [Workflow de bootstrap](.github/workflows/bootstrap.yml) e [histórico de execuções](https://github.com/tc-organization-26/oficina-k8s-infra/actions/workflows/bootstrap.yml).
- [Workflow Terraform](.github/workflows/terraform.yml) e [histórico de execuções](https://github.com/tc-organization-26/oficina-k8s-infra/actions/workflows/terraform.yml).

### Fluxo de branches

`fase-3` valida e abre PR para `homologacao`; `homologacao` faz deploy em `hom` e abre PR para `main`; `main` faz deploy em `prod`. Os merges são manuais. Executar manualmente em `fase-3` também só valida. Consulte [branches e ambientes](docs/EXECUCAO-AWS.md#branches-e-ambientes).

## Troubleshooting

Consulte o [guia de diagnóstico deste componente](docs/TROUBLESHOOTING.md) para sintomas, comandos de verificação e correções por assunto. O guia também referencia os demais componentes quando a falha atravessa rede, banco, autenticação ou aplicação.