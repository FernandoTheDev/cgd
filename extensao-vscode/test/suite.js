'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vscode = require('vscode');
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(action, message) {
  for (let i = 0; i < 100; i++) {
    const value = await action();
    if (value) return value;
    await delay(100);
  }
  throw new Error(message);
}
async function run() {
  const extension = vscode.extensions.getExtension('fernandothedev.cgd');
  assert(extension, 'Extensão não encontrada');
  await extension.activate();
  const root = vscode.workspace.workspaceFolders[0].uri.fsPath;
  const file = path.join(root, 'teste.delegua');
  fs.writeFileSync(
    file,
    'funcao dobro(valor:inteiro){retorna valor*2}\nvar resultado=dobro(3)\nescreva(resultado) // comentário\n',
  );
  const uri = vscode.Uri.file(file);
  const document = await vscode.workspace.openTextDocument(uri);
  await vscode.languages.setTextDocumentLanguage(document, 'cgd');
  await vscode.window.showTextDocument(document);
  const at = new vscode.Position(1, 16);
  const hovers = await until(async () => {
    const value = await vscode.commands.executeCommand('vscode.executeHoverProvider', uri, at);
    return value?.length ? value : null;
  }, 'Hover não respondeu');
  assert(hovers.length > 0);
  const definitions = await vscode.commands.executeCommand(
    'vscode.executeDefinitionProvider',
    uri,
    at,
  );
  assert(definitions.length > 0, 'Definição ausente');
  const completion = await vscode.commands.executeCommand(
    'vscode.executeCompletionItemProvider',
    uri,
    at,
  );
  assert(
    completion.items.some(
      (item) => (typeof item.label === 'string' ? item.label : item.label.label) === 'dobro',
    ),
  );
  const legend = await vscode.commands.executeCommand(
    'vscode.provideDocumentSemanticTokensLegend',
    uri,
  );
  const tokens = await vscode.commands.executeCommand('vscode.provideDocumentSemanticTokens', uri);
  assert(
    legend?.tokenTypes.includes('comment') && tokens?.data.length > 0,
    'Tokens semânticos ausentes',
  );
  const rename = await vscode.commands.executeCommand(
    'vscode.executeDocumentRenameProvider',
    uri,
    at,
    'duplicar',
  );
  assert(
    rename.entries().some(([, edits]) => edits.length === 2),
    'Rename incorreto',
  );
  const formatted = await vscode.commands.executeCommand(
    'vscode.executeFormatDocumentProvider',
    uri,
    { tabSize: 4, insertSpaces: true },
  );
  assert(formatted?.length, 'Formatador LSP ausente: ' + JSON.stringify(formatted));
  const formattingEdit = new vscode.WorkspaceEdit();
  formattingEdit.set(uri, formatted);
  await vscode.workspace.applyEdit(formattingEdit);
  assert(
    document.getText().includes('\n    retorna valor * 2'),
    'Formatação incorreta: ' + JSON.stringify(formatted),
  );
  assert(!fs.existsSync(path.join(root, 'out')), 'A edição gerou artefatos de compilação');
  const edit = new vscode.WorkspaceEdit();
  edit.replace(uri, new vscode.Range(0, 0, document.lineCount, 0), 'var valor=1/0\n');
  await vscode.workspace.applyEdit(edit);
  await until(
    () => vscode.languages.getDiagnostics(uri).some((d) => String(d.code) === 'E3101'),
    'Diagnóstico estático ausente',
  );
  const restore = new vscode.WorkspaceEdit();
  restore.replace(uri, new vscode.Range(0, 0, document.lineCount, 0), 'escreva(42)\n');
  await vscode.workspace.applyEdit(restore);
  await document.save();
  await vscode.commands.executeCommand('cgd.compilar');
  const outputs = fs.readdirSync(path.join(root, 'out/cgd'));
  assert(
    outputs.some((file) => !file.endsWith('.c')),
    'Comando explícito não gerou executável',
  );
  const result = {
    passed: true,
    checks: [
      'activation',
      'hover',
      'definition',
      'completion',
      'semantic tokens',
      'rename',
      'formatting',
      'diagnostics',
      'no compile on edit',
      'explicit build',
    ],
  };
  fs.writeFileSync(
    path.join(process.env.CGD_TEST_REPORT_DIR, 'extensao.json'),
    JSON.stringify(result, null, 2),
  );
  console.log('CGD: testes no Extension Host passaram.');
}
module.exports = { run };
