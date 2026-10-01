#!/usr/bin/env python3
"""Ein Stellvertreter, der sich wie eine Agenten-TUI verhaelt -- fuer
test-absende-pruefung.sh.

Warum kein Zeilen-REPL wie in test-registry.sh: der Auftragstext von pi-worker ist
IMMER mehrzeilig (das Protokoll haengt hinter zwei Leerzeilen), und eine Shell im
Zeilenmodus liest daraus mehrere Zeilen, also mehrere vermeintliche Absendungen.
Eine echte TUI liest im Rohmodus und erkennt an den Klammern des Bracketed Paste,
dass eingefuegter Text kein Absenden ist -- genau das macht dieser Stellvertreter,
und nur so laesst sich zaehlen, wie oft WIRKLICH Enter gedrueckt wurde.

Spielarten (FAKE_KIND):
  sofort      Beim Enter ist die Eingabezeile augenblicklich wieder frei (claude).
  langsam     Der abgeschickte Text wird -- wie bei aider -- mit DEMSELBEN Zeichen
              wiederholt, mit dem die Eingabezeile gezeichnet wird, es laeuft ein
              Spinner, und erst nach FAKE_BUSY Sekunden ist die Zeile wieder frei.
              Waehrend dieser Zeit gibt es KEINE Eingabezeile, auch das wie bei aider.
  hart        Der Text wird nie angenommen, und der Bildschirm ruehrt sich nicht mehr.
  nie         Der Bildschirm bleibt in Bewegung, die Eingabezeile wird nie frei.
  korrekt     Wie 'sofort', aber der abgeschickte Text bleibt zusaetzlich als
              Verlaufszeile sichtbar -- fuer die INHALTSPRUEFUNG in
              test-absende-inhalt.sh: der wirklich gesendete Auftragstext muss im
              Pane auffindbar sein.
  verfaelscht Bildet den gemessenen Fall nach, in dem eine Terminal-Escape-Folge
              statt des Auftrags im Pane ankam: SCHON WAEHREND des Einfuegens
              zeigt die Eingabezeile nicht den echten, ankommenden Text, sondern
              eine feste Zeichenkette (als sei die Terminalantwort dem Paste
              beigemischt worden) -- der echte Text steht damit zu keinem
              Zeitpunkt im Pane, auch nicht kurz. Beim Enter leert sich die Zeile
              genauso wie bei 'korrekt', die Zeichenkette bleibt als
              Verlaufszeile stehen.
  taub        Haerterer Fall als 'hart' (2026-08-20, Nachtrag zum Zustellungs-
              Auftrag, gemessen: Pane %27 nahm ueberhaupt keine Taste mehr an,
              weder C-u noch Escape noch Backspace, bei lebendigem Prozess). Die
              TUI zeigt einen leeren Prompt und liest weiter von stdin (der
              Prozess LEBT), verwirft aber jedes gelesene Byte ungesehen -- kein
              Zeichen erreicht buf, auch C-u nicht. Anders als 'hart' (das C-u
              noch verarbeitet, nur Enter nicht) modelliert das den gemessenen
              Befund, dass GAR KEINE Taste mehr wirkt.
  ueberflutet Nachbildung der vier Fehlalarme vom 2026-09-09 bei Harness pi: wie
              'korrekt' (der Auftragstext bleibt als Verlaufszeile stehen), aber
              UNMITTELBAR danach flutet die TUI den Bildschirm mit tausenden
              Zeilen (Gedankengang- oder Werkzeugausgabe, kein Kunstgriff -- ein
              Auftrag, der eine groessere Datei liest, produziert das ohne
              Weiteres in Sekundenbruchteilen). Gestellt gemessen (eigener
              tmux-Socket, Pane 80x14): das schiebt die Marker-Zeile aus den
              letzten 2000 ROH-Zeilen des Panes heraus, obwohl der Auftrag
              laengst angekommen war -- siehe test-absende-inhalt.sh Fall 4 und
              KAPTUR_ZEILEN in pi-worker.
  umgebrochen Nachbildung des Fehlalarms vom 2026-09-09 (Spawn 'browserbase', pi
              v0.84, Pane 170 Spalten): der Auftrag kam vollstaendig an und der
              Worker lief, aber pi zeichnet den Verlauf mit EIGENEM wortweisen
              Umbruch -- eine erste Auftragszeile, die laenger ist als pis Breite,
              steht als zwei Verlaufszeilen im Pane, die zweite mit einem
              fuehrenden Leerzeichen. `capture-pane -J` setzt nur TERMINAL-Umbrueche
              wieder zusammen, nicht diese; zeile_da() in pi-worker fand die erste
              Zeile deshalb nie am Stueck. Breite ueber FAKE_UMBRUCH (Vorgabe 60).
  zerfallen   Nachbildung des gemeldeten aider-Ausfalls (2026-08-22): die ERSTEN
              ZERFALLEN_DROP Bytes eines Pastes gehen verloren (wie bei einem
              vollgelaufenen Kernel-Puffer unter Last), der Rest -- einschliesslich
              der letzten (Protokoll-)Zeile mit dem Marker -- kommt unversehrt an.
              Die Bytes werden schon BEIM LESEN verworfen (nicht erst beim
              Anzeigen): so fehlt der Zeilenanfang auch in der Live-Anzeige
              WAEHREND des Einfuegens, genau wie bei einem echten Bytefehler auf
              der Uebertragungsstrecke -- ein Verstuemmeln erst in absenden() waere
              zu spaet gewesen, weil tmux die volle Live-Anzeige laengst in seinen
              Verlauf geschrieben haette, bevor ueberhaupt Enter faellt. Der alte,
              marker-only Beleg in pi-worker haette den fehlenden Zeilenanfang
              trotzdem als 'Submission verifiziert' durchgehen lassen, weil der
              Marker (das Dateiende der Protokoll-Zeile) unversehrt blieb; siehe
              test-absende-inhalt.sh Fall 3.

FAKE_PROMPT ist das Zeichen der Eingabezeile, FAKE_LOG die Datei, in die jedes
EMPFANGENE Enter geschrieben wird (eine Zeile 'ENTER' je Tastendruck).

FAKE_RAW (2026-08-20, Stresstest der Zustellung) ist eine Datei, in die JEDES
gelesene Byte unveraendert mitgeschrieben wird -- vor jeder Deutung, vor dem
Zusammensetzen halber Escape-Folgen, vor dem Ersetzen der Zeilenumbrueche
innerhalb eines Pastes. Das ist die einzige Quelle, an der sich WORTGLEICH
pruefen laesst, was im Pane ankam: die TEXT-Zeile von merke_text() taugt dafuer
nicht, weil sie Zeilenumbrueche laengst durch ' / ' ersetzt hat und ein
Auftragstext, der selbst ' / ' enthaelt, davon nicht mehr zu unterscheiden
waere. Der Auftragstext traegt im Betrieb Pfade, Befehle und Fehlermeldungen --
da entscheidet jedes Zeichen.
"""

