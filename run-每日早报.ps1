param([switch]$Force)

# ============================================================
#  每日经济早报 · codex exec 生成脚本（v2）
#  供 Windows「任务计划程序」每天 8:30 / 登录时调用
#  变更：① codex exec 加 40 分钟超时，防止网络重连无限挂起
#        ② 报告未落盘时自动从 logs\最近一次-汇报.txt 自愈恢复
#        ③ 只有确认今日报告真实生成后才提交推送，不再“假成功”
#  生成后自动 git 提交并推送到 GitHub（GitHub Pages 公网站点）
# ============================================================
$ErrorActionPreference = "Continue"

$Project    = "C:\Users\jzz20\Desktop\经济早报手机app"
$CodexCli   = ""
$PromptFile = Join-Path $Project "automation\exec-提示词.txt"
$LogDir     = Join-Path $Project "logs"
$LogFile    = Join-Path $LogDir "运行日志.log"
$LastMsg    = Join-Path $LogDir "最近一次-汇报.txt"
$OutputFile = Join-Path $LogDir "codex-运行输出.log"
$TimeoutSec = 2400   # codex exec 超时上限（秒）= 40 分钟；正常约 5 分钟

# 确保 codex 能找到配置与登录信息
if (-not $env:CODEX_HOME) { $env:CODEX_HOME = Join-Path $env:USERPROFILE ".codex" }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location -LiteralPath $Project

