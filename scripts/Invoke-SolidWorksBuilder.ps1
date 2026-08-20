[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$SolidWorksRoot,
    [string]$BuildRoot,
    [switch]$CompileOnly,
    [switch]$CloseWhenFinished,
    [switch]$KeepBuildDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    throw 'OutputDirectory 必须是用户已确认的绝对路径。'
}

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
if ([System.IO.Path]::GetExtension($resolvedSource) -ne '.cs') {
    throw 'SourcePath 必须指向 C# 源文件（.cs）。'
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
    throw "输出路径是文件而不是目录：$resolvedOutput"
}
if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    $resolvedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'solidworks-skill'))
}
else {
    if (-not [System.IO.Path]::IsPathRooted($BuildRoot)) {
        throw 'BuildRoot 必须是绝对路径。'
    }
    $resolvedBuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
}
if (Test-Path -LiteralPath $resolvedBuildRoot -PathType Leaf) {
    throw "BuildRoot 是文件而不是目录：$resolvedBuildRoot"
}
if (-not (Test-Path -LiteralPath $resolvedBuildRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedBuildRoot -Force | Out-Null
}

function Remove-EphemeralBuildDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedDirectory = [System.IO.Path]::GetFullPath($Directory)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $rootPrefix = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedDirectory.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝清理 BuildRoot 之外的目录：$resolvedDirectory"
    }
    if ((Split-Path -Leaf $resolvedDirectory) -notmatch '^rebuild_tool_\d{8}_\d{6}_\d{3}$') {
        throw "拒绝清理名称异常的目录：$resolvedDirectory"
    }
    $directoryInfo = Get-Item -LiteralPath $resolvedDirectory -Force -ErrorAction Stop
    if (($directoryInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "拒绝清理重解析点目录：$resolvedDirectory"
    }
    $modelExtensions = @('.SLDPRT', '.SLDASM', '.SLDDRW', '.STEP', '.STP')
    $modelFiles = @(
        Get-ChildItem -LiteralPath $resolvedDirectory -Recurse -File -ErrorAction Stop |
            Where-Object { $modelExtensions -contains $_.Extension.ToUpperInvariant() }
    )
    if ($modelFiles.Count -gt 0) {
        throw "临时编译目录包含模型文件，拒绝清理：$resolvedDirectory"
    }
    Remove-Item -LiteralPath $resolvedDirectory -Recurse -Force
}

$probePath = Join-Path $PSScriptRoot 'Test-SolidWorksEnvironment.ps1'
$probeArguments = @{}
if (-not [string]::IsNullOrWhiteSpace($SolidWorksRoot)) {
    $probeArguments['SolidWorksRoot'] = $SolidWorksRoot
}
$environment = & $probePath @probeArguments
if (-not $environment.Ready) {
    throw ('SolidWorks 自动化环境不完整：' + ($environment | ConvertTo-Json -Depth 4 -Compress))
}

$buildDirectory = Join-Path $resolvedBuildRoot ('rebuild_tool_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $buildDirectory | Out-Null

$sourceCopy = Join-Path $buildDirectory ([System.IO.Path]::GetFileName($resolvedSource))
Copy-Item -LiteralPath $resolvedSource -Destination $sourceCopy

$executablePath = Join-Path $buildDirectory (([System.IO.Path]::GetFileNameWithoutExtension($resolvedSource)) + '.exe')
$compilerArguments = @(
    '/nologo',
    '/optimize+',
    '/target:exe',
    ('/out:' + $executablePath),
    ('/reference:' + $environment.InteropSldWorks),
    ('/reference:' + $environment.InteropSwConst)
)

$frameworkDirectory = [System.IO.Path]::GetDirectoryName([string]$environment.CSharpCompiler)
$systemWebExtensions = Join-Path $frameworkDirectory 'System.Web.Extensions.dll'
if (Test-Path -LiteralPath $systemWebExtensions -PathType Leaf) {
    $compilerArguments += '/reference:' + $systemWebExtensions
}
$compilerArguments += $sourceCopy

& $environment.CSharpCompiler @compilerArguments
$compileExitCode = $LASTEXITCODE
if ($compileExitCode -ne 0 -or -not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "C# builder 编译失败，退出码：$compileExitCode"
}

Copy-Item -LiteralPath $environment.InteropSldWorks -Destination $buildDirectory
Copy-Item -LiteralPath $environment.InteropSwConst -Destination $buildDirectory

$compileResult = [pscustomobject]@{
    SourcePath = $resolvedSource
    OutputDirectory = $resolvedOutput
    BuildRoot = $resolvedBuildRoot
    BuildDirectory = $buildDirectory
    ExecutablePath = $executablePath
    SolidWorksRoot = $environment.SolidWorksRoot
    CompileExitCode = $compileExitCode
    Executed = $false
    BuilderExitCode = $null
    BuildDirectoryRetained = $true
    CleanupStatus = 'NotAttempted'
    CleanupError = $null
}

if ($CompileOnly) {
    if ($KeepBuildDirectory) {
        $compileResult.CleanupStatus = 'RetainedByRequest'
    }
    else {
        try {
            Remove-EphemeralBuildDirectory -Directory $buildDirectory -Root $resolvedBuildRoot
            $compileResult.BuildDirectoryRetained = $false
            $compileResult.CleanupStatus = 'RemovedAfterCompileOnly'
        }
        catch {
            $compileResult.CleanupStatus = 'CleanupFailed'
            $compileResult.CleanupError = $_.Exception.Message
            Write-Warning ("编译成功，但临时目录清理失败：" + $_.Exception.Message)
        }
    }
    $compileResult
    return
}

$runArguments = @($resolvedOutput)
if ($CloseWhenFinished) {
    $runArguments += '--close'
}

& $executablePath @runArguments
$builderExitCode = $LASTEXITCODE
$compileResult.Executed = $true
$compileResult.BuilderExitCode = $builderExitCode

if ($builderExitCode -ne 0) {
    $compileResult.CleanupStatus = 'RetainedAfterBuilderFailure'
    $compileResult
    throw "SolidWorks builder 执行失败，退出码：$builderExitCode。检查输出目录中的生成日志。"
}

if ($KeepBuildDirectory) {
    $compileResult.CleanupStatus = 'RetainedByRequest'
}
else {
    try {
        Remove-EphemeralBuildDirectory -Directory $buildDirectory -Root $resolvedBuildRoot
        $compileResult.BuildDirectoryRetained = $false
        $compileResult.CleanupStatus = 'RemovedAfterSuccessfulRun'
    }
    catch {
        $compileResult.CleanupStatus = 'CleanupFailed'
        $compileResult.CleanupError = $_.Exception.Message
        Write-Warning ("构建成功，但临时目录清理失败：" + $_.Exception.Message)
    }
}

$compileResult
