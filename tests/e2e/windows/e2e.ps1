<#
 Copyright 2026 Han Li and contributors

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
#>

# End-to-end checks of this plugin with a real vfox on Windows: the same checks
# as tests/e2e/linux/e2e.sh. The plugin is registered from the checkout the
# script runs in. It needs vfox 1.1.0 or later on PATH (link --detect), and
# network access to ziglang.org and machengine.org.
#
# Run it from the repository root in PowerShell 7:
#   pwsh -NoProfile -File tests/e2e/windows/e2e.ps1

$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

# The Mach build used below, and the zig installed as a system copy, with the
# SHA-256 that ziglang.org's index lists for its archive (tests/fixtures/index).
$MachName = '2024.11.0-mach'
$MachVersion = '0.14.0-dev.2577+271452d22'
$SystemVersion = '0.12.1'
$SystemUrl = "https://ziglang.org/download/$SystemVersion/zig-windows-x86_64-$SystemVersion.zip"
$SystemSha256 = '52459b147c2de4d7c28f6b1a4b3d571c114e96836bf8e31c953a7d2f5e94251c'

# A work directory with a space in its name, as paths on Windows often have one.
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ('zig e2e ' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null

# A private home for vfox, so the run never touches the real one. vfox keeps its
# user and shared directories under %USERPROFILE%\.vfox, a directory named .vfox
# as the default is, so the installs made here are not taken for system installs.
$env:USERPROFILE = Join-Path $Work 'home'
$env:HOME = $env:USERPROFILE
New-Item -ItemType Directory -Path $env:USERPROFILE | Out-Null
Remove-Item Env:VFOX_HOME -ErrorAction SilentlyContinue

function Write-Step([string] $Name) {
    Write-Output ''
    Write-Output "== $Name"
}

function Write-Pass([string] $Name) {
    Write-Output "PASS $Name"
}

# Invoke-Capture runs Program with Arguments and returns its exit code and the
# text it wrote to standard output and to standard error. The two streams are
# read separately, and in full, so a message on either one is kept: the
# *>&1 merge that this script used before lost the message of a failing vfox
# command on Windows.
function Invoke-Capture([string] $Program, [string[]] $Arguments) {
    $executable = (Get-Command -Name $Program -CommandType Application | Select-Object -First 1).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($executable)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        Code   = $process.ExitCode
        Stdout = $stdout.Result
        Stderr = $stderr.Result
    }
}

# Invoke-Native runs a command with its output in $Work\$Log. When the command
# fails, it stops the script and shows both streams.
function Invoke-Native([string] $Log, [string] $Program, [string[]] $Arguments) {
    $result = Invoke-Capture $Program $Arguments
    $text = $result.Stdout + $result.Stderr
    Set-Content -Path (Join-Path $Work $Log) -Value $text -Encoding utf8 -NoNewline
    if ($result.Code -ne 0) {
        Write-Output "--- $Program $($Arguments -join ' ') exited with $($result.Code) ---"
        Write-Output '--- stdout ---'
        Write-Output $result.Stdout
        Write-Output '--- stderr ---'
        Write-Output $result.Stderr
        throw "$Program $($Arguments -join ' ') failed with exit code $($result.Code)"
    }
    return $text
}

# Test-TextFound passes when Text contains Needle.
function Test-TextFound([string] $Label, [string] $Text, [string] $Needle) {
    if (-not $Text.Contains($Needle)) {
        Write-Output '--- output ---'
        Write-Output $Text
        throw "$Label`: expected to find: $Needle"
    }
    Write-Pass $Label
}

# Test-CommandFailure passes when the command fails and says Needle, on either
# stream.
function Test-CommandFailure([string] $Label, [string] $Needle, [string] $Program, [string[]] $Arguments) {
    $result = Invoke-Capture $Program $Arguments
    $text = $result.Stdout + $result.Stderr
    if ($result.Code -eq 0) {
        Write-Output '--- output ---'
        Write-Output $text
        throw "$Label`: the command should have failed"
    }
    Test-TextFound $Label $text $Needle
}

