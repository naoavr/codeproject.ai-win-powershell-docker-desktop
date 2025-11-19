<#
.SYNOPSIS
    CodeProject.AI Server Installation Script for Windows Docker Desktop
.DESCRIPTION
    Installs CodeProject.AI Server using Docker Desktop on Windows
    Includes ALPR and Face Detection modules with PaddlePaddle fix
.NOTES
    Target: Windows 10/11 with Docker Desktop
    Run as Administrator
#>

# Requires -RunAsAdministrator

# Color output functions
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Info($message) {
    Write-ColorOutput Green "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
}

function Write-Error-Custom($message) {
    Write-ColorOutput Red "[ERROR] $message"
}

function Write-Warning-Custom($message) {
    Write-ColorOutput Yellow "[WARNING] $message"
}

# Configuration variables
$CPAI_PORT = 32168
$CPAI_CONTAINER_NAME = "codeproject-ai"
$CPAI_DATA_DIR = "C:\ProgramData\CodeProject\AI\data"
$CPAI_MODULES_DIR = "C:\ProgramData\CodeProject\AI\modules"

Write-Info "Starting CodeProject.AI Server installation on Windows..."

#######################################################
# 1. Check if running as Administrator
#######################################################
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error-Custom "This script must be run as Administrator!"
    Write-Host "Right-click PowerShell and select 'Run as Administrator'"
    exit 1
}

#######################################################
# 2. Check Docker Desktop Installation
#######################################################
Write-Info "Checking Docker Desktop installation..."

$dockerInstalled = Get-Command docker -ErrorAction SilentlyContinue

if (-not $dockerInstalled) {
    Write-Warning-Custom "Docker Desktop is not installed!"
    Write-Host ""
    Write-Host "Please install Docker Desktop from:"
    Write-Host "https://www.docker.com/products/docker-desktop"
    Write-Host ""
    Write-Host "After installation:"
    Write-Host "1. Start Docker Desktop"
    Write-Host "2. Wait for it to fully start (whale icon in system tray)"
    Write-Host "3. Run this script again"
    exit 1
}

Write-Info "Docker is installed: $(docker --version)"

#######################################################
# 3. Check if Docker Desktop is Running
#######################################################
Write-Info "Checking if Docker Desktop is running..."

$dockerRunning = $false
$retries = 0
$maxRetries = 3

while (-not $dockerRunning -and $retries -lt $maxRetries) {
    try {
        docker ps | Out-Null
        $dockerRunning = $true
        Write-Info "Docker Desktop is running"
    }
    catch {
        $retries++
        if ($retries -lt $maxRetries) {
            Write-Warning-Custom "Docker Desktop is not running. Attempting to start... (Attempt $retries/$maxRetries)"
            Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
            Write-Info "Waiting 30 seconds for Docker Desktop to start..."
            Start-Sleep -Seconds 30
        }
        else {
            Write-Error-Custom "Docker Desktop is not running and failed to start automatically."
            Write-Host "Please start Docker Desktop manually and run this script again."
            exit 1
        }
    }
}

#######################################################
# 4. Create Data Directories
#######################################################
Write-Info "Creating data directories..."

New-Item -Path $CPAI_DATA_DIR -ItemType Directory -Force | Out-Null
New-Item -Path $CPAI_MODULES_DIR -ItemType Directory -Force | Out-Null

Write-Info "Data directories created"

#######################################################
# 5. Stop and Remove Existing Container
#######################################################
Write-Info "Checking for existing container..."

$existingContainer = docker ps -a --filter "name=$CPAI_CONTAINER_NAME" --format "{{.Names}}"

if ($existingContainer -eq $CPAI_CONTAINER_NAME) {
    Write-Info "Stopping and removing existing container..."
    docker stop $CPAI_CONTAINER_NAME | Out-Null
    docker rm $CPAI_CONTAINER_NAME | Out-Null
}

