#!/usr/bin/env python3
"""fake-ollama.py -- Test-Doppel fuer den 'ollama'-Client, nur fuer
test-consistency-config-claims.sh (Check 5, provider-bewusste
must_not_exceed_files-Pruefung). Versteht ausschliesslich 'list' und
'show <tag> --modelfile', mehr braucht Check 5 nicht.

Gesteuert ueber zwei Umgebungsvariablen, damit ein einziges Fixture-Skript
fuer alle Testfaelle reicht:

  FAKE_OLLAMA_AVAILABLE=0   'list' liefert Exit-Code 1 -- simuliert einen
                            nicht erreichbaren Daemon oder ein fehlendes
                            Binary. Fehlt die Variable oder steht sie auf
                            irgendetwas ausser '0', ist 'list' erfolgreich.
  FAKE_OLLAMA_SHOW_DIR=dir  Verzeichnis mit einer Datei je bekanntem Tag
                            (Dateiname = Tag, '/' und ':' durch '_' ersetzt).
                            Der Dateiinhalt ist die Ausgabe von
                            'ollama show <tag> --modelfile'. Kein Treffer
                            -> Exit-Code 1 (Tag unbekannt).
"""
import os
import sys


def sanitize(tag):
    return tag.replace("/", "_").replace(":", "_")


def main():
    args = sys.argv[1:]
    if not args:
        return 2
    if os.environ.get("FAKE_OLLAMA_AVAILABLE", "1") == "0":
        sys.stderr.write("fake-ollama: nicht erreichbar (Testmodus)\n")
        return 1
    if args[0] == "list":
        print("NAME\tID\tSIZE\tMODIFIED")
        return 0
    if args[0] == "show" and len(args) >= 2:
        tag = args[1]
        show_dir = os.environ.get("FAKE_OLLAMA_SHOW_DIR")
        if not show_dir:
            return 1
        path = os.path.join(show_dir, sanitize(tag))
        if not os.path.isfile(path):
            sys.stderr.write("fake-ollama: unbekanntes Modell '%s'\n" % tag)
            return 1
        with open(path) as f:
            sys.stdout.write(f.read())
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
