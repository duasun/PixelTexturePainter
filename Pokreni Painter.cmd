@echo off
setlocal
if exist "%~dp0build\PixelTexturePainter.exe" (
    start "" "%~dp0build\PixelTexturePainter.exe"
    exit /b
)
where godot >nul 2>nul
if not errorlevel 1 (
    start "" godot --path "%~dp0."
    exit /b
)
set "PAINTER_GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
if not exist "%PAINTER_GODOT%" (
    echo Godot nije pronadjen. Otvori project.godot kroz Godot Project Manager.
    pause
    exit /b 1
)
start "" "%PAINTER_GODOT%" --path "%~dp0."
