#!/usr/bin/env node
// ATTRAPPEN-HARNESS fuer die Chat-Sitzung (12.08.).
//
// Er spricht dasselbe Protokoll wie `claude --print --input-format stream-json
// --output-format stream-json`, und was er ausspuckt, ist NICHT ausgedacht:
// die Ereignisse des ersten Zuges stammen Zeile fuer Zeile aus dem echten
// Mitschnitt unter fixtures/chatsdk/. Damit prueft die Oberflaechen-Suite die
// ganze Kette -- Prozess, Strom, Fenster, Freigabe -- ohne ein Modell zu
// fragen, ohne Anmeldung und ohne Kosten.
//
// Was er kann, und mehr braucht der Test nicht:
//   * den `initialize`-Handschlag beantworten -- mit Slash-Befehlen und dem
//     geltenden Freigabemodus, so wie die echte CLI (gemessen 12.08.)
//   * `set_permission_mode` und `interrupt` beantworten, ebenfalls in der
//     gemessenen Form
//   * auf die erste Nachricht den Mitschnitt abspielen
//   * auf jede weitere eine Freigabefrage stellen und die Antwort befolgen:
//     bei 'allow' meldet er Erfolg, bei 'deny' den Fehler, den die echte CLI
//     in genau diesem Fall meldet (gemessen: tool_result mit is_error)
//
// Zwei Schalter ueber die Umgebung, beide fuer je einen Befund:
//   ATTRAPPE_LAST=<n>   statt des Mitschnitts ein Werkzeugergebnis von rund
//                       200 KB und danach <n> Teilstuecke -- die Last, mit der
//                       Befund B1 gemessen wird.
//   ATTRAPPE_RESUME_TOT=1  sieht er `--resume`, bricht er mit Rueckgabewert 1
//                       ab, OHNE je ein init geschickt zu haben. Genau der
//                       Fall, den der Reviewer an der echten CLI gemessen hat
//                       ('No conversation found'), Grundlage von Befund B3.
//
// Aufruf wie die echte CLI; die Flags werden gelesen, aber nur geprueft.
import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const hier = dirname(fileURLToPath(import.meta.url));
const mitschnitt = join(hier, 'fixtures', 'chatsdk', 'sitzung-zwei-zuege.jsonl');

const args = process.argv.slice(2);
const hatFlag = (f) => args.includes(f);

// Ohne diese drei taete die echte CLI etwas anderes -- der Attrappen-Harness
// sagt es deutlich, statt still ein anderes Verhalten zu zeigen.
if (!hatFlag('--print') || !hatFlag('--verbose')) {
  process.stderr.write('Attrappe: --print und --verbose fehlen\n');
  process.exit(2);
}
const fragtNach = hatFlag('--permission-prompt-tool');

// Der Fehlstart auf einer verschwundenen Unterhaltung (Befund B3). Die echte
// CLI schreibt in diesem Fall nach stderr und geht mit 1 -- ohne ein einziges
// Ereignis auf stdout, insbesondere ohne `init`.
if (process.env.ATTRAPPE_RESUME_TOT === '1' && hatFlag('--resume')) {
  process.stderr.write('No conversation found with session ID: attrappe-tot\n');
  process.exit(1);
}

/** Wie viele Teilstuecke der Lastmodus schickt; 0 heisst: normaler Betrieb. */
const last = Number.parseInt(process.env.ATTRAPPE_LAST ?? '0', 10) || 0;

/**
 * DAS TRAEGE KIND (Befund B5). Auf SIGTERM geht dieser Prozess erst nach
 * <n> Millisekunden. Damit laesst sich von aussen MESSEN, ob die App auf das
 * echte Ende ihrer Kinder wartet: tut sie es, dauert ihr Herunterfahren
 * mindestens so lange; tut sie es nicht, ist sie sofort weg und laesst ein
 * Waisenkind zurueck.
 */
const traege = Number.parseInt(process.env.ATTRAPPE_TRAEGE_MS ?? '0', 10) || 0;
/** Gilt fuer JEDEN Weg hinaus -- siehe `rl.on('close')` weiter unten. */
function langsamRaus() {
  if (traege <= 0) {
    process.exit(0);
    return;
  }
  setTimeout(() => process.exit(0), traege);
}
if (traege > 0) process.on('SIGTERM', langsamRaus);

function schreibe(o) {
  process.stdout.write(`${JSON.stringify(o)}\n`);
}

const SITZUNG = 'attrappe-0001-0002-0003';

/** Die Ereignisse des Mitschnitts, mit der eigenen Sitzungskennung. */
function mitschnittZeilen() {
  const raus = [];
  for (const zeile of readFileSync(mitschnitt, 'utf8').split('\n')) {
    if (!zeile.trim()) continue;
    let e;
    try {
      e = JSON.parse(zeile);
    } catch {
      continue;
    }
    if (e.session_id) e.session_id = SITZUNG;
    raus.push(e);
  }
  return raus;
}

