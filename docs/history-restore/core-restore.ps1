# Run from a dedicated, clean checkout of the exact Core alpha source.
# Prerequisites: PowerShell 7, Git, Docker Desktop with Linux containers.
# The password below belongs only to newly created disposable local clusters.
$ErrorActionPreference = 'Stop'
$expectedSource = 'c96b9da749b2d95661973485b2a026897329c8cd'
$repoDir = (Get-Location).Path
$actualSource = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualSource -ne $expectedSource) { throw 'Check out the exact Core alpha source before running.' }
git diff --quiet
if ($LASTEXITCODE -ne 0) { throw 'Tracked source must be clean.' }
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { throw 'Staged source must be clean.' }
$proofDir = Join-Path $repoDir 'core-proof'
if (Test-Path -LiteralPath $proofDir) { throw 'Use a fresh checkout: core-proof already exists.' }
New-Item -ItemType Directory $proofDir | Out-Null
$runId = ([guid]::NewGuid().ToString('N')).Substring(0,12)
$testNetwork = "wirespeed-core-proof-$runId"
$testImage = "wirespeed-core-proof:$runId"
$testSource = "wirespeed-core-source-$runId"
$testTarget = "wirespeed-core-target-$runId"
$createdContainers = @()
$networkCreated = $false
$imageCreated = $false
@'
FROM postgres:16-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends python3 && rm -rf /var/lib/apt/lists/*
'@ | Set-Content -Encoding ascii (Join-Path $proofDir 'Dockerfile')
try {
  docker build --tag $testImage $proofDir
  if ($LASTEXITCODE -ne 0) { throw 'Disposable test image build failed.' }
  $imageCreated = $true
  docker network create --internal $testNetwork | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Isolated test network creation failed.' }
  $networkCreated = $true
  foreach ($testContainer in @($testSource, $testTarget)) {
    docker run --detach --name $testContainer --network $testNetwork -e POSTGRES_PASSWORD=synthetic-local-only $testImage | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Disposable cluster creation failed.' }
    $createdContainers += $testContainer
    $isReady = $false
    for ($attempt=0; $attempt -lt 45; $attempt++) {
      docker exec $testContainer pg_isready -U postgres -d postgres *> $null
      if ($LASTEXITCODE -eq 0) { $isReady = $true; break }
      Start-Sleep -Seconds 1
    }
    if (-not $isReady) { throw 'Disposable cluster did not become ready.' }
  }
  $sourceDsn = "postgresql://postgres:synthetic-local-only@${testSource}:5432/postgres"
  $targetDsn = "postgresql://postgres:synthetic-local-only@${testTarget}:5432/postgres"
  docker run --rm --network $testNetwork -e PYTHONDONTWRITEBYTECODE=1 --mount "type=bind,src=$repoDir,dst=/src,readonly" --mount "type=bind,src=$proofDir,dst=/proof" -w /src --entrypoint python3 $testImage -m scripts.c2_provider_exit_rehearsal --source-dsn $sourceDsn --target-dsn $targetDsn --commit $expectedSource --output-dir /proof
  if ($LASTEXITCODE -ne 0) { throw 'C2 rehearsal failed.' }
  $archiveHash = (Get-FileHash -Algorithm SHA256 (Join-Path $proofDir 'sovereign-memory-c2.bundle.tar')).Hash.ToLowerInvariant()
  docker run --rm --network none -e PYTHONDONTWRITEBYTECODE=1 --mount "type=bind,src=$repoDir,dst=/src,readonly" --mount "type=bind,src=$proofDir,dst=/proof,readonly" -w /src --entrypoint python3 $testImage scripts/validate_sovereignty_bundle.py /proof/sovereign-memory-c2.bundle.tar --expected-sha256 $archiveHash
  if ($LASTEXITCODE -ne 0) { throw 'Bundle validation failed.' }
  docker run --rm --network none --entrypoint python3 $testImage --version
  docker run --rm --network none --entrypoint psql $testImage --version
  Write-Output 'PASS: synthetic C2 rehearsal and bundle validation. Inspect core-proof/receipt.json.'
} finally {
  foreach ($testContainer in $createdContainers) {
    docker rm --force --volumes $testContainer 2>$null | Out-Null
  }
  if ($networkCreated) { docker network rm $testNetwork 2>$null | Out-Null }
  if ($imageCreated) { docker image rm $testImage 2>$null | Out-Null }
}
