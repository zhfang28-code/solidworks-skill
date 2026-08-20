[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$BaseName,

    [ValidateSet('Part', 'Assembly')]
    [string]$DocumentType = 'Part',

    [string]$NativeModelPath,
    [string]$StepPath,
    [string]$IsometricPreviewPath,
    [string]$FrontPreviewPath,
    [string]$SidePreviewPath,
    [string]$AuditPath,
    [string]$BuildLogPath,
    [switch]$RequireBom,
    [string]$BomPath,
    [switch]$WriteManifest,
    [switch]$Force,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    throw 'OutputDirectory 必须是绝对路径。'
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Container)) {
    throw "交付目录不存在：$resolvedOutput"
}

function Resolve-DeliveryPath {
    param([string]$Path, [string]$DefaultName)

    $selected = if ([string]::IsNullOrWhiteSpace($Path)) { $DefaultName } else { $Path }
    if ([System.IO.Path]::IsPathRooted($selected)) {
        return [System.IO.Path]::GetFullPath($selected)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $resolvedOutput $selected))
}

$documentExtension = if ($DocumentType -eq 'Assembly') { '.SLDASM' } else { '.SLDPRT' }
$expected = @(
    [pscustomobject]@{ Kind = 'NativeModel'; Required = $true; Path = (Resolve-DeliveryPath $NativeModelPath ($BaseName + $documentExtension)) },
    [pscustomobject]@{ Kind = 'STEP'; Required = $true; Path = (Resolve-DeliveryPath $StepPath ($BaseName + '.STEP')) },
    [pscustomobject]@{ Kind = 'IsometricPreview'; Required = $true; Path = (Resolve-DeliveryPath $IsometricPreviewPath ($BaseName + '_等轴测.png')) },
    [pscustomobject]@{ Kind = 'FrontPreview'; Required = $true; Path = (Resolve-DeliveryPath $FrontPreviewPath ($BaseName + '_正视.png')) },
    [pscustomobject]@{ Kind = 'SidePreview'; Required = $true; Path = (Resolve-DeliveryPath $SidePreviewPath ($BaseName + '_侧视.png')) },
    [pscustomobject]@{ Kind = 'AuditData'; Required = $true; Path = (Resolve-DeliveryPath $AuditPath ($BaseName + '_模型审查数据.json')) },
    [pscustomobject]@{ Kind = 'BuildLog'; Required = $true; Path = (Resolve-DeliveryPath $BuildLogPath ($BaseName + '_生成日志.txt')) }
)

if ($RequireBom) {
    $expected += [pscustomobject]@{
        Kind = 'BOM'
        Required = $true
        Path = (Resolve-DeliveryPath $BomPath ($BaseName + '_BOM.xlsx'))
    }
}

$checks = foreach ($item in $expected) {
    $exists = Test-Path -LiteralPath $item.Path -PathType Leaf
    $file = if ($exists) { Get-Item -LiteralPath $item.Path } else { $null }
    [pscustomobject]@{
        Kind = $item.Kind
        Required = $item.Required
        Path = $item.Path
        Exists = $exists
        SizeBytes = $(if ($file) { $file.Length } else { 0 })
        Sha256 = $(if ($file -and $file.Length -gt 0) { (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash } else { $null })
    }
}

$missing = @($checks | Where-Object { $_.Required -and (-not $_.Exists -or $_.SizeBytes -le 0) })
$result = [pscustomobject]@{
    Ready = ($missing.Count -eq 0)
    OutputDirectory = $resolvedOutput
    BaseName = $BaseName
    DocumentType = $DocumentType
    Checks = @($checks)
    MissingRequired = @($missing)
    CheckedAt = (Get-Date).ToString('o')
}

if ($WriteManifest) {
    $manifestPath = Join-Path $resolvedOutput 'delivery_manifest.json'
    $hashPath = Join-Path $resolvedOutput 'SHA256.txt'
    foreach ($target in @($manifestPath, $hashPath)) {
        if ((Test-Path -LiteralPath $target) -and -not $Force) {
            throw "目标已存在；如确认覆盖清单文件，请加 -Force：$target"
        }
    }

    $result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $hashLines = $checks |
        Where-Object { $_.Sha256 } |
        ForEach-Object { $_.Sha256 + '  ' + [System.IO.Path]::GetFileName($_.Path) }
    $hashLines | Set-Content -LiteralPath $hashPath -Encoding UTF8
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 7
}
else {
    $result
}
