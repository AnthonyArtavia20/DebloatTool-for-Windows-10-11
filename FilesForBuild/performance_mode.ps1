# ==============================================================
#  performance_mode.ps1 — Optimizacion de recursos del sistema
#  Autor: Anthony Artavia
#  Ejecutar como Administrador
#  NOTA: Ejecutar ULTIMO en el flujo (debloat -> hardcore -> este)
# ==============================================================

. "$PSScriptRoot\Common.ps1"
Reset-StepCounters
Start-ScriptLog -ScriptName "performance_mode"

Write-Host "=== Performance Mode ===" -ForegroundColor Cyan

# ── Memory Manager ─────────────────────────────────────────────
Invoke-Step "Desactivando compresion de memoria y page combining" {
    Disable-MMAgent -MemoryCompression -ErrorAction Stop
    Disable-MMAgent -PageCombining -ErrorAction Stop
}

# ── Core Parking OFF ───────────────────────────────────────────
# powercfg.exe es un comando externo: se revisa $LASTEXITCODE porque
# no lanza una excepcion de PowerShell por si mismo si falla.
Invoke-Step "Desactivando core parking" {
    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
    if ($LASTEXITCODE -ne 0) { throw "powercfg -setacvalueindex devolvio codigo $LASTEXITCODE" }
    powercfg -setactive SCHEME_CURRENT
    if ($LASTEXITCODE -ne 0) { throw "powercfg -setactive devolvio codigo $LASTEXITCODE" }
}

# ── GPU: Hardware Scheduling (sin power saving) ────────────────
Invoke-Step "Configurando GPU para rendimiento maximo" {
    Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2
}

# ── Multimedia Scheduler (prioridad para juegos/apps exigentes) ─
Invoke-Step "Configurando scheduler multimedia" {
    Set-RegValue -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0
    Set-RegValue -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "GPU Priority" -Value 8
    Set-RegValue -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority" -Value 6
}

# ── Reiniciar Explorer (unico reinicio del flujo completo) ──────
Invoke-Step "Reiniciando Explorer" {
    Stop-Process -Name explorer -Force -ErrorAction Stop
}

Write-Host "[!] Reinicia Windows para aplicar todos los cambios." -ForegroundColor Magenta
Write-ScriptSummary -ScriptName "performance_mode"
