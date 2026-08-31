"""
Launcher.py — Interfaz grafica para Windows 11 Debloat & Performance.

Se compila a un .exe UNICO con PyInstaller: los .ps1 (Common.ps1,
debloat_windows11.ps1, etc.) quedan EMBEBIDOS dentro del exe via
--add-data, asi que en la carpeta de destino solo aparece DebloatTool.exe,
nada suelto.

Al arrancar, el exe extrae esos .ps1 embebidos a una carpeta persistente
(%LOCALAPPDATA%\\DebloatTool) y corre desde ahi — NO desde la carpeta
temporal que PyInstaller usa internamente (sys._MEIPASS), porque esa
carpeta se borra al cerrar el programa y Common.ps1 usa $PSScriptRoot
para decidir donde escribir Logs/: si se ejecutara desde _MEIPASS, los
logs desaparecerian en cada cierre. La copia se sobreescribe en cada
arranque para que nunca quede desincronizada de lo que trae el exe.

Esto NO es cifrado ni ofuscacion real: un .exe de PyInstaller se puede
abrir con herramientas como pyinstxtractor y sacar los .ps1 tal cual.
Solo evita que aparezcan como archivos sueltos a simple vista.

Requiere: Python 3.10+, pip install -r requirements.txt
Build:    pyinstaller DebloatTool.spec   (ver ese archivo para los flags)
"""

import os
import sys
import glob
import shutil
import queue
import threading
import subprocess
from tkinter import messagebox

import customtkinter as ctk

# ── Datos de la app (editá esto con lo tuyo) ────────────────────────────
APP_TITLE = "Windows 10/11 Debloat & Performance"
APP_VERSION = "1.0.0"
APPDATA_FOLDER_NAME = "DebloatTool"  # bajo %LOCALAPPDATA%

# Seccion "Acerca de": modifica estos valores con tus datos. Cualquiera
# que quede vacio ("") simplemente no se muestra en la ventana.
AUTHOR_INFO = {
    "nombre": "Anthony Artavia",
    "contacto": "",   # ej: "github.com/tu-usuario" o un correo
    "notas": "Herramienta personal de debloat y optimizacion para Windows 10/11.",
}

# ── Configuracion de scripts ─────────────────────────────────────────────

# El boton principal de la pantalla: corre el flujo completo recomendado.
MAIN_SCRIPT = (
    "Ejecutar todo automatizado (recomendado)", "run_all.ps1",
    "Corre los 4 pasos en orden: limpieza, candado, rendimiento, tarea programada.",
)

# Los pasos individuales: viven en la ventana de "Ejecutar manualmente",
# separados del boton principal para no saturar la pantalla de inicio.
MANUAL_SCRIPTS = [
    ("1. Limpieza base", "debloat_windows11.ps1",
     "Copilot, Widgets, Bing, telemetria, apps basura, anuncios de Start."),
    ("2. Candado (bloqueo total)", "debloat_hardcore.ps1",
     "Evita que Windows reinstale lo que ya se quito."),
    ("3. Modo rendimiento", "performance_mode.ps1",
     "Memoria, core parking, GPU y scheduler para menos latencia."),
    ("4. Instalar candado automatico", "install_lock_task.ps1",
     "Tarea programada que re-aplica el candado en cada arranque."),
    ("Re-aplicar candado ahora (manual)", "lock_after_update_Manual_.ps1",
     "Por si acabas de instalar una actualizacion grande de Windows."),
]

# Boton de reversion: separado de todo lo anterior porque deshace, no aplica.
RESTORE_SCRIPT = (
    "Restaurar configuración original", "restore_defaults.ps1",
    "Revierte políticas y el candado automático. Las apps ya eliminadas NO se reinstalan.",
)
RESTORE_CONFIRM_TEXT = (
    "Esto va a:\n\n"
    "• Quitar la tarea programada que re-aplica el candado en cada arranque\n"
    "• Revertir Copilot, Bing/Web Search, Cloud Content, telemetría, anuncios\n"
    "  de Start/lock screen, y los ajustes de rendimiento (memoria, energía,\n"
    "  GPU, scheduler)\n"
    "• Re-activar las tareas de tracking que se habían desactivado\n\n"
    "Las apps que ya se desinstalaron (Xbox, Gaming Services, Clipchamp,\n"
    "Widgets, apps de Bing, etc.) NO se van a reinstalar.\n\n"
    "¿Continuar?"
)


# ── Utilidades sin dependencia de la GUI (testeables por separado) ──────

