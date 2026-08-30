"""Lanzador de la suite de tests bajo cobertura
Lo invoca scripts/run_coverage.ps1, que ya vuelca .env.test al entorno):
    python scripts/_coverage_runner.py [args de manage.py test...]
"""
import os
import sys


def _preload_osgeo_sqlite():
    """Carga la sqlite3.dll de OSGeo4W antes que la de Python (solo Windows)."""
    if os.name != "nt":
        return
    osgeo_dir = os.environ.get("OSGEO4W_DIR")
    if not osgeo_dir:
        return
    osgeo_bin = os.path.join(osgeo_dir, "bin")
    if not os.path.isdir(osgeo_bin):
        return
    os.add_dll_directory(osgeo_bin)
    sqlite_dll = os.path.join(osgeo_bin, "sqlite3.dll")
    if os.path.exists(sqlite_dll):
        import ctypes
        ctypes.WinDLL(sqlite_dll)


def main():
    _preload_osgeo_sqlite()
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if project_root not in sys.path:
        sys.path.insert(0, project_root)
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "blablaUCM.settings")

    import coverage
    cov = coverage.Coverage()
    cov.start()

    code = 0
    try:
        from django.core.management import execute_from_command_line
        execute_from_command_line([sys.argv[0], "test"] + sys.argv[1:])
    except SystemExit as exc:  # el comando test hace sys.exit(nº de fallos)
        code = exc.code if isinstance(exc.code, int) else (0 if not exc.code else 1)
    finally:
        cov.stop()
        cov.save()

    sys.exit(code)


if __name__ == "__main__":
    main()
