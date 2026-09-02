"""Genera el informe en Markdown que la CI publica en GitHub.

Lee dos ficheros producidos por el job de tests y escribe por stdout un
resumen legible:

    test-results/junit.xml  -> lo escribe unittest-xml-reporting (el runner
                               XMLTestRunner); trae totales y el detalle de
                               cada test fallido.
    coverage.json           -> lo escribe `coverage json`; trae el porcentaje
                               global y el desglose por fichero.

El workflow redirige esta salida a $GITHUB_STEP_SUMMARY (la pagina del run) y
la reutiliza como comentario en el pull request.

Uso:
    python scripts/ci_report.py [--min 85] > informe.md
"""
import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET

# Rutas relativas a la raiz del proyecto Django (donde se ejecuta manage.py)
JUNIT_PATH = os.path.join("test-results", "junit.xml")
COVERAGE_JSON_PATH = "coverage.json"

# Cuantos tests fallidos se detallan antes de cortar la lista: un fallo masivo
# (p.ej. la BBDD no arranca) generaria cientos de entradas identicas.
MAX_DETAILED_FAILURES = 25


def _read_suites(file_path):
    """Devuelve la lista de elementos <testsuite> del XML de JUnit"""
    root = ET.parse(file_path).getroot()
    if root.tag == "testsuite":
        return [root]
    return list(root.iter("testsuite"))


def _tests_summary():
    """Bloque Markdown con el resultado de la suite"""
    if not os.path.exists(JUNIT_PATH):
        return [
            "## Tests",
            "",
            f"No se genero `{JUNIT_PATH}`: la suite no llego a terminar. "
            "Revisa el log del paso que la ejecuta.",
            "",
        ], False

    suites = _read_suites(JUNIT_PATH)

    total = sum(int(s.get("tests", 0)) for s in suites)
    failures = sum(int(s.get("failures", 0)) for s in suites)
    errors = sum(int(s.get("errors", 0)) for s in suites)
    skipped = sum(int(s.get("skipped", 0)) for s in suites)
    second_tokens = sum(float(s.get("time", 0) or 0) for s in suites)
    passed = total - failures - errors - skipped

    ok = failures == 0 and errors == 0
    icon = "OK" if ok else "FALLA"

    lines = [
        f"## Tests: {icon}",
        "",
        "| Total | Correctos | Fallos | Errores | Omitidos | Tiempo |",
        "| ---: | ---: | ---: | ---: | ---: | ---: |",
        f"| {total} | {passed} | {failures} | {errors} | {skipped} "
        f"| {second_tokens:.1f}s |",
        "",
    ]

    if not ok:
        # Detalle de que ha fallado, para no tener que abrir el log completo.
        broken = []
        for suite in suites:
            for case in suite.iter("testcase"):
                for kind, label in (("failure", "Fallo"), ("error", "Error")):
                    node = case.find(kind)
                    if node is None:
                        continue
                    name = f"{case.get('classname', '')}.{case.get('name', '')}"
                    message = (node.get("message") or "").strip().splitlines()
                    message = message[0] if message else "(sin mensaje)"
                    broken.append((label, name, message))

        lines += ["### Tests que no pasan", ""]
        for label, name, message in broken[:MAX_DETAILED_FAILURES]:
            lines.append(f"- **{label}** `{name}`: {message}")
        if len(broken) > MAX_DETAILED_FAILURES:
            left_over = len(broken) - MAX_DETAILED_FAILURES
            lines.append(f"- ... y {left_over} mas (ver el log del job).")
        lines.append("")

    return lines, ok


def _coverage_summary(minimum):
    """Bloque Markdown con la cobertura global y el desglose por fichero"""
    if not os.path.exists(COVERAGE_JSON_PATH):
        return [
            "## Cobertura",
            "",
            f"No se genero `{COVERAGE_JSON_PATH}`.",
            "",
        ]

    with open(COVERAGE_JSON_PATH, encoding="utf-8") as file_handle:
        data = json.load(file_handle)

    totals = data["totals"]
    percentage = totals["percent_covered"]
    icon = "OK" if minimum is None or percentage >= minimum else "POR DEBAJO DEL MINIMO"

    lines = [
        f"## Cobertura: {percentage:.1f}% ({icon})",
        "",
        "| Sentencias | Sin cubrir | Ramas | Ramas sin cubrir | Minimo exigido |",
        "| ---: | ---: | ---: | ---: | ---: |",
        f"| {totals['num_statements']} | {totals['missing_lines']} "
        f"| {totals['num_branches']} | {totals['missing_branches']} "
        f"| {'-' if minimum is None else f'{minimum}%'} |",
        "",
    ]

    # Los ficheros peor cubiertos son los unicos que interesa mirar de un
    # vistazo, el informe HTML completo va como artefacto del job.
    files = [
        (file_path, info["summary"]["percent_covered"], info["summary"]["missing_lines"])
        for file_path, info in data["files"].items()
        if info["summary"]["num_statements"] > 0
    ]
    files.sort(key=lambda f: f[1])
    worst = [f for f in files if f[1] < 100][:15]

    if worst:
        lines += [
            "<details><summary>Ficheros con menos cobertura</summary>",
            "",
            "| Fichero | Cobertura | Lineas sin cubrir |",
            "| --- | ---: | ---: |",
        ]
        for file_path, pct, uncovered in worst:
            lines.append(f"| `{file_path}` | {pct:.1f}% | {uncovered} |")
        lines += ["", "</details>", ""]

    lines.append(
        "El informe HTML navegable (`htmlcov/`) esta en los artefactos del job."
    )
    lines.append("")
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--min",
        type=float,
        default=None,
        help="Cobertura minima exigida, solo para mostrarla en el informe.",
    )
    args = parser.parse_args()

    tests_block, _ = _tests_summary()

    lines = ["# Informe de la suite del backend", ""]
    lines += tests_block
    lines += _coverage_summary(args.min)

    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
