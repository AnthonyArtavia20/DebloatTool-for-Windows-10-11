# ==============================================================
#  debloat_hardcore.ps1 — Candado del sistema (AI/Cloud/Tracking)
#  Autor: Anthony Artavia
#  Ejecutar como Administrador
# ==============================================================

. "$PSScriptRoot\Common.ps1"
Reset-StepCounters
Start-ScriptLog -ScriptName "debloat_hardcore"

Write-Host "=== Hardcore Lock ===" -ForegroundColor Cyan

# ── Recall + Activity Feed ─────────────────────────────────────
Invoke-Step "Desactivando Recall y Activity Feed" {
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Value 0
}

# ── Cloud Content ──────────────────────────────────────────────
Invoke-Step "Bloqueando Cloud Content" {
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableCloudOptimizedContent" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableSoftLanding" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1
}

# ── Bing Chat + Copilot + Web Search ────────────────────────────
# DisableWebSearch va en HKLM (a nivel de politica, no de usuario) para
# que no dependa de que este script haya corrido con la sesion "correcta"
# logueada — es la misma politica que se re-aplica en cada arranque desde
# install_lock_task.ps1.
Invoke-Step "Bloqueando Bing Chat, Copilot y Web Search" {
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CopilotInWindowsEnabled" -Value 0
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "ConnectedSearchUseWeb" -Value 0
}

# ── Windows Update: no reinstalar drivers innecesarios ─────────
Invoke-Step "Bloqueando reinstalacion de drivers via WU" {
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Value 1
}

# ── Tareas ocultas de tracking ─────────────────────────────────
# Se usa Disable-ScheduledTask (cmdlet nativo) en vez de schtasks.exe,
# y cada tarea se maneja por separado: si una no existe en este build
# de Windows, se avisa y se sigue con las demas.
Invoke-Step "Desactivando tareas de tracking" {
    $tasks = @(
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "StartupAppTask" },
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "MareBackup" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" }
    )
    foreach ($t in $tasks) {
        try {
            Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "    [!] Tarea no encontrada: $($t.Name) (se omite)" -ForegroundColor DarkYellow
        }
    }
}

# ── Bloquear reinstalacion automatica (paquetes provisionados) ──
# Remove-AppxPackage (usado en debloat_windows11.ps1) solo saca la app
# de las cuentas que ya existen en la maquina. Si el paquete sigue
# "provisionado" a nivel de imagen del sistema, Windows lo vuelve a
# instalar solo en cualquier cuenta nueva que se cree, y a veces lo
# repone despues de una actualizacion de feature (23H2 -> 24H2, etc).
# Sacarlo de la lista de aprovisionamiento evita ambos casos. Esto no
# existia antes: es la pieza que de verdad sostiene el "candado" para
# apps (las policies ya cubrian Copilot/Cloud Content, pero nada
# evitaba que Xbox/Gaming Services/Clipchamp se re-aprovisionaran).
Invoke-Step "Bloqueando reinstalacion de apps basura (paquetes provisionados)" {
    $patterns = @(
        "*Clipchamp*", "*Xbox*", "*GamingServices*", "*GamingApp*",
        "*BingNews*", "*BingWeather*", "*GetHelp*", "*Getstarted*",
        "*MicrosoftOfficeHub*", "*WindowsFeedbackHub*", "*WebExperience*"
    )
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($pattern in $patterns) {
        $provisioned |
            Where-Object { $_.DisplayName -like $pattern -and $_.DisplayName -notlike "*XboxGameCallableUI*" } |
            ForEach-Object {
                $pkgName = $_.PackageName
                try { Remove-AppxProvisionedPackage -Online -PackageName $pkgName -ErrorAction Stop | Out-Null }
                catch { Write-Host "    [!] No se pudo des-aprovisionar $($_.DisplayName): $($_.Exception.Message)" -ForegroundColor DarkYellow }
            }
    }
}

Write-Host "`n[i] Ejecutar performance_mode.ps1 a continuacion." -ForegroundColor DarkGray
Write-ScriptSummary -ScriptName "debloat_hardcore"
