#!/usr/bin/env python3
"""Das Ende des Controllerdienstes: nach `close` ist der Faden weg und der Prozess haengt nicht.

Ursache, gegen die diese Proben stehen (gemessen 20./21.09.2026): `bind_agent` startete je
Bindung einen Dienstfaden, der bis zum Sitzungsende (300 s) in einem `recv` wartete, und
`close` schloss den Serversocket aus einem fremden Faden.  Steht der Faden gerade im `poll`
auf derselben Dateinummer, weckt ihn das nicht -- die Nummer wird sofort neu vergeben, und der
Faden wartet die vollen 300 s.  Weil der Faden kein Daemon war, wartete `threading._shutdown`
beim Beenden auf ihn, und der Testlauf brach mit 124 ab.

Ohne die Reparatur sind alle drei Proben rot: der Faden lebt nach `close` weiter, und die
beiden Kindprozesse enden nicht binnen weniger Sekunden.
"""

import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(SHELL))
import agents_controller as ac
import agents_data as ad
from herkunft_fixture import aufbau_herkunft

# Der Kindprozess bindet einen Agenten und endet; `close` nur, wenn es als Argument steht.
# Der Klient wird bewusst NICHT geschlossen: dann bleibt dem Dienstfaden nur das Weck-Paar.
KIND = """import sys
sys.path.insert(0, sys.argv[1])
import agents_controller as ac
controller = ac.AgentController(sys.argv[2], "run-1", lambda binding: True)
client = controller.bind_agent("m1", "mitglied")
if sys.argv[3] == "close":
    controller.close()
print("fertig", flush=True)
"""

FRIST = 20.0   # Frist des Kindprozesses; ohne Reparatur laeuft er in die Sitzungsfrist (300 s)
SCHNELL = 10.0  # "binnen weniger Sekunden": so lange darf ein sauberes Ende hoechstens dauern


class ControllerEndeTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="controller-ende-")
        self.world = Path(self.tmp.name) / "welt"
        with aufbau_herkunft(ad) as aufbau:
            ad.create_world(self.world, name="Ende", main_name="main", sender=aufbau)
            ad.create_agent(self.world, "m1", "mitglied", None, "Mitglied m1",
                            None, None, None, None, None, None, "lokal", aufbau, None)
        self.kind = Path(self.tmp.name) / "kind.py"
        self.kind.write_text(KIND, encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def dienstfaeden(self):
        return [t for t in threading.enumerate() if t.name == "agents-controller" and t.is_alive()]

    def kind_laufen_lassen(self, modus):
        start = time.monotonic()
        try:
            fertig = subprocess.run([sys.executable, str(self.kind), str(SHELL), str(self.world), modus],
                                    text=True, capture_output=True, timeout=FRIST)
        except subprocess.TimeoutExpired:
            self.fail("Der Kindprozess (%s) endete nicht binnen %.0f s; der Dienstfaden haelt ihn auf"
                      % (modus, FRIST))
        return time.monotonic() - start, fertig

    def test_close_beendet_den_dienstfaden_ohne_dass_der_klient_geschlossen_wird(self):
        vorher = len(self.dienstfaeden())
        controller = ac.AgentController(self.world, "run-1", lambda binding: True)
        client = controller.bind_agent("m1", "mitglied")
        self.assertEqual(len(self.dienstfaeden()), vorher + 1)
        start = time.monotonic()
        controller.close()          # ohne client.close(): nur das Weck-Paar holt den Faden heraus
        dauer = time.monotonic() - start
        self.assertLess(dauer, SCHNELL, "close hat %.1f s gebraucht" % dauer)
        self.assertEqual(self.dienstfaeden(), [])
        controller.join()           # wirft, wenn ein Faden ueberlebt
        client.close()

    def test_prozess_endet_nach_close_binnen_weniger_sekunden(self):
        dauer, fertig = self.kind_laufen_lassen("close")
        self.assertEqual(fertig.returncode, 0, fertig.stderr)
        self.assertIn("fertig", fertig.stdout)
        self.assertLess(dauer, SCHNELL, "Der Prozess brauchte %.1f s nach close" % dauer)
        self.assertNotIn("enden nicht binnen", fertig.stderr)

    def test_vergessener_controller_haelt_den_prozess_nicht_auf(self):
        dauer, fertig = self.kind_laufen_lassen("offen")
        self.assertEqual(fertig.returncode, 0, fertig.stderr)
        self.assertLess(dauer, SCHNELL, "Der Prozess brauchte %.1f s ohne close" % dauer)


if __name__ == "__main__":
    unittest.main()
