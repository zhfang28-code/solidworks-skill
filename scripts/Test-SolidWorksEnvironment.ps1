[CmdletBinding()]
param(
    [string]$SolidWorksRoot,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootCandidates = New-Object 'System.Collections.Generic.List[string]'

function Add-RootCandidate {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $candidate = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return
    }

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $candidate = Split-Path -LiteralPath $candidate -Parent
    }
    if (-not $rootCandidates.Contains($candidate)) {
        [void]$rootCandidates.Add($candidate)
    }
}

Add-RootCandidate $SolidWorksRoot

$registryRoots = @(
    'HKLM:\SOFTWARE\SolidWorks',
    'HKLM:\SOFTWARE\WOW6432Node\SolidWorks'
)
$installPropertyNames = @('InstallDir', 'Install Location', 'SolidWorks Folder', 'Path')

foreach ($registryRoot in $registryRoots) {
    if (-not (Test-Path -LiteralPath $registryRoot)) { continue }
    Get-ChildItem -LiteralPath $registryRoot -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $properties = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) { return }
        foreach ($propertyName in $installPropertyNames) {
            $property = $properties.PSObject.Properties[$propertyName]
            if ($null -ne $property) {
                Add-RootCandidate ([string]$property.Value)
            }
        }
    }
}

Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    Add-RootCandidate (Join-Path $_.Root 'Program Files\SOLIDWORKS Corp\SOLIDWORKS')
    Add-RootCandidate (Join-Path $_.Root 'Program Files (x86)\SOLIDWORKS Corp\SOLIDWORKS')
}

$resolvedRoot = $null
foreach ($candidate in $rootCandidates) {
    if (Test-Path -LiteralPath (Join-Path $candidate 'SLDWORKS.exe') -PathType Leaf) {
        $resolvedRoot = $candidate
        break
    }
}

$sldWorksExe = $null
$interopSldWorks = $null
$interopSwConst = $null
if ($resolvedRoot) {
    $sldWorksExe = Join-Path $resolvedRoot 'SLDWORKS.exe'
    $interopSldWorks = Join-Path $resolvedRoot 'api\redist\SolidWorks.Interop.sldworks.dll'
    $interopSwConst = Join-Path $resolvedRoot 'api\redist\SolidWorks.Interop.swconst.dll'
}

$templateCandidates = New-Object 'System.Collections.Generic.List[string]'
$programDataRoot = [Environment]::GetFolderPath('CommonApplicationData')
foreach ($templateSearchRoot in @(
    (Join-Path $programDataRoot 'SOLIDWORKS'),
    $(if ($resolvedRoot) { Join-Path $resolvedRoot 'data\templates' } else { $null })
)) {
    if ([string]::IsNullOrWhiteSpace($templateSearchRoot)) { continue }
    if (-not (Test-Path -LiteralPath $templateSearchRoot -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $templateSearchRoot -Filter '*.prtdot' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 25 |
        ForEach-Object { [void]$templateCandidates.Add($_.FullName) }
}

$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$cSharpCompiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

$result = [pscustomobject]@{
    Ready = [bool](
        $resolvedRoot -and
        (Test-Path -LiteralPath $sldWorksExe -PathType Leaf) -and
        (Test-Path -LiteralPath $interopSldWorks -PathType Leaf) -and
        (Test-Path -LiteralPath $interopSwConst -PathType Leaf) -and
        $templateCandidates.Count -gt 0 -and
        $cSharpCompiler
    )
    SolidWorksRoot = $resolvedRoot
    SolidWorksExe = $sldWorksExe
    InteropSldWorks = $(if ($interopSldWorks -and (Test-Path -LiteralPath $interopSldWorks)) { $interopSldWorks } else { $null })
    InteropSwConst = $(if ($interopSwConst -and (Test-Path -LiteralPath $interopSwConst)) { $interopSwConst } else { $null })
    PartTemplates = @($templateCandidates)
    CSharpCompiler = $cSharpCompiler
    Host = [pscustomobject]@{
        OS = [Environment]::OSVersion.VersionString
        Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
}
else {
    $result
}
