# ==============================================================
#  restore_defaults.ps1 — Revierte la optimizacion (candado + tweaks)
#  Autor: Anthony Artavia
#  Ejecutar como Administrador
#
#  Deja el sistema como estaba ANTES de debloat_windows11.ps1 /
#  debloat_hardcore.ps1 / performance_mode.ps1 / install_lock_task.ps1,
#  con UNA excepcion a proposito: las apps que ya se desinstalaron
#  (Xbox, Gaming Services, Clipchamp, Widgets/WebExperience, Bing
#  News/Weather, GetHelp, Getstarted, Office Hub, Feedback Hub) NO se
#  reinstalan. Esto solo deshace configuracion y politicas — nunca
#  vuelve a instalar nada.
#
#  Tambien quita la tarea programada "SystemPolicyMaintenance": sin
#  eso, la proxima actualizacion de Windows podria traer de vuelta
#  Bing/Copilot/etc. mientras algo los sigue re-bloqueando en cada
#  arranque sin que te des cuenta.
#
#  NOTA HONESTA: estos scripts nunca guardaron el valor que tenian ANTES
#  de tocarlos (no existe un snapshot). "Restaurar" aca significa borrar
#  la politica/valor que este toolkit agrego -para que Windows vuelva a
#  su comportamiento por defecto al no encontrar nada configurado-, no
#  "devolver el numero exacto que habia" si vos ya habias tocado algo a
#  mano antes de usar esta herramienta. Para memoria y energia se usan
#  los comandos oficiales de reset (Enable-MMAgent, powercfg
#  -restoredefaultschemes) en vez de un numero fijo, por la misma razon
#  de fondo: no sabemos que traia tu equipo antes, pero si sabemos cual
#  es el default de fabrica de Windows.
# ==============================================================

. "$PSScriptRoot\Common.ps1"
Reset-StepCounters
Start-ScriptLog -ScriptName "restore_defaults"

Write-Host "=== Restaurando configuracion original (las apps ya eliminadas NO se reinstalan) ===" -ForegroundColor Cyan

# ── Quitar la tarea programada (candado automatico) ────────────
# Primero que todo: si esto no se quita antes de tocar el resto, un
# arranque en medio de la ejecucion podria re-aplicar algo que ya
# restauramos.
Invoke-Step "Quitando tarea programada (candado automatico)" {
    $task = Get-ScheduledTask -TaskName "SystemPolicyMaintenance" -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName "SystemPolicyMaintenance" -Confirm:$false -ErrorAction Stop
    }
}

# ── Copilot ──────────────────────────────────────────────────
Invoke-Step "Restaurando Copilot" {
    Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot"
}

# ── Widgets (solo la politica; la app WebExperience NO se reinstala) ──
Invoke-Step "Restaurando politica de Widgets" {
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests"
}

# ── Bing, Cortana y Web Search ──────────────────────────────────
Invoke-Step "Restaurando Bing, Cortana y Web Search" {
    Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled"
    Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CopilotInWindowsEnabled"
    Remove-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "ConnectedSearchUseWeb"
}

# ── Telemetria ───────────────────────────────────────────────────
Invoke-Step "Restaurando telemetria" {
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry"
}

# ── Sugerencias / anuncios de Start y lock screen ──────────────
Invoke-Step "Restaurando sugerencias y anuncios de Start/lock screen" {
    $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmValues = @(
        "ContentDeliveryAllowed", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled",
        "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled",
        "SystemPaneSuggestionsEnabled", "RotatingLockScreenEnabled", "RotatingLockScreenOverlayEnabled",
        "SubscribedContent-310093Enabled", "SubscribedContent-314563Enabled", "SubscribedContent-338387Enabled",
        "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled",
        "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled", "SubscribedContent-353698Enabled"
    )
    foreach ($name in $cdmValues) {
        Remove-RegValue -Path $cdmPath -Name $name
    }
}

# ── Recall / Activity Feed ───────────────────────────────────────
Invoke-Step "Restaurando Recall y Activity Feed" {
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "PublishUserActivities"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "UploadUserActivities"
}

# ── Cloud Content ────────────────────────────────────────────────
Invoke-Step "Restaurando Cloud Content" {
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableCloudOptimizedContent"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableSoftLanding"
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures"
}

# ── Windows Update: drivers ───────────────────────────────────────
Invoke-Step "Restaurando reinstalacion de drivers via WU" {
    Remove-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate"
}

# ── Re-activar tareas de tracking ─────────────────────────────────
Invoke-Step "Re-activando tareas de tracking" {
    $tasks = @(
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "StartupAppTask" },
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "MareBackup" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" }
    )
    foreach ($t in $tasks) {
        try {
            Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "    [!] Tarea no encontrada: $($t.Name) (se omite)" -ForegroundColor DarkYellow
        }
    }
}

# ── Rendimiento: memoria, energia, GPU, scheduler multimedia ────
Invoke-Step "Restaurando memoria (compresion y page combining)" {
    Enable-MMAgent -MemoryCompression -ErrorAction Stop
    Enable-MMAgent -PageCombining -ErrorAction Stop
}

Invoke-Step "Restaurando planes de energia de fabrica" {
    powercfg -restoredefaultschemes
    if ($LASTEXITCODE -ne 0) { throw "powercfg -restoredefaultschemes devolvio codigo $LASTEXITCODE" }
}

Invoke-Step "Restaurando GPU y scheduler multimedia" {
    Remove-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode"
    Remove-RegValue -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness"
    Remove-RegValue -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "GPU Priority"
    Remove-RegValue -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority"
}

# ── Reiniciar Explorer ────────────────────────────────────────────
Invoke-Step "Reiniciando Explorer" {
    Stop-Process -Name explorer -Force -ErrorAction Stop
}

Write-Host "`n[i] Las apps ya desinstaladas (Xbox, Gaming Services, Clipchamp, Widgets, Bing News/Weather, promo apps) NO se reinstalaron a proposito." -ForegroundColor DarkGray
Write-Host "[i] Reinicia Windows para que todo quede aplicado." -ForegroundColor Magenta
Write-ScriptSummary -ScriptName "restore_defaults"