#######################################################
# 6. Pull CodeProject.AI Docker Image
#######################################################
Write-Info "Pulling CodeProject.AI Server Docker image..."
Write-Info "This may take several minutes..."

docker pull codeproject/ai-server:latest

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Failed to pull Docker image. Check your internet connection."
    exit 1
}

Write-Info "Docker image pulled successfully"

#######################################################
# 7. Run CodeProject.AI Container
#######################################################
Write-Info "Starting CodeProject.AI Server container..."

docker run -d `
    --name $CPAI_CONTAINER_NAME `
    --restart unless-stopped `
    -p "${CPAI_PORT}:32168" `
    -v "${CPAI_DATA_DIR}:/etc/codeproject/ai" `
    -v "${CPAI_MODULES_DIR}:/app/modules" `
    -e TZ=Europe/Lisbon `
    codeproject/ai-server:latest

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Failed to start container"
    exit 1
}

Write-Info "Container started. Waiting 60 seconds for initialization..."
Start-Sleep -Seconds 60

#######################################################
# 8. Verify Container is Running
#######################################################
$containerRunning = docker ps --filter "name=$CPAI_CONTAINER_NAME" --format "{{.Names}}"

if ($containerRunning -ne $CPAI_CONTAINER_NAME) {
    Write-Error-Custom "Container failed to start. Check logs with: docker logs $CPAI_CONTAINER_NAME"
    exit 1
}

Write-Info "Container is running successfully"

#######################################################
# 9. Wait for API to be Ready
#######################################################
Write-Info "Waiting for API to be ready..."

$apiReady = $false
$retries = 0
$maxRetries = 20

while (-not $apiReady -and $retries -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:${CPAI_PORT}/v1/status" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $apiReady = $true
            Write-Info "API is ready!"
        }
    }
    catch {
        $retries++
        Write-Info "Waiting for API... (attempt $retries/$maxRetries)"
        Start-Sleep -Seconds 10
    }
}

if (-not $apiReady) {
    Write-Warning-Custom "API took longer than expected. Continuing anyway..."
}

#######################################################
# 10. Install Face Processing Module
#######################################################
Write-Info "Installing Face Detection module..."

Start-Sleep -Seconds 10

try {
    Invoke-WebRequest -Uri "http://localhost:${CPAI_PORT}/v1/module/install/FaceProcessing" `
        -Method POST `
        -ContentType "application/json" `
        -Body "{}" `
        -UseBasicParsing `
        -TimeoutSec 30 | Out-Null
    
    Write-Info "Face Processing module installation initiated"
}
catch {
    Write-Warning-Custom "Face Processing module installation request may have failed"
}

Write-Info "Waiting 60 seconds for Face Processing module..."
Start-Sleep -Seconds 60

#######################################################
# 11. Install ALPR Module
#######################################################
Write-Info "Installing ALPR (Automatic License Plate Recognition) module..."

