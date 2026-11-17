'use strict';
const vscode = require('vscode');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFile } = require('node:child_process');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');
let client;
let context;
let output;
let compiling = false;

function compiler() {
  const configuration = vscode.workspace.getConfiguration('cgd');
  const configured = vscode.workspace.isTrusted
    ? configuration.get('executable')
    : configuration.inspect('executable')?.globalValue;
  if (configured) return configured;
  if (vscode.workspace.isTrusted) {
    for (const folder of vscode.workspace.workspaceFolders || []) {
      const candidate = path.join(
        folder.uri.fsPath,
        process.platform === 'win32' ? 'cgd.exe' : 'cgd',
      );
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  const bundled = context.asAbsolutePath(
    path.join('bin', process.platform === 'win32' ? 'cgd.exe' : 'cgd'),
  );
  return fs.existsSync(bundled) ? bundled : 'cgd';
}
async function start() {
  if (client) await client.stop();
  const executable = compiler();
  client = new LanguageClient(
    'cgd',
    'CGD — servidor local',
    {
      command: executable,
      args: ['--lsp'],
      transport: TransportKind.stdio,
      options: { cwd: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath },
    },
    {
      documentSelector: [
        { scheme: 'file', language: 'cgd' },
        { scheme: 'untitled', language: 'cgd' },
      ],
      outputChannel: output,
      synchronize: { fileEvents: vscode.workspace.createFileSystemWatcher('**/*.delegua') },
      initializationOptions: { offline: true },
      middleware: {
        provideInlayHints: (document, range, token, next) =>
          vscode.workspace.getConfiguration('cgd').get('inlayHints')
            ? next(document, range, token)
            : [],
      },
    },
  );
  await client.start();
}
async function build(run = false, checkOnly = false) {
  if (!vscode.workspace.isTrusted)
    throw new Error('Confie no workspace antes de compilar ou executar.');
  if (compiling) throw new Error('Uma compilação já está em andamento.');
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== 'cgd')
    throw new Error('Abra um arquivo CGD / Delégua.');
  if (editor.document.isUntitled) {
    if (!(await vscode.commands.executeCommand('workbench.action.files.save'))) return;
  } else if (!(await editor.document.save())) return;
  const document = vscode.window.activeTextEditor.document;
  const source = document.uri.fsPath;
  const folder =
    vscode.workspace.getWorkspaceFolder(document.uri)?.uri.fsPath || path.dirname(source);
  const destination = path.join(
    folder,
    'out',
    'cgd',
    path.basename(source, '.delegua') +
      '-' +
      crypto.createHash('sha256').update(source).digest('hex').slice(0, 8) +
      (process.platform === 'win32' ? '.exe' : ''),
  );
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const args = [source, ...(checkOnly ? ['--verificar'] : ['-s', destination])];
  if (!checkOnly && vscode.workspace.getConfiguration('cgd').get('optimizar')) args.push('-o');
  compiling = true;
  output.show(true);
  output.appendLine(`CGD: ${checkOnly ? 'verificar' : 'compilar'} ${source}`);
  try {
    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: 'CGD', cancellable: true },
      (_, token) =>
        new Promise((resolve, reject) => {
          const child = execFile(
            compiler(),
            args,
            { cwd: folder, maxBuffer: 8 * 1024 * 1024 },
            (error, stdout, stderr) => {
              if (stdout) output.append(stdout);
              if (stderr) output.append(stderr);
              if (error)
                reject(
                  new Error(
                    error.killed
                      ? 'Compilação cancelada.'
                      : `Falha na compilação (${error.code}). Consulte a saída CGD.`,
                  ),
                );
              else resolve();
            },
          );
          token.onCancellationRequested(() => child.kill());
        }),
    );
    if (run && !checkOnly) {
      const task = new vscode.Task(
        { type: 'cgd', file: source },
        vscode.workspace.getWorkspaceFolder(document.uri) || vscode.TaskScope.Workspace,
        'Executar ' + path.basename(source),
        'CGD',
        new vscode.ProcessExecution(destination, [], { cwd: folder }),
      );
      task.presentationOptions = {
        reveal: vscode.TaskRevealKind.Always,
        focus: true,
        panel: vscode.TaskPanelKind.Dedicated,
      };
      await vscode.tasks.executeTask(task);
    } else vscode.window.setStatusBarMessage('CGD: operação concluída.', 3000);
  } finally {
    compiling = false;
  }
}
function guarded(action) {
  return async () => {
    try {
      await action();
    } catch (error) {
      vscode.window.showErrorMessage(error.message);
    }
  };
}
async function activate(extensionContext) {
  context = extensionContext;
  output = vscode.window.createOutputChannel('CGD');
  context.subscriptions.push(
    output,
    vscode.commands.registerCommand(
      'cgd.compilar',
      guarded(() => build()),
    ),
    vscode.commands.registerCommand(
      'cgd.executar',
      guarded(() => build(true)),
    ),
    vscode.commands.registerCommand(
      'cgd.verificar',
      guarded(() => build(false, true)),
    ),
    vscode.commands.registerCommand('cgd.reiniciarServidor', guarded(start)),
    vscode.debug.registerDebugConfigurationProvider('cgd', {
      async resolveDebugConfiguration() {
        await guarded(() => build(true))();
        return undefined; // F5 é execução; DAP está explicitamente adiado.
      },
    }),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration('cgd.executable')) guarded(start)();
    }),
  );
  await start();
}
async function deactivate() {
  if (client) await client.stop();
}
module.exports = { activate, deactivate };
