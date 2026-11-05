<#
.SYNOPSIS
  Sets up the whole DevFlow DevOps lab on this machine with one command.

.DESCRIPTION
  1. Checks Docker Desktop and its Kubernetes cluster are running
  2. Creates the Kubernetes namespaces, quotas and the Jenkins deploy account (RBAC)
  3. Installs metrics-server (for autoscaling) and Prometheus + Grafana
  4. Starts the registry and SonarQube, then configures SonarQube (password, token, webhook)
  5. Builds and starts Jenkins, which configures itself from ci/jenkins/casc.yaml
  Safe to run again: every step checks what already exists.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoUrl = 'https://github.com/Shash309/DevFlow.git'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$CiDir = Join-Path $Root 'ci'
$EnvFile = Join-Path $CiDir '.env'
$SecretsDir = Join-Path $CiDir 'secrets'
$KubeContext = 'docker-desktop'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "    $text" -ForegroundColor Green }

function New-Password([int]$Length = 20) {
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $bytes = New-Object byte[] $Length
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Read-EnvFile {
    $values = [ordered]@{}
    if (Test-Path $EnvFile) {
        foreach ($line in Get-Content $EnvFile) {
            if ($line -match '^\s*([A-Z_]+)=(.*)$') { $values[$Matches[1]] = $Matches[2] }
        }
    }
    $values
}

function Write-EnvFile($values) {
    $lines = $values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    [IO.File]::WriteAllLines($EnvFile, [string[]]$lines)
}

function Invoke-Native {
    # Runs a native command and stops the script if it fails
    param([scriptblock]$Command, [string]$What)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)" }
}

function Wait-Until([scriptblock]$Condition, [string]$What, [int]$TimeoutSeconds = 300) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try { if (& $Condition) { return } } catch { }
        Start-Sleep -Seconds 5
    }
    throw "Timed out waiting for $What"
}

function kc { & kubectl --context $KubeContext @args }

# ---------------------------------------------------------------------------
Step 'Checking prerequisites'
docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker is not running. Start Docker Desktop and try again.' }
Ok 'Docker is running'

kc get nodes *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Kubernetes context '$KubeContext' is not reachable. In Docker Desktop: Settings > Kubernetes > Enable Kubernetes > Apply & restart."
}
Ok 'Kubernetes (docker-desktop) is running'

# ---------------------------------------------------------------------------
Step 'Generating passwords (ci/.env, git-ignored)'
$envValues = Read-EnvFile
foreach ($key in 'JENKINS_ADMIN_PASSWORD', 'SONAR_ADMIN_PASSWORD') {
    if (-not $envValues[$key]) { $envValues[$key] = New-Password }
}
if (-not $envValues['SONAR_TOKEN']) { $envValues['SONAR_TOKEN'] = 'pending' }
$envValues['DEVFLOW_REPO_URL'] = $RepoUrl
Write-EnvFile $envValues
Ok "Passwords stored in $EnvFile"

# ---------------------------------------------------------------------------
Step 'Creating namespaces, quotas and Jenkins RBAC'
Invoke-Native { kc apply -f (Join-Path $Root 'k8s\namespaces.yaml') } 'Namespaces'
Invoke-Native { kc apply -f (Join-Path $Root 'k8s\quotas.yaml') } 'Quotas'
Invoke-Native { kc apply -f (Join-Path $Root 'k8s\jenkins-rbac.yaml') } 'RBAC'