let zug = 0;
/** Die offene Freigabefrage -- Kennung und was danach passieren soll. */
let offeneFrage = '';

/**
 * DER LASTMODUS (Befund B1). Erst ein Werkzeugergebnis von rund 200 KB, dann
 * viele Teilstuecke -- also genau die Lage, in der ein Voll-Neuaufbau je
 * Teilstueck teuer wird: ein sehr grosser Block steht schon im Verlauf,
 * waehrend der naechste Text Zeichen fuer Zeichen dazukommt.
 *
 * Der grosse Text ist absichtlich kein einziger Buchstabe tausendfach: Zeilen
 * unterschiedlicher Laenge kommen dem naeher, was ein echtes `Read` liefert,
 * und ein Verlauf mit vielen Zeilen ist fuer die Anzeige die teurere Arbeit.
 */
function lastAbspielen() {
  const zeilen = [];
  for (let i = 0; zeilen.join('\n').length < 200_000; i += 1) {
    zeilen.push(`${String(i).padStart(6, ' ')}  ${'x'.repeat(20 + (i % 60))}`);
  }
  const gross = zeilen.join('\n');

  schreibe({
    type: 'system', subtype: 'init', session_id: SITZUNG,
    model: 'attrappe-last', cwd: process.cwd(), permissionMode: 'default',
  });
  schreibe({
    type: 'assistant',
    session_id: SITZUNG,
    message: {
      role: 'assistant',
      content: [{
        // Je Zug eine EIGENE Kennung. Dieselbe zweimal zu schicken hiesse,
        // denselben Block noch einmal zu fuellen -- dann wird sein Element mit
        // Recht neu gebaut, und die Messung zu B1 misst den falschen Fall.
        type: 'tool_use', id: `toolu_last_${zug}`, name: 'Read',
        input: { file_path: `/tmp/attrappe/gross-${zug}.txt` },
      }],
    },
  });
  schreibe({
    type: 'user',
    session_id: SITZUNG,
    message: {
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: `toolu_last_${zug}`, content: gross, is_error: false }],
    },
  });

  // Und jetzt die Teilstuecke -- EINZELN UND MIT ABSTAND. Der Abstand ist
  // nicht Zierde: schriebe die Attrappe alle 400 auf einmal, kaeme im
  // Hauptprozess EIN stdout-Stueck an, das Fenster zeichnete einmal, und die
  // Messung haette nichts gemessen. Die echte CLI schickt sie ebenfalls
  // einzeln, verteilt ueber die Zeit, in der das Modell schreibt.
  schreibe({ type: 'stream_event', session_id: SITZUNG, event: { type: 'message_start' } });
  schreibe({
    type: 'stream_event', session_id: SITZUNG,
    event: { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
  });
  let i = 0;
  const takt = setInterval(() => {
    if (i >= last) {
      clearInterval(takt);
      schreibe({ type: 'stream_event', session_id: SITZUNG, event: { type: 'content_block_stop', index: 0 } });
      schreibe({
        type: 'result', subtype: 'success', session_id: SITZUNG, is_error: false,
        num_turns: 1, duration_ms: 9, usage: { input_tokens: 3, output_tokens: last }, total_cost_usd: 0,
      });
      return;
    }
    schreibe({
      type: 'stream_event', session_id: SITZUNG,
      event: { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: `Stueck ${i}. ` } },
    });
    i += 1;
  }, 2);
}

