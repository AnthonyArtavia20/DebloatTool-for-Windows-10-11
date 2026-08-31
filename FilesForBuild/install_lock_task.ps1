# ==============================================================
#  install_lock_task.ps1 — Instala una tarea programada AUTOCONTENIDA
#  que re-aplica el candado (Copilot/Bing+Web Search/Cloud Content+
#  Spotlight/Gaming Services) en cada arranque de Windows.
#
#  Diferencia clave con la version anterior: el comando completo va
#  EMBEBIDO dentro de la definicion de la tarea (codificado en base64),
#  no apunta a lock_after_update.ps1 en disco. Esto permite borrar
#  esta carpeta despues de correr este script una sola vez — la tarea
#  sigue funcionando sola, sin dejar ningun archivo tuyo en la maquina.
#
#  Tambien corrige un problema real: si la tarea corriera como SYSTEM
#  usando Set-ItemProperty normal sobre HKCU, escribiria en el perfil
#  de SYSTEM, no en el del usuario real. Por eso el comando embebido
#  recorre los perfiles de usuario reales de la PC (via HKEY_USERS)
#  para aplicar las llaves de HKCU a cada uno, sin importar quien este
#  logueado en el momento del arranque.
#
#  Autor: Anthony Artavia
#  Ejecutar como Administrador (una sola vez por maquina)
# ==============================================================

. "$PSScriptRoot\Common.ps1"
Reset-StepCounters
Start-ScriptLog -ScriptName "install_lock_task"

Write-Host "=== Instalando candado automatico (autocontenido) ===" -ForegroundColor Cyan

Invoke-Step "Registrando tarea programada" {

    # Este es el comando que se ejecuta en CADA arranque, embebido en la
    # tarea. No depende de ningun archivo en disco.
    $lockCommand = @'
try {
    $p = "HKLM:\Software\Policies\Microsoft\WindowsCopilot"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    New-ItemProperty -Path $p -Name "TurnOffWindowsCopilot" -Value 1 -PropertyType DWord -Force | Out-Null
} catch {}

try {
    $p = "HKLM:\Software\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    New-ItemProperty -Path $p -Name "DisableWindowsConsumerFeatures" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $p -Name "DisableCloudOptimizedContent" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $p -Name "DisableWindowsSpotlightFeatures" -Value 1 -PropertyType DWord -Force | Out-Null
} catch {}

try {
    $p = "HKLM:\Software\Policies\Microsoft\Windows\Windows Search"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    New-ItemProperty -Path $p -Name "DisableWebSearch" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $p -Name "ConnectedSearchUseWeb" -Value 0 -PropertyType DWord -Force | Out-Null
} catch {}

try {
    Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*GamingServices*" -or $_.Name -like "*GamingApp*" -or $_.Name -like "*WebExperience*" } |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
} catch {}

$profiles = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Special -and $_.LocalPath -like "C:\Users\*" }

foreach ($prof in $profiles) {
    $sid = $prof.SID
    $hivePath = "Registry::HKEY_USERS\$sid"
    $alreadyLoaded = Test-Path $hivePath
    $ntuser = Join-Path $prof.LocalPath "NTUSER.DAT"
    $unloadNeeded = $false

    if (-not $alreadyLoaded -and (Test-Path $ntuser)) {
        reg load "HKU\$sid" "$ntuser" 2>$null | Out-Null
        $alreadyLoaded = Test-Path $hivePath
        $unloadNeeded = $true
    }

    if ($alreadyLoaded) {
        try {
            $searchPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Search"
            if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
            New-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $searchPath -Name "CopilotInWindowsEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

            $explorerPolicyPath = "Registry::HKEY_USERS\$sid\Software\Policies\Microsoft\Windows\Explorer"
            if (-not (Test-Path $explorerPolicyPath)) { New-Item -Path $explorerPolicyPath -Force | Out-Null }
            New-ItemProperty -Path $explorerPolicyPath -Name "DisableSearchBoxSuggestions" -Value 1 -PropertyType DWord -Force | Out-Null
        } catch {}
    }

    if ($unloadNeeded) {
        [gc]::Collect()
        Start-Sleep -Milliseconds 300
        reg unload "HKU\$sid" 2>$null | Out-Null
    }
}
'@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($lockCommand))

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encoded"

    $trigger = New-ScheduledTaskTrigger -AtStartup

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    # Nombre neutro a proposito: no delata que es una herramienta de debloat.
    Register-ScheduledTask -TaskName "SystemPolicyMaintenance" -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
}

Write-Host "[i] La tarea queda autocontenida. Ya podes borrar esta carpeta completa despues de este paso." -ForegroundColor DarkGray
Write-Host "[i] Verificar en cualquier momento con: Get-ScheduledTask -TaskName 'SystemPolicyMaintenance'" -ForegroundColor DarkGray
Write-ScriptSummary -ScriptName "install_lock_task"