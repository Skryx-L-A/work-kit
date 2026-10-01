// Test-only chat model provider for the VS Code Language Model API. It scripts a worker that
// writes one file and finishes, so the extension host test covers the vscode.lm provider path.
const vscode = require('vscode');

function lastUserText(messages) {
  const texts = [];
  for (const m of messages) {
    for (const p of m.content) {
      if (p instanceof vscode.LanguageModelTextPart) texts.push(p.value);
    }
  }
  return texts.join('\n');
}

function countToolResults(messages) {
  let n = 0;
  for (const m of messages) {
    for (const p of m.content) {
      if (p instanceof vscode.LanguageModelToolResultPart) n++;
    }
  }
  return n;
}

exports.activate = function activate(context) {
  if (!vscode.lm.registerLanguageModelChatProvider) {
    return;
  }
  context.subscriptions.push(vscode.lm.registerLanguageModelChatProvider('kit-test', {
    provideLanguageModelChatInformation() {
      return [{
        id: 'scripted', name: 'Scripted', family: 'kit-test', version: '1', tooltip: 'test',
        maxInputTokens: 100000, maxOutputTokens: 4000, capabilities: { toolCalling: true },
      }];
    },
    async provideLanguageModelChatResponse(model, messages, options, progress) {
      const done = countToolResults(messages);
      const text = lastUserText(messages);
      if (!options.tools || options.tools.length === 0) {
        progress.report(new vscode.LanguageModelTextPart('no tools'));
      } else if (done === 0) {
        progress.report(new vscode.LanguageModelTextPart('Writing the file.'));
        progress.report(new vscode.LanguageModelToolCallPart('c1', 'write_file', { path: 'lm-out/hello.txt', content: 'from vscode.lm' }));
      } else if (done === 1) {
        progress.report(new vscode.LanguageModelToolCallPart('c2', 'finish', { result: `## What\nwrote lm-out/hello.txt\n\n## Verified\nsaw task: ${text.includes('# Task: lm-worker')}` }));
      } else {
        progress.report(new vscode.LanguageModelTextPart('finished'));
      }
    },
    provideTokenCount(model, text) {
      return typeof text === 'string' ? Math.ceil(text.length / 4) : 10;
    },
  }));
};
