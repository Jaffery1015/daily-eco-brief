# ============================================================
#  每日经济早报 · codex exec 生成脚本
#  供 Windows「任务计划程序」每天早上 8:30 调用
#  日志与最近一次汇报保存在 logs\ 目录
# ============================================================
$ErrorActionPreference = "Continue"

$Project    = "C:\Users\jzz20\Desktop\经济早报手机app"
$CodexCli   = "C:\Users\jzz20\AppData\Local\OpenAI\Codex\bin\110b3d66a02d864e\codex.exe"
$PromptFile = Join-Path $Project "automation\exec-提示词.txt"
$LogDir     = Join-Path $Project "logs"
$LogFile    = Join-Path $LogDir "运行日志.log"
$LastMsg    = Join-Path $LogDir "最近一次-汇报.txt"
$OutputFile = Join-Path $LogDir "codex-运行输出.log"

# 确保 codex 能找到配置与登录信息
if (-not $env:CODEX_HOME) { $env:CODEX_HOME = Join-Path $env:USERPROFILE ".codex" }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location -LiteralPath $Project

function Log([string]$msg) {
  $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path -LiteralPath $CodexCli)) {
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd) { $CodexCli = $cmd.Source }
  else {
    Log "[错误] 找不到 codex 可执行文件: $CodexCli"
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
Log "[开始] 运行 codex exec 生成每日经济早报..."

# 无人值守运行：-C 项目目录、跳过 git 检查、workspace-write 沙箱、不弹交互
& $CodexCli exec -C $Project --skip-git-repo-check -s workspace-write --color never -o $LastMsg $Prompt *>> $OutputFile
$code = $LASTEXITCODE
Log ("[结束] 退出码 = {0}" -f $code)
exit $code