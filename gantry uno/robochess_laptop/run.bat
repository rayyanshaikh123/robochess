@echo off
REM RoboChess - one-click launcher for Windows.
REM First run creates a local virtual environment and installs dependencies.

cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [RoboChess] First run - creating virtual environment...
    py -3 -m venv .venv
    if errorlevel 1 (
        echo.
        echo Could not create the virtual environment.
        echo Install Python 3 from https://python.org and tick "Add python.exe to PATH".
        pause
        exit /b 1
    )
    ".venv\Scripts\python.exe" -m pip install --upgrade pip -q
    echo [RoboChess] Installing dependencies...
    ".venv\Scripts\python.exe" -m pip install -r requirements.txt
    if errorlevel 1 (
        echo Dependency install failed - check your internet connection.
        pause
        exit /b 1
    )
)

echo [RoboChess] Starting control server...
".venv\Scripts\python.exe" server.py %*
pause
