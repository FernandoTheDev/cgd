#!/usr/bin/env python3
"""Valida o núcleo async C isoladamente, sem alterar o runtime instalado/local."""

import json
import os
import shlex
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "vendor/delegua-runtime"
OUT = ROOT / "out/assincronismo"


def run(command, **kwargs):
    return subprocess.run(command, check=True, timeout=180, **kwargs)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report_file = OUT / "resultado.json"
    report_file.write_text(json.dumps({"complete": False, "variants": []}) + "\n")
    flags = shlex.split(
        subprocess.check_output(
            [os.environ.get("PKG_CONFIG", "pkg-config"), "--cflags", "bdw-gc", "libcurl"],
            text=True,
        )
    )
    libraries = shlex.split(
        subprocess.check_output(
            [os.environ.get("PKG_CONFIG", "pkg-config"), "--libs", "bdw-gc", "libcurl"],
            text=True,
        )
    )
    # O runtime já contém a tabela gerada da toolchain pelo build anterior.
    # Não regerar arquivos externos nem substituir libdelegua_rt.o neste teste.
    if not (RUNTIME / ".build/curl_infos.inc").is_file():
        raise SystemExit(
            "Execute ./build-runtime para preparar a tabela libcurl antes deste teste."
        )
    sources = sorted(str(path) for path in (RUNTIME / "src").glob("*.c")) + sorted(
        str(path)
        for path in (RUNTIME / "src/gc").glob("*.c")
        if path.name != "gc_boehm_compat.c"
    )
    variants = [
        ("clang", []),
        ("gcc", ["-O2"]),
        ("clang", ["-O1", "-DNDEBUG", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]),
    ]
    reports = []
    for compiler, extra in variants:
        if not shutil.which(compiler):
            raise SystemExit(f"Compilador necessário ausente: {compiler}")
        name = compiler + ("-san" if any("sanitize" in flag for flag in extra) else "-normal")
        folder = OUT / name
        folder.mkdir(exist_ok=True)
        started = time.monotonic()
        binary = folder / "async"
        strict = [
            "-std=c99",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-pedantic",
            "-Wconversion",
            "-Wshadow",
            "-g",
        ]
        objects = []
        for source in sources:
            target = folder / (Path(source).stem + ".o")
            # Fontes anteriores emitem avisos de fluxo com GCC/O2:
            # seus helpers de panic não são anotados noreturn. Otimizar apenas
            # o núcleo async, as rotinas e seu teste evita alterar/suprimir avisos externos.
            source_extra = (
                []
                if compiler == "gcc"
                and Path(source).name != "assincrono.c"
                and not Path(source).name.startswith("rotinas_")
                else extra
            )
            run([compiler, *strict, *source_extra, *flags, "-c", source, "-o", str(target)])
            objects.append(str(target))
        run(
            [
                compiler,
                *strict,
                *extra,
                *flags,
                str(RUNTIME / "tests/assincrono.c"),
                str(RUNTIME / "tests/rotinas_pool.c"),
                *objects,
                *libraries,
                "-ldl",
                "-lm",
                "-rdynamic",
                "-o",
                str(binary),
            ]
        )
        env = os.environ.copy()
        # Boehm GC e LeakSanitizer não compõem um detector confiável de leaks.
        env["ASAN_OPTIONS"] = "detect_leaks=0:detect_stack_use_after_return=0:abort_on_error=1"
        env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
        run([str(binary)], env=env)
        # Mesmos objetos, API C anterior e FFI em pasta isolada de out/.
        (folder / ".build").mkdir(exist_ok=True)
        run(
            [
                compiler,
                "-std=c99",
                "-fPIC",
                "-shared",
                *flags,
                str(RUNTIME / "ffi/soma.c"),
                "-o",
                str(folder / ".build/soma.so"),
            ]
        )
        legacy = folder / "runtime"
        legacy_extra = [] if compiler == "gcc" else extra
        run(
            [
                compiler,
                "-std=c99",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-g",
                *legacy_extra,
                *flags,
                str(RUNTIME / "tests/runtime.c"),
                *objects,
                *libraries,
                "-ldl",
                "-lm",
                "-rdynamic",
                "-o",
                str(legacy),
            ]
        )
        run([str(legacy)], cwd=folder, env=env)
        modes = [
            "source-site",
            "legacy-source",
            "power",
            "intdiv",
            "membership",
            "tuple-conversion",
            "random-range",
            "index",
            "overflow",
            "sub",
            "mul",
            "div",
            "cast",
            "parse",
            "shift",
            "slice",
            "tuple",
            "null",
            "allocation",
            "key",
            "arity",
            "ffi",
            "closed",
        ]
        for mode in modes:
            result = subprocess.run(
                [str(legacy), mode],
                cwd=folder,
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            if result.returncode != 1 or "R0001" not in result.stderr:
                raise RuntimeError(
                    f"API C anterior: {name}/{mode}: {result.returncode}\n{result.stdout}{result.stderr}"
                )
        reports.append(
            {
                "variant": name,
                "legacy_api": True,
                "gcc_optimized_core_only": compiler == "gcc",
                "seconds": round(time.monotonic() - started, 3),
                "passed": True,
            }
        )
        report_file.write_text(
            json.dumps({"complete": False, "variants": reports}, indent=2) + "\n"
        )
    # O pool só manipula pacotes nativos. Isolá-lo evita instrumentar o GC
    # conservador e permite detectar races na fila e no cancelamento.
    pool_binary = OUT / "rotinas-tsan"
    run(
        [
            "clang",
            "-std=c99",
            "-g",
            "-O1",
            "-fsanitize=thread",
            "-ffunction-sections",
            "-fdata-sections",
            "-DCGD_TEST_POOL_MAIN",
            *flags,
            str(RUNTIME / "src/rotinas_pool.c"),
            str(RUNTIME / "src/rotinas_transferencia.c"),
            str(RUNTIME / "tests/rotinas_pool.c"),
            "-Wl,--gc-sections",
            "-pthread",
            "-o",
            str(pool_binary),
        ]
    )
    run([str(pool_binary)], env={**os.environ, "TSAN_OPTIONS": "halt_on_error=1"})
    reports.append({"variant": "pool-tsan", "passed": True})
    report_file.write_text(json.dumps({"complete": True, "variants": reports}, indent=2) + "\n")
    print(
        "Núcleo async e rotinas passaram em Clang, GCC e ASan/UBSan. Pool isolado passou em TSan."
    )


if __name__ == "__main__":
    main()
