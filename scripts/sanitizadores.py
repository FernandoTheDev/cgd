#!/usr/bin/env python3
"""Valida a API C e todos os programas com ASan/UBSan; restaura o runtime normal."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
flags = '-DNDEBUG -fsanitize=address,undefined -fno-omit-frame-pointer'
base = {key: value for key, value in os.environ.items() if key not in ['CC','CFLAGS','ASAN_OPTIONS','UBSAN_OPTIONS']}
sanitized = {**base, 'CC': 'clang', 'CFLAGS': flags, 'ASAN_OPTIONS': 'detect_leaks=0:detect_stack_use_after_return=0', 'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'}
steps = []

def run(label, command, environment, cwd=ROOT):
    print('>>>', label, flush=True)
    result = subprocess.run(command, cwd=cwd, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1200)
    print(result.stdout, flush=True)
    steps.append({'label':label,'status':result.returncode,'output':result.stdout})
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, command)

passed = False
try:
    with tempfile.TemporaryDirectory(prefix='cgd asan ') as tmp:
        run('API C com NDEBUG + ASan + UBSan', ['./tests/run.sh'], sanitized, ROOT/'vendor/delegua-runtime')
        shutil.copy2(ROOT/'vendor/delegua-runtime/libdelegua_rt.o',ROOT/'lib/libdelegua_rt.o')
        wrapper=Path(tmp)/'cc-sanitizado'
        wrapper.write_text('#!/bin/sh\nexec clang -DNDEBUG -fsanitize=address,undefined -fno-omit-frame-pointer "$@"\n')
        wrapper.chmod(0o755)
        environment={**sanitized,'CC':str(wrapper)}
        run('Integração sanitizada', [sys.executable,'testes/integracao.py'],environment)
        run('Todos os exemplos sanitizados', [sys.executable,'testes/exemplos.py'],environment)
        passed=True
finally:
    restored=subprocess.run(['./build-runtime'],cwd=ROOT,env={**base,'CC':'clang'},text=True,capture_output=True)
    if restored.returncode:
        print(restored.stdout+restored.stderr,file=sys.stderr)
        passed=False
    out=ROOT/'out/sanitizadores.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps({'passed':passed,'flags':flags,'asan_options':sanitized['ASAN_OPTIONS'],'steps':steps,'normal_runtime_restored':restored.returncode==0},ensure_ascii=False,indent=2)+'\n')
if not passed:
    raise SystemExit(1)
print('Sanitizadores passaram; runtime normal restaurado.')
