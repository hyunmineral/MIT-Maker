@echo off
title PYNQ-Z2 Ethernet IP Setup
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [ERROR] Not running as Administrator.
  echo Right-click this file and choose "Run as administrator".
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$a = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*Realtek Gaming GbE*' }; Set-NetIPInterface -InterfaceIndex $a.ifIndex -Dhcp Disabled; Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false; New-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress 192.168.2.1 -PrefixLength 24 | Out-Null; Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Format-Table IPAddress,PrefixLength; Test-Connection 192.168.2.99 -Count 2"
echo.
echo Done. Press any key to close.
pause >nul