import os
import sys
import termios
import time
import tty

KIND = os.environ.get("FAKE_KIND", "sofort")
PROMPT = os.environ.get("FAKE_PROMPT", "❯")
BUSY = float(os.environ.get("FAKE_BUSY", "8") or 0)
LOG = os.environ.get("FAKE_LOG", "")
RAW = os.environ.get("FAKE_RAW", "")
# Breite, an der die Spielart 'umgebrochen' ihre Verlaufszeilen selbst umbricht.
UMBRUCH_BREITE = int(os.environ.get("FAKE_UMBRUCH", "60") or 60)
# FAKE_UMBRUCH_HART=1: auch mitten im Wort umbrechen (pi bei einem Pfad, der laenger
# ist als die Zeile -- Fehlalarm 2026-09-10, Spawn 'ausrollen', Pane 80 Spalten).
UMBRUCH_HART = os.environ.get("FAKE_UMBRUCH_HART", "") == "1"

# Das gemessene Rauschen selbst (2026-08-17): eine Device-Attributes-Antwort, die
# statt des Auftrags im Pane stand, waehrend die Eingabezeile trotzdem leer wirkte.
RAUSCHEN = "?1;2;4c>84;0;0c>|tmux 3.7b"

buf = ""            # was in der Eingabezeile steht
echo = []           # wiederholte Auftragszeilen (die aider-Form)
spinner = ""
eingabezeile = True


