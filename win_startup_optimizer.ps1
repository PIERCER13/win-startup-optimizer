<#
.SYNOPSIS
    piercer_win-startup-optimizer - Mede impacto de programas de inicializacao, apps UWP Startup e servicos Automaticos.
    Author: piercer
#>
param(
    [switch]$ExportCsv,
    [string]$OutFile = ".\startup_audit.csv"
)

$ErrorActionPreference = "SilentlyContinue"
Write-Host "`n=== piercer_win-startup-optimizer ===" -ForegroundColor Red

$results = New-Object System.Collections.Generic.List[object]

$runPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

foreach ($path in $runPaths) {
    if (Test-Path $path) {
        $props = Get-ItemProperty -Path $path
        $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            $cmd = [string]$_.Value
            $exe = $cmd
            if ($cmd -match '^"([^"]+)"') { $exe = $matches[1] }
            elseif ($cmd -match '^([^\s]+)') { $exe = $matches[1] }
            $exists = Test-Path $exe
            $sigStatus = "N/A"
            if ($exists) {
                $sig = Get-AuthenticodeSignature -FilePath $exe
                if ($sig) { $sigStatus = $sig.Status.ToString() }
            }
            $results.Add([PSCustomObject]@{
                Fonte      = "Registry"
                Local      = $path
                Nome       = $_.Name
                Comando    = $cmd
                ArquivoOK  = $exists
                Assinatura = $sigStatus
            })
        }
    }
}

$startupDirs = @(
    [Environment]::GetFolderPath("Startup"),
    [Environment]::GetFolderPath("CommonStartup")
)
foreach ($dir in $startupDirs) {
    if ($dir -and (Test-Path $dir)) {
        Get-ChildItem -Path $dir -File | ForEach-Object {
            $results.Add([PSCustomObject]@{
                Fonte      = "StartupFolder"
                Local      = $dir
                Nome       = $_.Name
                Comando    = $_.FullName
                ArquivoOK  = $true
                Assinatura = (Get-AuthenticodeSignature -FilePath $_.FullName).Status.ToString()
            })
        }
    }
}

Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq "Auto" -and $_.PathName -notmatch "System32|SysWOW64" } | ForEach-Object {
    $results.Add([PSCustomObject]@{
        Fonte      = "AutoService(3rdParty)"
        Local      = $_.StartMode
        Nome       = $_.Name
        Comando    = $_.PathName
        ArquivoOK  = $true
        Assinatura = $_.State
    })
}

$results | Format-Table -AutoSize Fonte, Nome, ArquivoOK, Assinatura, Comando

if ($ExportCsv) {
    $results | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
    Write-Host "[OK] Exportado para $OutFile" -ForegroundColor Green
}
