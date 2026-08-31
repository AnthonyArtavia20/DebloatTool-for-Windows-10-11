# ==============================================================
#  Common.ps1 — Funciones compartidas de logging y manejo de errores
#  Autor: Anthony Artavia
#  Este archivo se debe dot-sourcear al inicio de cada script:
#      . "$PSScriptRoot\Common.ps1"
# ==============================================================

$Global:OkCount     = 0
$Global:FailCount   = 0
$Global:FailedSteps = @()

function Reset-StepCounters {
    $Global:OkCount     = 0
    $Global:FailCount   = 0
    $Global:FailedSteps = @()
}

function Start-ScriptLog {
    param([Parameter(Mandatory)][string]$ScriptName)

    $logDir = Join-Path $PSScriptRoot "Logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFile = Join-Path $logDir "$ScriptName`_$stamp.log"

    try {
        Start-Transcript -Path $logFile -Append -Force | Out-Null
    }
    catch {
        Write-Host "[!] No se pudo iniciar el log ($($_.Exception.Message)), continuando sin log." -ForegroundColor DarkYellow
    }
}

# Envuelve cada paso del script: si falla, lo reporta y sigue con el resto
# en vez de detener toda la ejecucion.
function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action,
        # Texto opcional que se muestra SOLO si el paso falla, para
        # limitaciones ya conocidas (no accionables) donde no queremos
        # que el operador pierda tiempo re-investigando algo ya cerrado.
        # No cambia el conteo de OK/Error: el paso se sigue registrando
        # como fallo real, solo se le agrega contexto.
        [string]$KnownIssueNote
    )

    Write-Host "[*] $Description..." -ForegroundColor Yellow
    try {
        & $Action | Out-Null
        Write-Host "    [OK]" -ForegroundColor Green
        $Global:OkCount++
    }
    catch {
        Write-Host "    [FAIL] $($_.Exception.Message)" -ForegroundColor Red
        if ($KnownIssueNote) {
            Write-Host "    [i] $KnownIssueNote" -ForegroundColor DarkGray
        }
        $Global:FailCount++
        $Global:FailedSteps += $Description
    }
}

# Usa cmdlets nativos (para que los errores sean excepciones reales que
# try/catch puede atrapar), con fallback a reg.exe para un bug conocido
# del proveedor de registro de PowerShell: crear una clave NUEVA bajo
# "...\Policies\..." con New-Item puede fallar con Access Denied incluso
# en sesion elevada, mientras que reg.exe (API nativa) si funciona.
function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = "DWord"
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # Guardamos el mensaje del cmdlet nativo ANTES de tocar reg.exe,
        # porque reg.exe no genera una excepcion .NET (solo exit code),
        # asi que $_ no cambia, pero lo hacemos explicito para que quede
        # claro cual mensaje viene de cual intento.
        $nativeError = $_.Exception.Message

        $regPath = $Path -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU'
        $regType = switch ($Type) {
            "DWord"  { "REG_DWORD" }
            "String" { "REG_SZ" }
            "QWord"  { "REG_QWORD" }
            default  { "REG_DWORD" }
        }

        # Antes esto se descartaba con Out-Null: no sabiamos si reg.exe
        # fallaba por lo mismo que el cmdlet nativo o por otra razon.
        # Ahora se captura stdout+stderr real de reg.exe para poder
        # distinguirlo en el log.
        $regOutput = (& reg add "$regPath" /v "$Name" /t $regType /d "$Value" /f 2>&1 | Out-String).Trim()

        if ($LASTEXITCODE -ne 0) {
            throw "Fallo con cmdlet nativo ('$nativeError') y con reg.exe (salida: '$regOutput')"
        }
    }
}

# Inverso de Set-RegValue, para scripts de reversion. A diferencia de
# Set-RegValue, si el valor o la ruta no existen NO es un error — significa
# que ya esta en su estado por defecto, que es exactamente lo que se busca.
# No borra la clave contenedora aunque quede vacia: podria tener otros
# valores que no son nuestros (de una GPO real, o algo que el usuario haya
# configurado antes de usar esta herramienta).
function Remove-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    }
}

function Write-ScriptSummary {
    param([Parameter(Mandatory)][string]$ScriptName)

    Write-Host "`n----- Resumen: $ScriptName -----" -ForegroundColor Cyan
    Write-Host "  Pasos OK: $Global:OkCount    Pasos con error: $Global:FailCount" -ForegroundColor Cyan
    if ($Global:FailCount -gt 0) {
        Write-Host "  Detalle de fallos:" -ForegroundColor Red
        foreach ($step in $Global:FailedSteps) {
            Write-Host "   - $step" -ForegroundColor Red
        }
    }
    try { Stop-Transcript | Out-Null } catch {}
}

# Chequeo puramente informativo — no bloquea nada. Util si en el futuro
# corres esto en una PC que si este en dominio.
function Test-DomainStatus {
    try {
        $info = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($info.PartOfDomain) {
            Write-Host "[!] Este equipo esta unido a un dominio ($($info.Domain)). Group Policy podria revertir estos cambios." -ForegroundColor DarkYellow
        }
        else {
            Write-Host "[i] Equipo en Workgroup (sin dominio). Sin riesgo de GPO." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "[!] No se pudo determinar el estado de dominio: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}