#!/usr/bin/python3
# Baut die stdin-Eingabe fuer `wb-pane-write mobil-*` aus umschlag.json:
#   stdin-bauen.py <request_id> <aktion> <maschine> <socket> <pane> [text]
# Der Body enthaelt die gebundenen Werte, damit die Eingabe so aussieht wie eine echte;
# die Signatur ist eine ERFUNDENE Zeichenfolge -- hier gibt es kein Schluesselmaterial.
import base64
import hashlib
import json
import os
import sys

request_id, aktion, maschine, sock, pane = sys.argv[1:6]
text = sys.argv[6] if len(sys.argv) > 6 else ""
body = json.dumps({"aktion": aktion, "maschine": maschine, "socket": sock, "pane": pane,
                   "text": text}, sort_keys=True).encode("utf-8")
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "umschlag.json"), encoding="utf-8") as f:
    umschlag = json.load(f)
umschlag["request_id"] = request_id
umschlag["body_sha256"] = hashlib.sha256(body).hexdigest()
sys.stdout.write(json.dumps({"umschlag": umschlag, "body_b64": base64.b64encode(body).decode("ascii")}))
