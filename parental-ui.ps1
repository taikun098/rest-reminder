# 机顶盒「该休息了」持续弹窗控制器
# 功能：① 立即开始弹 / ② 设定倒计时到点自动弹 / ③ 弹满 N 分钟后自动停止
#       孩子按返回、换台会被 2 秒内弹回来；点停止或关掉窗口即停
# 依赖：adb（platform-tools），盒子开启网络 adb（5555）

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- 基础参数 ----------
$script:AdbPath = ''
foreach ($p in @("$env:USERPROFILE\platform-tools\adb.exe", "C:\Users\user\platform-tools\adb.exe", "C:\platform-tools\adb.exe")) {
    if (Test-Path -LiteralPath $p) { $script:AdbPath = $p; break }
}
if (-not $script:AdbPath) { $script:AdbPath = 'adb' }

$script:ImgLocal  = Join-Path $PSScriptRoot 'rest.png'
$script:ImgRemote = '/sdcard/rest.png'
$script:Popped    = 0
$script:Running   = $false
$script:Dev       = ''
$script:CdLeft    = 0
$script:BlkLeft   = 0

$script:PopCmd = 'f=$(dumpsys window | /system/xbin/busybox grep mCurrentFocus); case "$f" in *PhotoViewActivity*) echo ALREADY;; *) am start -n com.xiaobaifile.tv/com.xiaobaifile.tv.view.PhotoViewActivity -d file:///sdcard/rest.png -t image/png >/dev/null 2>&1; sleep 1; echo POP;; esac'

# ---------- 界面 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = '机顶盒 · 该休息了（弹窗控制器）'
$form.Size = New-Object System.Drawing.Size(700, 640)
$form.StartPosition = 'CenterScreen'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = '设备地址'
$lblIp.AutoSize = $true
$lblIp.Location = New-Object System.Drawing.Point(22, 22)
$form.Controls.Add($lblIp)

$txtIp = New-Object System.Windows.Forms.TextBox
$txtIp.Text = '192.168.0.190:5555'
$txtIp.Location = New-Object System.Drawing.Point(100, 18)
$txtIp.Size = New-Object System.Drawing.Size(190, 30)
$form.Controls.Add($txtIp)

$lblInt = New-Object System.Windows.Forms.Label
$lblInt.Text = '间隔(秒)'
$lblInt.AutoSize = $true
$lblInt.Location = New-Object System.Drawing.Point(310, 22)
$form.Controls.Add($lblInt)

$numInt = New-Object System.Windows.Forms.NumericUpDown
$numInt.Minimum = 1
$numInt.Maximum = 60
$numInt.Value = 2
$numInt.Location = New-Object System.Drawing.Point(380, 18)
$numInt.Size = New-Object System.Drawing.Size(60, 30)
$form.Controls.Add($numInt)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = '开始弹窗'
$btnStart.Location = New-Object System.Drawing.Point(455, 14)
$btnStart.Size = New-Object System.Drawing.Size(215, 38)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 90)
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatStyle = 'Flat'
$form.Controls.Add($btnStart)

$btnOnce = New-Object System.Windows.Forms.Button
$btnOnce.Text = '弹一次试试'
$btnOnce.Location = New-Object System.Drawing.Point(22, 60)
$btnOnce.Size = New-Object System.Drawing.Size(120, 32)
$form.Controls.Add($btnOnce)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '未开始'
$lblStatus.Location = New-Object System.Drawing.Point(155, 65)
$lblStatus.Size = New-Object System.Drawing.Size(515, 26)
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblStatus)

# ---------- 定时启动区 ----------
$grpTimer = New-Object System.Windows.Forms.GroupBox
$grpTimer.Text = '① 定时启动：选一个时长，到点自动开始弹'
$grpTimer.Location = New-Object System.Drawing.Point(22, 100)
$grpTimer.Size = New-Object System.Drawing.Size(648, 102)
$form.Controls.Add($grpTimer)

$script:RadioMinutes = @{}
$presets = @(15, 30, 45, 60)
for ($i = 0; $i -lt $presets.Count; $i++) {
    $m = $presets[$i]
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = "$m 分钟"
    $rb.AutoSize = $true
    $rb.Location = New-Object System.Drawing.Point((14 + $i * 92), 26)
    $script:RadioMinutes[$m] = $rb
    $grpTimer.Controls.Add($rb)
}