try {
    Invoke-WebRequest -Uri "http://localhost:${CPAI_PORT}/v1/module/install/ALPR" `
        -Method POST `
        -ContentType "application/json" `
        -Body "{}" `
        -UseBasicParsing `
        -TimeoutSec 30 | Out-Null
    
    Write-Info "ALPR module installation initiated"
}
catch {
    Write-Warning-Custom "ALPR module installation request may have failed"
}

Write-Info "Waiting 90 seconds for ALPR module initial setup..."
Start-Sleep -Seconds 90

#######################################################
# 12. Apply PaddlePaddle Fix for ALPR
#######################################################
Write-Info "Applying PaddlePaddle fix for ALPR module..."

$fixScript = @'
cd /app/modules/ALPR || exit 1
VENV_PATH=$(find . -name "venv" -type d | head -n 1)
if [ -z "$VENV_PATH" ]; then
    echo "ERROR: Could not find ALPR virtual environment"
    exit 1
fi
echo "Found virtual environment at: $VENV_PATH"
source "$VENV_PATH/bin/activate"
echo "Fixing PaddlePaddle installation..."
pip uninstall -y paddlepaddle paddlepaddle-gpu protobuf 2>/dev/null || true
pip install "protobuf>=3.1.0,<=3.20.2"
pip install paddlepaddle==2.6.0 -i https://mirror.baidu.com/pypi/simple
python -c "import paddle; print('PaddlePaddle version:', paddle.__version__)"
echo "PaddlePaddle fix applied successfully"
deactivate
'@

docker exec -i $CPAI_CONTAINER_NAME bash -c $fixScript

if ($LASTEXITCODE -eq 0) {
    Write-Info "PaddlePaddle fix applied successfully"
}
else {
    Write-Warning-Custom "PaddlePaddle fix may have failed. Check container logs."
}

#######################################################
# 13. Restart Container
#######################################################
Write-Info "Restarting container to apply fixes..."
docker restart $CPAI_CONTAINER_NAME | Out-Null

Write-Info "Waiting 45 seconds for restart..."
Start-Sleep -Seconds 45

#######################################################
# 14. Configure Windows Firewall
#######################################################
Write-Info "Configuring Windows Firewall..."

try {
    New-NetFirewallRule -DisplayName "CodeProject.AI Server" `
        -Direction Inbound `
        -LocalPort $CPAI_PORT `
        -Protocol TCP `
        -Action Allow `
        -ErrorAction SilentlyContinue | Out-Null
    Write-Info "Firewall rule added for port $CPAI_PORT"
}
catch {
    Write-Warning-Custom "Could not create firewall rule. You may need to allow port $CPAI_PORT manually."
}

#######################################################
# 15. Create Management Scripts
#######################################################
Write-Info "Creating management scripts..."

$scriptsDir = "C:\ProgramData\CodeProject\AI\scripts"
New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null

# Start script
@"
docker start $CPAI_CONTAINER_NAME
Write-Host "CodeProject.AI Server started"
"@ | Out-File -FilePath "$scriptsDir\Start-CPAI.ps1" -Encoding UTF8

# Stop script
@"
docker stop $CPAI_CONTAINER_NAME
Write-Host "CodeProject.AI Server stopped"
"@ | Out-File -FilePath "$scriptsDir\Stop-CPAI.ps1" -Encoding UTF8

# Restart script
@"
docker restart $CPAI_CONTAINER_NAME
Write-Host "CodeProject.AI Server restarted"
"@ | Out-File -FilePath "$scriptsDir\Restart-CPAI.ps1" -Encoding UTF8

# Status script
@"
`$running = docker ps --filter "name=$CPAI_CONTAINER_NAME" --format "{{.Names}}"
if (`$running -eq "$CPAI_CONTAINER_NAME") {
    Write-Host "CodeProject.AI Server is running" -ForegroundColor Green
    docker ps | Select-String "$CPAI_CONTAINER_NAME"
} else {
    Write-Host "CodeProject.AI Server is NOT running" -ForegroundColor Red
}
"@ | Out-File -FilePath "$scriptsDir\Get-CPAI-Status.ps1" -Encoding UTF8

# Logs script
@"
docker logs -f $CPAI_CONTAINER_NAME
"@ | Out-File -FilePath "$scriptsDir\Get-CPAI-Logs.ps1" -Encoding UTF8

