@echo off
chcp 65001 >nul
title 每日经济早报 - 手机版服务器
cd /d "%~dp0"

echo ==============================================
echo   正在启动「每日经济早报」手机版服务器...
echo ==============================================

where node >nul 2>nul
if %errorlevel%==0 (
  node server.js
  goto :eof
)

where python >nul 2>nul
if %errorlevel%==0 (
  python -m http.server 8000 --bind 0.0.0.0
  goto :eof
)

where py >nul 2>nul
if %errorlevel%==0 (
  py -m http.server 8000 --bind 0.0.0.0
  goto :eof
)

set "NODE_BUNDLED=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
if exist "%NODE_BUNDLED%" (
  "%NODE_BUNDLED%" server.js
  goto :eof
)

echo [ERROR] 未找到 Node.js 或 Python，请先安装其一（https://nodejs.org）。
pause