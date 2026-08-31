# ==============================================================
#  lock_after_update.ps1 — Candado rapido post-Windows Update
#  Autor: Anthony Artavia
#  Ejecutar como Administrador
#  Usar despues de un Windows Update grande (23H2, 24H2, etc.)
# ==============================================================

. "$PSScriptRoot\Common.ps1"
Reset-StepCounters
Start-ScriptLog -ScriptName "lock_after_update"

Write-Host "=== Lock After Update ===" -ForegroundColor Cyan

# ── Copilot ────────────────────────────────────────────────────
Invoke-Step "Re-bloqueando Copilot" {
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CopilotInWindowsEnabled" -Value 0
}

# ── Bing / Web Search (WU suele resetear estas keys) ───────────
Invoke-Step "Re-bloqueando Bing y Web Search" {
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
    Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Search" -Name "ConnectedSearchUseWeb" -Value 0
}

# ── Cloud Content ──────────────────────────────────────────────
Invoke-Step "Re-bloqueando Cloud Content" {
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableCloudOptimizedContent" -Value 1
    Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1
}

# ── Gaming Services (vuelve si se instala un juego de Store/Game Pass) ──
Invoke-Step "Re-eliminando Gaming Services" {
    Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*GamingServices*" -or $_.Name -like "*GamingApp*" -or $_.Name -like "*WebExperience*" } |
        ForEach-Object {
            $pkg = $_
            try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop }
            catch { Write-Host "    [!] No se pudo quitar $($pkg.Name): $($_.Exception.Message)" -ForegroundColor DarkYellow }
        }
}

Write-ScriptSummary -ScriptName "lock_after_update"
