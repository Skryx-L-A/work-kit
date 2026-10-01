#!/usr/bin/env python3
"""stub-companion-daemon.py -- Schirm-Daemon fuer test-wb-companion.sh: ein
minimaler Nachbau des Companion-Protokolls (hello, request/response nach
~/AI/companion/app/protocol/schema/*.json) fuer report_status/ask_question/
report, damit wb-companion ohne den echten Companion-Daemon geprueft werden
kann.

Mehrere Verbindungen nacheinander, ein Thread je Verbindung, damit ein
einziger Prozess die ganze Testsuite bedient. Verhalten je Verbindung aus
<steuer>/modus (Vorgabe 'ok'), frisch gelesen bei jedem `hello`:
  ok             jede Anfrage bekommt status:"ok".
  not_supported  jede Anfrage bekommt status:"error", code "not_supported".
  drop           hello wird beantwortet, danach wird jede Verbindung bei der
                 ersten Anfrage ohne Antwort geschlossen ("Verbindung weg").
  reject_token   hello selbst wird mit `rejected` beantwortet.
Jede empfangene Anfrage wird als eine JSON-Zeile an <steuer>/log.jsonl
angehaengt (mit Dateisperre, weil mehrere Verbindungen gleichzeitig
schreiben koennen).

Aufruf: stub-companion-daemon.py <socket-pfad> <steuer-verzeichnis> <erwartetes-token>
Beendet sich bei SIGTERM (Vorgabe-Verhalten von Python) oder wenn
<steuer>/stop angelegt wird.
"""
import fcntl
import json
import os
import socket
import sys
import threading

SOCK, STEUER, ERWARTETES_TOKEN = sys.argv[1], sys.argv[2], sys.argv[3]


def modus_lesen():
    try:
        with open(os.path.join(STEUER, "modus"), encoding="utf-8") as f:
            return f.read().strip() or "ok"
    except OSError:
        return "ok"


def protokollieren(objekt):
    pfad = os.path.join(STEUER, "log.jsonl")
    with open(pfad, "a", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(objekt, ensure_ascii=False) + "\n")
        fcntl.flock(f, fcntl.LOCK_UN)


def zeile_lesen(conn, puffer):
    while b"\n" not in puffer[0]:
        try:
            stueck = conn.recv(65536)
        except OSError:
            return None
        if not stueck:
            return None
        puffer[0] += stueck
    zeile, rest = puffer[0].split(b"\n", 1)
    puffer[0] = rest
    try:
        return json.loads(zeile)
    except json.JSONDecodeError:
        return None


def zeile_senden(conn, objekt):
    try:
        conn.sendall((json.dumps(objekt, ensure_ascii=False) + "\n").encode("utf-8"))
    except OSError:
        pass


def bedienen(conn):
    puffer = [b""]
    try:
        hello = zeile_lesen(conn, puffer)
        if hello is None or hello.get("type") != "hello":
            return
        modus = modus_lesen()
        if modus == "reject_token" or hello.get("token") != ERWARTETES_TOKEN:
            zeile_senden(conn, {"type": "rejected", "code": "unauthorized",
                                "message": "Token nicht erkannt"})
            return
        zeile_senden(conn, {"type": "welcome", "protocol_version": 2, "role": "agent",
                            "daemon_version": "stub", "run_id": "stub-run",
                            "session_namespace": "reported:0"})
        while True:
            req = zeile_lesen(conn, puffer)
            if req is None:
                return
            protokollieren(req)
            if modus == "drop":
                return
            if modus == "not_supported":
                zeile_senden(conn, {"type": "response", "id": req.get("id"), "status": "error",
                                    "payload": {"code": "not_supported", "message": "vom Schirm abgelehnt"}})
            else:
                zeile_senden(conn, {"type": "response", "id": req.get("id"), "status": "ok", "payload": "ack"})
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    os.makedirs(STEUER, exist_ok=True)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(SOCK)
    s.listen(8)
    s.settimeout(0.3)
    while not os.path.exists(os.path.join(STEUER, "stop")):
        try:
            conn, _ = s.accept()
        except socket.timeout:
            continue
        threading.Thread(target=bedienen, args=(conn,), daemon=True).start()
    s.close()
    try:
        os.unlink(SOCK)
    except OSError:
        pass


if __name__ == "__main__":
    main()