# Fix ALPR script
@"
Write-Host "Applying ALPR PaddlePaddle fix..." -ForegroundColor Yellow
`$fixScript = @'
cd /app/modules/ALPR
VENV_PATH=`$(find . -name "venv" -type d | head -n 1)
source "`$VENV_PATH/bin/activate"
pip uninstall -y paddlepaddle paddlepaddle-gpu protobuf
pip install "protobuf>=3.1.0,<=3.20.2"
pip install paddlepaddle==2.6.0 -i https://mirror.baidu.com/pypi/simple
python -c "import paddle; print('PaddlePaddle version:', paddle.__version__)"
deactivate
'@
docker exec -i $CPAI_CONTAINER_NAME bash -c `$fixScript
docker restart $CPAI_CONTAINER_NAME
Write-Host "Fix applied. Waiting for restart..." -ForegroundColor Yellow
Start-Sleep -Seconds 30
Write-Host "Done. Check dashboard for ALPR status." -ForegroundColor Green
"@ | Out-File -FilePath "$scriptsDir\Fix-CPAI-ALPR.ps1" -Encoding UTF8

Write-Info "Management scripts created in: $scriptsDir"

#######################################################
# Installation Complete - Display Summary
#######################################################

Clear-Host

Write-Host ""
Write-ColorOutput Green "╔══════════════════════════════════════════════════════════╗"
Write-ColorOutput Green "║                                                          ║"
Write-ColorOutput Green "║          CodeProject.AI Installation Complete!          ║"
Write-ColorOutput Green "║                                                          ║"
Write-ColorOutput Green "╚══════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "Server URL: http://localhost:$CPAI_PORT"
Write-Host "Dashboard: http://localhost:$CPAI_PORT"
Write-Host ""
Write-Host "Installation Method: Docker Desktop Container"
Write-Host "Container Name: $CPAI_CONTAINER_NAME"
Write-Host ""
Write-Host "Installed modules:"
Write-Host "  - ALPR (Automatic License Plate Recognition) - with PaddlePaddle fix"
Write-Host "  - Face Detection & Recognition"
Write-Host ""
Write-Host "Note: Modules may take several minutes to fully initialize."
Write-Host "      If ALPR shows errors, run: $scriptsDir\Fix-CPAI-ALPR.ps1"
Write-Host ""
Write-Host "Management Scripts (run in PowerShell):"
Write-Host "  Start:      $scriptsDir\Start-CPAI.ps1"
Write-Host "  Stop:       $scriptsDir\Stop-CPAI.ps1"
Write-Host "  Restart:    $scriptsDir\Restart-CPAI.ps1"
Write-Host "  Status:     $scriptsDir\Get-CPAI-Status.ps1"
Write-Host "  Logs:       $scriptsDir\Get-CPAI-Logs.ps1"
Write-Host "  Fix ALPR:   $scriptsDir\Fix-CPAI-ALPR.ps1"
Write-Host ""
Write-Host "Docker Commands:"
Write-Host "  Start:   docker start $CPAI_CONTAINER_NAME"
Write-Host "  Stop:    docker stop $CPAI_CONTAINER_NAME"
Write-Host "  Logs:    docker logs -f $CPAI_CONTAINER_NAME"
Write-Host "  Shell:   docker exec -it $CPAI_CONTAINER_NAME bash"
Write-Host ""
Write-Host "Data directories:"
Write-Host "  Config:  $CPAI_DATA_DIR"
Write-Host "  Modules: $CPAI_MODULES_DIR"
Write-Host "  Scripts: $scriptsDir"
Write-Host ""
Write-Host ""

Write-ColorOutput Green "╔══════════════════════════════════════════════════════════╗"
Write-ColorOutput Green "║                                                          ║"
Write-ColorOutput Green "║                      Powered by NAO                      ║"
Write-ColorOutput Green "║                                                          ║"
Write-ColorOutput Green "║                           SIIC                           ║"
Write-ColorOutput Green "║                                                          ║"
Write-ColorOutput Green "║              Comando Territorial de Aveiro               ║"
Write-ColorOutput Green "║                                                          ║"
Write-ColorOutput Green "╚══════════════════════════════════════════════════════════╝"
Write-Host ""

Write-Info "Installation completed successfully!"
Write-Host ""
Write-Host "Access the dashboard at http://localhost:$CPAI_PORT to verify modules are running."
Write-Host "If ALPR is not working, run the fix script: $scriptsDir\Fix-CPAI-ALPR.ps1"
Write-Host ""
