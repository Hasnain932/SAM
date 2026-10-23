@echo off
rem One command to build, stamp a new version and deploy:  .\deploy.bat
rem (stamp.ps1 must sit next to this file)
rem NOTE: no --wasm here on purpose. The wasm build does not start reliably on iPhone Safari.
call flutter build web --release --pwa-strategy=none --no-web-resources-cdn
if errorlevel 1 (
  echo Build failed, not deploying.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stamp.ps1"
if errorlevel 1 (
  echo Version stamp failed, not deploying.
  exit /b 1
)
call firebase deploy