def zeichne():
    teile = ["\x1b[H\x1b[2J", "Fake-TUI (%s)\r\n" % KIND]
    for z in echo:
        teile.append("%s %s\r\n" % (PROMPT, z))
    if spinner:
        teile.append("   %s\r\n" % spinner)
    if eingabezeile:
        # 'verfaelscht': schon WAEHREND des Tippens/Einfuegens zeigt die Zeile nie
        # den echten Puffer, sondern das Rauschen -- der echte Text darf zu keinem
        # Zeitpunkt im Pane (und damit im tmux-Verlauf) auftauchen, sonst misst der
        # Test nur die eigene Positivprobe zweimal statt den nachgestellten Fehler.
        anzeige = RAUSCHEN if (KIND == "verfaelscht" and buf) else buf
        if KIND == "umgebrochen" and anzeige:
            # Auch der EDITOR bricht bei pi selbst um, nicht erst der Verlauf:
            # waehrend des Einfuegens darf der Text ebenfalls nie am Stueck im
            # Pane stehen, sonst laege er ueber den Terminal-Umbruch (-J) doch
            # wieder zusammengesetzt im tmux-Verlauf, und Fall 5 misst nichts.
            import textwrap
            zeilen = []
            for z in anzeige.split(" / "):
                zeilen.extend(textwrap.wrap(z, width=UMBRUCH_BREITE, subsequent_indent=" ",
                                            break_long_words=UMBRUCH_HART, break_on_hyphens=False) or [z])
            anzeige = "\r\n ".join(zeilen)
        teile.append("%s %s" % (PROMPT, anzeige))
    sys.stdout.write("".join(teile))
    sys.stdout.flush()


def merke_enter():
    if not LOG:
        return
    try:
        with open(LOG, "a") as f:
            f.write("ENTER\n")
    except OSError:
        pass


