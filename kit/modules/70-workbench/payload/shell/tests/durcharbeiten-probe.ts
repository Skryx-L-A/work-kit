// Prüfstand für pi-extensions/wb-durcharbeiten.ts — gefahren von
// shell/tests/test-durcharbeiten-stopp.sh über `deno run`.
//
// Die Erweiterung läuft sonst nur in einer echten pi-Sitzung. Hier bekommt sie
// eine Attrappe von `pi`, die dieselben Ereignisse liefert, die eine echte
// Sitzung liefert — die Feldnamen stammen aus einer MESSUNG an einem echten
// Worker (21.09., Protokoll in der Sitzungsnotiz), nicht aus einer Vermutung:
// ein abgebrochener Zug erscheint als `message_end` mit role "assistant" und
// `stopReason: "aborted"`.
//
// Ausgegeben wird eine Zeile je Fall: "<fall> anstoesse=<n>". Der Shell-Test
// darüber entscheidet, welche Zahl richtig ist.

type Hoerer = (ev: unknown, ctx: unknown) => unknown;

const auftrag = {
  role: "user",
  content: "Auftrag. Ergebnis nach ~/.pi-workers/results/probe/x.md schreiben, dann DONE.",
};

function assistentOhneWerkzeug(stopReason?: string) {
  return {
    role: "assistant",
    content: [{ type: "text", text: "Ich schreibe jetzt die Endfassung." }],
    stopReason,
  };
}

async function fall(name: string, rolleImPane: string, abbruch: boolean) {
  // Die Rolle des Panes liest die Erweiterung über tmux. Im Prüfstand steht
  // stattdessen eine Attrappe im PATH, die der Shell-Test angelegt hat; welche
  // Rolle sie meldet, sagt diese Umgebungsvariable.
  Deno.env.set("WB_PROBE_ROLLE", rolleImPane);
  Deno.env.set("TMUX_PANE", "%1");

  const hoerer = new Map<string, Hoerer[]>();
  let anstoesse = 0;
  const pi = {
    on(name: string, h: Hoerer) {
      const liste = hoerer.get(name) ?? [];
      liste.push(h);
      hoerer.set(name, liste);
    },
    sendUserMessage(_text: string) {
      anstoesse += 1;
    },
    registerCommand(_n: string, _o: unknown) {},
  };

  const mod = await import(`../../pi-extensions/wb-durcharbeiten.ts?fall=${name}`);
  mod.default(pi as never);

  const feuere = async (ereignis: string, ev: unknown) => {
    for (const h of hoerer.get(ereignis) ?? []) await h(ev, ctx);
  };
  const ctx = {
    isIdle: () => true,
    hasPendingMessages: () => false,
    ui: { notify: () => {} },
  };

  await feuere("message_end", { message: auftrag });
  await feuere("message_end", { message: assistentOhneWerkzeug(abbruch ? "aborted" : "stop") });
  await feuere("agent_settled", {});

  console.log(`${name} anstoesse=${anstoesse}`);
}

await fall("worker-normal", "worker", false);
await fall("worker-abgebrochen", "worker", true);
await fall("orchestrator-normal", "orchestrator", false);
