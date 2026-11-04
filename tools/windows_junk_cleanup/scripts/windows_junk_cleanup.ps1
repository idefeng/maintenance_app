<#
.SYNOPSIS
    Windows junk scanner / cleaner for the maintenance_app win-tools project.

.DESCRIPTION
    Scans common Windows junk locations and reports reclaimable space.
    Default mode is dry-run (scan only). Deletion requires -Clean and an
    interactive confirmation (unless -Yes is passed).

    User-scoped categories work without admin. System categories that need
    elevation are still scanned when readable; cleaning them documents the
    admin requirement and skips safely when not elevated.

.PARAMETER Scan
    Explicit scan / dry-run mode (default when neither -Scan nor -Clean is set).

.PARAMETER Clean
    Delete selected categories after confirmation.

.PARAMETER Categories
    Comma-separated category ids to include. Default: all discoverable categories.
    Use -ListCategories to see ids.

.PARAMETER ListCategories
    Print supported category ids and exit.

.PARAMETER Yes
    Skip the interactive "type YES" confirmation when cleaning.
    Still refuses to clean Windows.old unless -IncludeWindowsOld is set.

.PARAMETER IncludeWindowsOld
    Allow Windows.old to be considered for cleaning (still warns loudly).

.PARAMETER Json
    Also write a JSON report under tools/windows_junk_cleanup/runtime/reports/.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows_junk_cleanup.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows_junk_cleanup.ps1 -Clean -Categories UserTemp,BrowserCache

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows_junk_cleanup.ps1 -Clean -Categories WindowsTemp -Yes
#>

[CmdletBinding(DefaultParameterSetName = 'Scan')]
param(
    [Parameter(ParameterSetName = 'Scan')]
    [switch]$Scan,

    [Parameter(ParameterSetName = 'Clean')]
    [switch]$Clean,

    [string[]]$Categories = @(),

    [switch]$ListCategories,

    [Parameter(ParameterSetName = 'Clean')]
    [switch]$Yes,

    [switch]$IncludeWindowsOld,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Format-ByteSize {
    param([long]$Bytes)
    if ($Bytes -lt 0) { $Bytes = 0 }
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $value = [double]$Bytes
    $i = 0
    while ($value -ge 1024 -and $i -lt ($units.Count - 1)) {
        $value /= 1024
        $i++
    }
    if ($i -eq 0) {
        return ('{0} {1}' -f [int]$value, $units[$i])
    }
    return ('{0:N2} {1}' -f $value, $units[$i])
}

function Get-DirectorySizeBytes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string[]]$Include = @('*'),
        [switch]$FilesOnly
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [long]0
    }

    $total = [long]0
    try {
        $items = Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if ($item.PSIsContainer) { continue }
            $matched = $false
            foreach ($pattern in $Include) {
                if ($item.Name -like $pattern) {
                    $matched = $true
                    break
                }
            }
            if ($matched) {
                $total += [long]$item.Length
            }
        }
    }
    catch {
        # Unreadable paths contribute 0; caller sees NeedsAdmin / Skipped notes.
    }
    return $total
}

function Test-PathReadable {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-ToolPath {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return $null }
    return $cmd.Source
}

function Write-Zh {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host $Message -ForegroundColor $Color
}

function New-Finding {
    param(
        [string]$Id,
        [string]$NameZh,
        [string]$Description,
        [string[]]$Paths,
        [long]$Bytes,
        [bool]$NeedsAdmin,
        [bool]$Present,
        [string]$Risk,
        [string]$Note = '',
        [scriptblock]$CleanAction = $null
    )

    return [pscustomobject]@{
        Id          = $Id
        NameZh      = $NameZh
        Description = $Description
        Paths       = @($Paths | Where-Object { $_ })
        Bytes       = $Bytes
        NeedsAdmin  = $NeedsAdmin
        Present     = $Present
        Risk        = $Risk
        Note        = $Note
        CleanAction = $CleanAction
    }
}

# ---------------------------------------------------------------------------
# Safe clean primitives — never wipe roots wholesale without filters
# ---------------------------------------------------------------------------