# Invoke-VfoxShellCode runs the PowerShell that vfox prints, which is what the
# shell hook evaluates: the activation, and the environment of the global zig.
function Invoke-VfoxShellCode {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'vfox prints the PowerShell that its shell hook evaluates; this is that evaluation, with no other input')]
    param([string[]] $Arguments)
    Invoke-Expression ((& vfox @Arguments) | Out-String)
}

# Use-Zig makes the spec the global zig. Then it refreshes the environment the
# way the shell hook does between prompts, which a script does not get.
function Use-Zig([string] $Spec) {
    Invoke-Native 'use.log' 'vfox' @('use', '--global', $Spec) | Out-Null
    Invoke-VfoxShellCode 'env', '-s', 'pwsh'
}

function Get-ZigVersion {
    return ((zig version 2>&1) | Out-String).Trim()
}

try {
    Write-Step 'vfox is 1.1.0 or later'
    $vfoxVersion = [regex]::Match((vfox --version | Out-String), '\d+\.\d+\.\d+').Value
    if ([string]::IsNullOrEmpty($vfoxVersion)) {
        throw 'vfox --version names no version'
    }
    $lowest = @('1.1.0', $vfoxVersion) | Sort-Object { [version] $_ } | Select-Object -First 1
    if ($lowest -ne '1.1.0') {
        throw "vfox 1.1.0 or later is needed for link --detect, found: $vfoxVersion"
    }
    Write-Pass "vfox $vfoxVersion is 1.1.0 or later"

    Write-Step 'standard error is read'
    # vfox writes this usage error to standard error alone, so the check fails if
    # the output of standard error is lost.
    $usage = Invoke-Capture 'vfox' @('link')
    if ($usage.Code -eq 0) {
        throw 'vfox link without arguments should fail'
    }
    Test-TextFound 'vfox link without arguments writes its usage to standard error' $usage.Stderr 'usage: vfox link'

    # vfox use needs the shell hook set up first, as an interactive shell has it.
    Invoke-VfoxShellCode 'activate', 'pwsh'

    Write-Step 'register the plugin from this checkout'
    $zip = Join-Path $Work 'zig.zip'
    Compress-Archive -Path (Join-Path $Repo 'metadata.lua'), (Join-Path $Repo 'hooks'), (Join-Path $Repo 'lib') -DestinationPath $zip
    Invoke-Native 'add.log' 'vfox' @('add', 'zig', '--source', $zip) | Out-Null
    Write-Pass 'vfox add zig --source <the checkout>'
    # The notes printed by vfox info point to the README, which lists the names.
    $info = Invoke-Native 'info.log' 'vfox' @('info', 'zig')
    Test-TextFound 'vfox info zig points to the README' $info 'README.md'

    Write-Step 'vfox search zig'
    $search = Invoke-Native 'search.log' 'vfox' @('search', 'zig')
    Test-TextFound 'the search lists 0.13.0' $search '0.13.0'
    Test-TextFound 'the search names the nightly' $search 'nightly'
    Test-TextFound 'the search names a Mach build' $search $MachName
    Test-TextFound 'the search marks a release as latest' $search 'latest'

    Write-Step 'install a pinned release'
    $install = Invoke-Native 'install-0.13.0.log' 'vfox' @('install', 'zig@0.13.0')
    # vfox prints this only when the download has a checksum to compare with.
    Test-TextFound 'the download is verified against its checksum' $install 'Verifying checksum'
    Use-Zig 'zig@0.13.0'
    Test-TextFound 'zig 0.13.0 is on PATH' (Get-ZigVersion) '0.13.0'

    Write-Step 'the standard library is found from the installed zig'
    $hello = Join-Path $Work 'hello.zig'
    Set-Content -Path $hello -Value @'
const std = @import("std");

pub fn main() void {
    std.debug.print("hello from zig\n", .{});
}
'@ -Encoding utf8
    Push-Location $Work
    try {
        $run = zig run hello.zig 2>&1 | Out-String
    }
    finally {
        Pop-Location
    }
    Test-TextFound 'zig run compiles against the std library' $run 'hello from zig'

    Write-Step 'install latest'
    Invoke-Native 'install-latest.log' 'vfox' @('install', 'zig@latest') | Out-Null
    # The release that search marks latest is the one that installs.
    $latestLine = ($search -split "`r?`n" | Where-Object { $_ -match 'latest' } | Select-Object -First 1)
    $expected = [regex]::Match([string] $latestLine, '\d+\.\d+\.\d+').Value
    if ([string]::IsNullOrEmpty($expected)) {
        throw 'the search output names no release as latest'
    }
    Write-Pass "search marks $expected as latest"
    Use-Zig 'zig@latest'
    Test-TextFound 'zig@latest selects the release search marks latest' (Get-ZigVersion) $expected

    Write-Step 'install a Mach build by its name'
    Invoke-Native 'install-mach.log' 'vfox' @('install', "zig@$MachName") | Out-Null
    Use-Zig "zig@$MachName"
    Test-TextFound "zig@$MachName selects the Mach build" (Get-ZigVersion) $MachVersion

    Write-Step 'a version the index does not list fails'
    Test-CommandFailure 'vfox install zig@9.9.9 fails' 'is not listed for windows/amd64' 'vfox' @('install', 'zig@9.9.9')

    Write-Step 'a zig that vfox did not install is linked with link --detect'
    $systemRoot = Join-Path $Work 'system'
    $systemLeaf = "zig-windows-x86_64-$SystemVersion"
    $systemDir = Join-Path $systemRoot $systemLeaf
    New-Item -ItemType Directory -Path $systemRoot | Out-Null
    $archive = Join-Path $Work 'system.zip'
    Invoke-Native 'system-download.log' 'curl.exe' @('--fail', '--silent', '--show-error', '--location', '--retry', '3', '--output', $archive, $SystemUrl) | Out-Null
    $digest = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
    if ($digest -ne $SystemSha256) {
        throw "the zig $SystemVersion archive does not match its checksum: $digest"
    }
    Expand-Archive -Path $archive -DestinationPath $systemRoot
    Write-Pass "unpacked zig $SystemVersion as a system copy"

    # The copy is only on PATH, which is where link --detect looks first.
    $env:PATH = "$systemDir;$env:PATH"
    $detect = Invoke-Native 'detect.log' 'vfox' @('link', '--detect', '-y', 'zig')
    # Names are checked by their last folder: a temporary folder can be spelled with
    # 8.3 short names, which vfox may print in full.
    Test-TextFound 'link --detect finds the copy on PATH' $detect $systemLeaf
    Test-TextFound 'link --detect names the version' $detect $SystemVersion

    $list = Invoke-Native 'list.log' 'vfox' @('list', 'zig')
    Test-TextFound 'vfox list shows the link' $list $systemLeaf

    Use-Zig "zig@$SystemVersion"
    Test-TextFound 'the linked zig runs' (Get-ZigVersion) $SystemVersion

    # Versions vfox installed are not offered again, so a second run finds nothing new.
    $again = Invoke-Native 'detect-again.log' 'vfox' @('link', '--detect', '-y', 'zig')
    Test-TextFound 'a second link --detect finds nothing new' $again 'No new zig installations found'

    # Removing the link leaves the directory where it was.
    Invoke-Native 'uninstall.log' 'vfox' @('uninstall', "zig@$SystemVersion") | Out-Null
    if (-not (Test-Path (Join-Path $systemDir 'zig.exe'))) {
        throw 'uninstalling a link removed the system zig'
    }
    Write-Pass 'vfox uninstall removes the link and keeps the system zig'

    Write-Step 'all checks passed'
}
finally {
    Remove-Item -Path $Work -Recurse -Force -ErrorAction SilentlyContinue
}
