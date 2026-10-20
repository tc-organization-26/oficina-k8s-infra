[CmdletBinding()]
param(
    [string]$StateBucketName,
    [string]$AwsRegion = "us-east-1",
    [string]$GitHubOwner = "tc-organization-26",
    [string[]]$Repositories = @(
        "gestao-oficina-tc-1",
        "oficina-k8s-infra",
        "oficina-db-infra",
        "oficina-auth-lambda"
    ),
    [string[]]$LegacyRepositories = @("gestao-oficina-tc-1"),
    [switch]$SkipGitHubVariables
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$terraformDirectory = Join-Path $projectRoot "bootstrap"
$generatedVariables = Join-Path $terraformDirectory "repositories.auto.tfvars.json"
$backendFile = Join-Path $terraformDirectory "backend.tf"

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(ValueFromRemainingArguments)] [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "O comando '$Command $($Arguments -join ' ')' terminou com codigo $LASTEXITCODE."
    }
}

function Get-GitHubResource {
    param([Parameter(Mandatory)] [string]$Uri)

    $headers = @{
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"           = "oficina-bootstrap"
    }
    if ($env:GH_ADMIN_TOKEN) {
        $headers.Authorization = "Bearer $($env:GH_ADMIN_TOKEN)"
    }

    Invoke-RestMethod -Uri $Uri -Headers $headers
}

function Set-BackendFile {
    @"
terraform {
  backend "s3" {}
}
"@ | Set-Content -LiteralPath $backendFile -Encoding utf8
}

foreach ($command in @("aws", "terraform")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "O executavel '$command' nao foi encontrado no PATH."
    }
}

$caller = & aws sts get-caller-identity --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $caller.Account) {
    throw "Nao foi possivel identificar a conta AWS. Atualize as credenciais do Lab."
}

if (-not $StateBucketName) {
    $StateBucketName = "oficina-fiap-tfstate-$($caller.Account)"
}

Write-Host "Conta AWS detectada: $($caller.Account)"
Write-Host "Bucket de state: $StateBucketName"

try {
    $owner = Get-GitHubResource "https://api.github.com/orgs/$GitHubOwner"
}
catch {
    $owner = Get-GitHubResource "https://api.github.com/users/$GitHubOwner"
}

$repositoryVariables = [ordered]@{}
foreach ($repositoryName in $Repositories) {
    $repository = Get-GitHubResource "https://api.github.com/repos/$GitHubOwner/$repositoryName"
    $repositoryVariables[$repositoryName] = [ordered]@{
        repository_id     = [string]$repository.id
        immutable_subject = $LegacyRepositories -notcontains $repositoryName
    }
}

$oidcProviderArn = "arn:aws:iam::$($caller.Account):oidc-provider/token.actions.githubusercontent.com"
& aws iam get-open-id-connect-provider --open-id-connect-provider-arn $oidcProviderArn *> $null
$oidcProviderExists = $LASTEXITCODE -eq 0

$configuration = [ordered]@{
    aws_region          = $AwsRegion
    state_bucket_name   = $StateBucketName
    github_owner        = $GitHubOwner
    github_owner_id     = [string]$owner.id
    github_repositories = $repositoryVariables
}
if ($oidcProviderExists) {
    $configuration.existing_github_oidc_provider_arn = $oidcProviderArn
}

$configuration | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $generatedVariables -Encoding utf8

& aws s3api head-bucket --bucket $StateBucketName *> $null
$stateBucketExists = $LASTEXITCODE -eq 0

if ($stateBucketExists) {
    Write-Host "Bootstrap existente encontrado; conectando ao state remoto."
    Set-BackendFile
    Invoke-Checked terraform "-chdir=$terraformDirectory" init -reconfigure `
        "-backend-config=bucket=$StateBucketName" `
        "-backend-config=key=bootstrap/terraform.tfstate" `
        "-backend-config=region=$AwsRegion" `
        "-backend-config=encrypt=true" `
        "-backend-config=use_lockfile=true"

    $stateAccount = & terraform "-chdir=$terraformDirectory" output -raw aws_account_id 2>$null
    if ($LASTEXITCODE -eq 0 -and $stateAccount -and $stateAccount.Trim() -ne [string]$caller.Account) {
        throw "O state pertence a conta $($stateAccount.Trim()), mas as credenciais atuais pertencem a $($caller.Account)."
    }

    Invoke-Checked terraform "-chdir=$terraformDirectory" apply -auto-approve
}
else {
    Write-Host "Primeira execucao; criando os recursos com state local temporario."
    if (Test-Path $backendFile) {
        Remove-Item -LiteralPath $backendFile -Force
    }

    Invoke-Checked terraform "-chdir=$terraformDirectory" init
    Invoke-Checked terraform "-chdir=$terraformDirectory" apply -auto-approve

    Write-Host "Migrando o state do bootstrap para o S3."
    Set-BackendFile
    Invoke-Checked terraform "-chdir=$terraformDirectory" init -migrate-state -force-copy `
        "-backend-config=bucket=$StateBucketName" `
        "-backend-config=key=bootstrap/terraform.tfstate" `
        "-backend-config=region=$AwsRegion" `
        "-backend-config=encrypt=true" `
        "-backend-config=use_lockfile=true"
}

$roleArn = (& terraform "-chdir=$terraformDirectory" output -raw github_actions_role_arn).Trim()

if (-not $SkipGitHubVariables) {
    if (-not $env:GH_ADMIN_TOKEN) {
        Write-Warning "GH_ADMIN_TOKEN ausente; as variaveis dos repositorios nao foram configuradas."
    }
    elseif (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warning "GitHub CLI ausente; as variaveis dos repositorios nao foram configuradas."
    }
    else {
        $previousGitHubToken = $env:GH_TOKEN
        $env:GH_TOKEN = $env:GH_ADMIN_TOKEN
        try {
            foreach ($repositoryName in $Repositories) {
                $repositorySlug = "$GitHubOwner/$repositoryName"
                Invoke-Checked gh variable set AWS_ROLE_ARN --body $roleArn --repo $repositorySlug
                Invoke-Checked gh variable set AWS_REGION --body $AwsRegion --repo $repositorySlug
                Invoke-Checked gh variable set TF_STATE_BUCKET --body $StateBucketName --repo $repositorySlug
            }
        }
        finally {
            $env:GH_TOKEN = $previousGitHubToken
        }
    }
}

Write-Host "Bootstrap concluido. Role OIDC: $roleArn"