function Clear-DirectoryContents {
    param(
        [string]$Path,
        [int]$OlderThanHours = 0,
        [string[]]$ExcludeNamePatterns = @()
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0 }
    }

    $deleted = 0
    $failed = 0
    $freed = [long]0
    $cutoff = $null
    if ($OlderThanHours -gt 0) {
        $cutoff = (Get-Date).AddHours(-1 * $OlderThanHours)
    }

    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        $skip = $false
        foreach ($pat in $ExcludeNamePatterns) {
            if ($item.Name -like $pat) { $skip = $true; break }
        }
        if ($skip) { continue }

        if ($null -ne $cutoff) {
            $stamp = $item.LastWriteTime
            if ($item.PSIsContainer -eq $false -and $item.CreationTime -gt $stamp) {
                $stamp = $item.CreationTime
            }
            if ($stamp -gt $cutoff) { continue }
        }

        try {
            if ($item.PSIsContainer) {
                $size = Get-DirectorySizeBytes -Path $item.FullName
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $freed += $size
            }
            else {
                $freed += [long]$item.Length
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
            }
            $deleted++
        }
        catch {
            $failed++
        }
    }

    return [pscustomobject]@{ Deleted = $deleted; Failed = $failed; FreedApprox = $freed }
}

function Clear-MatchingFiles {
    param(
        [string]$Path,
        [string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0 }
    }

    $deleted = 0
    $failed = 0
    $freed = [long]0

    foreach ($pattern in $Patterns) {
        $files = @(Get-ChildItem -LiteralPath $Path -Force -Filter $pattern -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            if ($file.PSIsContainer) { continue }
            try {
                $freed += [long]$file.Length
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $deleted++
            }
            catch {
                $failed++
            }
        }
    }

    return [pscustomobject]@{ Deleted = $deleted; Failed = $failed; FreedApprox = $freed }
}

# ---------------------------------------------------------------------------
# Category catalog
# ---------------------------------------------------------------------------

$script:IsAdmin = Test-IsAdministrator
$script:LocalAppData = [Environment]::GetFolderPath('LocalApplicationData')
$script:UserProfile = $env:USERPROFILE
$script:WinDir = $env:WINDIR
if ([string]::IsNullOrWhiteSpace($script:WinDir)) { $script:WinDir = 'C:\Windows' }

