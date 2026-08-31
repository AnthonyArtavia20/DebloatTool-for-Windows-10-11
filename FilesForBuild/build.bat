@echo off
setlocal enabledelayedexpansion
REM build.bat — genera DebloatTool.exe con los .ps1 embebidos adentro
REM (via DebloatTool.spec). El resultado en dist\DebloatTool.exe es
REM autocontenido: no necesita los .ps1 sueltos al lado, los extrae solo
REM a %LOCALAPPDATA%\DebloatTool en cada arranque. Correr build.bat una
REM sola vez (o cada vez que edites launcher.py o algun .ps1).
REM
REM IMPORTANTE: este script (y Python) solo hacen falta en TU PC, la que
REM compila. El DebloatTool.exe resultante es standalone: el cliente que
REM lo recibe no necesita Python ni corre build.bat, solo hace doble
REM click sobre el .exe ya compilado.

set "PYTHON_CMD="
call :detect_python
if defined PYTHON_CMD goto :found_python

echo [INFO] No se detecto una instalacion real de Python en esta PC
echo        (o el comando "python" esta apuntando al stub falso de la
echo        Microsoft Store).
where winget >nul 2>nul
if errorlevel 1 goto :manual_install

echo.
echo Instalando Python automaticamente con winget, un momento...
winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
if errorlevel 1 goto :manual_install

REM Reintentar deteccion por si el PATH de esta misma ventana ya se actualizo
call :detect_python
if defined PYTHON_CMD goto :found_python

echo.
echo Python se instalo correctamente, pero esta ventana de cmd no toma el
echo PATH nuevo hasta que se reabra. Cerra esta ventana y volve a correr
echo build.bat una vez mas — esa segunda vez ya va a compilar solo.
pause
exit /b 0

:manual_install
echo.
echo [ERROR] No se pudo instalar Python automaticamente (no hay winget
echo         disponible o fallo la instalacion).
echo.
echo Opcion A - Instalar Python manualmente:
echo   1. https://www.python.org/downloads/
echo   2. Durante la instalacion, marca la casilla
echo      "Add python.exe to PATH"
echo.
echo Opcion B - Si ya tenes Python instalado y esto sigue fallando:
echo   El alias de Microsoft Store esta tapando el comando "python".
echo   Desactivalo en: Configuracion ^> Aplicaciones ^> Configuracion
echo   avanzada de aplicaciones ^> Alias de ejecucion de aplicaciones
echo   ^> apagar "python.exe" / "python3.exe"
echo.
pause
exit /b 1

:found_python
echo [1/2] Instalando dependencias (customtkinter, pyinstaller)...
%PYTHON_CMD% -m pip install --upgrade pip >nul
%PYTHON_CMD% -m pip install -r requirements.txt
if errorlevel 1 (
    echo [ERROR] Fallo la instalacion de dependencias.
    pause
    exit /b 1
)

echo [2/2] Compilando DebloatTool.exe (con los .ps1 embebidos)...
%PYTHON_CMD% -m PyInstaller DebloatTool.spec
if errorlevel 1 (
    echo [ERROR] Fallo la compilacion.
    pause
    exit /b 1
)

echo.
echo Listo. dist\DebloatTool.exe ya trae todo adentro (los .ps1 quedaron
echo empaquetados, no hace falta copiar nada mas). Podes moverlo a
echo cualquier carpeta y correrlo con doble click.
pause
exit /b 0

REM ------------------------------------------------------------------
REM :detect_python
REM Busca un Python REAL, descartando el stub falso de la Microsoft
REM Store (que vive dentro de una carpeta "WindowsApps"). No confia en
REM capturar "python --version": ese stub no escribe por la salida
REM redirigida, asi que hay que mirar directamente la ruta con "where".
REM Deja PYTHON_CMD seteado ("py -3" o "python") si encuentra uno real.
REM ------------------------------------------------------------------
:detect_python
for /f "delims=" %%p in ('where py 2^>nul') do (
    echo %%p | findstr /I "WindowsApps" >nul
    if errorlevel 1 (
        set "PYTHON_CMD=py -3"
        exit /b 0
    )
)
for /f "delims=" %%p in ('where python 2^>nul') do (
    echo %%p | findstr /I "WindowsApps" >nul
    if errorlevel 1 (
        set "PYTHON_CMD=python"
        exit /b 0
    )
)
exit /b 1
