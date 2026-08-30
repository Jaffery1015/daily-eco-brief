param(
  [string]$Project   = "C:\Users\jzz20\Desktop\经济早报手机app",
  [string]$ReportLog = "",
  [string]$Date      = ""
)
# ============================================================
#  extract-report-from-log.ps1
#  从 logs\最近一次-汇报.txt 中按固定分节提取并恢复 4 个报告文件
#  （用于 codex exec 因只读沙箱等原因未能落盘时的自愈/恢复）
#  写入前会把 JSON 规范化成 App(data/schema.json) 需要的字段形状
# ============================================================
$ErrorActionPreference = "Stop"
if (-not $Date)      { $Date      = Get-Date -Format "yyyy-MM-dd" }
if (-not $ReportLog) { $ReportLog = Join-Path $Project "logs\最近一次-汇报.txt" }

function Write-Utf8([string]$Path, [string]$Content) {
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

# ---- 规范化：让任意字段形状的报告变成 App 需要的形状 ----
function Normalize-Report($o) {
  $meta = [ordered]@{}
  $meta.title = '每日经济早报'
  $meta.date = $o.meta.date
  $meta.weekday = $o.meta.weekday
  if ($null -ne $o.meta.dataCutoff)      { $meta.dataCutoff = $o.meta.dataCutoff }
  elseif ($null -ne $o.meta.data_cutoff) { $meta.dataCutoff = $o.meta.data_cutoff }
  else { $meta.dataCutoff = '' }
  $meta.editor = 'Codex 经济学助手'
  if ($null -ne $o.meta.updatedAt)       { $meta.updatedAt = $o.meta.updatedAt }
  elseif ($null -ne $o.meta.updated_at)  { $meta.updatedAt = $o.meta.updated_at }
  else { $meta.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
  if ($null -ne $o.meta.isTradingDay) { $meta.isTradingDay = $o.meta.isTradingDay } else { $meta.isTradingDay = $true }

  $keys = @('chinaPolicy','chinaData','globalCentralBanks','assets','industry')
  $focus = [ordered]@{}
  if ($o.focus -is [System.Array]) {
    for ($i=0; $i -lt $keys.Count; $i++) {
      if ($i -lt $o.focus.Count -and $null -ne $o.focus[$i]) { $focus[$keys[$i]] = [string]$o.focus[$i] }
      else { $focus[$keys[$i]] = '' }
    }
  } else {
    foreach ($k in $keys) { $focus[$k] = if ($null -ne $o.focus.$k) { $o.focus.$k } else { '' } }
  }

  $china = [ordered]@{}
  $china.policy     = @($o.china.policy)
  $china.data       = @($o.china.data)
  $china.highlights = @($o.china.highlights)

  $global = [ordered]@{}
  $cb = $null
  if ($null -ne $o.global.centralBanks) { $cb = $o.global.centralBanks }
  elseif ($null -ne $o.global.central_banks) { $cb = $o.global.central_banks }
  $global.centralBanks = @($cb | ForEach-Object {
    if ($_ -is [string]) {
      $m = [regex]::Match($_, '^(.+?)[：:](.*)$')
      if ($m.Success) { [ordered]@{ name = $m.Groups[1].Value; content = $m.Groups[2].Value } }
      else { [ordered]@{ name = ''; content = $_ } }
    } else { [ordered]@{ name = if ($null -ne $_.name) { $_.name } else { '' }; content = if ($null -ne $_.content) { $_.content } else { '' } } }
  })
  $global.bondsFx = if ($null -ne $o.global.bondsFx) { @($o.global.bondsFx) } elseif ($null -ne $o.global.bond_fx) { @($o.global.bond_fx) } else { @() }
  $global.geopolitics = if ($null -ne $o.global.geopolitics) { @($o.global.geopolitics) } elseif ($null -ne $o.global.geopolitics_trade) { @($o.global.geopolitics_trade) } else { @() }

  $schedule = @($o.schedule | ForEach-Object {
    [ordered]@{ time = $_.time; event = $_.event; watch = if ($null -ne $_.watch) { $_.watch } else { $_.highlight } }
  })

  $learning = @($o.learning | ForEach-Object {
    [ordered]@{ concept = if ($null -ne $_.concept) { $_.concept } else { '课堂概念映射' }; question = $_.question; answer = $_.answer }
  })

  $tracker = @()
  $trItems = @($o.tracker)
  if ($trItems.Count -gt 0 -and $null -ne $trItems[0].items) {
    $note = $trItems[0].note
    $first = $true
    foreach ($it in @($trItems[0].items)) {
      $tracker += [ordered]@{ name = $it.name; value = $it.value; freq = if ($null -ne $it.freq) { $it.freq } else { '' }; note = if ($first) { $note } else { '' } }
      $first = $false
    }
  } else {
    $tracker = @($trItems | ForEach-Object {
      [ordered]@{ name = if ($null -ne $_.name) { $_.name } else { '' }; value = if ($null -ne $_.value) { $_.value } else { '' }; freq = if ($null -ne $_.freq) { $_.freq } else { '' }; note = if ($null -ne $_.note) { $_.note } else { '' } }
    })
  }

  return [ordered]@{ meta = $meta; focus = $focus; china = $china; global = $global; assets = $o.assets; schedule = $schedule; learning = $learning; tracker = $tracker }
}

if (-not (Test-Path -LiteralPath $ReportLog)) {
  Write-Output "ERR: 汇报日志不存在: $ReportLog"
  exit 1
}
$text = [System.IO.File]::ReadAllText($ReportLog, [System.Text.Encoding]::UTF8)
$restored = @()
$blank = '(?:[ \t]*\r?\n)*'

$m1 = [regex]::Match($text, ('## 文件 1[^\r\n]*\r?\n' + $blank + '```(?:json)?\r?\n(?<json>.*?)\r?\n```'), [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($m1.Success) {
  $json = $m1.Groups['json'].Value
  try { $o = $json | ConvertFrom-Json } catch { Write-Output "ERR: 文件1 JSON 解析失败: $($_.Exception.Message)"; exit 1 }
  if ($o.meta.date -ne $Date) { Write-Output "WARN: 文件1 中 meta.date=$($o.meta.date) 与目标日期 $Date 不一致，仍按内容写入" }
  $norm = Normalize-Report $o
  $outJson = $norm | ConvertTo-Json -Depth 20
  $latest  = Join-Path $Project "data\latest.json"
  $archive = Join-Path $Project "data\reports\$Date.json"
  Write-Utf8 $latest $outJson;  $restored += $latest
  Write-Utf8 $archive $outJson; $restored += $archive
  Write-Output "OK: 已恢复并规范化 latest.json 与 reports\$Date.json"
} else { Write-Output "ERR: 未找到 文件1 代码块"; exit 1 }

$m2 = [regex]::Match($text, ('## 文件 2[^\r\n]*\r?\n' + $blank + '```(?:json)?\r?\n(?<json>.*?)\r?\n```'), [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($m2.Success) {
  $hjson = $m2.Groups['json'].Value
  try { $h = $hjson | ConvertFrom-Json } catch { Write-Output "ERR: 文件2 JSON 解析失败: $($_.Exception.Message)"; exit 1 }
  $hPath = Join-Path $Project "data\history.json"
  $oldItems = @()
  if (Test-Path -LiteralPath $hPath) {
    try { $old = (Get-Content -LiteralPath $hPath -Raw -Encoding UTF8 | ConvertFrom-Json); $oldItems = @($old.items) } catch {}
  }
  $seen = @{}; $items = @()
  foreach ($it in @($h.items)) { if (-not $seen.ContainsKey($it.date)) { $seen[$it.date] = $true; $items += $it } }
  foreach ($it in $oldItems)   { if (-not $seen.ContainsKey($it.date)) { $seen[$it.date] = $true; $items += $it } }
  $out = @{ items = $items } | ConvertTo-Json -Depth 6
  Write-Utf8 $hPath $out; $restored += $hPath
  Write-Output "OK: 已恢复 history.json（共 $($items.Count) 条）"
} else { Write-Output "ERR: 未找到 文件2 代码块"; exit 1 }

$m3 = [regex]::Match($text, ('## 文件 3[^\r\n]*\r?\n' + $blank + '```(?:markdown|md)?\r?\n(?<md>.*?)\r?\n```'), [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($m3.Success) {
  $mdPath = Join-Path $Project "data\每日经济早报-$Date.md"
  Write-Utf8 $mdPath $m3.Groups['md'].Value; $restored += $mdPath
  Write-Output "OK: 已恢复 每日经济早报-$Date.md"
} else { Write-Output "ERR: 未找到 文件3 代码块"; exit 1 }

Write-Output ("RESTORED: " + ($restored -join " | "))
exit 0
