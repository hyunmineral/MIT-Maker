@echo off
title PYNQ-Z2 SD Card Writer
echo ============================================
echo  PYNQ-Z2 SD Card Writer
echo ============================================
echo.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [ERROR] Not running as Administrator.
  echo Right-click this file and choose "Run as administrator".
  echo.
  pause
  exit /b 1
)
echo [OK] Administrator privileges confirmed.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\robot\pynq-image\write_sd2.ps1"
echo.
echo ============================================
echo  Finished. Press any key to close.
echo ============================================
pause >nul