const rl = createInterface({ input: process.stdin });
rl.on('line', (zeile) => {
  let e;
  try {
    e = JSON.parse(zeile);
  } catch {
    return;
  }

  if (e.type === 'control_request' && e.request?.subtype === 'initialize') {
    // DIE FORM IST GEMESSEN (12.08., CLI 2.1.228): die Antwort auf den
    // Handschlag traegt `commands` und `current_permission_mode` -- das
    // init-Ereignis tut es NICHT. Drei Befehle genuegen dem Test; die volle
    // Form steht in fixtures/chatsdk/initialize-antwort.jsonl.
    schreibe({
      type: 'control_response',
      response: {
        subtype: 'success',
        request_id: e.request_id,
        response: {
          commands: [
            { name: 'compact', description: 'Free up context by summarizing the conversation so far', argumentHint: '' },
            { name: 'clear', description: 'Start a new session with empty context', argumentHint: '[name]' },
            { name: 'context', description: 'Visualize current context usage as a colored grid' },
          ],
          current_permission_mode: 'default',
        },
      },
    });
    return;
  }

  // DEN FREIGABEMODUS ZUR LAUFZEIT SETZEN (Luecke 5c). Die echte CLI antwortet
  // mit `{mode: "<der neue>"}` auf einen bekannten Modus und mit einer Absage
  // auf einen unbekannten -- die Absage nennt die vollstaendige Liste, und
  // genau daraus liest die Ansicht ihre Auswahl.
  if (e.type === 'control_request' && e.request?.subtype === 'set_permission_mode') {
    // `auto` fehlt ABSICHTLICH: die Suite braucht einen Modus, den der Harness
    // ablehnt, um zu belegen, dass eine Absage NICHT in der Buchfuehrung landet
    // (Reviewbefund 5). Die echte CLI lehnt je nach Lage ebenfalls einzelne
    // Modi ab -- `bypassPermissions` etwa, wenn ein Flag es verbietet.
    const gueltig = ['acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan'];
    if (gueltig.includes(e.request.mode)) {
      schreibe({
        type: 'control_response',
        response: { subtype: 'success', request_id: e.request_id, response: { mode: e.request.mode } },
      });
    } else {
      schreibe({
        type: 'control_response',
        response: {
          subtype: 'error',
          request_id: e.request_id,
          error: `Cannot set permission mode: must be one of ${gueltig.join(', ')}`,
        },
      });
    }
    return;
  }

  // EINEN LAUFENDEN ZUG UNTERBRECHEN (Punkt 6). Gemessene Antwort der echten
  // CLI: `{still_queued: []}`.
  if (e.type === 'control_request' && e.request?.subtype === 'interrupt') {
    schreibe({
      type: 'control_response',
      response: { subtype: 'success', request_id: e.request_id, response: { still_queued: [] } },
    });
    return;
  }

  // Die Antwort auf unsere Freigabefrage.
  if (e.type === 'control_response' && e.response?.request_id === offeneFrage) {
    const erlaubt = e.response?.response?.behavior === 'allow';
    const grund = e.response?.response?.message ?? 'abgelehnt';
    schreibe({
      type: 'user',
      session_id: SITZUNG,
      message: {
        role: 'user',
        content: [{
          type: 'tool_result',
          tool_use_id: 'toolu_attrappe',
          content: erlaubt ? 'geschrieben' : grund,
          is_error: !erlaubt,
        }],
      },
    });
    schreibe({
      type: 'assistant',
      session_id: SITZUNG,
      message: {
        role: 'assistant',
        content: [{ type: 'text', text: erlaubt ? 'Die Datei ist angelegt.' : 'Verstanden, ich lasse es.' }],
      },
    });
    schreibe({
      type: 'result',
      subtype: 'success',
      session_id: SITZUNG,
      is_error: false,
      num_turns: zug,
      duration_ms: 5,
      usage: { input_tokens: 7, output_tokens: 11 },
      total_cost_usd: 0.0001,
    });
    offeneFrage = '';
    return;
  }

  if (e.type !== 'user') return;
  zug += 1;

  if (last > 0) {
    lastAbspielen();
    return;
  }

  if (zug === 1) {
    for (const ereignis of mitschnittZeilen()) schreibe(ereignis);
    return;
  }

  if (!fragtNach) {
    schreibe({
      type: 'result', subtype: 'success', session_id: SITZUNG, is_error: false,
      num_turns: zug, duration_ms: 3, usage: { input_tokens: 1, output_tokens: 1 }, total_cost_usd: 0,
    });
    return;
  }

  // Die Freigabefrage -- dieselbe Form wie die gemessene der echten CLI.
  offeneFrage = `attrappe-frage-${zug}`;
  schreibe({
    type: 'assistant',
    session_id: SITZUNG,
    message: {
      role: 'assistant',
      content: [{
        type: 'tool_use',
        id: 'toolu_attrappe',
        name: 'Write',
        input: { file_path: '/tmp/attrappe/neu.txt', content: 'hallo' },
      }],
    },
  });
  schreibe({
    type: 'control_request',
    request_id: offeneFrage,
    request: {
      subtype: 'can_use_tool',
      tool_name: 'Write',
      display_name: 'Write',
      input: { file_path: '/tmp/attrappe/neu.txt', content: 'hallo' },
      description: 'neu.txt',
      permission_suggestions: [{ type: 'setMode', mode: 'acceptEdits', destination: 'session' }],
      tool_use_id: 'toolu_attrappe',
    },
  });
});

// NICHT sofort raus, wenn die Traegheit eingeschaltet ist: `beende()` schliesst
// erst stdin und schickt dann SIGTERM. Ginge dieser Prozess schon beim
// Schliessen von stdin, waere die Messung zu Befund B5 wertlos -- sie faende
// nie ein Kind vor, auf das die App haette warten muessen.
rl.on('close', langsamRaus);