def merke_text(inhalt):
    # Zusaetzlich zum blossen Zaehlen (merke_enter): der WORTGLEICHE Inhalt der
    # Eingabezeile im Moment des Enter, fuer test-zustellung-eingabezeile.sh
    # (2026-08-20) -- ob liegengebliebener Text sich mit dem neuen Auftrag
    # vermischt hat, sieht man nur am tatsaechlichen Inhalt, nicht an einer
    # blossen Zaehlung. Additiv: die beiden bestehenden Tests lesen nur
    # '^ENTER'-Zeilen und ignorieren diese TEXT-Zeile.
    if not LOG:
        return
    try:
        with open(LOG, "a") as f:
            f.write("TEXT\t%s\n" % inhalt.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t"))
    except OSError:
        pass


def beschaeftigt(sekunden, endlos=False):
    """Sichtbar arbeiten: der Spinner aendert sich, es gibt keine Eingabezeile."""
    global spinner, eingabezeile
    eingabezeile = False
    i = 0
    ende = time.time() + sekunden
    while endlos or time.time() < ende:
        spinner = "arbeitet %d" % i
        zeichne()
        i += 1
        time.sleep(0.25)


def absenden():
    global buf, echo, spinner, eingabezeile
    merke_enter()
    merke_text(buf)
    if KIND == "hart":
        return                      # nichts geschieht, der Text bleibt stehen
    if KIND == "sofort":
        buf = ""
        zeichne()
        return
    if KIND == "korrekt":
        # wie 'sofort', aber der Text bleibt -- als Verlaufszeile, nicht mehr in der
        # Eingabezeile -- sichtbar stehen, wie bei einer echten TUI, die das
        # abgeschickte Nutzer-Turn im Gespraechsverlauf zeigt.
        echo = [z for z in buf.split(" / ") if z.strip()] or ["(kein Text angekommen)"]
        buf = ""
        zeichne()
        return
    if KIND == "verfaelscht":
        # Die Eingabezeile leert sich genauso wie bei 'korrekt' -- die Verlaufszeile
        # zeigt weiterhin das Rauschen, nicht den (laengst verworfenen) echten Text.
        echo = [RAUSCHEN]
        buf = ""
        zeichne()
        return
    if KIND == "zerfallen":
        # buf traegt die Verstuemmelung schon (siehe ZERFALLEN_DROP im Leseloop) --
        # hier wie 'korrekt' nur noch als eigene Verlaufszeilen anzeigen.
        echo = [z for z in buf.split(" / ") if z.strip()] or ["(kein Text angekommen)"]
        buf = ""
        zeichne()
        return
    if KIND == "umgebrochen":
        # Wie 'korrekt', aber die TUI bricht jede Verlaufszeile SELBST um (pi:
        # wortweise an der eigenen Breite, Folgezeilen mit einem fuehrenden
        # Leerzeichen). Das ist kein Terminal-Umbruch -- `capture-pane -J` setzt
        # nichts zusammen, im Verlauf stehen echte Zeilenenden. Siehe
        # test-absende-inhalt.sh Fall 5.
        import textwrap
        echo = []
        for z in buf.split(" / "):
            if not z.strip():
                continue
            echo.extend(textwrap.wrap(z, width=UMBRUCH_BREITE, subsequent_indent=" ",
                                      break_long_words=UMBRUCH_HART, break_on_hyphens=False)
                        or [z])
        echo = echo or ["(kein Text angekommen)"]
        buf = ""
        zeichne()
        return
    if KIND == "ueberflutet":
        # Wie 'korrekt': der Auftragstext bleibt als Verlaufszeile sichtbar.
        # Danach flutet die TUI den Bildschirm -- ROH, nicht ueber zeichne()'s
        # Voll-Neuzeichnen, denn genau das natuerliche Scrollen (kein Clear, nur
        # ueber den unteren Rand hinausschreiben) ist es, das echte Zeilen in
        # tmux' Verlauf schiebt und die Marker-Zeile darin nach oben verdraengt.
        # 'echo' wird NACH der Flut geleert (2026-09-09, Fundstelle: die erste
        # Fassung dieses Tests bestand trotz kaputtem -2000-Code, weil die
        # Leseschleife nach JEDEM gelesenen Byteblock ohnehin noch einmal
        # zeichne() aufruft -- ein volles Clear+Neuzeichnen, das 'echo' und
        # damit den Marker ein zweites Mal direkt UNTER der Flut ausgegeben
        # haette, egal ob absenden() selbst noch ein zeichne() anhaengt oder
        # nicht). Eine echte TUI, die laengst tausende Zeilen weitergescrollt
        # ist, zeigt die urspruengliche Nutzer-Nachricht in ihrem aktuellen
        # Ausschnitt auch nicht mehr eigens an -- nur noch der (echte) tmux-
        # Verlauf traegt sie. Der einzige verbleibende Beleg ist deshalb genau
        # die EINE Verlaufszeile aus dem zeichne()-Aufruf VOR der Flut.
        echo = [z for z in buf.split(" / ") if z.strip()] or ["(kein Text angekommen)"]
        buf = ""
        zeichne()
        flut = "".join(
            "Gedankengang-Zeile %05d: Auftrag ist angekommen und wird bearbeitet.\r\n" % i
            for i in range(4000)
        )
        sys.stdout.write(flut)
        sys.stdout.flush()
        echo = []
        eingabezeile = True
        return
    # langsam / nie: der Auftrag wird wiederholt, dann wird sichtbar gearbeitet.
    echo = [z for z in buf.split(" / ") if z.strip()] or ["(kein Text angekommen)"]
    buf = ""
    if KIND == "nie":
        # Die Eingabezeile wird nie wieder frei: die Wiederholung bleibt stehen und
        # taeuscht damit dauerhaft einen haengenden Prompt vor, waehrend sich der
        # Bildschirm weiter bewegt.
        beschaeftigt(0, endlos=True)
        return
    beschaeftigt(BUSY)
    echo = []
    spinner = ""
    eingabezeile = True
    zeichne()


def main():
    global buf
    fd = sys.stdin.fileno()
    try:
        alt = termios.tcgetattr(fd)
    except termios.error:
        alt = None
    if alt is not None:
        tty.setraw(fd)
    try:
        # Den Klammer-Einfuege-Modus ANFORDERN. Ohne das schickt `tmux paste-buffer -p`
        # den Text ohne Klammern (es setzt sie nur, wenn die Anwendung sie verlangt
        # hat), und jeder Zeilenumbruch im Auftragstext saehe aus wie ein Enter --
        # gemessen 2026-08-08: der Stellvertreter zaehlte doppelt so viele Enter, wie
        # getippt wurden. Jede echte Agenten-TUI fordert diesen Modus an.
        sys.stdout.write("\x1b[?2004h")
        sys.stdout.flush()
        zeichne()
        im_paste = False
        rest = b""
        # ZERFALLEN_DROP: nur beim ALLERERSTEN Paste dieser Sitzung wirksam (kein
        # Zaehler je Paste) -- ein zweites Einfuegen (etwa ein erneuter Auftrag im
        # selben Pane) soll nicht ebenfalls verstuemmelt werden, das gemessene
        # Schadensbild betraf genau EINEN Spawn.
        zerfallen_uebrig = 20 if KIND == "zerfallen" else 0
        while True:
            try:
                daten = os.read(fd, 4096)
            except OSError:
                break
            if not daten:
                break
            if RAW:
                # Unveraendert und VOR jeder Deutung -- auch fuer 'taub', denn
                # gerade dort ist die Frage "kam es ueberhaupt an der Anwendung
                # an?" von "wurde es verarbeitet?" zu trennen.
                try:
                    with open(RAW, "ab") as f:
                        f.write(daten)
                except OSError:
                    pass
            if KIND == "taub":
                # Gelesen (der Prozess LEBT und blockiert nicht), aber verworfen --
                # kein einziges Byte erreicht buf, auch C-u nicht. Siehe Kopfkommentar.
                continue
            daten = rest + daten
            rest = b""
            i = 0
            while i < len(daten):
                # Die Klammern des Bracketed Paste. Ein halb angekommener Marker
                # wandert in den Rest und wird beim naechsten Lesen fortgesetzt.
                if daten[i:i + 6] == b"\x1b[200~":
                    im_paste = True
                    i += 6
                    continue
                if daten[i:i + 6] == b"\x1b[201~":
                    im_paste = False
                    i += 6
                    continue
                if daten[i:i + 1] == b"\x1b" and len(daten) - i < 6:
                    rest = daten[i:]
                    i = len(daten)
                    break
                c = daten[i:i + 1]
                i += 1
                if c in (b"\r", b"\n"):
                    if im_paste:
                        # Zeilenumbruch INNERHALB eines Pastes ist Text, kein Absenden.
                        buf += " / "
                        continue
                    absenden()
                    continue
                if c == b"\x1b":
                    continue        # sonstige Steuerfolge: nicht anzeigen
                if c == b"\x15":
                    # C-u (2026-08-20, fuer test-zustellung-eingabezeile.sh): wie in
                    # readline/prompt_toolkit die Eingabezeile leeren, nicht als
                    # Steuerzeichen in buf mitschreiben -- sonst haette die Taste, mit
                    # der pi-worker jetzt vor jedem Absenden liegengebliebenen Text
                    # entfernt, in diesem Stellvertreter gar keine Wirkung.
                    buf = ""
                    continue
                try:
                    zeichen = c.decode("utf-8", "ignore")
                except Exception:
                    zeichen = ""
                if zeichen and im_paste and zerfallen_uebrig > 0:
                    # Verworfen, wie ein Byte, das nie am Ziel ankam -- VOR jeder
                    # Anzeige, damit weder die Live-Eingabezeile waehrend des
                    # Einfuegens noch die spaetere Verlaufszeile das fehlende
                    # Zeichen je gezeigt haetten.
                    zerfallen_uebrig -= 1
                    continue
                buf += zeichen
            zeichne()
    finally:
        try:
            sys.stdout.write("\x1b[?2004l")
            sys.stdout.flush()
        except Exception:
            pass
        if alt is not None:
            try:
                termios.tcsetattr(fd, termios.TCSADRAIN, alt)
            except termios.error:
                pass


main()
