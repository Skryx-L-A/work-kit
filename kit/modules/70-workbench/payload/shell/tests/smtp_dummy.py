#!/usr/bin/env python3
"""Lokaler SMTP-Dummy fuer Tests des Sendewegs (test-wb-agents-freigaben.py und der Zug auf host2).

Lauscht nur auf 127.0.0.1, Port 0 (das System waehlt), ohne TLS. Er kennt EHLO, AUTH PLAIN/LOGIN, MAIL, RCPT,
DATA, RSET, NOOP und QUIT. Die Anmeldung vergleicht er mit einem vorgegebenen Testpasswort und merkt sich nur, ob
sie stimmte; das Passwort selbst speichert und schreibt er nie. Nichts verlaesst die Maschine.

Als Programm: ``smtp_dummy.py <ordner>`` schreibt den Port nach ``<ordner>/port``, jede angenommene Mail als Zeile
nach ``<ordner>/mails.jsonl`` (Absender, Empfaenger, Kopfzeilen, SHA-256 des Rumpfs) und laeuft bis SIGTERM.
Das Testpasswort liest es aus ``<ordner>/passwort``.
"""
from __future__ import annotations

import base64
import email
import hashlib
import json
import signal
import socketserver
import sys
import threading
from pathlib import Path


class _Handler(socketserver.StreamRequestHandler):
    timeout = 30

    def _zeile(self, text: str) -> None:
        self.wfile.write((text + "\r\n").encode("utf-8"))

    def _pruefen(self, benutzer: str, passwort: str) -> bool:
        ok = benutzer == self.server.benutzer and passwort == self.server.passwort
        self._zeile("235 2.7.0 angemeldet" if ok else "535 5.7.8 Anmeldung abgelehnt")
        return ok

    def handle(self) -> None:
        server = self.server
        angemeldet, absender, empfaenger = False, None, []
        self._zeile("220 dummy ESMTP")
        while True:
            roh = self.rfile.readline(65536)
            if not roh:
                return
            zeile = roh.decode("utf-8", "replace").rstrip("\r\n")
            befehl = zeile.split(" ", 1)[0].upper()
            if befehl in ("EHLO", "HELO"):
                self.wfile.write(b"250-dummy\r\n250-AUTH PLAIN LOGIN\r\n250-8BITMIME\r\n250 SMTPUTF8\r\n")
            elif befehl == "AUTH":
                teile = zeile.split()
                art = teile[1].upper() if len(teile) > 1 else ""
                try:
                    if art == "PLAIN":
                        if len(teile) > 2:
                            token = teile[2]
                        else:
                            self._zeile("334 ")
                            token = self.rfile.readline(65536).decode().strip()
                        _, benutzer, passwort = base64.b64decode(token).decode("utf-8").split("\0", 2)
                    elif art == "LOGIN":
                        self._zeile("334 VXNlcm5hbWU6")
                        benutzer = base64.b64decode(self.rfile.readline(65536).strip()).decode("utf-8")
                        self._zeile("334 UGFzc3dvcmQ6")
                        passwort = base64.b64decode(self.rfile.readline(65536).strip()).decode("utf-8")
                    else:
                        self._zeile("504 5.5.4 unbekannt")
                        continue
                except (ValueError, UnicodeDecodeError):
                    self._zeile("501 5.5.2 kaputt")
                    continue
                angemeldet = self._pruefen(benutzer, passwort)
                with server.sperre:
                    server.anmeldungen.append({"benutzer": benutzer, "ok": angemeldet})
            elif befehl == "MAIL":
                if not angemeldet:
                    self._zeile("530 5.7.0 erst anmelden")
                    continue
                absender = zeile.partition(":")[2].strip().split(" ")[0].strip("<>")
                empfaenger = []
                self._zeile("250 2.1.0 ok")
            elif befehl == "RCPT":
                adresse = zeile.partition(":")[2].strip().split(" ")[0].strip("<>")
                if adresse in server.ablehnen:
                    self._zeile("550 5.1.1 unbekannt")
                else:
                    empfaenger.append(adresse)
                    self._zeile("250 2.1.5 ok")
            elif befehl == "DATA":
                self._zeile("354 los")
                daten = bytearray()
                while True:
                    teil = self.rfile.readline(1024 * 1024)
                    if not teil or teil in (b".\r\n", b".\n"):
                        break
                    daten += teil[1:] if teil.startswith(b"..") else teil
                nachricht = email.message_from_bytes(bytes(daten))
                rumpf = (nachricht.get_payload(decode=True) or b"").replace(b"\r\n", b"\n")
                eintrag = {"von": absender, "an": list(empfaenger),
                           "kopf": {k: str(v) for k, v in nachricht.items()},
                           "rumpf_sha256": hashlib.sha256(rumpf).hexdigest(), "rumpf": rumpf.decode("utf-8", "replace")}
                with server.sperre:
                    server.mails.append(eintrag)
                    if server.ablage is not None:
                        with open(server.ablage, "a", encoding="utf-8") as stream:
                            stream.write(json.dumps({k: v for k, v in eintrag.items() if k != "rumpf"},
                                                    ensure_ascii=False) + "\n")
                self._zeile("250 2.0.0 angenommen")
            elif befehl in ("RSET", "NOOP"):
                self._zeile("250 2.0.0 ok")
            elif befehl == "QUIT":
                self._zeile("221 2.0.0 tschuess")
                return
            else:
                self._zeile("502 5.5.1 nicht unterstuetzt")


class SmtpDummy(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, passwort: str, benutzer: str = "postfach@example.org", ablage: Path | None = None):
        super().__init__(("127.0.0.1", 0), _Handler)
        self.passwort, self.benutzer, self.ablage = passwort, benutzer, ablage
        self.mails: list[dict] = []
        self.anmeldungen: list[dict] = []
        self.ablehnen: set[str] = set()
        self.sperre = threading.Lock()
        self._thread = threading.Thread(target=self.serve_forever, name="smtp-dummy", daemon=True)

    @property
    def port(self) -> int:
        return self.server_address[1]

    def starten(self) -> "SmtpDummy":
        self._thread.start()
        return self

    def beenden(self) -> None:
        self.shutdown()
        self.server_close()
        self._thread.join(5)


def main(argv: list[str]) -> int:
    ordner = Path(argv[1])
    passwort = (ordner / "passwort").read_text(encoding="utf-8").strip()
    dummy = SmtpDummy(passwort, ablage=ordner / "mails.jsonl").starten()
    (ordner / "port").write_text("%d\n" % dummy.port)
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    stop.wait()
    dummy.beenden()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
