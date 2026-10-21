[CmdletBinding()]
param(
    [string]$ModuleFile = (Join-Path $PSScriptRoot "../.terraform/modules/eks/main.tf")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ModuleFile)) {
    throw "Modulo EKS nao encontrado em '$ModuleFile'. Execute terraform init antes deste script."
}

$content = (Get-Content -LiteralPath $ModuleFile -Raw) -replace "`r`n", "`n"

$sessionOriginal = 'data "aws_iam_session_context" "current" {' + "`n" + '  count = local.create ? 1 : 0'
$sessionPatched = 'data "aws_iam_session_context" "current" {' + "`n" + '  count = 0 # AWS Lab bloqueia iam:GetRole para a role voclabs'
$bootstrapOriginal = 'bootstrap_cluster_creator_admin_permissions = false'
$bootstrapPatched = 'bootstrap_cluster_creator_admin_permissions = true # Compatibilidade com AWS Lab'

if ($content.Contains($sessionOriginal)) {
    $content = $content.Replace($sessionOriginal, $sessionPatched)
}
elseif (-not $content.Contains($sessionPatched)) {
    throw "Estrutura inesperada do modulo EKS: aws_iam_session_context nao localizado."
}

if ($content.Contains($bootstrapOriginal)) {
    $content = $content.Replace($bootstrapOriginal, $bootstrapPatched)
}
elseif (-not $content.Contains($bootstrapPatched)) {
    throw "Estrutura inesperada do modulo EKS: configuracao de bootstrap nao localizada."
}

Set-Content -LiteralPath $ModuleFile -Value $content -Encoding utf8NoBOM
Write-Host "Modulo EKS ajustado para as restricoes IAM do AWS Lab."