def get_resource_dir() -> str:
    """Donde estan los .ps1 tal como quedaron empacados en el exe.
    En modo compilado (PyInstaller --onefile) es la carpeta temporal
    sys._MEIPASS que el bootloader arma en cada arranque. En modo
    desarrollo (corriendo launcher.py suelto) es la carpeta del script."""
    if getattr(sys, "frozen", False):
        return getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def get_work_dir() -> str:
    """Donde se COPIAN y desde donde se EJECUTAN los .ps1 realmente.
    Tiene que ser una carpeta persistente (no sys._MEIPASS, que Windows
    borra al cerrar el programa) porque Common.ps1 usa $PSScriptRoot
    para decidir donde escribir Logs/ — si esa carpeta desaparece, los
    logs desaparecen con ella. En modo desarrollo no hace falta copiar
    nada: se corre directo desde la carpeta del script."""
    if getattr(sys, "frozen", False):
        local_appdata = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        return os.path.join(local_appdata, APPDATA_FOLDER_NAME)
    return get_resource_dir()


def sync_scripts(resource_dir: str, work_dir: str) -> list:
    """Copia todos los .ps1 embebidos a la carpeta de trabajo persistente.
    Sobreescribe siempre: si se recompila el exe con logica nueva, la
    copia en disco no puede quedar desactualizada. Devuelve la lista de
    archivos copiados; no toca Logs/ si ya existe."""
    os.makedirs(work_dir, exist_ok=True)
    copied = []
    for src in glob.glob(os.path.join(resource_dir, "*.ps1")):
        dst = os.path.join(work_dir, os.path.basename(src))
        shutil.copyfile(src, dst)
        copied.append(dst)
    return copied


def script_path(base_dir: str, filename: str) -> str:
    return os.path.join(base_dir, filename)


def classify_line(line: str) -> str:
    """Devuelve el tag de color a aplicar segun el contenido de la linea,
    para que el log se vea igual de claro que en la consola de PowerShell."""
    stripped = line.strip()
    if "[FAIL]" in stripped or "ErrorTerminación" in stripped or "ERROR:" in stripped:
        return "fail"
    if "[!]" in stripped:
        return "warn"
    if "[OK]" in stripped:
        return "ok"
    if stripped.startswith("[*]") or stripped.startswith("==="):
        return "step"
    return "default"


def build_powershell_command(ps1_path: str) -> list:
    return [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ps1_path,
    ]


def is_admin() -> bool:
    """Chequeo informativo. El exe empaquetado con --uac-admin ya deberia
    forzar la elevacion antes de que este codigo corra; esto es un respaldo
    para cuando se corre launcher.py suelto en modo desarrollo."""
    try:
        import ctypes
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return True  # en Linux/dev no aplica; no bloquear la UI por esto


# ── Aplicacion ────────────────────────────────────────────────────────

class DebloatApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.resource_dir = get_resource_dir()
        self.base_dir = get_work_dir()
        self.output_queue: "queue.Queue[tuple[str, str]]" = queue.Queue()
        self.running = False
        self.manual_window = None
        self.manual_buttons = []

        self.title(APP_TITLE)
        self.geometry("880x620")
        self.minsize(760, 520)

        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("green")

        self._build_layout()
        self._poll_queue()

        if getattr(sys, "frozen", False):
            try:
                copied = sync_scripts(self.resource_dir, self.base_dir)
                self._log(f"[i] {len(copied)} scripts sincronizados en {self.base_dir}\n", "step")
            except Exception as exc:
                self._log(f"[FAIL] No se pudieron copiar los scripts: {exc}\n", "fail")
                self.base_dir = self.resource_dir  # respaldo: intentar correr desde donde esten

        if not is_admin():
            self._log("[!] No se detecto sesion de administrador. Los scripts van a fallar sin permisos elevados.\n", "warn")

    # -- construccion de la UI ------------------------------------------------

    def _build_layout(self):
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)

        header = ctk.CTkFrame(self, fg_color="transparent")
        header.grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 8))
        ctk.CTkLabel(
            header, text=APP_TITLE,
            font=ctk.CTkFont(family="Segoe UI", size=20, weight="bold"),
        ).pack(anchor="w")
        ctk.CTkLabel(
            header, text=self.base_dir,
            font=ctk.CTkFont(family="Consolas", size=11),
            text_color="gray60",
        ).pack(anchor="w")

        body = ctk.CTkFrame(self, fg_color="transparent")
        body.grid(row=1, column=0, sticky="nsew", padx=16, pady=8)
        body.grid_columnconfigure(1, weight=1)
        body.grid_rowconfigure(0, weight=1)

        # Panel izquierdo: acciones. self.buttons son los que se
        # deshabilitan mientras algo corre (todo excepto Logs/Acerca de).
        actions = ctk.CTkFrame(body, width=260)
        actions.grid(row=0, column=0, sticky="ns", padx=(0, 12))
        actions.grid_propagate(False)
        self.buttons = []

        label, filename, desc = MAIN_SCRIPT
        main_btn = ctk.CTkButton(
            actions, text=label, anchor="w", height=44,
            font=ctk.CTkFont(size=13, weight="bold"),
            command=lambda f=filename, l=label: self._run(f, l),
        )
        main_btn.pack(fill="x", padx=12, pady=(16, 2))
        ctk.CTkLabel(
            actions, text=desc, anchor="w", justify="left",
            font=ctk.CTkFont(size=10), text_color="gray55", wraplength=230,
        ).pack(fill="x", padx=12, pady=(0, 14))
        self.buttons.append(main_btn)

        manual_btn = ctk.CTkButton(
            actions, text="Ejecutar manualmente...", anchor="w",
            fg_color="gray30", hover_color="gray25",
            command=self._open_manual_window,
        )
        manual_btn.pack(fill="x", padx=12, pady=(0, 4))
        ctk.CTkLabel(
            actions, text="Corre cada paso por separado, uno a la vez.",
            anchor="w", justify="left", font=ctk.CTkFont(size=10),
            text_color="gray55", wraplength=230,
        ).pack(fill="x", padx=12, pady=(0, 14))
        self.buttons.append(manual_btn)

        r_label, r_filename, r_desc = RESTORE_SCRIPT
        restore_btn = ctk.CTkButton(
            actions, text=r_label, anchor="w",
            fg_color="#8a4b1f", hover_color="#743d17",
            command=lambda f=r_filename, l=r_label: self._confirm_and_run_restore(f, l),
        )
        restore_btn.pack(fill="x", padx=12, pady=(0, 2))
        ctk.CTkLabel(
            actions, text=r_desc, anchor="w", justify="left",
            font=ctk.CTkFont(size=10), text_color="gray55", wraplength=230,
        ).pack(fill="x", padx=12, pady=(0, 14))
        self.buttons.append(restore_btn)

        ctk.CTkFrame(actions, height=2, fg_color="gray25").pack(fill="x", padx=12, pady=8)

        ctk.CTkButton(
            actions, text="Abrir carpeta de Logs", fg_color="gray30",
            hover_color="gray25", command=self._open_logs,
        ).pack(fill="x", padx=12, pady=(4, 4))
        ctk.CTkButton(
            actions, text="Acerca de", fg_color="gray30",
            hover_color="gray25", command=self._open_about,
        ).pack(fill="x", padx=12, pady=(0, 12))

        # Panel derecho: log en vivo
        log_frame = ctk.CTkFrame(body)
        log_frame.grid(row=0, column=1, sticky="nsew")
        log_frame.grid_columnconfigure(0, weight=1)
        log_frame.grid_rowconfigure(0, weight=1)

        self.log_box = ctk.CTkTextbox(
            log_frame, font=ctk.CTkFont(family="Consolas", size=12),
            wrap="word", state="disabled",
        )
        self.log_box.grid(row=0, column=0, sticky="nsew", padx=8, pady=8)
        for tag, color in (
            ("ok", "#4CAF50"), ("fail", "#E53935"),
            ("warn", "#FBC02D"), ("step", "#4FC3F7"), ("default", "#D0D0D0"),
        ):
            self.log_box.tag_config(tag, foreground=color)

        # Barra de estado
        status = ctk.CTkFrame(self, fg_color="transparent")
        status.grid(row=2, column=0, sticky="ew", padx=16, pady=(0, 12))
        self.status_label = ctk.CTkLabel(status, text="Listo.", anchor="w")
        self.status_label.pack(side="left")
        self.progress = ctk.CTkProgressBar(status, mode="indeterminate", width=180)
        self.progress.pack(side="right")

    def _open_manual_window(self):
        if self.manual_window is not None and self.manual_window.winfo_exists():
            self.manual_window.lift()
            self.manual_window.focus()
            return

        win = ctk.CTkToplevel(self)
        win.title("Ejecutar manualmente")
        win.geometry("380x420")
        win.transient(self)  # queda asociada a la principal, pero no modal
        self.manual_window = win
        self.manual_buttons = []

        def on_close():
            self.manual_window = None
            self.manual_buttons = []
            win.destroy()

        win.protocol("WM_DELETE_WINDOW", on_close)

        ctk.CTkLabel(
            win, text="Pasos individuales",
            font=ctk.CTkFont(size=15, weight="bold"),
        ).pack(anchor="w", padx=16, pady=(16, 8))

        frame = ctk.CTkScrollableFrame(win)
        frame.pack(fill="both", expand=True, padx=12, pady=(0, 12))

        for label, filename, desc in MANUAL_SCRIPTS:
            btn = ctk.CTkButton(
                frame, text=label, anchor="w",
                command=lambda f=filename, l=label: self._run(f, l),
            )
            btn.pack(fill="x", pady=(4, 0))
            ctk.CTkLabel(
                frame, text=desc, anchor="w", justify="left",
                font=ctk.CTkFont(size=10), text_color="gray55", wraplength=320,
            ).pack(fill="x", pady=(0, 8))
            self.manual_buttons.append(btn)

        # Si algo ya estaba corriendo cuando se abrio esta ventana, que
        # nazca deshabilitada tambien.
        if self.running:
            for btn in self.manual_buttons:
                btn.configure(state="disabled")

    def _open_about(self):
        win = ctk.CTkToplevel(self)
        win.title("Acerca de")
        win.geometry("360x300")
        win.transient(self)
        win.resizable(False, False)

        ctk.CTkLabel(
            win, text=APP_TITLE,
            font=ctk.CTkFont(size=16, weight="bold"), wraplength=320,
        ).pack(anchor="w", padx=20, pady=(20, 2))
        ctk.CTkLabel(
            win, text=f"Versión {APP_VERSION}",
            font=ctk.CTkFont(size=12), text_color="gray60",
        ).pack(anchor="w", padx=20, pady=(0, 12))

        ctk.CTkFrame(win, height=2, fg_color="gray30").pack(fill="x", padx=20, pady=(0, 12))

        if AUTHOR_INFO.get("notas"):
            ctk.CTkLabel(
                win, text=AUTHOR_INFO["notas"], anchor="w", justify="left",
                font=ctk.CTkFont(size=12), wraplength=320,
            ).pack(anchor="w", padx=20, pady=(0, 12))

        if AUTHOR_INFO.get("nombre"):
            ctk.CTkLabel(
                win, text=f"Autor: {AUTHOR_INFO['nombre']}", anchor="w",
                font=ctk.CTkFont(size=12),
            ).pack(anchor="w", padx=20, pady=(0, 2))
        if AUTHOR_INFO.get("contacto"):
            ctk.CTkLabel(
                win, text=AUTHOR_INFO["contacto"], anchor="w",
                font=ctk.CTkFont(size=12), text_color="gray60",
            ).pack(anchor="w", padx=20, pady=(0, 2))

        ctk.CTkButton(win, text="Cerrar", command=win.destroy).pack(pady=16)

    # -- acciones ---------------------------------------------------------

    def _open_logs(self):
        log_dir = os.path.join(self.base_dir, "Logs")
        os.makedirs(log_dir, exist_ok=True)
        os.startfile(log_dir)

    def _confirm_and_run_restore(self, filename: str, label: str):
        if self.running:
            return
        if messagebox.askyesno("Restaurar configuración original", RESTORE_CONFIRM_TEXT):
            self._run(filename, label)

    def _run(self, filename: str, label: str):
        if self.running:
            return
        ps1 = script_path(self.base_dir, filename)
        if not os.path.isfile(ps1):
            self._log(f"[FAIL] No se encontro {filename} en {self.base_dir}.\n", "fail")
            return

        self.running = True
        self._set_buttons_enabled(False)
        self.status_label.configure(text=f"Ejecutando: {label}...")
        self.progress.start()
        self._log(f"\n=== {label} ===\n", "step")

        thread = threading.Thread(target=self._stream_process, args=(ps1,), daemon=True)
        thread.start()

    def _stream_process(self, ps1_path: str):
        try:
            proc = subprocess.Popen(
                build_powershell_command(ps1_path),
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
                cwd=self.base_dir,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            for line in proc.stdout:
                self.output_queue.put(("line", line))
            proc.wait()
            self.output_queue.put(("done", str(proc.returncode)))
        except Exception as exc:
            self.output_queue.put(("done", f"error:{exc}"))

    def _poll_queue(self):
        try:
            while True:
                kind, payload = self.output_queue.get_nowait()
                if kind == "line":
                    self._log(payload, classify_line(payload))
                elif kind == "done":
                    self._on_finished(payload)
        except queue.Empty:
            pass
        self.after(80, self._poll_queue)

    def _on_finished(self, payload: str):
        self.running = False
        self._set_buttons_enabled(True)
        self.progress.stop()
        if payload.startswith("error:"):
            self.status_label.configure(text="Error al lanzar PowerShell.")
            self._log(f"[FAIL] {payload[6:]}\n", "fail")
        elif payload == "0":
            self.status_label.configure(text="Listo. Terminó sin errores.")
        else:
            self.status_label.configure(text=f"Terminó con código {payload}.")

    def _set_buttons_enabled(self, enabled: bool):
        state = "normal" if enabled else "disabled"
        for btn in self.buttons:
            btn.configure(state=state)
        for btn in self.manual_buttons:
            btn.configure(state=state)

    def _log(self, text: str, tag: str = "default"):
        self.log_box.configure(state="normal")
        self.log_box.insert("end", text, tag)
        self.log_box.see("end")
        self.log_box.configure(state="disabled")


if __name__ == "__main__":
    app = DebloatApp()
    app.mainloop()
