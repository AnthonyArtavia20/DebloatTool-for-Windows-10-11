# ==============================================================
#  debloat_windows11.ps1 — Limpieza base del sistema
#  Autor: Anthony Artavia
#  Ejecutar como Administrador
# ==============================================================

. "$PSScriptRoot\Common.ps1"
Reset-StepCounters
Start-ScriptLog -ScriptName "debloat_windows11"

Write-Host "=== Windows 11 Debloat ===" -ForegroundColor Cyan
Test-DomainStatus

# Punto de restauracion antes de modificar
# Si falla, lo mas comun es que el servicio VSS (Volume Shadow Copy) este
# deshabilitado -a veces a proposito, por politica antiransomware de la
# empresa o del antivirus, que borra/limita shadow copies-. Chequeamos
# antes de intentar para dar un mensaje claro en vez del error generico
# de COM que tira Checkpoint-Computer.
Invoke-Step "Creando punto de restauracion" {
    $vss = Get-Service -Name "VSS" -ErrorAction SilentlyContinue
    if ($vss -and $vss.StartType -eq "Disabled") {
        throw "Servicio VSS deshabilitado (probablemente politica de seguridad/antiransomware). Para habilitarlo: Set-Service -Name VSS -StartupType Manual"
    }
    Checkpoint-Computer -Description "Antes de debloat" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
}

# ── Copilot ────────────────────────────────────────────────────
Invoke-Step "Desactivando Copilot" {
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
}

# ── Widgets / WebExperience ────────────────────────────────────
# Separado en dos pasos: si la clave de politica falla (bloqueada por
# AV/EDR en algunas maquinas), la desinstalacion del appx igual corre.
Invoke-Step "Bloqueando Widgets via politica" {
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
} -KnownIssueNote "Fallo repetido en varias maquinas/corridas con el mismo error. Sin impacto: el paso siguiente desinstala WebExperience de todas formas. Ver Notas_Dominio_y_Telemetria para detalle."

Invoke-Step "Desinstalando app de Widgets (WebExperience)" {
    Get-AppxPackage -AllUsers *WebExperience* -ErrorAction SilentlyContinue |
        ForEach-Object {
            $pkg = $_
            try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop }
            catch { Write-Host "    [!] No se pudo quitar $($pkg.Name): $($_.Exception.Message)" -ForegroundColor DarkYellow }
        }
}

# ── Bing + Cortana ─────────────────────────────────────────────
# BingSearchEnabled por si sola ya no alcanza: es un flag legado que
# Windows Update resetea seguido. DisableWebSearch es la politica real
# ("Do not allow web search") que saca a Bing de los resultados del
# buscador; DisableSearchBoxSuggestions saca las sugerencias/autocompletado
# en linea del cuadro de busqueda.
Invoke-Step "Desactivando Bing y Cortana" {
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
    Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "ConnectedSearchUseWeb" -Value 0
}

# ── Telemetria base ────────────────────────────────────────────
Invoke-Step "Reduciendo telemetria" {
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
}

# ── Apps basura ────────────────────────────────────────────────
# Cada paquete se quita individualmente: si uno falla (protegido por el
# sistema), no detiene la eliminacion del resto.
#
# IMPORTANTE: -AllUsers va tanto en el Get como en el Remove. Antes solo
# estaba en el Get-AppxPackage, asi que el Remove-AppxPackage sin -AllUsers
# solo lo sacaba del contexto del usuario que corre el script — el paquete
# seguia registrado para otros perfiles. Esto es lo que dejaba sobrevivir
# paquetes que en teoria ya se habian "quitado".
#
# *Xbox* NUNCA hizo match con Gaming Services ni con la app nueva de Xbox:
# sus nombres de paquete son "Microsoft.GamingServices" y "Microsoft.GamingApp"
# — ninguno de los dos contiene la palabra "Xbox". Por eso Gaming Services
# seguia apareciendo en el Administrador de tareas aunque el resto de Xbox
# ya no estuviera. Mismo caso con Bing: BingNews/BingWeather son apps aparte
# del toggle de busqueda que ya se maneja arriba.
Invoke-Step "Eliminando apps basura (Clipchamp, Xbox, Gaming Services, Bing apps, promo apps)" {
    $bloatPatterns = @(
        "*Clipchamp*",
        "*Xbox*",
        "*GamingServices*",
        "*GamingApp*",
        "*BingNews*",
        "*BingWeather*",
        "*GetHelp*",
        "*Getstarted*",
        "*MicrosoftOfficeHub*",
        "*WindowsFeedbackHub*"
    )

    # XboxGameCallableUI se excluye: es un system app protegido, no puede
    # desinstalarse y solo genera error sin efecto util.
    foreach ($pattern in $bloatPatterns) {
        Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*XboxGameCallableUI*" } |
            ForEach-Object {
                $pkg = $_
                try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop }
                catch { Write-Host "    [!] No se pudo quitar $($pkg.Name): $($_.Exception.Message)" -ForegroundColor DarkYellow }
            }
    }

    # Gaming Services corre ademas como servicio de Windows (GamingServices /
    # GamingServicesNet), no solo como appx. Se para de una vez si ya estaba
    # corriendo; el candado en debloat_hardcore.ps1 evita que vuelva a
    # aprovisionarse solo.
    Get-Service -Name "GamingServices", "GamingServicesNet" -ErrorAction SilentlyContinue |
        Stop-Service -Force -ErrorAction SilentlyContinue
}

# ── Sugerencias / anuncios de Start y lock screen ──────────────
# ContentDeliveryManager es el mecanismo detras de los "apps sugeridas"
# en Start, los tips que aparecen solos, y el contenido rotativo de
# Windows Spotlight en la pantalla de bloqueo. Es HKCU (por usuario) y
# no requiere reinicio de Explorer para casi nada, pero al ir justo antes
# del restart de todas formas no hace falta un paso aparte.
Invoke-Step "Desactivando sugerencias y anuncios de Start/lock screen" {
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
        Set-RegValue -Path $cdmPath -Name $name -Value 0
    }
}

# ── Reiniciar Explorer ─────────────────────────────────────────
Invoke-Step "Reiniciando Explorer" {
    Stop-Process -Name explorer -Force -ErrorAction Stop
}

Write-ScriptSummary -ScriptName "debloat_windows11"