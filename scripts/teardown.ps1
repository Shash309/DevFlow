<#
.SYNOPSIS
  Removes the DevFlow lab from this machine.

.DESCRIPTION
  Deletes the environment and monitoring namespaces (apps, databases, Prometheus, Grafana)
  and stops Jenkins, SonarQube and the registry.
  With -Purge it also deletes their data volumes and ci\.env (a clean slate).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\teardown.ps1
  powershell -ExecutionPolicy Bypass -File scripts\teardown.ps1 -Purge
#>
[CmdletBinding()]
param([switch]$Purge)

$Root = Split-Path -Parent $PSScriptRoot
$CiDir = Join-Path $Root 'ci'
$EnvFile = Join-Path $CiDir '.env'

Write-Host '==> Deleting Kubernetes namespaces (apps, databases, monitoring)' -ForegroundColor Cyan
kubectl --context docker-desktop delete -f (Join-Path $Root 'k8s\namespaces.yaml') --ignore-not-found --wait=false
kubectl --context docker-desktop delete clusterrole,clusterrolebinding devflow-prometheus --ignore-not-found

Write-Host '==> Stopping Jenkins, SonarQube and the registry' -ForegroundColor Cyan
$compose = @('compose', '-f', (Join-Path $CiDir 'docker-compose.yml'))
if (Test-Path $EnvFile) { $compose = @('compose', '--env-file', $EnvFile, '-f', (Join-Path $CiDir 'docker-compose.yml')) }
if ($Purge) {
    docker @compose down -v
    docker volume rm devflow-trivy-cache 2>$null
    Remove-Item $EnvFile, (Join-Path $CiDir 'secrets') -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '    Data volumes and ci\.env deleted' -ForegroundColor Yellow
} else {
    docker @compose down
    Write-Host '    Data kept. Run setup.ps1 to start again, or teardown.ps1 -Purge to delete everything.'
}