$rbCustom = New-Object System.Windows.Forms.RadioButton
$rbCustom.Text = '自定义'
$rbCustom.AutoSize = $true
$rbCustom.Location = New-Object System.Drawing.Point(390, 26)
$grpTimer.Controls.Add($rbCustom)

$numCustom = New-Object System.Windows.Forms.NumericUpDown
$numCustom.Minimum = 1
$numCustom.Maximum = 600
$numCustom.Value = 90
$numCustom.Location = New-Object System.Drawing.Point(462, 24)
$numCustom.Size = New-Object System.Drawing.Size(70, 30)
$numCustom.Enabled = $false
$grpTimer.Controls.Add($numCustom)

$lblMin = New-Object System.Windows.Forms.Label
$lblMin.Text = '分钟'
$lblMin.AutoSize = $true
$lblMin.Location = New-Object System.Drawing.Point(538, 28)
$grpTimer.Controls.Add($lblMin)

$btnCd = New-Object System.Windows.Forms.Button
$btnCd.Text = '倒计时开始'
$btnCd.Location = New-Object System.Drawing.Point(14, 60)
$btnCd.Size = New-Object System.Drawing.Size(140, 30)
$grpTimer.Controls.Add($btnCd)

$lblCd = New-Object System.Windows.Forms.Label
$lblCd.Text = '未设置倒计时'
$lblCd.Location = New-Object System.Drawing.Point(170, 66)
$lblCd.Size = New-Object System.Drawing.Size(460, 26)
$lblCd.ForeColor = [System.Drawing.Color]::DimGray
$grpTimer.Controls.Add($lblCd)

# ---------- 自动停止区 ----------
$grpBlock = New-Object System.Windows.Forms.GroupBox
$grpBlock.Text = '② 自动停止：弹多久后自己收'
$grpBlock.Location = New-Object System.Drawing.Point(22, 210)
$grpBlock.Size = New-Object System.Drawing.Size(648, 102)
$form.Controls.Add($grpBlock)

$script:RadioBlock = @{}
$bp = @(1, 2, 3)
for ($i = 0; $i -lt $bp.Count; $i++) {
    $m = $bp[$i]
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = "$m 分钟"
    $rb.AutoSize = $true
    $rb.Location = New-Object System.Drawing.Point((14 + $i * 92), 26)
    if ($m -eq 2) { $rb.Checked = $true }
    $script:RadioBlock[$m] = $rb
    $grpBlock.Controls.Add($rb)
}

$rbBlockFree = New-Object System.Windows.Forms.RadioButton
$rbBlockFree.Text = '不限(手动停)'
$rbBlockFree.AutoSize = $true
$rbBlockFree.Location = New-Object System.Drawing.Point(296, 26)
$grpBlock.Controls.Add($rbBlockFree)

$rbBlockCustom = New-Object System.Windows.Forms.RadioButton
$rbBlockCustom.Text = '自定义'
$rbBlockCustom.AutoSize = $true
$rbBlockCustom.Location = New-Object System.Drawing.Point(410, 26)
$grpBlock.Controls.Add($rbBlockCustom)

$numBlock = New-Object System.Windows.Forms.NumericUpDown
$numBlock.Minimum = 1
$numBlock.Maximum = 120
$numBlock.Value = 5
$numBlock.Location = New-Object System.Drawing.Point(482, 24)
$numBlock.Size = New-Object System.Drawing.Size(70, 30)
$numBlock.Enabled = $false
$grpBlock.Controls.Add($numBlock)

$lblBlockUnit = New-Object System.Windows.Forms.Label
$lblBlockUnit.Text = '分钟'
$lblBlockUnit.AutoSize = $true
$lblBlockUnit.Location = New-Object System.Drawing.Point(558, 28)
$grpBlock.Controls.Add($lblBlockUnit)

$lblBlk = New-Object System.Windows.Forms.Label
$lblBlk.Text = '自动停止：未启用'
$lblBlk.Location = New-Object System.Drawing.Point(14, 62)
$lblBlk.Size = New-Object System.Drawing.Size(620, 26)
$lblBlk.ForeColor = [System.Drawing.Color]::DimGray
$grpBlock.Controls.Add($lblBlk)