function Log([string]$msg) {
  $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

# 防重复：当天早报已生成则跳过（避免“8:30 + 登录补跑”等多次触发重复生成；手动加 -Force 可强制重跑）
$today = Get-Date -Format "yyyy-MM-dd"
$todayReport = Join-Path $Project ("data\reports\" + $today + ".json")
$todayMd    = Join-Path $Project ("data\每日经济早报-" + $today + ".md")

# 若 reports\$today.json 存在但不是今天的（自愈/误恢复的旧内容），删掉后重新生成，避免一直“跳过”
if (Test-Path -LiteralPath $todayReport) {
  $stale = $true
  try {
    $chk = Get-Content -LiteralPath $todayReport -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($chk.meta.date -eq $today) { $stale = $false }
  } catch {}
  if ($stale) {
    Log "[清理] reports\$today.json 日期不是今天，删除旧文件后重新生成"
    Remove-Item -LiteralPath $todayReport,$todayMd -Force -ErrorAction SilentlyContinue
  }
}

if ((Test-Path -LiteralPath $todayReport) -and (-not $Force)) {
  Log "[跳过] 今日($today)早报已生成，跳过本次运行（如需强制重跑请加 -Force）"
  exit 0
}

# 自动定位 codex CLI：优先 Codex 桌面端自带的最新版（路径 hash 会随更新变化）
$binRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
if (Test-Path -LiteralPath $binRoot) {
  $found = Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $exe = Join-Path $_.FullName "codex.exe"
    if (Test-Path -LiteralPath $exe) { Get-Item -LiteralPath $exe }
  }
  if ($found) { $CodexCli = ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
}
if (-not (Test-Path -LiteralPath $CodexCli)) {
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { $CodexCli = $cmd.Source }
  else {
    Log "[错误] 找不到 codex 可执行文件（已尝试 Codex bin 目录与 PATH）"
    exit 1
  }
}
if (-not (Test-Path -LiteralPath $PromptFile)) {
  Log "[错误] 找不到提示词文件: $PromptFile"
  exit 1
}

# 检查本地模型代理（cc-switch）是否在线：127.0.0.1:15721
try {
  $probe = New-Object System.Net.Sockets.TcpClient
  $iar = $probe.BeginConnect("127.0.0.1", 15721, $null, $null)
  if (-not $iar.AsyncWaitHandle.WaitOne(3000)) {
    Log "[错误] 本地模型代理(cc-switch, 127.0.0.1:15721)未运行，无法生成早报。请先启动 cc-switch 并开启本地代理。"
    $probe.Close()
    exit 2
  }
  $probe.Close()
} catch {
  Log "[错误] 检查本地模型代理失败: $($_.Exception.Message)"
  exit 2
}

# 显式按 UTF-8 读取提示词
$Prompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)

# ---- 运行 codex exec（带超时，stdin 传入提示词，输出落盘） ----
Log "[开始] 运行 codex exec 生成每日经济早报..."
$promptTmp = Join-Path $env:TEMP ("codex-prompt-" + [guid]::NewGuid().ToString("N") + ".txt")
$outTmp    = Join-Path $env:TEMP ("codex-out-"   + [guid]::NewGuid().ToString("N") + ".txt")
$errTmp    = Join-Path $env:TEMP ("codex-err-"   + [guid]::NewGuid().ToString("N") + ".txt")
[System.IO.File]::WriteAllText($promptTmp, $Prompt, (New-Object System.Text.UTF8Encoding($false)))

# - 表示从 stdin 读取提示词；-o 把最终汇报写入 最近一次-汇报.txt
$argStr = 'exec -C "' + $Project + '" --skip-git-repo-check -s workspace-write --color never -o "' + $LastMsg + '" -'
$proc = $null
try {
  $proc = Start-Process -FilePath $CodexCli -ArgumentList $argStr -PassThru -WindowStyle Hidden `
          -RedirectStandardInput $promptTmp -RedirectStandardOutput $outTmp -RedirectStandardError $errTmp
} catch {
  Log "[错误] 启动 codex exec 失败: $($_.Exception.Message)"
  Remove-Item -LiteralPath $promptTmp,$outTmp,$errTmp -Force -ErrorAction SilentlyContinue
  exit 3
}

$finished = $proc.WaitForExit($TimeoutSec * 1000)
if (-not $finished) {
  try { $proc.Kill() } catch {}
  Log "[错误] codex exec 超过 $TimeoutSec 秒未结束，已强制终止（疑似 cc-switch/DeepSeek 网络问题）"
  $code = 124
} else {
  # 修复：WaitForExit(超时) 后 ExitCode 可能仍为 null，需再 WaitForExit() 刷新，否则会漏掉提交推送
  try { $proc.WaitForExit() } catch {}
  $code = $proc.ExitCode
  if ($null -eq $code) { $code = 0 }
}

# 把本次输出追加到 codex-运行输出.log（保留原有日志习惯）
foreach ($f in @($outTmp, $errTmp)) {
  if (Test-Path -LiteralPath $f) {
    try { $raw = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) } catch { $raw = "" }
    if ($raw) { [System.IO.File]::AppendAllText($OutputFile, $raw, (New-Object System.Text.UTF8Encoding($false))) }
  }
}
Remove-Item -LiteralPath $promptTmp,$outTmp,$errTmp -Force -ErrorAction SilentlyContinue

# ---- 自愈：codex 因只读沙箱/网络等原因未落盘时，从最近一次汇报恢复 ----
if (-not (Test-Path -LiteralPath $todayReport)) {
  Log "[自愈] 今日报告文件不存在（codex 退出码 $code），尝试从 logs\最近一次-汇报.txt 恢复..."
  & (Join-Path $Project "automation\extract-report-from-log.ps1") -Project $Project -Date $today *>> $OutputFile
  if (Test-Path -LiteralPath $todayReport) {
    Log "[自愈] 恢复成功：latest.json / reports\$today.json / history.json / md"
    # 校验恢复内容确实是今天的（防止把旧日期内容当作今日推送）
    try {
      $meta = Get-Content -LiteralPath $todayReport -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($meta.meta.date -ne $today) {
        Log "[错误] 自愈恢复的文件 meta.date=$($meta.meta.date) 不是 $today，判定失败（不推送旧内容冒充今日）"
        $code = 3
      } else {
        Log "[校验] 自愈恢复的内容日期正确（meta.date=$($meta.meta.date)）"
        $code = 0
      }
    } catch {
      Log "[错误] 自愈恢复的文件解析失败，判定失败"
      $code = 3
    }
  } else {
    Log "[错误] 自愈恢复失败：今日报告仍未生成（请检查网络/代理，或手动生成）"
    if ($code -eq 0) { $code = 3 }
  }
} else {
  # 报告文件存在，但确认内容确实是今天的（防止旧文件误判为成功）
  try {
    $meta = Get-Content -LiteralPath $todayReport -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($meta.meta.date -ne $today) {
      Log "[错误] reports\$today.json 存在但 meta.date=$($meta.meta.date)，视为未生成"
      $code = 3
    } else {
      Log "[校验] reports\$today.json 内容为今日报告（meta.date=$($meta.meta.date)）"
    }
  } catch {
    Log "[错误] reports\$today.json 解析失败，视为未生成"
    $code = 3
  }
}

# ---- 生成成功后，自动同步到 GitHub（部署到 Pages 后保持最新） ----
if ($code -eq 0) {
  Log "[同步] 提交并推送数据到 GitHub..."
  $Git = "C:\Users\jzz20\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe"
  if (-not (Test-Path -LiteralPath $Git)) {
    $gcmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gcmd) { $Git = $gcmd.Source } else { $Git = "" }
  }
  if ($Git -and (Test-Path -LiteralPath (Join-Path $Project ".git"))) {
    $null = & $Git -C $Project add -A 2>&1
    $staged = @(& $Git -C $Project diff --cached --name-only 2>&1)
    $stamp = Get-Date -Format "yyyy-MM-dd"
    if ($staged.Count -gt 0) {
      $null = & $Git -C $Project -c core.quotepath=false commit -m "daily report $stamp" 2>&1
      $remote = & $Git -C $Project remote get-url origin 2>&1
      if ($LASTEXITCODE -eq 0 -and $remote) {
        $pushOk = $false
        for ($attempt = 1; $attempt -le 5; $attempt++) {
          $null = & $Git -C $Project push origin main 2>&1
          if ($LASTEXITCODE -eq 0) { $pushOk = $true; break }
          Log ("[同步] 第 {0}/5 次推送失败（退出码 {1}），30 秒后重试..." -f $attempt, $LASTEXITCODE)
          Start-Sleep -Seconds 30
        }
        if ($pushOk) { Log "[同步] 已提交 $($staged.Count) 个文件并推送成功" }
        else { Log "[同步] 推送失败：请检查网络后手动执行 git push" }
      } else {
        Log "[同步] 尚未配置远程仓库 origin，跳过推送（部署到 GitHub Pages 后会自动启用）"
      }
    } else {
      Log "[同步] 没有需要提交的变更，跳过提交与推送"
    }
  } else {
    Log "[同步] 未找到 git 或 .git，跳过推送"
  }
}

Log ("[结束] 退出码 = {0}" -f $code)
exit $code
