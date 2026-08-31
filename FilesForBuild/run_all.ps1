# ==============================================================
#  run_all.ps1 — Launcher principal
#  Autor: Anthony Artavia
#  Ejecutar como Administrador
# ==============================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$scripts = @(
    "debloat_windows11.ps1",
    "debloat_hardcore.ps1",
    "performance_mode.ps1",
    "install_lock_task.ps1"
)

$results = @()

foreach ($script in $scripts) {
    $path = Join-Path $scriptDir $script
    Write-Host "`n==============================" -ForegroundColor DarkGray
    Write-Host " Ejecutando: $script" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor DarkGray

    try {
        & $path
        $results += [PSCustomObject]@{ Script = $script; Estado = "Completado" }
    }
    catch {
        # Si un script se cae por completo (error no manejado dentro de el),
        # no se detiene todo run_all: se registra y se sigue con el siguiente.
        Write-Host "[FAIL] $script se detuvo de forma inesperada: $($_.Exception.Message)" -ForegroundColor Red
        $results += [PSCustomObject]@{ Script = $script; Estado = "ERROR" }
    }
}

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host " Resumen general" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
$results | Format-Table -AutoSize

Write-Host "Revisa la carpeta 'Logs' junto a los scripts para el detalle de cada paso." -ForegroundColor DarkGray
Write-Host "`nTodo completado. Reinicia Windows ahora." -ForegroundColor Green