# ---------- 日志 ----------
$lbLog = New-Object System.Windows.Forms.ListBox
$lbLog.Location = New-Object System.Drawing.Point(22, 324)
$lbLog.Size = New-Object System.Drawing.Size(648, 220)
$lbLog.HorizontalScrollbar = $true
$form.Controls.Add($lbLog)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000

$cdTimer = New-Object System.Windows.Forms.Timer
$cdTimer.Interval = 1000

$blkTimer = New-Object System.Windows.Forms.Timer
$blkTimer.Interval = 1000

# ---------- 逻辑 ----------
function Write-Log([string]$msg) {
    $ts = Get-Date -Format 'HH:mm:ss'
    [void]$lbLog.Items.Add("[$ts] $msg")
    while ($lbLog.Items.Count -gt 300) { $lbLog.Items.RemoveAt(0) }
    $lbLog.TopIndex = [Math]::Max(0, $lbLog.Items.Count - 1)
}

function Set-Status([string]$text, [string]$color) {
    $lblStatus.Text = $text
    $lblStatus.ForeColor = [System.Drawing.Color]::FromName($color)
}

function Format-Left([int]$sec) {
    $h = [Math]::Floor($sec / 3600)
    $m = [Math]::Floor(($sec % 3600) / 60)
    $s = $sec % 60
    if ($h -gt 0) { return ('{0}:{1:00}:{2:00}' -f $h, $m, $s) }
    return ('{0:00}:{1:00}' -f $m, $s)
}

function Initialize-Device([string]$dev) {
    & $script:AdbPath connect $dev 2>&1 | Out-Null
    $probe = (& $script:AdbPath -s $dev shell 'echo READY' 2>&1) -join ' '
    if ($probe -notmatch 'READY') { throw "连不上设备 $dev，请检查网络和盒子是否开机" }
    $has = (& $script:AdbPath -s $dev shell "ls $($script:ImgRemote) 2>/dev/null") -join ' '
    if ($has -notmatch 'rest\.png') {
        if (-not (Test-Path -LiteralPath $script:ImgLocal)) { throw "找不到本地提示图：$($script:ImgLocal)" }
        & $script:AdbPath -s $dev push $script:ImgLocal $script:ImgRemote 2>&1 | Out-Null
        Write-Log '已把提示图推送到盒子'
    }
}

function Invoke-Pop([string]$dev) {
    $out = (& $script:AdbPath -s $dev shell $script:PopCmd 2>&1) -join ' '
    if ($out -match 'POP') {
        $script:Popped++
        Write-Log "已弹出提示（第 $($script:Popped) 次）"
    }
    elseif ($out -match 'ALREADY') {
        # 还盖着，不用重复弹
    }
    else {
        Write-Log ('adb 返回异常：' + ($out -replace '\s+', ' ').Trim())
    }
}

function Get-BlockMinutes {
    if ($rbBlockFree.Checked) { return 0 }
    if ($rbBlockCustom.Checked) { return [int]$numBlock.Value }
    foreach ($m in $script:RadioBlock.Keys) {
        if ($script:RadioBlock[$m].Checked) { return [int]$m }
    }
    return 0
}

function Update-BlkLabel {
    if ($script:BlkLeft -gt 0) {
        $lblBlk.Text = "自动停止中 · 剩余 $(Format-Left $script:BlkLeft) 后自动收"
        $lblBlk.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}

function Start-Blocking {
    Cancel-Countdown
    $script:Dev = $txtIp.Text.Trim()
    try {
        Initialize-Device $script:Dev
    }
    catch {
        Write-Log $_.Exception.Message
        Set-Status '启动失败' 'Firebrick'
        return
    }
    $script:Popped = 0
    $script:Running = $true
    $timer.Interval = [int]$numInt.Value * 1000
    $timer.Start()
    $txtIp.Enabled = $false
    $numInt.Enabled = $false
    $btnStart.Text = '停止'
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(170, 60, 60)
    Set-Status ("运行中 · 每 $($numInt.Value) 秒检查一次 · 关窗即停") 'SeaGreen'
    Write-Log "开始弹窗，设备 $($script:Dev)，间隔 $($numInt.Value) 秒"
    Invoke-Pop $script:Dev

    $bm = Get-BlockMinutes
    if ($bm -gt 0) {
        $script:BlkLeft = $bm * 60
        $blkTimer.Start()
        Update-BlkLabel
        Write-Log "弹满 $bm 分钟后自动停止"
    }
    else {
        $lblBlk.Text = '自动停止：未启用（靠你手动停）'
        $lblBlk.ForeColor = [System.Drawing.Color]::DimGray
    }
}

function Stop-Blocking {
    $timer.Stop()
    $blkTimer.Stop()
    $script:BlkLeft = 0
    $script:Running = $false
    $txtIp.Enabled = $true
    $numInt.Enabled = $true
    $btnStart.Text = '开始弹窗'
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 90)
    $lblBlk.Text = '自动停止：未启用'
    $lblBlk.ForeColor = [System.Drawing.Color]::DimGray
    Set-Status ("已停止 · 本轮共弹 $($script:Popped) 次") 'DimGray'
    Write-Log '已停止弹窗'
    if ($script:Dev -ne '') {
        & $script:AdbPath -s $script:Dev shell 'input keyevent 3' 2>&1 | Out-Null
        Write-Log '已让盒子回到桌面'
    }
}

