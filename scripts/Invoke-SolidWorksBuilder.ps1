[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$SolidWorksRoot,
    [switch]$CompileOnly,
    [switch]$CloseWhenFinished
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

$probePath = Join-Path $PSScriptRoot 'Test-SolidWorksEnvironment.ps1'
$probeArguments = @{}
if (-not [string]::IsNullOrWhiteSpace($SolidWorksRoot)) {
    $probeArguments['SolidWorksRoot'] = $SolidWorksRoot
}
$environment = & $probePath @probeArguments
if (-not $environment.Ready) {
    throw ('SolidWorks 自动化环境不完整：' + ($environment | ConvertTo-Json -Depth 4 -Compress))
}

$buildDirectory = Join-Path $resolvedOutput ('rebuild_tool_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
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
    BuildDirectory = $buildDirectory
    ExecutablePath = $executablePath
    SolidWorksRoot = $environment.SolidWorksRoot
    CompileExitCode = $compileExitCode
    Executed = $false
    BuilderExitCode = $null
}

if ($CompileOnly) {
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
    $compileResult
    throw "SolidWorks builder 执行失败，退出码：$builderExitCode。检查输出目录中的生成日志。"
}

$compileResult
