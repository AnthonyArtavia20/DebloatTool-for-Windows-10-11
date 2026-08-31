# DebloatTool.spec — bundlea launcher.py + todos los .ps1 de esta carpeta
# en un solo DebloatTool.exe.
#
# Correr con:  pyinstaller DebloatTool.spec
# (no con pyinstaller launcher.py directo, porque ahi se pierden los flags
# de abajo: uac_admin, y sobre todo la lista de .ps1 embebidos)

import glob

ps1_files = glob.glob("*.ps1")
if not ps1_files:
    raise SystemExit(
        "No se encontraron archivos .ps1 en esta carpeta. "
        "Corré esto desde la carpeta donde estan Common.ps1, run_all.ps1, etc."
    )

datas = [(f, ".") for f in ps1_files]

a = Analysis(
    ["launcher.py"],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="DebloatTool",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    uac_admin=True,
    icon="app.ico",
    version="version_info.txt",
)
