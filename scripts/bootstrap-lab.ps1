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
    [string]$LabRoleName = "LabRole",
    [switch]$SkipGitHubVariables
)

$ErrorActionPreference = "Stop"

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

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "O executavel 'aws' nao foi encontrado no PATH."
}

$caller = & aws sts get-caller-identity --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $caller.Account) {
    throw "Nao foi possivel identificar a conta AWS. Atualize os secrets temporarios do Lab."
}

if (-not $StateBucketName) {
    $StateBucketName = "oficina-fiap-tfstate-$($caller.Account)"
}

Write-Host "Conta AWS detectada: $($caller.Account)"
Write-Host "Bucket de state: $StateBucketName"

& aws s3api head-bucket --bucket $StateBucketName *> $null
$bucketExists = $LASTEXITCODE -eq 0

if (-not $bucketExists) {
    Write-Host "Criando bucket de state sem gerenciamento pelo provider Terraform."
    if ($AwsRegion -eq "us-east-1") {
        Invoke-Checked aws s3api create-bucket --bucket $StateBucketName --region $AwsRegion
    }
    else {
        Invoke-Checked aws s3api create-bucket --bucket $StateBucketName --region $AwsRegion `
            --create-bucket-configuration "LocationConstraint=$AwsRegion"
    }
}
else {
    Write-Host "Bucket de state existente encontrado."
}

$versioning = '{"Status":"Enabled"}'
$encryption = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
$publicAccess = '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'

Invoke-Checked aws s3api put-bucket-versioning --bucket $StateBucketName `
    --versioning-configuration $versioning
Invoke-Checked aws s3api put-bucket-encryption --bucket $StateBucketName `
    --server-side-encryption-configuration $encryption
Invoke-Checked aws s3api put-public-access-block --bucket $StateBucketName `
    --public-access-block-configuration $publicAccess

$labRoleArn = (& aws iam get-role --role-name $LabRoleName --query Role.Arn --output text).Trim()
if ($LASTEXITCODE -ne 0 -or -not $labRoleArn -or $labRoleArn -eq "None") {
    throw "A role '$LabRoleName' nao foi encontrada ou nao pode ser consultada."
}

Write-Host "Role preexistente do Lab: $labRoleArn"

if (-not $SkipGitHubVariables) {
    if (-not $env:GH_ADMIN_TOKEN) {
        throw "GH_ADMIN_TOKEN ausente; nao foi possivel configurar as variables dos repositorios."
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI ausente; nao foi possivel configurar as variables dos repositorios."
    }

    $previousGitHubToken = $env:GH_TOKEN
    $env:GH_TOKEN = $env:GH_ADMIN_TOKEN
    try {
        foreach ($repositoryName in $Repositories) {
            $repositorySlug = "$GitHubOwner/$repositoryName"
            Write-Host "Configurando variables em $repositorySlug"
            Invoke-Checked gh variable set AWS_ROLE_ARN --body $labRoleArn --repo $repositorySlug
            Invoke-Checked gh variable set LAB_ROLE_ARN --body $labRoleArn --repo $repositorySlug
            Invoke-Checked gh variable set AWS_REGION --body $AwsRegion --repo $repositorySlug
            Invoke-Checked gh variable set TF_STATE_BUCKET --body $StateBucketName --repo $repositorySlug
        }
    }
    finally {
        $env:GH_TOKEN = $previousGitHubToken
    }
}

Write-Host "Bootstrap do Lab concluido. Bucket: $StateBucketName"
Write-Host "LabRole: $labRoleArn"