function Get-SelectedMinutes {
    if ($rbCustom.Checked) { return [int]$numCustom.Value }
    foreach ($m in $script:RadioMinutes.Keys) {
        if ($script:RadioMinutes[$m].Checked) { return [int]$m }
    }
    return 0
}

function Update-CdLabel {
    if ($script:CdLeft -gt 0) {
        $lblCd.Text = "倒计时中 · 剩余 $(Format-Left $script:CdLeft) · 到点自动开始弹"
        $lblCd.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}

function Start-Countdown {
    $mins = Get-SelectedMinutes
    if ($mins -le 0) {
        Write-Log '请先在上面选一个时长（15/30/45/60 分钟，或自定义）'
        return
    }
    if ($script:Running) {
        Write-Log '正在弹窗中，先停止再设定时'
        return
    }
    $script:CdLeft = $mins * 60
    $cdTimer.Start()
    $btnCd.Text = '取消倒计时'
    Update-CdLabel
    Write-Log "已设定倒计时：$mins 分钟后自动开始弹窗"
}

function Cancel-Countdown {
    if ($script:CdLeft -gt 0 -or $cdTimer.Enabled) {
        $cdTimer.Stop()
        $script:CdLeft = 0
        $btnCd.Text = '倒计时开始'
        $lblCd.Text = '倒计时已取消'
        $lblCd.ForeColor = [System.Drawing.Color]::DimGray
    }
}

# ---------- 事件 ----------
$timer.Add_Tick({
    if (-not $script:Running) { return }
    try { Invoke-Pop $script:Dev }
    catch { Write-Log ('错误：' + $_.Exception.Message) }
})

$cdTimer.Add_Tick({
    $script:CdLeft--
    if ($script:CdLeft -gt 0) {
        Update-CdLabel
        return
    }
    $cdTimer.Stop()
    $btnCd.Text = '倒计时开始'
    $lblCd.Text = '时间到，开始弹窗'
    $lblCd.ForeColor = [System.Drawing.Color]::SeaGreen
    Write-Log '倒计时结束，自动开始弹窗'
    Start-Blocking
})

$blkTimer.Add_Tick({
    $script:BlkLeft--
    if ($script:BlkLeft -gt 0) {
        Update-BlkLabel
        return
    }
    $blkTimer.Stop()
    Write-Log '弹窗时长已到，自动停止'
    Stop-Blocking
})

$btnStart.Add_Click({
    if ($script:Running) { Stop-Blocking } else { Start-Blocking }
})

$btnCd.Add_Click({
    if ($cdTimer.Enabled) { Cancel-Countdown; Write-Log '已取消倒计时' } else { Start-Countdown }
})

$btnOnce.Add_Click({
    $dev = $txtIp.Text.Trim()
    try {
        Initialize-Device $dev
        Invoke-Pop $dev
    }
    catch { Write-Log $_.Exception.Message }
})

$rbCustom.Add_CheckedChanged({
    $numCustom.Enabled = $rbCustom.Checked
})

$rbBlockCustom.Add_CheckedChanged({
    $numBlock.Enabled = $rbBlockCustom.Checked
})

$form.Add_FormClosing({
    $cdTimer.Stop()
    $blkTimer.Stop()
    if ($script:Running) { Stop-Blocking }
})

Write-Log '就绪：可立即开始，也可先设倒计时；弹多久后自动收可自选'
Write-Log '关闭本窗口即停止弹窗'
[void]$form.ShowDialog()
