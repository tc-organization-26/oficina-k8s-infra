# Troubleshooting — oficina-k8s-infra

[README](../README.md) · [Validação local e execução manual](VALIDACAO-E-EXECUCAO-MANUAL.md) · [Execução na AWS](EXECUCAO-AWS.md)

## Troubleshooting de outros repositórios da solução

- [Aplicação: Docker, Java, API, Pods e Datadog](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/TROUBLESHOOTING.md).
- [Banco: RDS, conectividade, credenciais e snapshots](https://github.com/tc-organization-26/oficina-db-infra/blob/HEAD/docs/TROUBLESHOOTING.md).
- [Autenticação: Python, Lambda, CPF e Authorizer](https://github.com/tc-organization-26/oficina-auth-lambda/blob/HEAD/docs/TROUBLESHOOTING.md).

Este guia parte do sintoma, indica o que conferir e orienta a correção. Execute os comandos na raiz deste repositório, salvo indicação diferente. Cada bloco é um procedimento de diagnóstico independente; os exemplos usam PowerShell.

Nos exemplos AWS, use uma sessão válida e defina:

```powershell
$oficinaEnv = "hom"
$oficinaRegion = "us-east-1"
$env:AWS_DEFAULT_REGION = $oficinaRegion
aws sts get-caller-identity
```

Para produção, altere o ambiente para `prod` e confira a conta antes de prosseguir. As credenciais do GitHub não configuram o terminal; o [guia AWS](EXECUCAO-AWS.md#credenciais-e-ferramentas) explica os pré-requisitos de acesso. Ao compartilhar evidências, informe ambiente, horário, URL/caminho, status HTTP, ID do workflow e mensagem de erro. Remova tokens, senhas e valores de secrets dos trechos compartilhados.

## Assuntos

- [Credenciais AWS e GitHub Actions](#credenciais-aws-e-github-actions)
- [Bootstrap e configuração inicial](#bootstrap-e-configuração-inicial)
- [Terraform e state S3](#terraform-e-state-s3)
- [EKS, nós e acesso Kubernetes](#eks-nós-e-acesso-kubernetes)
- [Add-ons e escalabilidade](#add-ons-e-escalabilidade)
- [Rede, NLB e API Gateway](#rede-nlb-e-api-gateway)
- [Encerramento e recursos remanescentes](#encerramento-e-recursos-remanescentes)

## Credenciais AWS e GitHub Actions

### ExpiredToken, InvalidClientTokenId ou assinatura inválida

Renove juntos `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` na organização (com acesso ao repositório) ou nos Repository secrets. Atualize também o terminal utilizado. Verifique espaços acidentais e relógio da máquina se houver erro de assinatura/tempo. Repita `aws sts get-caller-identity`; ele precisa identificar a conta esperada antes de um novo deploy.

Se o erro persistir no Actions, confira se um secret do Environment está sobrescrevendo o valor renovado da organização. Reinicie a execução após corrigir; não é necessário refazer o bootstrap só para renovar credenciais.

### ParameterNotFound, ResourceNotFound ou recursos do ambiente errado

Confirme `AWS_REGION`, o ambiente (`hom`/`prod`), o prefixo `/oficina/ENV` e a conclusão da etapa anterior. Plataforma, banco e autenticação usam `dev` como padrão Terraform; a observabilidade da API usa `hom`. Selecione explicitamente `hom` ou `prod` para integrar o ambiente implantado. A primeira instalação segue bootstrap → plataforma → banco → autenticação → API → reexecução da autenticação para Datadog.

```powershell
aws ssm get-parameters-by-path --path "/oficina/$oficinaEnv" --recursive --query "Parameters[].Name" --output table
```

Uma lista vazia pode indicar conta/região errada ou pré-requisito ainda ausente. `AccessDenied` significa falta de permissão, não prova que o recurso não existe.

### Deploy pulado, execução aguardando aprovação ou PR sem checks novos

`fase-3` valida; apenas `homologacao` e `main` fazem deploy. O merge para `homologacao` já dispara a implantação em `hom`; não execute outro deploy manual após um merge bem-sucedido. Abrir um PR não dispara uma execução adicional: os workflows atuais não têm gatilho `pull_request`.

Se o job aguardar aprovação, confira as regras do GitHub Environment `homologacao`/`producao`. Se aguardar outro workflow, confira a concorrência configurada. Os runners são `ubuntu-latest`; instruções antigas para instalar um runner Windows self-hosted não se aplicam.

### Workflow não aparece, ferramentas faltam ou execução usa código antigo

Confira se o arquivo está em `.github/workflows`, se a branch selecionada contém a versão esperada e se o workflow permite execução manual. Uma alteração local ainda não enviada ao GitHub não muda o Actions. Na interface, procure o nome do workflow; no CLI, use o nome do arquivo mostrado no README.

`command not found` em um runner indica que a etapa de setup não foi executada ou que foi usada outra branch/versão do workflow. Confira o log dessa etapa antes de instalar ferramentas por fora da esteira. Para uma execução pendente, confira disponibilidade do runner e limites de uso da organização.

### PR automático falha com Resource not accessible by integration ou 403

Confira permissões de escrita e criação de PRs em **Settings → Actions → General → Workflow permissions**, além das políticas da organização. A promoção usa `GITHUB_TOKEN`; `GH_ADMIN_TOKEN` é reservado ao bootstrap. Verifique se a execução de origem passou e se há commits a promover. PR já existente é reutilizado; falha de deploy impede a promoção seguinte.

### IAM nega CreateRole, CreateOpenIDConnectProvider, PassRole ou leitura de secrets

O fluxo educacional atual reutiliza LabRole e não cria roles/OIDC. Tentativas de criação podem indicar código de outra branch ou bootstrap legado. Leia a ação e o recurso negados no log e confira a role configurada; reutilizar LabRole não garante todas as permissões necessárias. A instituição precisa liberar a ação quando houver negação imposta pela conta. Não troque para credenciais de outra conta mantendo o mesmo state.

## Bootstrap e configuração inicial

### GH_ADMIN_TOKEN ausente, GitHub 404 ou falha ao gravar variables

Confirme os quatro repositórios remotos, seus nomes e o acesso do token para leitura e administração de Actions Variables. `GH_ADMIN_TOKEN` fica neste repositório; o bootstrap não seleciona Environment e precisa encontrar também os três secrets AWS fora de Environment secrets. Um 404 de repositório privado pode ser falta de acesso.

O script usa `tc-organization-26` e a lista dos quatro repositórios por padrão. Em outra organização, revise os parâmetros `GitHubOwner`/`Repositories` do script e a chamada do workflow. O token do bootstrap não é o token de leitura do GHCR nem o `GITHUB_TOKEN` de promoção.

### LabRole não existe ou iam:GetRole é negado

O bootstrap consulta a LabRole preexistente; ele não a cria. Confira conta, nome da role e permissão de leitura. O patch do módulo EKS evita uma consulta à role `voclabs`, mas não elimina a consulta da LabRole no bootstrap. Em conta comum, adapte IAM conforme a observação do guia AWS; trocar somente o nome de uma variable não prepara as roles.

### BucketAlreadyExists, região incorreta ou bootstrap tenta criar bucket existente

O nome S3 é global; use um bucket apropriado da conta e região. `head-bucket` retorna erro tanto por falta de acesso quanto por ausência, e o script atual pode tentar criar o bucket após uma falha de acesso. Confira a mensagem original e as permissões de versionamento, criptografia e bloqueio público. Não remova um bucket existente para contornar esse erro.

### Bootstrap parou pela metade ou variables não aparecem

Ele executa S3, consulta da role e distribuição ao GitHub em sequência. Confira a última operação concluída; um bucket já criado não significa que todas as variables foram gravadas. Corrija a causa e repita o bootstrap para reutilizar o bucket. Confira `AWS_REGION`, `TF_STATE_BUCKET` e `LAB_ROLE_ARN` nos quatro repositórios. `AWS_ROLE_ARN` é de compatibilidade; secrets AWS/JWT/GHCR/Datadog não são distribuídos por esse script.

### Patch não encontra o módulo ou informa estrutura inesperada

```powershell
terraform init -backend=false
pwsh ./scripts/patch-eks-module-for-lab.ps1
terraform validate
```

Use PowerShell 7 (`pwsh`) na raiz. O patch depende da estrutura do módulo EKS `21.26.0`; uma atualização de módulo exige revisar o patch. Ele modifica a cópia em `.terraform/modules` e precisa ser aplicado após cada init do fluxo atual. Não edite o cache à mão nem remova o patch sem preparar o acesso ao cluster.

## Terraform e state S3

### Terraform ausente, pasta errada ou sintaxe inválida

Use Terraform compatível com o projeto (o CI fixa `1.15.9`, mínimo `1.10.0`). Confira `terraform version`. Os arquivos Terraform deste componente ficam na raiz. Em `terraform.tfvars`, use HCL com valores literais ou variáveis `TF_VAR_*`; expressões Spring como `${VAR:padrao}` não são válidas nesse arquivo. `TF_VAR_*` não substitui os argumentos do backend.

```powershell
terraform fmt -check -recursive
terraform init -backend=false
pwsh ./scripts/patch-eks-module-for-lab.ps1
terraform validate
```

`fmt -check` informa divergência de formato; aplique `fmt` nos arquivos que alterou e revise o diff. O `init -backend=false` valida sem acessar o state S3, mas ainda pode baixar providers/módulos. Ele não prepara a aplicação na AWS.

### Falha no download, checksum ou provider incompatível

Confira rede, proxy, certificados e as versões de Terraform/providers declaradas. Use o lockfile versionado; um erro de checksum pode indicar pacote corrompido, plataforma sem hash registrado ou mudança de dependências. Não apague o lockfile nem rode `init -upgrade` como correção automática: isso pode selecionar versões diferentes. Mudanças de provider devem ser intencionais, revisadas e validadas antes do plano.

### Bucket ausente, AccessDenied ou Backend configuration changed

Conclua o bootstrap e confirme o bucket em `TF_STATE_BUCKET`, conta e região. Uma resposta 403 de `head-bucket` não prova ausência do bucket. O backend precisa de acesso aos objetos do state e do lock. No terminal, informe o mesmo bucket e a mesma chave do CI/CD:

```powershell
$oficinaBucket = "BUCKET_DISTRIBUIDO_PELO_BOOTSTRAP"
$env:TF_VAR_environment = $oficinaEnv
$env:TF_VAR_aws_region = $oficinaRegion
$env:TF_VAR_lab_role_arn = "arn:aws:iam::ACCOUNT_ID:role/LabRole"
aws s3api head-bucket --bucket $oficinaBucket
terraform init -reconfigure `
  -backend-config="bucket=$oficinaBucket" `
  -backend-config="key=oficina/k8s/$oficinaEnv.tfstate" `
  -backend-config="region=$oficinaRegion" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"
pwsh ./scripts/patch-eks-module-for-lab.ps1
```

`-reconfigure` seleciona a configuração; não transfere automaticamente os recursos de outro state. Se há uma migração real de backend, preserve backup e planeje a migração, em vez de apontar um state vazio para recursos existentes. Pedidos de `secret_suffix`, `KUBE_CONFIG_BASE64` ou backend Kubernetes indicam instruções antigas da fase 2.

### Error acquiring the state lock

Confira execuções ativas no Actions e terminais. Aguarde a operação que possui o lock; interromper o acompanhamento não significa que o processo parou. As esteiras serializam sua própria branch, mas um apply manual ainda pode concorrer.

Somente após confirmar que não há operação ativa e que o backend acima é o correto, remova um lock abandonado com o ID exibido no erro:

```powershell
terraform force-unlock ID_EXATO_MOSTRADO_NO_ERRO
```

Não use `-lock=false`, não reutilize um ID de exemplo e não apague o objeto `.tflock` como rotina. Consulte a [referência do force-unlock](https://developer.hashicorp.com/terraform/cli/commands/force-unlock).

### Apply interrompido, recurso já existente ou plano propõe recriação inesperada

Uma execução com falha pode ter criado parte dos recursos. Preserve state e logs, corrija a causa e gere um novo plano no mesmo backend; não reaplique um plano salvo antes de mudanças no ambiente. Se o plano tentar criar tudo novamente, confira a chave, workspace e conta. O projeto usa o workspace padrão e chaves distintas por ambiente.

Recursos existentes fora do state exigem avaliação de importação, não exclusão por tentativa. Revise substituições e destruições antes de aplicar. Não edite o state manualmente para esconder uma divergência.

## EKS, nós e acesso Kubernetes

### Cluster não aparece, kubectl usa outro contexto ou ExecCredential é incompatível

Confira estado do cluster e gere o kubeconfig com a sessão/conta corretas:

```powershell
aws eks list-clusters --region $oficinaRegion
aws eks describe-cluster --name "oficina-$oficinaEnv-eks" --query "cluster.{Name:name,Status:status,Endpoint:endpoint}" --output table
aws eks update-kubeconfig --name "oficina-$oficinaEnv-eks" --region $oficinaRegion
kubectl config current-context
kubectl get nodes -o wide
```

Os nomes acima usam `project_name=oficina`. Se o cluster ainda não existir, consulte a etapa Terraform que falhou; se existir com outro prefixo, use o nome real. Para `ExecCredential v1alpha1`, confira AWS CLI/kubectl do ambiente e regere o kubeconfig; não substitua a versão de API no arquivo por tentativa.

### Unauthorized ou Forbidden

As credenciais AWS podem ser válidas sem acesso Kubernetes. Confira a identidade usada na criação e a identidade atual. O fluxo educacional habilita o acesso inicial do criador por patch; outra role pode não ter esse acesso. Preserve o state e o log de criação antes de revisar permissões. Criar o cluster com outra credencial e depois renovar para uma identidade diferente pode mudar o acesso.

### Timeout, erro x509 ou conexão recusada ao endpoint EKS

Confira DNS, proxy, certificado, rede local e o endpoint retornado pela AWS. O endpoint administrativo é público neste Terraform; isso não torna nós/NLB/RDS públicos. Use o kubeconfig do cluster atual, não de uma recriação anterior. Não adicione flags de ignorar TLS como solução permanente.

### NodeCreationFailure, nós NotReady ou node group não estabiliza

```powershell
aws eks list-nodegroups --cluster-name "oficina-$oficinaEnv-eks" --output table
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

Consulte também `aws eks describe-nodegroup --cluster-name NOME_DO_CLUSTER --nodegroup-name NOME_REAL_DO_NODEGROUP`. Leia `health.issues` e status antes de repetir o apply. Confira LabRole/PassRole, limites da conta, disponibilidade do tipo de instância, rotas/NAT, DNS e comunicação com o control plane. Não substitua o provisionamento por `eksctl create cluster`: isso criaria recursos fora deste state. Veja a [referência EKS](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html).

### Pods Pending, sem capacidade ou IPs disponíveis

Eventos `Insufficient cpu/memory` pedem avaliar requests e capacidade; o node group tem mínimo 1, desejado 2 e máximo 4 por padrão. Falhas de criação de sandbox/IP podem indicar CNI ou sub-redes sem endereços. Confira os Pods de sistema, o autoscaler, quotas e disponibilidade de endereços antes de aumentar réplicas. O HPA da API e a escala de nós são mecanismos diferentes.

## Add-ons e escalabilidade

### Metrics Server ausente ou kubectl top sem métricas

```powershell
kubectl get deployment metrics-server -n kube-system
kubectl logs deployment/metrics-server -n kube-system --tail=100
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

Confira rollout, APIService, eventos e comunicação com kubelet. Aguarde métricas após inicialização. O release é gerenciado por `autoscaling.tf`; não instale outra cópia por manifesto latest. O antigo patch de certificado do Docker Desktop não é um procedimento padrão para EKS.

### Cluster Autoscaler não escala ou AccessDenied

```powershell
helm status cluster-autoscaler -n kube-system
kubectl get deployment -n kube-system -l app.kubernetes.io/instance=cluster-autoscaler
kubectl logs -n kube-system -l app.kubernetes.io/instance=cluster-autoscaler --tail=120
```

O nome do Deployment pode ser composto pelo chart; procure o release/label em vez de assumir que ele se chama exatamente `cluster-autoscaler`. Confira descoberta do cluster, permissões Auto Scaling na role dos nós e acesso às credenciais via IMDSv2. O launch template do fluxo educacional usa hop limit 2 e IRSA desabilitado. Verifique tags/ASG, versão do autoscaler compatível com Kubernetes e máximo de nós; o chart não tem versão fixada no Terraform atual. Uma escala recusada por quota/capacidade não se resolve apenas aumentando o HPA.

### Helm release já existe, falha de certificado ou timeout no apply

Confira acesso Kubernetes antes de culpar o chart. Se um release já existir fora do state, avalie importação e propriedade do recurso, sem apagar às cegas. Inspecione `helm list -n kube-system`, eventos e logs dos workloads. Os providers Helm precisam acessar o cluster e executar `aws eks get-token`; credenciais AWS renovadas são necessárias também nessa etapa.

### PVC Pending ou EBS CSI sem permissão

O banco deste projeto é RDS; não há PVC PostgreSQL a corrigir no EKS. Se outro workload usar EBS, confira StorageClass, eventos do PVC e permissões/identidade do add-on EBS CSI. Não use instruções antigas de `postgres-data` ou `hostpath` para reparar o RDS.

## Rede, NLB e API Gateway

### Gateway responde 404 após provisionar a plataforma

Este Terraform cria Gateway, stage, VPC Link e integração HTTP, mas as rotas são criadas por `oficina-auth-lambda`. Antes desse deploy, um 404 pode ser esperado. Confira conta, URL atual e rotas:

```powershell
$oficinaApiId = aws ssm get-parameter --name "/oficina/$oficinaEnv/edge/http-api-id" --query Parameter.Value --output text
aws apigatewayv2 get-routes --api-id $oficinaApiId --query "Items[].{Route:RouteKey,Auth:AuthorizationType}" --output table
```

O stage é `$default`: não acrescente `/hom` ou `/prod` à URL. Use o novo ID após recriação do Gateway. Se uma rota protegida for recusada por JWT, continue no guia de autenticação.

### Gateway retorna 502/503/504, mas port-forward funciona

Investigue integração, VPC Link, NLB, targets e NodePort. O NLB é interno e não é um endpoint público para o computador. Consulte o estado da ligação e dos targets:

```powershell
aws apigatewayv2 get-vpc-links --query "Items[].{Name:Name,State:VpcLinkStatus}" --output table
aws elbv2 describe-load-balancers --query "LoadBalancers[].{Name:LoadBalancerName,Scheme:Scheme,State:State.Code}" --output table
aws elbv2 describe-target-groups --query "TargetGroups[].{Name:TargetGroupName,Arn:TargetGroupArn,Port:Port}" --output table
aws elbv2 describe-target-health --target-group-arn ARN_DO_TARGET_GROUP --output table
```

Use o ARN do ambiente correto. Confira SG/rede do VPC Link, listener TCP 80, target group na porta do NodePort e attachment ao ASG dos nós. O healthcheck do NLB é TCP: target saudável não comprova que o readiness HTTP/banco está saudável. Compare com `GET /actuator/health/readiness` e com o diagnóstico do Service/Pods da API.

### Service sem EXTERNAL-IP, NodePort inacessível ou ENIs/SGs em uso

É esperado: Service NodePort, nós e NLB ficam privados, com acesso público pelo Gateway. Não altere o Service para LoadBalancer para contornar o desenho. Na remoção, dependências Lambda/VPC Link/RDS podem manter ENIs e SGs em uso; confira a origem e remova na ordem do guia AWS. Não apague interfaces gerenciadas manualmente durante um apply/destroy.

### Nós não baixam imagens, Lambdas sem internet ou NAT indisponível

Confira `enable_nat_gateway`, estado do NAT, rotas das sub-redes privadas e saída DNS/HTTPS. O NAT usa sub-rede pública com rota ao Internet Gateway. Desabilitar o NAT sem fornecer outra saída pode interromper GHCR, Secrets Manager e Datadog. Uma sub-rede chamada pública não garante IP público a todo workload; o login Lambda usa rede privada.

## Encerramento e recursos remanescentes

### Destroy falha por dependência ou recursos continuam na conta

Conclua a [ordem de encerramento](EXECUCAO-AWS.md#encerramento): API/observabilidade, autenticação, banco e só então plataforma. Confira a mesma conta/região/state do apply. Recursos podem levar tempo para liberar dependências; leia o erro antes de repetir. O bucket de state é criado fora do Terraform e deve ser preservado até o fim.

```powershell
aws eks list-clusters --region $oficinaRegion
aws ec2 describe-nat-gateways --filter "Name=state,Values=pending,available,deleting" --query "NatGateways[].{Id:NatGatewayId,State:State,Vpc:VpcId}" --output table
aws elbv2 describe-load-balancers --query "LoadBalancers[].{Name:LoadBalancerName,State:State.Code}" --output table
```

Confira também EC2, volumes, IPs elásticos, RDS/snapshots, logs e monitores externos pertinentes. Uma lista vazia de EKS não comprova encerramento de todos os recursos. A renovação ou expiração de credenciais não substitui a remoção do ambiente.