# ---------------------------------------------------------------------------
Step 'Installing metrics-server (needed by the production autoscaler)'
Invoke-Native { kc apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml } 'metrics-server'
# Docker Desktop's kubelet uses a self-signed certificate
$args0 = kc -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}'
if ($args0 -notmatch 'kubelet-insecure-tls') {
    Invoke-Native {
        kc -n kube-system patch deploy metrics-server --type=json `
            -p '[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'
    } 'metrics-server patch'
}

# ---------------------------------------------------------------------------
Step 'Installing Prometheus and Grafana (namespace monitoring)'
kc -n monitoring get secret grafana-admin *> $null
if ($LASTEXITCODE -ne 0) {
    $envValues['GRAFANA_ADMIN_PASSWORD'] = New-Password
    Write-EnvFile $envValues
    Invoke-Native { kc -n monitoring create secret generic grafana-admin --from-literal=password=$($envValues['GRAFANA_ADMIN_PASSWORD']) } 'Grafana secret'
}
Invoke-Native { kc apply -k (Join-Path $Root 'k8s\monitoring') } 'Monitoring'

# ---------------------------------------------------------------------------
Step 'Writing the kubeconfig Jenkins deploys with (least-privilege ServiceAccount)'
Wait-Until { (kc -n devflow-ci get secret jenkins-deployer-token -o jsonpath='{.data.token}') } 'the ServiceAccount token'
$token = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kc -n devflow-ci get secret jenkins-deployer-token -o jsonpath='{.data.token}')))
$caData = kc -n devflow-ci get secret jenkins-deployer-token -o jsonpath='{.data.ca\.crt}'
$server = kc config view --minify -o jsonpath='{.clusters[0].cluster.server}'
$serverUri = [Uri]$server
# Inside the Jenkins container the host is host.docker.internal; the certificate is for the original name
$containerServer = "https://host.docker.internal:$($serverUri.Port)"
New-Item -ItemType Directory -Force $SecretsDir | Out-Null
$kubeconfig = @"
apiVersion: v1
kind: Config
clusters:
  - name: docker-desktop
    cluster:
      server: $containerServer
      tls-server-name: $($serverUri.Host)
      certificate-authority-data: $caData
users:
  - name: jenkins-deployer
    user:
      token: $token
contexts:
  - name: jenkins
    context:
      cluster: docker-desktop
      user: jenkins-deployer
current-context: jenkins
"@
[IO.File]::WriteAllText((Join-Path $SecretsDir 'kubeconfig'), $kubeconfig)
Ok 'ci/secrets/kubeconfig written'

# ---------------------------------------------------------------------------
Step 'Starting the registry and SonarQube'
$compose = @('compose', '--env-file', $EnvFile, '-f', (Join-Path $CiDir 'docker-compose.yml'))
Invoke-Native { docker @compose up -d registry sonarqube } 'docker compose (registry, sonarqube)'

$sonar = 'http://localhost:9000'
Write-Host '    Waiting for SonarQube to start (first start takes 1-3 minutes)...'
Wait-Until { (Invoke-RestMethod "$sonar/api/system/status").status -eq 'UP' } 'SonarQube' 600

function Get-BasicAuth($user, $password) {
    @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${user}:$password")) }
}
$sonarPassword = $envValues['SONAR_ADMIN_PASSWORD']
$defaultAuth = Get-BasicAuth 'admin' 'admin'
$isDefault = $false
try { $isDefault = (Invoke-RestMethod "$sonar/api/authentication/validate" -Headers $defaultAuth).valid } catch { }
if ($isDefault) {
    Invoke-RestMethod -Method Post "$sonar/api/users/change_password" -Headers $defaultAuth `
        -Body @{ login = 'admin'; previousPassword = 'admin'; password = $sonarPassword } | Out-Null
    Ok 'SonarQube admin password changed from the default'
}
$auth = Get-BasicAuth 'admin' $sonarPassword

# Fresh analysis token for Jenkins on every run
try { Invoke-RestMethod -Method Post "$sonar/api/user_tokens/revoke" -Headers $auth -Body @{ name = 'jenkins' } | Out-Null } catch { }
$tokenResponse = Invoke-RestMethod -Method Post "$sonar/api/user_tokens/generate" -Headers $auth -Body @{ name = 'jenkins' }
$envValues['SONAR_TOKEN'] = $tokenResponse.token
Write-EnvFile $envValues
Ok 'SonarQube token for Jenkins created'

# Webhook: SonarQube tells Jenkins the Quality Gate result
$hooks = (Invoke-RestMethod "$sonar/api/webhooks/list" -Headers $auth).webhooks
if (-not ($hooks | Where-Object { $_.name -eq 'jenkins' })) {
    Invoke-RestMethod -Method Post "$sonar/api/webhooks/create" -Headers $auth `
        -Body @{ name = 'jenkins'; url = 'http://devflow-jenkins:8080/sonarqube-webhook/' } | Out-Null
    Ok 'SonarQube -> Jenkins webhook created'
}

# ---------------------------------------------------------------------------
Step 'Building and starting Jenkins (configured as code)'
Invoke-Native { docker @compose up -d --build jenkins } 'docker compose (jenkins)'
Write-Host '    Waiting for Jenkins...'
Wait-Until {
    try { Invoke-WebRequest 'http://localhost:8080/login' -UseBasicParsing -TimeoutSec 5 | Out-Null; $true } catch { $false }
} 'Jenkins' 600

# ---------------------------------------------------------------------------
Step 'Done'
@"

  Jenkins     http://localhost:8080    user: admin   password: JENKINS_ADMIN_PASSWORD in ci\.env
  SonarQube   http://localhost:9000    user: admin   password: SONAR_ADMIN_PASSWORD in ci\.env
  Grafana     http://localhost:30300   (view without login; admin password: GRAFANA_ADMIN_PASSWORD in ci\.env)
  Prometheus  http://localhost:30090
  Registry    http://localhost:5000/v2/_catalog

  Environments (after their first pipeline run):
    development http://localhost:30001    testing    http://localhost:30002
    staging     http://localhost:30003    production http://localhost:30004

  Jenkins checks GitHub every minute and builds develop, testing, staging, main and feature/* branches.
"@ | Write-Host