function Get-CategoryCatalog {
    $catalog = @()

    # --- UserTemp ----------------------------------------------------------
    $userTempPaths = @()
    if ($env:TEMP) { $userTempPaths += $env:TEMP }
    if ($env:TMP -and ($env:TMP -ne $env:TEMP)) { $userTempPaths += $env:TMP }
    $localTemp = Join-Path $script:LocalAppData 'Temp'
    if ($userTempPaths -notcontains $localTemp) { $userTempPaths += $localTemp }
    $userTempPaths = @($userTempPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    $userTempBytes = [long]0
    foreach ($p in $userTempPaths) { $userTempBytes += Get-DirectorySizeBytes -Path $p }

    $catalog += New-Finding -Id 'UserTemp' -NameZh '用户临时文件' `
        -Description '当前用户 %TEMP% / LocalAppData\Temp' `
        -Paths $userTempPaths -Bytes $userTempBytes -NeedsAdmin:$false `
        -Present:($userTempPaths.Count -gt 0) -Risk 'low' `
        -Note '跳过仍被占用的文件；不删除目录本身。' `
        -CleanAction ({
            $sum = [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0 }
            foreach ($p in $userTempPaths) {
                $r = Clear-DirectoryContents -Path $p
                $sum.Deleted += $r.Deleted
                $sum.Failed += $r.Failed
                $sum.FreedApprox += $r.FreedApprox
            }
            $sum
        }.GetNewClosure())

    # --- WindowsTemp -------------------------------------------------------
    $winTemp = Join-Path $script:WinDir 'Temp'
    $winTempPresent = Test-Path -LiteralPath $winTemp
    $winTempReadable = $winTempPresent -and (Test-PathReadable -Path $winTemp)
    $winTempBytes = if ($winTempReadable) { Get-DirectorySizeBytes -Path $winTemp } else { [long]0 }
    $winTempNote = if (-not $winTempPresent) {
        '路径不存在。'
    }
    elseif (-not $winTempReadable) {
        '目录存在但当前权限无法完整读取；清理需要管理员。'
    }
    else {
        '清理 Windows\Temp 内容通常需要管理员；跳过锁定文件。'
    }

    $catalog += New-Finding -Id 'WindowsTemp' -NameZh '系统临时文件' `
        -Description 'Windows\Temp' `
        -Paths @($winTemp) -Bytes $winTempBytes -NeedsAdmin:$true `
        -Present:$winTempPresent -Risk 'low' -Note $winTempNote `
        -CleanAction ({
            if (-not $script:IsAdmin) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = '需要管理员权限' }
            }
            Clear-DirectoryContents -Path $winTemp
        }.GetNewClosure())

    # --- RecycleBin --------------------------------------------------------
    $recycleBytes = [long]0
    $recyclePresent = $true
    $recycleNote = '通过 Shell.Application 清空当前用户回收站。'
    try {
        # Rough size estimate from $Recycle.Bin sid folders (best-effort, no admin).
        $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
            $rb = Join-Path $_.Root ('$Recycle.Bin\' + $sid)
            if (Test-Path -LiteralPath $rb) {
                $recycleBytes += Get-DirectorySizeBytes -Path $rb
            }
        }
    }
    catch {
        $recycleNote = '无法精确估算大小；仍可清空回收站。'
    }

    $catalog += New-Finding -Id 'RecycleBin' -NameZh '回收站' `
        -Description '当前用户回收站' `
        -Paths @('shell:RecycleBinFolder') -Bytes $recycleBytes -NeedsAdmin:$false `
        -Present:$recyclePresent -Risk 'low' -Note $recycleNote `
        -CleanAction ({
            $approx = $recycleBytes
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                return [pscustomobject]@{ Deleted = 1; Failed = 0; FreedApprox = $approx }
            }
            catch {
                try {
                    $shell = New-Object -ComObject Shell.Application
                    $bin = $shell.NameSpace(0xA)
                    if ($null -ne $bin) {
                        $bin.Items() | ForEach-Object {
                            Remove-Item -LiteralPath $_.Path -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    return [pscustomobject]@{ Deleted = 1; Failed = 0; FreedApprox = $approx }
                }
                catch {
                    return [pscustomobject]@{ Deleted = 0; Failed = 1; FreedApprox = [long]0 }
                }
            }
        }.GetNewClosure())

    # --- ThumbnailCache ----------------------------------------------------
    $thumbDir = Join-Path $script:LocalAppData 'Microsoft\Windows\Explorer'
    $thumbPresent = Test-Path -LiteralPath $thumbDir
    $thumbBytes = if ($thumbPresent) {
        Get-DirectorySizeBytes -Path $thumbDir -Include @('thumbcache_*.db', 'iconcache_*.db')
    }
    else { [long]0 }

    $catalog += New-Finding -Id 'ThumbnailCache' -NameZh '缩略图缓存' `
        -Description 'Explorer thumbcache_*.db / iconcache_*.db' `
        -Paths @($thumbDir) -Bytes $thumbBytes -NeedsAdmin:$false `
        -Present:$thumbPresent -Risk 'low' `
        -Note '删除后资源管理器会自动重建；被占用的库文件可能跳过。' `
        -CleanAction ({
            Clear-MatchingFiles -Path $thumbDir -Patterns @('thumbcache_*.db', 'iconcache_*.db')
        }.GetNewClosure())

    # --- DeliveryOptimization ----------------------------------------------
    $doPaths = @(
        (Join-Path $script:WinDir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'),
        (Join-Path $script:LocalAppData 'Microsoft\Windows\DeliveryOptimization\Cache')
    )
    $doExisting = @($doPaths | Where-Object { Test-Path -LiteralPath $_ })
    $doBytes = [long]0
    $doReadableAny = $false
    foreach ($p in $doExisting) {
        if (Test-PathReadable -Path $p) {
            $doReadableAny = $true
            $doBytes += Get-DirectorySizeBytes -Path $p
        }
    }
    $doNeedsAdmin = $true
    $doNote = '仅清理 Delivery Optimization 缓存目录内容；不触碰服务配置。'
    if ($doExisting.Count -eq 0) {
        $doNote = '未发现 Delivery Optimization 缓存目录。'
    }
    elseif (-not $doReadableAny) {
        $doNote = '缓存目录存在但当前无法读取；清理通常需要管理员。'
    }

    $catalog += New-Finding -Id 'DeliveryOptimization' -NameZh '传递优化缓存' `
        -Description 'Delivery Optimization Cache' `
        -Paths $doExisting -Bytes $doBytes -NeedsAdmin:$doNeedsAdmin `
        -Present:($doExisting.Count -gt 0) -Risk 'low' -Note $doNote `
        -CleanAction ({
            if (-not $script:IsAdmin) {
                # Try user-scoped path only
                $userDo = Join-Path $script:LocalAppData 'Microsoft\Windows\DeliveryOptimization\Cache'
                if (Test-Path -LiteralPath $userDo) {
                    return Clear-DirectoryContents -Path $userDo
                }
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = '需要管理员权限清理系统级传递优化缓存' }
            }
            $sum = [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0 }
            foreach ($p in $doExisting) {
                $r = Clear-DirectoryContents -Path $p
                $sum.Deleted += $r.Deleted
                $sum.Failed += $r.Failed
                $sum.FreedApprox += $r.FreedApprox
            }
            $sum
        }.GetNewClosure())

    # --- WindowsUpdate (SoftwareDistribution\Download only) ----------------
    $wuDownload = Join-Path $script:WinDir 'SoftwareDistribution\Download'
    $wuPresent = Test-Path -LiteralPath $wuDownload
    $wuReadable = $wuPresent -and (Test-PathReadable -Path $wuDownload)
    $wuBytes = if ($wuReadable) { Get-DirectorySizeBytes -Path $wuDownload } else { [long]0 }
    $wuNote = '只清理 SoftwareDistribution\Download，不动 DataStore。建议在无进行中的 Windows Update 时清理；需要管理员。'
    if ($wuPresent -and -not $wuReadable) {
        $wuNote = '目录存在但当前无法读取；清理需要管理员，且仅限 Download 子目录。'
    }

    $catalog += New-Finding -Id 'WindowsUpdate' -NameZh 'Windows Update 下载残留' `
        -Description 'SoftwareDistribution\Download' `
        -Paths @($wuDownload) -Bytes $wuBytes -NeedsAdmin:$true `
        -Present:$wuPresent -Risk 'medium' -Note $wuNote `
        -CleanAction ({
            if (-not $script:IsAdmin) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = '需要管理员权限' }
            }
            # Prefer stopping wuauserv briefly if possible; fall back to best-effort delete.
            $stopped = $false
            try {
                $svc = Get-Service -Name wuauserv -ErrorAction Stop
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name wuauserv -Force -ErrorAction Stop
                    $stopped = $true
                }
            }
            catch { }

            $result = Clear-DirectoryContents -Path $wuDownload

            if ($stopped) {
                try { Start-Service -Name wuauserv -ErrorAction SilentlyContinue } catch { }
            }
            $result
        }.GetNewClosure())

    # --- BrowserCache (cache dirs only; never cookies/login data) ----------
    $browserPaths = @()
    $chromeCache = @(
        (Join-Path $script:LocalAppData 'Google\Chrome\User Data\Default\Cache'),
        (Join-Path $script:LocalAppData 'Google\Chrome\User Data\Default\Code Cache'),
        (Join-Path $script:LocalAppData 'Google\Chrome\User Data\Default\GPUCache')
    )
    $edgeCache = @(
        (Join-Path $script:LocalAppData 'Microsoft\Edge\User Data\Default\Cache'),
        (Join-Path $script:LocalAppData 'Microsoft\Edge\User Data\Default\Code Cache'),
        (Join-Path $script:LocalAppData 'Microsoft\Edge\User Data\Default\GPUCache')
    )
    $firefoxRoots = @()
    $ffProfiles = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $ffProfiles) {
        Get-ChildItem -LiteralPath $ffProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $firefoxRoots += (Join-Path $_.FullName 'cache2')
            $firefoxRoots += (Join-Path $_.FullName 'startupCache')
        }
    }
    $browserPaths = @($chromeCache + $edgeCache + $firefoxRoots | Where-Object { Test-Path -LiteralPath $_ })
    $browserBytes = [long]0
    foreach ($p in $browserPaths) { $browserBytes += Get-DirectorySizeBytes -Path $p }

    $catalog += New-Finding -Id 'BrowserCache' -NameZh '浏览器缓存' `
        -Description 'Chrome / Edge / Firefox 缓存目录（不含 Cookie / 登录数据）' `
        -Paths $browserPaths -Bytes $browserBytes -NeedsAdmin:$false `
        -Present:($browserPaths.Count -gt 0) -Risk 'low' `
        -Note '若浏览器正在运行，部分文件可能被占用而跳过；不会删除书签、密码或扩展配置。' `
        -CleanAction ({
            $sum = [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0 }
            foreach ($p in $browserPaths) {
                $r = Clear-DirectoryContents -Path $p
                $sum.Deleted += $r.Deleted
                $sum.Failed += $r.Failed
                $sum.FreedApprox += $r.FreedApprox
            }
            $sum
        }.GetNewClosure())

    # --- Windows.old -------------------------------------------------------
    $windowsOld = 'C:\Windows.old'
    try {
        $root = [System.IO.Path]::GetPathRoot($script:WinDir)
        if ($root) { $windowsOld = Join-Path $root 'Windows.old' }
    }
    catch { }

    $woPresent = Test-Path -LiteralPath $windowsOld
    $woReadable = $woPresent -and (Test-PathReadable -Path $windowsOld)
    $woBytes = if ($woReadable) { Get-DirectorySizeBytes -Path $windowsOld } else { [long]0 }
    $woNote = '严重警告：删除 Windows.old 后无法回退到上一版 Windows。默认扫描可见，清理必须额外传入 -IncludeWindowsOld，且通常需要管理员。'
    $allowWindowsOld = [bool]$IncludeWindowsOld

    $catalog += New-Finding -Id 'WindowsOld' -NameZh '旧系统 Windows.old' `
        -Description '上次升级遗留的 Windows.old' `
        -Paths @($windowsOld) -Bytes $woBytes -NeedsAdmin:$true `
        -Present:$woPresent -Risk 'high' -Note $woNote `
        -CleanAction ({
            if (-not $allowWindowsOld) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = '未指定 -IncludeWindowsOld' }
            }
            if (-not $script:IsAdmin) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = '需要管理员权限' }
            }
            if (-not (Test-Path -LiteralPath $windowsOld)) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = '不存在' }
            }
            try {
                $size = Get-DirectorySizeBytes -Path $windowsOld
                Remove-Item -LiteralPath $windowsOld -Recurse -Force -ErrorAction Stop
                return [pscustomobject]@{ Deleted = 1; Failed = 0; FreedApprox = $size }
            }
            catch {
                return [pscustomobject]@{ Deleted = 0; Failed = 1; FreedApprox = [long]0; Skipped = $_.Exception.Message }
            }
        }.GetNewClosure())

    # --- NpmCache ----------------------------------------------------------
    $npmCmd = Get-ToolPath -Name 'npm'
    $npmCachePath = $null
    $npmBytes = [long]0
    $npmPresent = $false
    $npmNote = '未检测到 npm，已跳过。'
    if ($npmCmd) {
        try {
            $npmCachePath = (& npm config get cache 2>$null | Select-Object -Last 1).ToString().Trim()
        }
        catch { }
        if (-not $npmCachePath) {
            $npmCachePath = Join-Path $script:LocalAppData 'npm-cache'
        }
        $npmPresent = Test-Path -LiteralPath $npmCachePath
        if ($npmPresent) {
            $npmBytes = Get-DirectorySizeBytes -Path $npmCachePath
            $npmNote = '仅清理 npm 缓存；不影响全局安装的包列表以外的项目 node_modules。'
        }
        else {
            $npmNote = '已安装 npm，但缓存目录不存在。'
        }
    }

    $catalog += New-Finding -Id 'NpmCache' -NameZh 'npm 缓存' `
        -Description 'npm cache directory' `
        -Paths @($npmCachePath) -Bytes $npmBytes -NeedsAdmin:$false `
        -Present:$npmPresent -Risk 'low' -Note $npmNote `
        -CleanAction ({
            if (-not $npmCmd) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = 'npm 不存在' }
            }
            try {
                & npm cache clean --force 2>&1 | Out-Null
                return [pscustomobject]@{ Deleted = 1; Failed = 0; FreedApprox = $npmBytes }
            }
            catch {
                if ($npmCachePath -and (Test-Path -LiteralPath $npmCachePath)) {
                    return Clear-DirectoryContents -Path $npmCachePath
                }
                return [pscustomobject]@{ Deleted = 0; Failed = 1; FreedApprox = [long]0 }
            }
        }.GetNewClosure())

    # --- PipCache ----------------------------------------------------------
    $pipCmd = Get-ToolPath -Name 'pip'
    if (-not $pipCmd) { $pipCmd = Get-ToolPath -Name 'pip3' }
    $pipCachePath = $null
    $pipBytes = [long]0
    $pipPresent = $false
    $pipNote = '未检测到 pip，已跳过。'
    if ($pipCmd) {
        try {
            $pipCachePath = (& pip cache dir 2>$null | Select-Object -Last 1).ToString().Trim()
        }
        catch { }
        if (-not $pipCachePath) {
            $pipCachePath = Join-Path $script:LocalAppData 'pip\Cache'
        }
        $pipPresent = Test-Path -LiteralPath $pipCachePath
        if ($pipPresent) {
            $pipBytes = Get-DirectorySizeBytes -Path $pipCachePath
            $pipNote = '仅清理 pip 下载缓存；不影响已安装的虚拟环境。'
        }
        else {
            $pipNote = '已安装 pip，但缓存目录不存在。'
        }
    }

    $catalog += New-Finding -Id 'PipCache' -NameZh 'pip 缓存' `
        -Description 'pip cache directory' `
        -Paths @($pipCachePath) -Bytes $pipBytes -NeedsAdmin:$false `
        -Present:$pipPresent -Risk 'low' -Note $pipNote `
        -CleanAction ({
            if (-not $pipCmd) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = 'pip 不存在' }
            }
            try {
                & pip cache purge 2>&1 | Out-Null
                return [pscustomobject]@{ Deleted = 1; Failed = 0; FreedApprox = $pipBytes }
            }
            catch {
                if ($pipCachePath -and (Test-Path -LiteralPath $pipCachePath)) {
                    return Clear-DirectoryContents -Path $pipCachePath
                }
                return [pscustomobject]@{ Deleted = 0; Failed = 1; FreedApprox = [long]0 }
            }
        }.GetNewClosure())

    # --- CargoCache --------------------------------------------------------
    $cargoCmd = Get-ToolPath -Name 'cargo'
    $cargoHome = $env:CARGO_HOME
    if ([string]::IsNullOrWhiteSpace($cargoHome)) {
        $cargoHome = Join-Path $script:UserProfile '.cargo'
    }
    $cargoRegistry = Join-Path $cargoHome 'registry\cache'
    $cargoGitDb = Join-Path $cargoHome 'git\db'
    $cargoPaths = @(@($cargoRegistry, $cargoGitDb) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    $cargoBytes = [long]0
    foreach ($p in $cargoPaths) { $cargoBytes += Get-DirectorySizeBytes -Path $p }
    $cargoPresent = $false
    $cargoNote = '未检测到 cargo，已跳过。'
    if ($cargoCmd) {
        $cargoPresent = $cargoPaths.Count -gt 0
        if ($cargoPresent) {
            $cargoNote = '仅清理 registry/cache 与 git/db；保留 .cargo/bin 与工具链。'
        }
        else {
            $cargoNote = '已安装 cargo，但常见缓存目录不存在。'
        }
    }

    $catalog += New-Finding -Id 'CargoCache' -NameZh 'Cargo 缓存' `
        -Description 'cargo registry/cache + git/db' `
        -Paths $cargoPaths -Bytes $cargoBytes -NeedsAdmin:$false `
        -Present:$cargoPresent -Risk 'low' -Note $cargoNote `
        -CleanAction ({
            if (-not $cargoCmd) {
                return [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0; Skipped = 'cargo 不存在' }
            }
            $sum = [pscustomobject]@{ Deleted = 0; Failed = 0; FreedApprox = [long]0 }
            foreach ($p in $cargoPaths) {
                $r = Clear-DirectoryContents -Path $p
                $sum.Deleted += $r.Deleted
                $sum.Failed += $r.Failed
                $sum.FreedApprox += $r.FreedApprox
            }
            $sum
        }.GetNewClosure())

    return $catalog
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$allCategoryMeta = @(
    @{ Id = 'UserTemp'; NameZh = '用户临时文件'; NeedsAdmin = $false; Risk = 'low' },
    @{ Id = 'WindowsTemp'; NameZh = '系统临时文件'; NeedsAdmin = $true; Risk = 'low' },
    @{ Id = 'RecycleBin'; NameZh = '回收站'; NeedsAdmin = $false; Risk = 'low' },
    @{ Id = 'ThumbnailCache'; NameZh = '缩略图缓存'; NeedsAdmin = $false; Risk = 'low' },
    @{ Id = 'DeliveryOptimization'; NameZh = '传递优化缓存'; NeedsAdmin = $true; Risk = 'low' },
    @{ Id = 'WindowsUpdate'; NameZh = 'Windows Update 下载残留'; NeedsAdmin = $true; Risk = 'medium' },
    @{ Id = 'BrowserCache'; NameZh = '浏览器缓存'; NeedsAdmin = $false; Risk = 'low' },
    @{ Id = 'WindowsOld'; NameZh = '旧系统 Windows.old'; NeedsAdmin = $true; Risk = 'high' },
    @{ Id = 'NpmCache'; NameZh = 'npm 缓存'; NeedsAdmin = $false; Risk = 'low' },
    @{ Id = 'PipCache'; NameZh = 'pip 缓存'; NeedsAdmin = $false; Risk = 'low' },
    @{ Id = 'CargoCache'; NameZh = 'Cargo 缓存'; NeedsAdmin = $false; Risk = 'low' }
)

if ($ListCategories) {
    Write-Zh '支持的清理类别：' Cyan
    foreach ($c in $allCategoryMeta) {
        $admin = if ($c.NeedsAdmin) { ' [需管理员]' } else { '' }
        Write-Host ("  {0,-22} {1}{2}  risk={3}" -f $c.Id, $c.NameZh, $admin, $c.Risk)
    }
    exit 0
}

$doClean = [bool]$Clean
# Default = scan
if (-not $Clean -and -not $Scan) {
    $Scan = $true
}

Write-Zh ''
Write-Zh '=== Windows 垃圾清理工具 (maintenance_app) ===' Cyan
Write-Zh ("模式: {0}" -f $(if ($doClean) { '清理 (Clean)' } else { '扫描 / 演练 (Scan，默认不删除)' })) Cyan
Write-Zh ("当前管理员权限: {0}" -f $(if ($script:IsAdmin) { '是' } else { '否（用户级扫描无需提升）' })) Gray
Write-Zh ''

Write-Zh '正在扫描可回收空间…' Yellow
$findings = @(Get-CategoryCatalog)

# Filter by requested categories
$selectedIds = @()
if ($Categories -and $Categories.Count -gt 0) {
    # Accept -Categories UserTemp,BrowserCache and -Categories UserTemp,BrowserCache as one string.
    $selectedIds = @(
        $Categories |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    $unknown = @($selectedIds | Where-Object { $id = $_; -not ($allCategoryMeta | Where-Object { $_.Id -eq $id }) })
    if ($unknown.Count -gt 0) {
        Write-Zh ("未知类别: {0}" -f ($unknown -join ', ')) Red
        Write-Zh '使用 -ListCategories 查看可用 id。' Yellow
        exit 2
    }
    $findings = @($findings | Where-Object { $selectedIds -contains $_.Id })
}

# Present summary table
Write-Zh ''
Write-Zh ('{0,-22} {1,-18} {2,12} {3,-8} {4}' -f '类别ID', '名称', '可回收', '权限', '状态') DarkGray
Write-Zh ('-' * 78) DarkGray

$totalBytes = [long]0
$reportItems = @()

foreach ($f in $findings) {
    $status = if (-not $f.Present) {
        '未发现'
    }
    elseif ($f.Bytes -le 0 -and $f.Id -ne 'RecycleBin') {
        '空 / 不可读'
    }
    else {
        '可清理'
    }

    if ($f.Id -eq 'WindowsOld' -and $f.Present) {
        $status = '需额外确认'
    }

    $adminMark = if ($f.NeedsAdmin) { '管理员' } else { '用户' }
    $sizeText = Format-ByteSize -Bytes $f.Bytes
    Write-Host ('{0,-22} {1,-18} {2,12} {3,-8} {4}' -f $f.Id, $f.NameZh, $sizeText, $adminMark, $status)
    if ($f.Note) {
        Write-Zh ("    说明: {0}" -f $f.Note) DarkGray
    }
    if ($f.Paths.Count -gt 0) {
        foreach ($p in ($f.Paths | Select-Object -First 3)) {
            Write-Zh ("    路径: {0}" -f $p) DarkGray
        }
        if ($f.Paths.Count -gt 3) {
            Write-Zh ("    …另有 {0} 个路径" -f ($f.Paths.Count - 3)) DarkGray
        }
    }

    if ($f.Present) {
        $totalBytes += $f.Bytes
    }

    $reportItems += [pscustomobject]@{
        id          = $f.Id
        name_zh     = $f.NameZh
        description = $f.Description
        bytes       = $f.Bytes
        size_human  = $sizeText
        needs_admin = $f.NeedsAdmin
        present     = $f.Present
        risk        = $f.Risk
        note        = $f.Note
        paths       = $f.Paths
        status      = $status
    }
}

Write-Zh ('-' * 78) DarkGray
Write-Zh ("合计可回收（估算）: {0}" -f (Format-ByteSize -Bytes $totalBytes)) Green
Write-Zh ''

# Persist JSON report
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolRoot = Split-Path -Parent $scriptDir
$reportsDir = Join-Path $toolRoot 'runtime\reports'
$logsDir = Join-Path $toolRoot 'runtime\logs'
if (-not (Test-Path -LiteralPath $reportsDir)) {
    New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportObj = [pscustomobject]@{
    generated_at   = (Get-Date).ToString('o')
    mode           = $(if ($doClean) { 'clean' } else { 'scan' })
    is_admin       = $script:IsAdmin
    total_bytes    = $totalBytes
    total_human    = (Format-ByteSize -Bytes $totalBytes)
    categories     = $reportItems
    selected       = $selectedIds
}

if ($Json -or -not $doClean) {
    $latestPath = Join-Path $reportsDir 'latest.json'
    $stampPath = Join-Path $reportsDir ("scan-{0}.json" -f $timestamp)
    $jsonText = $reportObj | ConvertTo-Json -Depth 6
    $jsonText | Set-Content -LiteralPath $latestPath -Encoding UTF8
    $jsonText | Set-Content -LiteralPath $stampPath -Encoding UTF8
    Write-Zh ("报告已写入: {0}" -f $latestPath) DarkGray
}

if (-not $doClean) {
    Write-Zh '当前为扫描模式，未删除任何文件。' Yellow
    Write-Zh '清理示例:' Gray
    Write-Zh '  powershell -ExecutionPolicy Bypass -File .\windows_junk_cleanup.ps1 -Clean' Gray
    Write-Zh '  powershell -ExecutionPolicy Bypass -File .\windows_junk_cleanup.ps1 -Clean -Categories UserTemp,BrowserCache' Gray
    Write-Zh '  # 系统级类别请用“以管理员身份运行”的 PowerShell 再执行 -Clean' Gray
    exit 0
}

# ---- Clean path ----
$toClean = @($findings | Where-Object {
        $_.Present -and (
            $_.Bytes -gt 0 -or
            $_.Id -eq 'RecycleBin' -or
            ($_.Id -eq 'WindowsOld' -and $IncludeWindowsOld)
        )
    })

# Windows.old gating
$toClean = @($toClean | Where-Object {
        if ($_.Id -eq 'WindowsOld' -and -not $IncludeWindowsOld) {
            Write-Zh '已跳过 Windows.old（高风险）。若确认删除，请追加 -IncludeWindowsOld。' Yellow
            return $false
        }
        return $true
    })

if ($toClean.Count -eq 0) {
    Write-Zh '没有可清理的目标（或所选类别为空 / 被策略跳过）。' Yellow
    exit 0
}

Write-Zh '即将清理以下类别：' Yellow
foreach ($f in $toClean) {
    $need = if ($f.NeedsAdmin -and -not $script:IsAdmin) { ' ※当前无管理员，可能部分跳过' } else { '' }
    Write-Host ("  - {0} ({1})  {2}{3}" -f $f.Id, $f.NameZh, (Format-ByteSize -Bytes $f.Bytes), $need)
}

if ($toClean | Where-Object { $_.Id -eq 'WindowsOld' }) {
    Write-Zh ''
    Write-Zh '!!! 警告: 将删除 Windows.old，升级回退将不可用 !!!' Red
}

if (-not $Yes) {
    Write-Zh ''
    Write-Zh '请输入 YES 确认删除（其他输入取消）:' Magenta
    $answer = Read-Host
    if ($answer -ne 'YES') {
        Write-Zh '已取消，未删除任何文件。' Yellow
        exit 0
    }
}

$cleanResults = @()
$freedTotal = [long]0

foreach ($f in $toClean) {
    Write-Zh ("正在清理: {0} …" -f $f.NameZh) Cyan
    try {
        if ($null -eq $f.CleanAction) {
            Write-Zh '  无清理动作，跳过。' DarkGray
            continue
        }
        $result = & $f.CleanAction
        $freed = [long]0
        if ($result -and ($result.PSObject.Properties.Name -contains 'FreedApprox')) {
            $freed = [long]$result.FreedApprox
        }
        $freedTotal += $freed
        $skip = ''
        if ($result -and ($result.PSObject.Properties.Name -contains 'Skipped')) {
            $skip = [string]$result.Skipped
        }
        if ($skip) {
            Write-Zh ("  跳过: {0}" -f $skip) Yellow
        }
        else {
            Write-Zh ("  完成，约释放 {0}（删除项 {1}，失败 {2}）" -f `
                (Format-ByteSize -Bytes $freed), $result.Deleted, $result.Failed) Green
        }
        $cleanResults += [pscustomobject]@{
            id           = $f.Id
            freed_bytes  = $freed
            deleted      = $result.Deleted
            failed       = $result.Failed
            skipped      = $skip
        }
    }
    catch {
        Write-Zh ("  失败: {0}" -f $_.Exception.Message) Red
        $cleanResults += [pscustomobject]@{
            id           = $f.Id
            freed_bytes  = 0
            deleted      = 0
            failed       = 1
            skipped      = $_.Exception.Message
        }
    }
}

Write-Zh ''
Write-Zh ("清理结束，约释放 {0}" -f (Format-ByteSize -Bytes $freedTotal)) Green

$cleanReport = [pscustomobject]@{
    generated_at = (Get-Date).ToString('o')
    mode         = 'clean'
    is_admin     = $script:IsAdmin
    freed_bytes  = $freedTotal
    freed_human  = (Format-ByteSize -Bytes $freedTotal)
    results      = $cleanResults
    scan         = $reportObj
}
$cleanLatest = Join-Path $reportsDir 'latest.json'
$cleanStamp = Join-Path $reportsDir ("clean-{0}.json" -f $timestamp)
$cleanJson = $cleanReport | ConvertTo-Json -Depth 8
$cleanJson | Set-Content -LiteralPath $cleanLatest -Encoding UTF8
$cleanJson | Set-Content -LiteralPath $cleanStamp -Encoding UTF8
Write-Zh ("报告已写入: {0}" -f $cleanLatest) DarkGray

exit 0
