#!/usr/bin/env python3
"""Empacota/instala a extensão local usando um CGD existente; nunca executa DUB."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
EXT = ROOT / "extensao-vscode"
parser = argparse.ArgumentParser()
parser.add_argument("--compiler", type=Path, default=ROOT / "cgd")
parser.add_argument("--package-only", action="store_true")
parser.add_argument(
    "--associate",
    action="store_true",
    help="Associar *.delegua ao CGD nas configurações do usuário, preservando JSONC.",
)
args = parser.parse_args()
compiler = args.compiler.resolve()
if not compiler.is_file():
    raise SystemExit("Compile o CGD uma vez antes: dub build --compiler=ldc2 --build=release")
if not (ROOT / "lib/libdelegua_rt.o").is_file():
    raise SystemExit("Runtime ausente. Execute ./build-runtime")
if not (EXT / "node_modules/vscode-languageclient/package.json").is_file():
    raise SystemExit("Instale dependências: npm ci --prefix extensao-vscode --ignore-scripts")
bundle = EXT / "bin"
bundle.mkdir(exist_ok=True)
shutil.copy2(compiler, bundle / "cgd")
shutil.copytree(ROOT / "lib", bundle / "lib", dirs_exist_ok=True)
headers = bundle / "vendor/delegua-runtime/src"
headers.mkdir(parents=True, exist_ok=True)
for header in (ROOT / "vendor/delegua-runtime/src").glob("*.h"):
    shutil.copy2(header, headers / header.name)
shutil.copytree(ROOT / "bibliotecas", bundle / "bibliotecas", dirs_exist_ok=True)
manifest = json.loads((EXT / "package.json").read_text())
output = ROOT / f"out/cgd-{manifest['version']}.vsix"
output.parent.mkdir(exist_ok=True)
# Pacote VSIX padrão: stdlib evita baixar ferramentas de publicação/assinatura.
metadata = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
<Metadata><Identity Language="pt-BR" Id="{escape(manifest["name"])}" Version="{escape(manifest["version"])}" Publisher="{escape(manifest["publisher"])}" TargetPlatform="linux-x64"/>
<DisplayName>{escape(manifest["displayName"])}</DisplayName><Description xml:space="preserve">{escape(manifest["description"])}</Description>
<Categories>Programming Languages</Categories><Tags>delegua,cgd,lsp</Tags><GalleryFlags/>
<Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="{escape(manifest["engines"]["vscode"])}"/><Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="workspace"/></Properties><License>extension/LICENSE</License></Metadata>
<Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/>
<Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/><Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md" Addressable="true"/><Asset Type="Microsoft.VisualStudio.Services.Content.License" Path="extension/LICENSE" Addressable="true"/></Assets></PackageManifest>"""
files = [
    EXT / name
    for name in (
        "package.json",
        "extension.js",
        "language-configuration.json",
        "README.md",
        "LICENSE",
    )
]
files += [path for path in bundle.rglob("*") if path.is_file()]
queue = list(manifest.get("dependencies", {}))
included = set()
while queue:
    name = queue.pop()
    if name in included:
        continue
    included.add(name)
    directory = EXT / "node_modules" / name
    package = json.loads((directory / "package.json").read_text())
    queue += list(package.get("dependencies", {}))
    files += [
        path
        for path in directory.rglob("*")
        if path.is_file()
        and "test" not in path.relative_to(directory).parts
        and "node_modules" not in path.relative_to(directory).parts
    ]
extensions = {path.suffix.lstrip(".") for path in files if path.suffix}
content_types = (
    '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    + "".join(
        f'<Default Extension="{escape(ext)}" ContentType="application/json"/>'
        if ext == "json"
        else f'<Default Extension="{escape(ext)}" ContentType="application/octet-stream"/>'
        for ext in sorted(extensions | {"vsixmanifest"})
    )
    + "</Types>"
)
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("extension.vsixmanifest", metadata)
    archive.writestr("[Content_Types].xml", content_types)
    for file in sorted(set(files)):
        archive.write(file, "extension/" + file.relative_to(EXT).as_posix())
print(
    f"Pacote local: {len(files)} arquivos; dependências de execução incluídas: {', '.join(sorted(included))}"
)

if not args.package_only:
    executable = shutil.which("code")
    if not executable:
        raise SystemExit(f"VSIX pronto em {output}; instale manualmente no VS Code.")
    subprocess.run([executable, "--install-extension", str(output), "--force"], check=True)
    extensions = subprocess.check_output(
        [executable, "--list-extensions", "--show-versions"], text=True
    )
    identity = f"{manifest['publisher']}.{manifest['name']}@{manifest['version']}"
    assert identity.lower() in extensions.lower(), extensions
    print(f"Instalação confirmada: {identity}")
    if args.associate:
        # jsonc-parser altera somente a associação solicitada; não reescreve settings.
        settings = (
            Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
            / "Code/User/settings.json"
        )
        script = """const fs=require('fs');const jsonc=require('./node_modules/jsonc-parser');const file=process.argv[1];fs.mkdirSync(require('path').dirname(file),{recursive:true});const text=fs.existsSync(file)?fs.readFileSync(file,'utf8'):'{}';const errors=[];jsonc.parse(text,errors,{allowTrailingComma:true});if(errors.length)throw Error('settings.json contém erros; associação não alterada');const edits=jsonc.modify(text,['files.associations','*.delegua'],'cgd',{formattingOptions:{insertSpaces:true,tabSize:2}});fs.writeFileSync(file,jsonc.applyEdits(text,edits));"""
        subprocess.run(["node", "-e", script, str(settings)], cwd=EXT, check=True)
        print("Associação *.delegua → cgd configurada, preservando demais configurações.")
print(f"VSIX: {output}")
