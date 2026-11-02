# Tecnologias e versões — oficina-k8s-infra

[README](../README.md) · [Validação local e execução manual](VALIDACAO-E-EXECUCAO-MANUAL.md) · [Execução no laboratório AWS](EXECUCAO-LAB-AWS.md)

| Tecnologia | Versão / referência | Uso |
| --- | --- | --- |
| Terraform | 1.15.9 no CI; mínimo 1.10.0 | Provisionamento da plataforma |
| Providers AWS / Helm | 6.69.1 / 3.3.0 no lock | Constraints `~> 6.0` / `~> 3.0` |
| Módulos VPC / EKS | 6.7.3 / 21.26.0 | Módulos Terraform fixados |
| Kubernetes/EKS | 1.34 por padrão | Cluster e workloads |
| Metrics Server / Cluster Autoscaler | Versão dos charts não fixada | Add-ons instalados pelo Helm |
| PowerShell / AWS CLI / kubectl | 7+ / 2.36.34 / 1.34.1 | Ferramentas de referência; PowerShell sem patch fixado |
| VPC, EC2, NLB, API Gateway, IAM, S3 e SSM | Serviços gerenciados | Rede, entrada HTTP, identidade, state e descoberta |
| GitHub Actions | Serviço gerenciado | Versões das actions no workflow |

As versões fixadas no código e nos lockfiles prevalecem. As tabelas distinguem versões fixadas, faixas aceitas, valores padrão e ferramentas de referência.

## Fontes das versões

- [versions.tf](../versions.tf), [lockfile](../.terraform.lock.hcl) e [workflow](../.github/workflows/terraform.yml): Terraform e providers.
- [main.tf](../main.tf): módulos VPC/EKS; [variables.tf](../variables.tf): versão padrão do Kubernetes.
- [autoscaling.tf](../autoscaling.tf): charts Metrics Server e Cluster Autoscaler sem atributo `version`; a fase-2 não fornece uma versão fixada para esses charts.

O chart de uma ferramenta, o binário Helm e o provider Terraform Helm possuem versões independentes. A presença do add-on EBS CSI no módulo EKS também não fixa uma versão específica do driver.

Serviços como GitHub Actions, GHCR, S3 e Secrets Manager não possuem uma versão de produto fixada pelo projeto.
