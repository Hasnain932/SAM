@echo off
rem One command to build, stamp a new version and deploy:  .\deploy.bat
call flutter build web --release --wasm --pwa-strategy=none --no-web-resources-cdn
if errorlevel 1 (
  echo Build failed, not deploying.
  exit /b 1
)
powershell -NoProfile -Command "$f='build\web\sw.js'; (Get-Content $f -Raw) -replace 'sam-[a-zA-Z0-9]+', ('sam-' + (Get-Date -Format yyyyMMddHHmmss)) | Set-Content $f -NoNewline"
if errorlevel 1 (
  echo Version stamp failed, not deploying.
  exit /b 1
)
call firebase deploy
