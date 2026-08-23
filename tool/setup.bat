:: Atalho para quem prefere clicar duas vezes ou usa o prompt de comando.
:: O -ExecutionPolicy Bypass evita o bloqueio padrao do Windows a scripts
:: .ps1 que vieram junto com o repositorio.
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
