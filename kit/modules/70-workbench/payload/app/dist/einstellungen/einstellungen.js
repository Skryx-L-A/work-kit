"use strict";
(() => {
  // src/einstellungen/texte.ts
  var DE = {
    "fenster.titel": "Agent-Workbench \u2013 Einstellungen",
    // --- Die sieben Seiten ---------------------------------------------------
    "seite.sitzung.titel": "Sitzung",
    "seite.sitzung.wofuer": "Womit eine neue Sitzung anf\xE4ngt",
    "seite.sitzung.unterzeile": "Womit eine neue Sitzung startet, wo sie anf\xE4ngt zu arbeiten, und wie ihre Leiste sich verh\xE4lt. Die Worker stellst du hier nicht ein: die richtet der Orchestrator f\xFCr dich ein.",
    "seite.erlaubnisse.titel": "Erlaubnisse",
    "seite.erlaubnisse.wofuer": "Was die Agenten d\xFCrfen",
    "seite.erlaubnisse.unterzeile": "Was ein Agent ohne R\xFCckfrage tun darf und wo er angehalten wird. Jede Zeile hier nimmt eine Sicherung weg oder setzt eine ein; neben jeder steht ein Zeichen, hinter dem der Grund steht.",
    "seite.harnesses.titel": "Programme und Modelle",
    "seite.harnesses.wofuer": "Anmelden, anbinden, deckeln",
    "seite.harnesses.unterzeile": "Welche Agenten-Programme auf dieser Maschine laufen, ob sie angemeldet sind, wie die lokalen Modelle erreicht werden, und wie tief der Orchestrator ungefragt gehen darf.",
    "seite.maschinen.titel": "Maschinen",
    "seite.maschinen.wofuer": "Rechner und Auslastung",
    "seite.maschinen.unterzeile": "Wie viel Arbeit diese Maschine gleichzeitig tragen darf.",
    "seite.aufsicht.titel": "Aufsicht und Meldungen",
    "seite.aufsicht.wofuer": "Wache, Stillstand, Hinweise",
    "seite.aufsicht.unterzeile": "Was das Programm von sich aus beobachtet, ab wann es eingreift, und wor\xFCber es dich au\xDFerhalb des Fensters benachrichtigt.",
    "seite.aussehen.titel": "Aussehen",
    "seite.aussehen.wofuer": "Farben, Schrift, Sprache",
    "seite.aussehen.unterzeile": "Wie das Programm aussieht und wie viel auf den Bildschirm passt. Nichts hiervon \xE4ndert, was die Agenten tun.",
    "seite.programm.titel": "Programm",
    "seite.programm.wofuer": "Dateien, Abweichungen, Sicherung",
    "seite.programm.unterzeile": "Wo die Dateien dieses Programms liegen, was bei dir von der Auslieferung abweicht, und wie du den ganzen Stand sicherst, zur\xFCcksetzt oder auf einen anderen Rechner \xFCbertr\xE4gst.",
    // --- Gruppenüberschriften ------------------------------------------------
    "gruppe.sitzung.start": "Womit eine neue Sitzung anf\xE4ngt",
    "gruppe.sitzung.leiste": "Die Sitzungsleiste",
    "gruppe.sitzung.schliessen": "Beim Schlie\xDFen des Fensters",
    "gruppe.erlaubnisse.vorsicht": "Ohne R\xFCckfragen arbeiten",
    "gruppe.erlaubnisse.guards": "Sicherungen vor jedem Befehl",
    "gruppe.erlaubnisse.rueckfragen": "Befehle, bei denen zur\xFCckgefragt wird",
    "gruppe.erlaubnisse.geheimnisse": "Was nie gelesen wird",
    "gruppe.erlaubnisse.werkzeuge": "Werkzeuge und MCP-Server",
    "gruppe.harnesses.programme": "Die Programme auf dieser Maschine",
    "gruppe.harnesses.lokal": "Lokale Modelle",
    "gruppe.harnesses.schluessel": "Zugang zu den Anbietern",
    "gruppe.harnesses.deckel": "Wie tief der Orchestrator ungefragt gehen darf",
    "gruppe.maschinen.liste": "Rechner in dieser Liste",
    "gruppe.maschinen.last": "Wie viel diese Maschine tr\xE4gt",
    "gruppe.aufsicht.wache": "Die Kontextwache",
    "gruppe.aufsicht.stillstand": "Stillstand",
    "gruppe.aufsicht.meldungen": "Benachrichtigungen",
    "gruppe.aussehen.thema": "Hell und dunkel",
    "gruppe.aussehen.terminal": "Schrift und Rollen",
    "gruppe.aussehen.panes": "Wie die Worker im Fenster liegen",
    "gruppe.aussehen.sprache": "Sprache und Ansicht",
    "gruppe.programm.dateien": "Wo was liegt",
    "gruppe.programm.abweichungen": "Was bei dir anders ist",
    "gruppe.programm.sicherung": "Sichern, zur\xFCcksetzen, \xFCbertragen",
    "gruppe.programm.erststart": "Der gef\xFChrte erste Start",
    // --- Seite 1: Sitzung ----------------------------------------------------
    "feld.orchestratorHarness.name": "Programm im Hauptfenster",
    "feld.orchestratorHarness.wirkung": "Welche Agenten-CLI der Orchestrator-Pane startet. Die Zahl daneben nennt die Modelle, die dazu passen.",
    "feld.orchestratorHarness.info": "Jeder registrierte Adapter steht zur Wahl, nicht nur Claude Code und pi. \u201Efehlt hier\u201C hei\xDFt: das Programm dieses Adapters gibt es auf {maschine} nicht, ein Start liefe ins Leere. Gepr\xFCft wird dasselbe, was auch wb-state vor einem Start pr\xFCft: das Binary im Pfad.",
    "feld.orchestratorHarness.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "feld.orchestratorModel.name": "Modell der Sitzung",
    "feld.orchestratorModel.wirkung": "Womit der Orchestrator denkt, solange beim Start nichts anderes gesagt wird.",
    "feld.orchestratorModel.info": "{anzahl} Modelle mit der Rolle \u201EOrchestrator\u201C f\xFCr dieses Programm. Die Kennung rechts ist die, mit der auch die Werkzeuge starten. Ein Modell, dessen Programm hier fehlt, bleibt in der Liste stehen und ist rot markiert \u2013 damit man sieht, warum es nicht anl\xE4uft, statt es zu suchen.",
    "feld.orchestratorModel.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "feld.orchestratorModel.leerName": "Modell",
    "feld.orchestratorModel.leerWirkung": "F\xFCr dieses Programm ist kein Modell mit der Rolle \u201EOrchestrator\u201C eingetragen.",
    "feld.orchestratorModel.leerInfo": "Ein Modell mit dieser Rolle anlegen: wb-state models add-model \u2026 --roles orchestrator. Solange keins da ist, startet die Sitzung mit dem, was die CLI selbst vorgibt.",
    "satz.keinModellFuerProgramm": "Kein Modell mit Programm \u201E{harness}\u201C und Rolle \u201EOrchestrator\u201C.",
    "feld.orchestratorEffort.name": "Wie tief die Sitzung denkt",
    "feld.orchestratorEffort.wirkung": "Die Stufe, mit der der Orchestrator startet. Deine Wahl \u2013 jede Stufe, die das Programm annimmt.",
    "feld.orchestratorEffort.info": "Das ist die Wahl eines Menschen, und einen Menschen bindet kein Deckel: alle Stufen sind w\xE4hlbar, auch die \xFCber dem Deckel; sie tragen nur eine Markierung. Der Deckel ist etwas anderes \u2013 er ist die Selbstbindung des Orchestrators f\xFCr Worker, die er ohne R\xFCckfrage startet. Welche Stufen es \xFCberhaupt gibt, sagt das Programm selbst: gemessen an seiner Hilfe, nicht aus einer Liste abgeschrieben. H\xF6here Stufen kosten mehr Zeit und mehr Kontingent.",
    "feld.orchestratorEffort.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "feld.orchestratorKontext.name": "Kontextfenster",
    "feld.orchestratorKontext.wirkung": "Wie viel Text \u201E{modell}\u201C gleichzeitig im Kopf beh\xE4lt. Nur bei einem Modell, das hier auf der Maschine l\xE4uft \u2013 bei einem Modell aus der Cloud geh\xF6rt diese Zahl dem Anbieter.",
    "feld.orchestratorKontext.info": "Ein gr\xF6\xDFeres Fenster h\xE4lt mehr Zusammenhang, belegt aber dauerhaft mehr Grafikspeicher: der Bedarf steigt mit jedem Token, und was nicht mehr hineinpasst, l\xE4sst den Start scheitern. Deshalb steht an jeder Stufe, was sie braucht und was gerade frei ist. Gesperrt ist nichts: Stufen, f\xFCr die der Speicher heute nicht reicht, bleiben w\xE4hlbar und tragen einen Hinweis \u2013 die Entscheidung liegt bei dir, nicht beim Programm. Gemessen wird sie von wb-kontext, zusammen mit dem freien Speicher dieses Augenblicks. Die Wahl gilt f\xFCr den Orchestrator; \xFCber die Fenster der Worker entscheidet der Orchestrator selbst.",
    "feld.orchestratorKontext.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "wort.kontextToken": "{tokens} Token",
    "wort.kontextEmpfohlen": "empfohlen",
    "satz.kontextBedarf": "Braucht {bedarf} GiB.",
    "satz.kontextSpeicher": "Frei sind {frei} GiB, die Gewichte des Modells belegen davon {gewichte} GB.",
    "satz.kontextFremderWert": "Gespeichert sind {tokens} Token \u2013 diese Stufe bietet das gew\xE4hlte Modell nicht an. Solange keine der Stufen gew\xE4hlt ist, startet die Sitzung mit dem gespeicherten Wert.",
    "satz.kontextWirdErmittelt": "Die Stufen werden ermittelt \u2026",
    "satz.kontextNichtErmittelt": "Die Stufen lie\xDFen sich nicht ermitteln: {grund}. Solange das so ist, startet die Sitzung mit dem Fenster, das f\xFCr dieses Modell eingetragen ist.",
    "feld.newSessionDefaultDir.name": "Ordner, in dem eine neue Sitzung anf\xE4ngt",
    "feld.newSessionDefaultDir.wirkung": "Diesen Ordner schl\xE4gt der Plus-Knopf vor, solange du keinen anderen w\xE4hlst.",
    "feld.newSessionDefaultDir.info": "Der Vorschlag, mehr nicht: gew\xE4hlt wird im Ordner-Dialog, und wer dort etwas anderes nimmt, bekommt das andere. \u201E~\u201C steht f\xFCr dein Heimatverzeichnis. Diese Einstellung war bis zum 11.08. nur in der VS-Code-Erweiterung erreichbar, obwohl dieses Programm sie l\xE4ngst liest; deshalb steht sie jetzt hier.",
    "feld.newSessionDefaultDir.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "feld.showStopped.name": "Beendete Sitzungen mitzeigen",
    "feld.showStopped.wirkung": "An: die Leiste zeigt auch Sitzungen, deren Terminal nicht mehr l\xE4uft \u2013 rot markiert.",
    "feld.showStopped.info": "Aus (Vorgabe) h\xE4lt die Leiste kurz: nur, was gerade lebt. An ist n\xFCtzlich, wenn man eine Sitzung von gestern wiederaufnehmen will \u2013 sie steht dann mit ihrem Ordner da und l\xE4sst sich anklicken. Das ist eine Einstellung und keine t\xE4gliche Handlung, deshalb steht sie hier und nicht als Knopf in der Leiste.",
    "feld.showStopped.etikett": "sofort",
    "feld.sort.name": "Reihenfolge in der Leiste",
    "feld.sort.wirkung": "Wonach die Sitzungen stehen, solange keine eigene Reihenfolge gezogen wurde.",
    "feld.sort.info": "Von Hand gezogen schl\xE4gt diese Vorgabe immer \u2013 wer eine Sitzung an einen Platz zieht, will sie dort haben. Die Vorgabe greift f\xFCr alles, was danach dazukommt. \u201Ezuletzt benutzt\u201C ordnet nach der letzten Bewegung im Terminal, nicht nach dem Anlegen.",
    "feld.sort.etikett": "sofort",
    "wort.sort.recent": "zuletzt benutzt",
    "wort.sort.folder": "nach Ordner",
    "wort.sort.name": "nach Name",
    // Die Einheiten hinter den Zahlenfeldern und die Ueberschrift der Seitenliste. Sie
    // standen bis 03.09.2026 als deutsche Literale im Code (einstellungen.ts) und im
    // Geruest (index.html) und blieben deshalb auch in der englischen Fassung deutsch --
    // das war die sichtbare Sprachmischung im Fenster, obwohl beide Tabellen hier
    // vollstaendig sind (536 Schluessel, keine Luecke).
    "wort.einheit.punkt": "Punkt",
    "wort.einheit.zeilen": "Zeilen",
    "wort.einheit.spalten": "Spalten",
    "wort.einstellungen": "Einstellungen",
    "feld.closeSessionOnWindowClose.name": "Terminal mit dem Fenster beenden",
    "feld.closeSessionOnWindowClose.wirkung": "Aus (Vorgabe): das Fenster geht zu, die tmux-Sitzung dahinter l\xE4uft weiter \u2013 beendet wird sie \xFCber den Rechtsklick auf die Sitzung. An: schlie\xDFt man das Fenster, endet auch die Sitzung.",
    "feld.closeSessionOnWindowClose.info": "Gemessen am 04.08.: drei geschlossene Fenster hielten ihre tmux-Sitzungen am Leben und zusammen 6,0 GB belegt. Ein Neuladen beendet nie etwas \u2013 die Sitzung gilt erst nach einer Karenzzeit als verwaist, und ein zur\xFCckkehrendes Fenster nimmt die Marke wieder weg. L\xE4uft noch ein Worker, bleibt sie ohnehin offen. Seit dem 07.08. steht die Vorgabe trotzdem auf aus: belegter Speicher l\xE4sst sich jederzeit zur\xFCckholen, eine versehentlich beendete Sitzung samt laufender Arbeit nicht.",
    "feld.closeSessionOnWindowClose.etikett": "sofort",
    // --- Seite 2: Erlaubnisse ------------------------------------------------
    "feld.workerSkipPermissions.name": "Worker arbeiten ohne R\xFCckfrage ihrer CLI",
    "feld.workerSkipPermissions.wirkung": "An: ein Worker h\xE4lt bei einem Schreibzugriff nicht an, sondern arbeitet durch.",
    "feld.workerSkipPermissions.info": "Das ist die folgenreichste stille Festlegung des ganzen Aufbaus, und sie stand bis zum 06.08. nur in einer Zeile Shell-Code. Die Guards und die R\xFCckfrage-Stufe greifen weiterhin \u2013 die Berechtigungsabfrage der CLI nicht. Aus hei\xDFt: jeder Worker h\xE4lt bei jedem Schreibzugriff an und wartet auf einen Menschen; ein Nachtlauf steht dann bis zum Morgen.",
    "feld.workerSkipPermissions.etikett": "gilt f\xFCr den n\xE4chsten Worker",
    "feld.orchestratorPermissionMode.name": "Wie viel der Orchestrator ohne R\xFCckfrage tun darf",
    "feld.orchestratorPermissionMode.wirkung": "Legt die R\xFCckfrage-Stufe fest, mit der die CLI der n\xE4chsten Orchestrator-Sitzung startet.",
    "feld.orchestratorPermissionMode.info": "Die sechs Stufen von claude --permission-mode, gemessen aus claude --help. Senken -- jeder Wechsel weg von bypassPermissions -- geht sofort und ohne Grund; das Anheben zur\xFCck auf bypassPermissions, die Vorgabe, verlangt einen echten Menschen an dieser Oberfl\xE4che und einen Grund, gepr\xFCft von wb-state selbst. shell/wb-code liest den Wert beim Start der n\xE4chsten Orchestrator-Sitzung, nicht in der laufenden. Worker bleiben unber\xFChrt -- die stellt der Orchestrator f\xFCr sich selbst ein.",
    "feld.orchestratorPermissionMode.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "feld.workerWorktrees.name": "Jeder Worker bekommt einen eigenen Arbeitsbaum",
    "feld.workerWorktrees.wirkung": "An: jeder Worker arbeitet in einem git-Repo in seinem eigenen Ordner und Zweig statt im gemeinsamen.",
    "feld.workerWorktrees.info": "Der Baum liegt unter ~/.pi-workers/worktrees/<name>, der Zweig hei\xDFt wb/<name>. Aus hei\xDFt: alle Worker arbeiten im \xFCbergebenen Verzeichnis und begegnen sich dort \u2013 zwei, die dieselbe Datei anfassen, \xFCberschreiben einander. Au\xDFerhalb eines git-Repos \xE4ndert der Schalter nichts. Er wirkt global, weil weder claude-worker noch pi-worker heute einen Schalter je Aufruf kennen.",
    "feld.workerWorktrees.etikett": "gilt f\xFCr den n\xE4chsten Worker",
    "feld.guards.name": "Welche Sicherungen mitlaufen",
    "feld.guards.wirkung": "Jede Sicherung ist einzeln abschaltbar. Eine abgeschaltete bleibt in der Liste stehen, mit Grund und Datum.",
    "feld.guards.info": "Sie laufen vor jedem Befehl, den ein Agent absetzt, in dieser Reihenfolge; die letzte ist die R\xFCckfrage-Stufe darunter. Was eine von ihnen hart ablehnt, kommt in der R\xFCckfrage-Stufe nie an. Zwei von ihnen (Laufende Konfiguration, Medien aus der Cloud) warnen nur und halten nichts an. Abschalten verlangt einen Grund und einen Menschen; er wird mit Datum daneben vermerkt, damit in einem halben Jahr noch jemand wei\xDF, warum die Sicherung fehlt.",
    "feld.guards.etikett": "sofort",
    "feld.askPatterns.name": "Befehle, bei denen zur\xFCckgefragt wird",
    "feld.askPatterns.wirkung": "Diese Befehle werden angehalten, erscheinen in der Freigabe-Ansicht und laufen nach einer einmaligen Freigabe durch.",
    "feld.askPatterns.info": "Weder harmlos noch verboten \u2013 das ist die Stufe dazwischen. Ein Muster trifft eine Stelle in der zerlegten Befehlszeile, nicht eine Zeichenkette irgendwo im Text: sonst hielte schon ein Absatz, der \u201Egit clean -fd\u201C nur erw\xE4hnt, den Guard an (so geschehen am 05.08.). Abgeschaltet statt gel\xF6scht bleibt sichtbar, dass es das Muster gibt. Eine Freigabe gilt f\xFCnfzehn Minuten, hart gedeckelt im Modul.",
    "feld.askPatterns.etikett": "sofort",
    "feld.secretExcludeDirs.name": "Ordner, die keine Ansicht betritt",
    "feld.secretExcludeDirs.wirkung": "Diese Ordner betritt keine Ansicht \u2013 sie werden \xFCbersprungen, nicht nur ausgeblendet.",
    "feld.secretExcludeDirs.info": "Dateibaum, Schnell\xF6ffner, Inhaltssuche und Editor fragen dieselbe Stelle; ein Filter, den eine Ansicht umgehen kann, ist keiner. Gepr\xFCft wird jeder Namensteil eines Pfades, nicht nur der letzte \u2013 sonst k\xE4me projekt/.ssh/config durch. Die Liste steht hier und nicht im Quelltext, weil man sie sehen und pr\xFCfen k\xF6nnen soll.",
    "feld.secretExcludeDirs.etikett": "sofort",
    "feld.secretExcludePatterns.name": "Dateinamen, die keine Ansicht zeigt",
    "feld.secretExcludePatterns.wirkung": "Dateien, deren Name auf eines dieser Muster passt, tauchen in keiner Ansicht auf.",
    "feld.secretExcludePatterns.info": "Ein Glob auf einen einzelnen Namensteil, ohne Pfadtrenner: * steht f\xFCr beliebig viele Zeichen, ? f\xFCr eines. Bewusst klein gehalten \u2013 ein voller Glob-Dialekt mit ** und {a,b} l\xE4dt zu Mustern ein, deren Wirkung man nicht mehr sieht. Gro\xDF- und Kleinschreibung spielt keine Rolle.",
    "feld.secretExcludePatterns.etikett": "sofort",
    "feld.werkzeuge.name": "Werkzeuge und MCP-Server eines Agenten",
    "feld.werkzeuge.wirkung": "Was ein Agent an Werkzeugen mitbekommt, steht heute in seiner eigenen Konfiguration \u2013 dieses Programm liest es, setzt es aber noch nicht.",
    "feld.werkzeuge.info": "Die Hooks unten kommen aus ~/.claude/settings.json und gelten f\xFCr jede Claude-Sitzung dieser Maschine; die MCP-Server h\xE4ngen an den Diensten, die mcp-shared verwaltet. Beides wird hier gezeigt und nicht geschrieben: ein Schalter, der eine fremde Konfiguration halb \xFCberschreibt, ist schlimmer als kein Schalter. Der Weg dorthin ist beschrieben (die Werkbank schreibt Harness-Konfigurationen \xFCber wb-harness-run) und noch nicht gebaut.",
    "satz.werkzeugeOhneHooks": "In ~/.claude/settings.json steht kein Hook. Ein Agent bekommt damit die Werkzeuge, die seine CLI von sich aus mitbringt.",
    "satz.werkzeugeMcp": "MCP-Server werden von mcp-shared als Hintergrunddienste gehalten und nicht von diesem Programm. Solange das so ist, steht hier kein Schalter daf\xFCr, sondern dieser Satz.",
    // Die elf Guards -- Kennungen aus hooks/bash-guard.py, Text von hier.
    "guard.secrets.name": "Geheimnisse",
    "guard.secrets.wirkung": "H\xE4lt jeden Befehl an, der einen Schl\xFCssel, ein Zertifikat oder den Geheimnis-Ordner anfasst.",
    "guard.secrets.info": "Deckt ~/work/brain/90-secrets, ~/.ssh und die \xFCblichen Zugangsdaten-Dateien ab \u2013 dieselbe Liste, die auch die Ordneransicht ausl\xE4sst. Aus hei\xDFt: ein Agent kann diese Dateien lesen, kopieren und in eine Ausgabe schreiben, ohne dass jemand gefragt wird.",
    "guard.git-add.name": "Alles auf einmal vormerken",
    "guard.git-add.wirkung": "H\xE4lt ein \u201Egit add\u201C an, das ein ganzes Verzeichnis oder den Arbeitsbaum einsammelt.",
    "guard.git-add.info": "Wer committet, nennt seine Pfade. Ein Verzeichnis-Add sieht harmlos aus und hat am 16.08. die halbfertige Arbeit einer zweiten Sitzung in zwei fremde Commits gezogen. Aus hei\xDFt: \u201Egit add -A\u201C geht wieder durch.",
    "guard.kill-pattern.name": "Fremde Prozesse beenden",
    "guard.kill-pattern.wirkung": "H\xE4lt Befehle an, die Prozesse abschie\xDFen, die dem Agenten nicht geh\xF6ren.",
    "guard.kill-pattern.info": "Ein pkill \xFCber einen zu weiten Ausdruck hat schon laufende Worker aus dem Grid genommen. Der Guard unterscheidet, was der Agent selbst gestartet hat, von dem, was vorher lief.",
    "guard.live-config.name": "Laufende Konfiguration",
    "guard.live-config.wirkung": "Warnt, wenn ein Befehl die Dateien anfasst, an denen das laufende Setup h\xE4ngt.",
    "guard.live-config.info": "Nur eine Warnung, kein Stopp: die Kette l\xE4uft weiter. Der Grund ist ein Vorfall, bei dem ein Test die echte Einstellungsdatei umgeschrieben und vier laufende Worker unsichtbar gemacht hat.",
    "guard.push-gate.name": "Push-Sperre f\xFCr Worker",
    "guard.push-gate.wirkung": "Ein Worker darf nicht pushen, keine Pull-Requests \xF6ffnen, nichts ver\xF6ffentlichen.",
    "guard.push-gate.info": "Der Orchestrator entscheidet \xFCber Pushes, weil nur er den ganzen Stand kennt. Der Guard erkennt die Rolle am Pane, nicht am Namen. Aus hei\xDFt: jeder Worker kann in ein \xF6ffentliches Repo dr\xFCcken.",
    "guard.media-cloud.name": "Medien aus der Cloud",
    "guard.media-cloud.wirkung": "Warnt, wenn ein Bild, ein Video oder eine Stimme von einem bezahlten Dienst statt lokal kommt.",
    "guard.media-cloud.info": "Nur eine Warnung. Die lokalen Werkzeuge (bild, video, tts, stt) kosten nichts und verlassen die Maschine nicht; ein Cloud-Aufruf tut beides und soll deshalb bewusst geschehen.",
    "guard.screencapture.name": "Bildschirmaufnahmen",
    "guard.screencapture.wirkung": "H\xE4lt Befehle an, die den Bildschirm abfotografieren oder aufzeichnen.",
    "guard.screencapture.info": "Ein Bildschirmfoto nimmt alles mit, was gerade offen ist \u2013 auch das, was niemanden etwas angeht. F\xFCr Belegbilder gibt es den Weg \xFCber das Fenster selbst, der nur das eigene Fenster aufnimmt.",
    "guard.snapshot.name": "Sicherung vor dem L\xF6schen",
    "guard.snapshot.wirkung": "H\xE4lt L\xF6schbefehle an, solange keine Kopie der Daten angelegt wurde.",
    "guard.snapshot.info": "Die Kopie landet unter ~/.local/trash-snapshots/<datum>-<name>/. Der Guard pr\xFCft, ob sie existiert, bevor der L\xF6schbefehl durchgeht \u2013 er ersetzt sie nicht.",
    "guard.commit-trailer.name": "Absender eines Commits",
    "guard.commit-trailer.wirkung": "H\xE4lt einen Commit an, der einen fremden Mitautor untergeschoben bekommt.",
    "guard.commit-trailer.info": "In diesen Repos steht ein Autor und sonst niemand. Der Guard ist der einzige, der mit einem Fehlerkode statt einer Antwort abbricht \u2013 er sitzt direkt vor dem Commit.",
    "guard.muster.name": "R\xFCckfrage-Stufe",
    "guard.muster.wirkung": "Die Musterliste weiter unten: Befehle, die weder harmlos noch verboten sind, werden angehalten.",
    "guard.muster.info": "Die letzte Stufe, und die einzige, die nicht ablehnt, sondern fragt. Sie sitzt hinter allen anderen: was ein Guard hart ablehnt, kommt hier nie an. Hier abgeschaltet hei\xDFt: kein Muster l\xF6st mehr eine R\xFCckfrage aus \u2013 auch die, die weiter unten angehakt sind.",
    "guard.pane-write.name": "In fremde Panes tippen",
    "guard.pane-write.wirkung": "H\xE4lt Befehle an, die mit tmux direkt in einen Orchestrator-Pane schreiben.",
    "guard.pane-write.info": "Die zweite Schicht neben wb-pane-write: sie f\xE4ngt den Weg an dem Werkzeug vorbei. Ein Test arbeitet auf einem eigenen Socket und ist davon nicht betroffen.",
    // --- Seite 3: Programme und Modelle --------------------------------------
    "feld.harnessTabelle.name": "Programme, Anmeldung und Chat-Ansicht",
    "feld.harnessTabelle.wirkung": "F\xFCr jedes Agenten-Programm: ob es hier startet, ob es angemeldet ist, welche Denkstufen es annimmt und ob es eine Chat-Ansicht tragen kann.",
    "feld.harnessTabelle.info": "Die Stufen sind an der Hilfe des jeweiligen Programms gemessen, nicht abgeschrieben. Die Anmeldung ist kein Ratespiel: gepr\xFCft wird, ob der Beleg vorliegt, den die Registry f\xFCr diesen Anbieter nennt \u2013 liegt keiner vor, steht \u201Enicht pr\xFCfbar\u201C da und nicht \u201Enicht angemeldet\u201C. Die Chat-Ansicht h\xE4ngt am Programm und nicht am Geschmack; was ein Programm nicht kann, bekommt hier kein graues Feld, sondern den Grund im Klartext.",
    "wort.startbar": "startet hier",
    "wort.nichtStartbar": "startet auf {maschine} nicht",
    // Stand bis zum 03.09.2026 als deutscher Text mitten in `einstellungen.ts` --
    // die Programmwahl zeigte ihn auch im englischen Fenster.
    "wort.fehltHier": "fehlt hier",
    "wort.angemeldet": "angemeldet",
    "wort.nichtAngemeldet": "nicht angemeldet",
    "wort.anmeldungUnbekannt": "nicht pr\xFCfbar",
    "wort.stufenNichtErmittelt": "nicht ermittelt",
    "wort.keineStufen": "kennt keine Stufen",
    "spalte.programm": "Programm",
    "spalte.stufen": "Stufen",
    "spalte.modelle": "Modelle",
    "spalte.hier": "Auf dieser Maschine",
    "spalte.anmeldung": "Anmeldung",
    "spalte.installiert": "Installiert",
    "spalte.neueste": "Neueste",
    "spalte.zuletztGeprueft": "Zuletzt gepr\xFCft",
    "wort.nochNichtGeprueft": "noch nicht gepr\xFCft",
    "wort.stunden": "Stunden",
    "wort.minuten": "Minuten",
    "spalte.chat": "Chat-Ansicht",
    "spalte.modell": "Modell",
    "spalte.deckel": "Deckel",
    "spalte.herkunft": "Herkunft",
    "spalte.grund": "Grund",
    "spalte.einstellung": "Einstellung",
    "spalte.beiDir": "Bei dir",
    "spalte.auslieferung": "Auslieferung",
    "spalte.anbieter": "Anbieter",
    "spalte.zugang": "Zugang",
    "spalte.eingabe": "Eingeben",
    "spalte.maschine": "Maschine",
    "spalte.wert": "Wert",
    "satz.chatKannNicht": "Kein Weg zum Gespr\xE4chsverlauf eingetragen \u2013 deshalb steht hier kein Schalter.",
    "satz.chatOhneMessung": "Eingetragen, aber ohne Messdatum \u2013 ohne die z\xE4hlt der Eintrag nicht.",
    "satz.chatKannLive": "liest mit, w\xE4hrend die Sitzung l\xE4uft",
    "satz.chatKannNichtLive": "liest erst, wenn die Sitzung steht",
    "satz.chatZeigtNicht": "Zeigt nicht: {liste}.",
    "feld.chatAnsicht.name": "Gespr\xE4ch statt Terminal anzeigen",
    "feld.chatAnsicht.wirkung": "An: die Werkbank zeichnet f\xFCr dieses Programm den Gespr\xE4chsverlauf statt des Terminalbilds.",
    "feld.chatAnsicht.info": "Der Schalter steht je Programm und nicht global, weil die F\xE4higkeit am Programm h\xE4ngt und nicht am Geschmack. Der Terminal-Pane l\xE4uft in beiden F\xE4llen weiter und wird weiter ausgewertet \u2013 nur so wei\xDF die Werkbank, ob das Programm gerade fragt, antwortet oder wartet; sichtbar ist blo\xDF die andere Darstellung. Was in keinem Protokoll steht (Freigabedialoge, Kontextauslastung, Fortschritt), steht in der Zeile daneben.",
    "feld.chatAnsicht.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    // Der Transportschalter steht auf DIESER Seite und nicht auf „Sitzung“: deren
    // Unterzeile sagt ausdruecklich, dass die Worker hier nicht eingestellt
    // werden. Er gehoert zur Frage, WORAUF ein Agenten-Programm laeuft -- damit
    // in die Gruppe „Die Programme auf dieser Maschine“.
    "feld.workerTransport.name": "Woran ein Worker-Pane h\xE4ngt",
    "feld.workerTransport.wirkung": "An tmux wie bisher, oder an einem Pseudo-Terminal, das die Werkbank selbst h\xE4lt. \u201Epty\u201C ist ein Prototyp: ein Worker je Pseudo-Terminal, Kontextwache und R\xFCckkanal laufen \xFCber den Steuerkanal, und mehrere pty-Panes nebeneinander in einem Tab sind noch nicht gebaut.",
    "feld.workerTransport.info": "Der Weg seit V1 ist tmux: jeder Worker ist ein Pane in einer tmux-Sitzung, und die Werkzeuge des Hauses sind darauf gebaut. \u201Epty\u201C kommt aus der Probe vom 04.09.2026 (app/src/main/pty.ts): die Werkbank startet den Worker selbst auf einem eigenen Pseudo-Terminal und spiegelt seinen Bytestrom in ein kopfloses Terminalmodell. Der Bildschirm, den die Kontextwache daraus liest, war in der Messung byteweise derselbe wie der von tmux, und nach einem Neustart der Werkbank stand der Worker mit derselben Unterhaltung wieder da. Offen sind zwei Stellen: die Tab-Ansicht zeichnet bisher nur einen einzelnen pty-Pane, und die Umgebung der Werkbank wird an den Worker vollst\xE4ndig vererbt. Steht der Schalter auf \u201Etmux\u201C, wird der Prototyp nicht einmal geladen; ein unbekannter Wert gilt als \u201Etmux\u201C und nicht als Fehler.",
    "feld.workerTransport.etikett": "gilt f\xFCr den n\xE4chsten Worker",
    "feld.ollamaEndpoint.name": "Adresse des lokalen Modell-Servers",
    "feld.ollamaEndpoint.wirkung": "Unter dieser Adresse werden die lokalen Modelle gesucht \u2013 Ollama, vLLM oder MLX, je nachdem, was dort antwortet.",
    "feld.ollamaEndpoint.info": "Bis zum 11.08. stand http://127.0.0.1:11434 an sieben Stellen fest im Quelltext und lie\xDF sich nirgends einstellen; wer Ollama auf einem anderen Rechner betreibt, musste sieben Dateien von Hand \xE4ndern. Dieses Feld ist die eine Stelle daf\xFCr. Erwartet wird eine vollst\xE4ndige Adresse mit http:// oder https:// und ohne Pfad am Ende. Ein Server im Netz statt auf dieser Maschine hei\xDFt: die Anfragen verlassen den Rechner \u2013 das ist eine Entscheidung und keine Kleinigkeit.",
    "feld.ollamaEndpoint.etikett": "gilt f\xFCr den n\xE4chsten Abruf",
    "satz.ollamaNochNichtVerdrahtet": "Der Wert wird gespeichert und hier angezeigt. Die sieben Stellen im Quelltext, die die Adresse heute noch fest enthalten, lesen ihn noch nicht \u2013 sie werden in einem eigenen Schritt nachgezogen.",
    "feld.modelDiscoveryAuto.name": "Modell-Kataloge von selbst abrufen",
    "feld.modelDiscoveryAuto.wirkung": "An: die Kataloge der Anbieter werden von selbst aus dem Netz geholt. Aus: nur noch auf Knopfdruck.",
    "feld.modelDiscoveryAuto.info": "Aus hei\xDFt nur, dass nicht mehr von selbst ins Netz gegangen wird. Die lokalen Quellen \u2013 ollama, die Modell-Listen der CLIs, Dateien \u2013 laufen weiter automatisch, und der Abruf von Hand bleibt immer bedienbar. Diese Einstellung war bis zum 11.08. nur in der VS-Code-Erweiterung erreichbar, obwohl wb-state sie l\xE4ngst liest.",
    "feld.modelDiscoveryAuto.etikett": "sofort",
    "feld.harnessUpdateAuto.name": "Agenten-Programme automatisch aktuell halten",
    "feld.harnessUpdateAuto.wirkung": "An: Die Werkbank pr\xFCft und aktualisiert die installierten Harness-CLIs selbstst\xE4ndig.",
    "feld.harnessUpdateAuto.info": "Aus verhindert bereits die Katalogabfrage und damit jeden automatischen Netzzugriff. Updates, die einen laufenden Prozess gef\xE4hrden k\xF6nnten, werden vorgemerkt und erst ohne lebende Sitzung ausgef\xFChrt.",
    "feld.harnessUpdateAuto.etikett": "beim n\xE4chsten Pr\xFCflauf",
    "feld.harnessUpdateIntervalHours.name": "Abstand der Harness-Pr\xFCfung",
    "feld.harnessUpdateIntervalHours.wirkung": "Nach dem verz\xF6gerten Start pr\xFCft die Werkbank in diesem Stundenabstand erneut.",
    "feld.harnessUpdateIntervalHours.info": "Der Abstand gilt zwischen zwei L\xE4ufen. Eine Sperrdatei verhindert, dass zwei Werkbank-Instanzen gleichzeitig aktualisieren.",
    "feld.harnessUpdateIntervalHours.etikett": "nach dem n\xE4chsten Pr\xFCflauf",
    "feld.orchestratorVorhersage.name": "Multi-Token-Vorhersage f\xFCr den Orchestrator",
    "feld.orchestratorVorhersage.wirkung": "An: der Orchestrator l\xE4dt, falls f\xFCr sein Modell hinterlegt, zus\xE4tzlich einen Entwerfer oder eine Fassung mit eingebautem Vorhersage-Kopf \u2013 schneller je Antwort, aber ohne gemeinsame Nebenl\xE4ufigkeit am MLX-Server.",
    "feld.orchestratorVorhersage.info": "Welche Wege es gibt, steht in der Registry: w\xE4hlbar ist nur, was dort hinterlegt und gemessen ist, kein freier Pfad. F\xFChrt die Registry f\xFCr das Modell mehrere Wege, stehen sie unter dem Haken zur Wahl, mit ihrer Herkunft darunter \u2013 samt der Stellen, an denen nichts gemessen wurde. Spekulatives Decoding und die geteilte Nebenl\xE4ufigkeit des MLX-Servers schlie\xDFen sich gegenseitig aus (mlx_lm.server schaltet die Stapelverarbeitung ab, sobald ein Entwerfer gesetzt ist) \u2013 deshalb steht dieser Schalter standardm\xE4\xDFig aus.",
    "feld.workerVorhersage.name": "Multi-Token-Vorhersage f\xFCr Worker",
    "feld.workerVorhersage.wirkung": "An: ein Worker mit einem lokalen Modell l\xE4dt, falls daf\xFCr hinterlegt, denselben Entwerfer oder eingebauten Kopf \u2013 getrennt vom Schalter des Orchestrators.",
    "feld.workerVorhersage.info": "Welches Modell dabei benutzt wird, steht in der Registry und ist hier nicht w\xE4hlbar \u2013 nur diese Anzeige zeigt es an. Gilt unabh\xE4ngig vom Orchestrator-Schalter: der eine kann an sein, der andere aus.",
    "wort.vorhersageEntwerfer": "externer Entwerfer",
    "wort.vorhersageEingebaut": "eingebauter Kopf",
    "satz.vorhersageModell": "Modell: {modell} ({bauart})",
    "satz.vorhersageKeine": "F\xFCr das aktuell gew\xE4hlte Modell ist keine Vorhersage hinterlegt.",
    "satz.vorhersageWegVorgabe": "{weg} (Vorgabe)",
    "feld.anbieter.name": "Zugang zu den Anbietern",
    "feld.anbieter.wirkung": "F\xFCr jeden Anbieter: woher sein Zugang kommt und ob er auf dieser Maschine vorliegt.",
    "feld.anbieter.info": "Ein Schl\xFCssel wird hier eingegeben, aber nicht in die Einstellungsdatei geschrieben \u2013 die ist geteilter Klartext, den auch Worker beschreiben, und ein Schl\xFCssel darin w\xE4re ein Schl\xFCssel im Klartext. Der Wert geht stattdessen einen eigenen Weg und wird danach nie wieder ausgelesen, um ihn anzuzeigen. Gezeigt wird deshalb weiterhin nur, ob der Zugang vorliegt \u2013 nie sein Wert und nie sein Ort. Ein Anbieter mit Abo statt Schl\xFCssel meldet stattdessen, ob die Anmeldung stattgefunden hat.",
    "wort.zugangDa": "liegt vor",
    "wort.zugangFehlt": "fehlt",
    "wort.zugangUnbekannt": "nicht pr\xFCfbar",
    "wort.zugangAbo": "Abo, kein Schl\xFCssel",
    "wort.zugangLokal": "l\xE4uft lokal, kein Zugang n\xF6tig",
    "feld.effortCaps.name": "H\xF6chste Stufe ohne R\xFCckfrage",
    "feld.effortCaps.wirkung": "Bis hierher darf der Orchestrator gehen, wenn er von sich aus einen Worker startet.",
    "feld.effortCaps.info": "\u201EAuslieferung\u201C hei\xDFt: der Wert kommt aus der Registry, so wie das Modell geliefert wurde. Sobald du einen Deckel setzt, steht dort \u201Evon dir\u201C mit Datum und Grund \u2013 und der Grund ist Pflicht, weil eine Selbstbindung ohne Begr\xFCndung nach einem halben Jahr wie eine technische Grenze aussieht. Senken darf jeder; anheben verlangt einen Menschen, gemessen an der Herkunft des Aufrufs. Zur\xFCck auf die Auslieferung geht \xFCber den ersten Eintrag der Auswahl.",
    "feld.effortCaps.etikett": "gilt f\xFCr den n\xE4chsten automatischen Start",
    "satz.deckelLeitsatzFett": "Ein Deckel bindet den Orchestrator, nicht dich. ",
    "satz.deckelLeitsatz": "Wenn du selbst startest, stehen dir alle Stufen offen, die das Programm annimmt. Der Deckel hier gilt f\xFCr Worker, die der Orchestrator ohne R\xFCckfrage startet: er soll sich nicht von selbst die teuerste Stufe geben.",
    "satz.deckelDieses": "Deckel dieses Modells: ",
    "satz.deckelGilt": ". Er gilt, wenn der Orchestrator von sich aus einen Worker startet \u2013 f\xFCr deine Wahl hier gilt er nicht. ",
    "satz.deckelDarueber": "Gestrichelt umrandet: die Stufen dar\xFCber ({stufen}).",
    "satz.deckelGrund": "Grund des Deckels: {grund}",
    "satz.deckelKeiner": "F\xFCr dieses Modell ist kein Deckel eingetragen \u2013 der Orchestrator vergibt jede Stufe.",
    "satz.deckelUeber": "\xDCber dem Deckel ({deckel}). W\xE4hlbar: der Deckel bindet den Orchestrator, nicht dich.",
    "wort.vonDir": "von dir gesetzt",
    "wort.ausAuslieferung": "Auslieferung",
    "wort.vonDirAm": "von dir, {datum}",
    "satz.deckelAuslieferungWahl": "Auslieferung ({deckel})",
    "wort.ohne": "ohne",
    "satz.stufenKeineWahl": "\u201E{harness}\u201C kennt keine Stufen \u2013 hier ist nichts zu w\xE4hlen.",
    "satz.stufenErstModell": "Erst ein Modell w\xE4hlen; die Stufen h\xE4ngen an seinem Programm.",
    // --- Seite 4: Maschinen --------------------------------------------------
    "feld.remoteMachines.name": "Rechner, die mitarbeiten",
    "feld.remoteMachines.wirkung": "Jede Maschine hier taucht in der Sitzungsleiste auf und steht als Ziel f\xFCr einen Worker zur Wahl.",
    "feld.remoteMachines.info": "Der Name ist der SSH-Alias, so wie \u201Essh host2\u201C ihn kennt \u2013 es gibt keine zweite Adressliste daneben. Ein anderer Hostname oder eine IP funktioniert genauso, sofern ssh damit umgehen kann; wer ein Gate davor hat, tr\xE4gt den Alias ein, der durch das Gate f\xFChrt. Mehr als zwei sind ausdr\xFCcklich vorgesehen. Die Liste bleibt leer, bis jemand etwas eintr\xE4gt: ein SSH-Ziel ist ein echter Netzzugriff und darf nie von selbst anspringen. Der Pr\xFCfknopf fragt genau einmal nach (ssh <name> true).",
    "feld.remoteMachines.etikett": "sofort",
    // Der Pause-Schalter je Zeile (04.09.): kein eigenes `feld()`, aber dieselbe
    // Textform wie jeder andere Schlüssel -- die Wirkungszeile steht unter der
    // Liste, `name`/`info` halten die Abweichungstabelle und die Suchleiter
    // vollständig, auch ohne eigenes Steuerelement in dieser Form.
    "feld.remoteMachinesPausiert.name": "Pausierte Maschinen",
    "feld.remoteMachinesPausiert.wirkung": "Die Sitzungen auf einer pausierten Maschine laufen dort ungest\xF6rt weiter \u2013 pausiert ist nur der Blick dieser Werkbank darauf: kein Abruf, keine Sitzungen in der Leiste, keine Spiegel-Panes.",
    "feld.remoteMachinesPausiert.info": "Der Name bleibt in \u201ERechner, die mitarbeiten\u201C eingetragen \u2013 der Schalter ist umkehrbar, ohne die Adresse neu einzutippen. Eine pausierte Maschine gilt nicht als \u201Enicht erreichbar\u201C: das sind zwei verschiedene Zust\xE4nde.",
    // Die mobile Werkbank (Paket 10): Server, Kopplung und Geräte -- nur hier am Mac.
    "gruppe.maschinen.mobil": "Mobilger\xE4t",
    "feld.mobileServer.name": "Mobile Werkbank",
    "feld.mobileServer.wirkung": "Startet den Server f\xFCr die Werkbank-App auf iPhone und iPad (127.0.0.1, dahinter ein HTTPS-Proxy). Aus: keine Verbindung vom Telefon, gekoppelte Ger\xE4te bleiben gespeichert.",
    "feld.mobileServer.info": "Jede Anfrage des Telefons ist mit dem Schl\xFCssel eines gekoppelten Ger\xE4ts signiert; ohne Signatur nimmt der Server nichts an, auch nicht von diesem Rechner. Koppeln und Widerrufen gehen nur hier mit einem echten Klick. Adressen und Port stehen in der Programmkonfiguration (mobileOrigins, mobileOrigin, mobilePort).",
    "mobil.stand.aus": "Aus.",
    "mobil.stand.laeuft": "L\xE4uft auf 127.0.0.1:{port} f\xFCr {origin}.",
    "mobil.stand.fehler": "Nicht gestartet: {grund}",
    "mobil.koppeln": "Ger\xE4t koppeln",
    "mobil.code": "Code am Telefon eingeben: {code}",
    "mobil.codeAblauf": "Gilt bis {zeit} Uhr, h\xF6chstens f\xFCnf Versuche. Der Code steht nur hier, nirgends sonst.",
    "mobil.codeAbgelaufen": "Der Code ist abgelaufen. F\xFCr ein weiteres Ger\xE4t erneut koppeln.",
    "mobil.ausblenden": "Ausblenden",
    "mobil.geraeteLeer": "Noch kein Ger\xE4t gekoppelt.",
    "mobil.geraetAktiv": "gekoppelt am {datum}",
    "mobil.geraetWiderrufen": "widerrufen am {datum}",
    "mobil.widerrufen": "Widerrufen",
    "satz.eigeneMaschine": "Diese Maschine \u2013 sie steht immer in der Liste und l\xE4sst sich nicht entfernen.",
    "satz.fremdeMaschine": "Erreicht \xFCber ssh {name} \u2013 der Name ist zugleich der SSH-Alias.",
    "satz.keineMaschine": "Keine weitere Maschine eingetragen. Ohne Eintrag geht das Programm nie von selbst ins Netz.",
    "satz.maschineSchonDa": "\u201E{name}\u201C steht schon in der Liste.",
    "satz.fremdeLast": "Wie viele Worker eine andere Maschine gleichzeitig tr\xE4gt, steht in deren eigener Einstellungsdatei und wird dort gesetzt: ssh {name} wb-state settings set maxWorkers <zahl>. Zwei Zahlen an zwei Orten f\xFCr dieselbe Frage w\xE4ren zwei Wahrheiten, von denen eine falsch ist.",
    "feld.maxWorkers.name": "Worker gleichzeitig auf dieser Maschine",
    "feld.maxWorkers.wirkung": "Mehr als so viele Worker nimmt eine Sitzung nicht an \u2013 der n\xE4chste Start wird abgelehnt.",
    "feld.maxWorkers.info": "Abgelehnt, nicht gestapelt: ein Start, der das Fenster \xFCberf\xFCllt, kostet mehr als ein Start, der sagt \u201Ezu viele\u201C. Bestehende Panes werden weiter wiederverwendet, ein fertiger Worker macht also sofort wieder Platz. Gez\xE4hlt werden Worker-Panes, keine Subagenten. Die Zahl geh\xF6rt der Maschine und nicht der Sitzung: was ein 48-GB-Rechner tr\xE4gt, tr\xE4gt ein kleinerer nicht.",
    "feld.maxWorkers.etikett": "sofort",
    "feld.schlafNachMinuten.name": "Unt\xE4tige Sitzungen schlafen legen nach",
    "feld.schlafNachMinuten.wirkung": "Eine Sitzung, die so lange nichts tut, gibt ihren Speicher frei; ein Klick auf ihre Kachel, eine Taste oder ein neuer Auftrag weckt sie, und die Unterhaltung geht weiter. 0 schaltet das ab.",
    "feld.schlafNachMinuten.info": "Gilt f\xFCr jeden Harness, der seine Unterhaltung fortsetzen kann (Claude, pi, Codex, opencode \u2026); einer ohne diesen Weg bleibt wach. Unt\xE4tig hei\xDFt: Inhalt unver\xE4ndert, kein laufender Werkzeugaufruf, keine Rechenlast. 60 Minuten sind die Lebensdauer des Prompt-Caches \u2013 danach kostet das Aufwecken keine zus\xE4tzlichen Token. Eine Nachricht einer anderen Claude-Sitzung erreicht eine schlafende nicht; daf\xFCr vorher wb-schlaf wecken.",
    "feld.schlafNachMinuten.etikett": "bei der n\xE4chsten Runde",
    "feld.defaultWorkerMachine.name": "Wo ein Worker l\xE4uft, wenn nichts gesagt wird",
    "feld.defaultWorkerMachine.wirkung": "Auf welche Maschine ein Worker geht, wenn beim Start keine genannt wird.",
    "feld.defaultWorkerMachine.info": 'Die Auswahl kommt aus der Liste dar\xFCber: jede dort eingetragene Maschine steht hier zur Wahl. \u201EDiese Maschine" hei\xDFt: der Worker l\xE4uft im selben Terminal-Server wie die Sitzung. Ein Ziel, das nicht antwortet, l\xE4sst den Start scheitern statt ihn umzuleiten \u2013 deshalb der Pr\xFCfknopf daneben.',
    "feld.defaultWorkerMachine.etikett": "gilt f\xFCr den n\xE4chsten Worker",
    "wort.dieseMaschine": "Diese Maschine ({name})",
    "feld.workerZustellung.name": "Wie ein Auftrag beim Worker ankommt",
    "feld.workerZustellung.wirkung": "\xDCber das Postfach der Sitzung, oder in die Eingabezeile des Panes getippt.",
    "feld.workerZustellung.info": "Getippt wird der Auftrag Zeichen f\xFCr Zeichen in das Terminal des Workers \u2013 sichtbar, aber anf\xE4llig: in der Nacht auf den 20.08. sind f\xFCnf Panes dabei eingefroren und Auftr\xE4ge stumm verschwunden. Claude Code bringt f\xFCr denselben Zweck ein Postfach mit, das nicht durch die Eingabezeile geht und deshalb nichts \xFCberschreiben und nichts blockieren kann. \u201EVon selbst\u201C nimmt das Postfach, wo es eines gibt, und tippt sonst; das ist die Vorgabe, weil ein Postfach heute nur Claude Code mitbringt \u2013 die \xFCbrigen Programme der Registry tippen so oder so, und eine Vorgabe, die f\xFCr sie nicht gilt, d\xFCrfte f\xFCr sie nichts kaputt machen. \u201ENur Postfach\u201C verlangt es und l\xE4sst die Zustellung h\xF6rbar scheitern, statt ersatzweise zu tippen: gedacht f\xFCr Pr\xFCfl\xE4ufe und f\xFCr den Fall, dass in gar keine Eingabezeile mehr geschrieben werden soll. F\xFCr einen Worker auf einem anderen Programm hei\xDFt diese Wahl deshalb, dass er gar keinen Auftrag bekommt. \u201ENur tippen\u201C ist der R\xFCckweg, falls das Postfach an einer k\xFCnftigen Fassung der CLI scheitert. Ob ein Auftrag angekommen ist, wird auf jedem der drei Wege gleich gepr\xFCft und im Klartext gemeldet.",
    "feld.workerZustellung.etikett": "gilt f\xFCr den n\xE4chsten Auftrag",
    "wort.workerZustellung.auto": "von selbst",
    "wort.workerZustellung.socket": "nur Postfach",
    "wort.workerZustellung.paste": "nur tippen",
    // --- Seite 5: Aufsicht und Meldungen -------------------------------------
    "feld.contextGuardAutostart.name": "Kontextwache l\xE4uft mit",
    "feld.contextGuardAutostart.wirkung": "An: das Programm startet die Wache selbst, sobald eine Sitzung steht \u2013 niemand muss daran denken.",
    "feld.contextGuardAutostart.info": 'Bis zum 06.08. startete der Orchestrator seine Wache selbst. Entscheidung des Nutzers, sie dem Programm zu geben: \u201EWenn jemand ein schw\xE4cheres Modell als Orchestrator nimmt, das nicht so zuverl\xE4ssig ist, soll die Kontextwache ja immer noch zuverl\xE4ssig sein." Sie h\xE4ngt damit nicht mehr an der Sorgfalt dessen, den sie \xFCberwacht. Aus hei\xDFt: es l\xE4uft keine Wache, au\xDFer jemand startet sie von Hand.',
    "feld.contextGuardAutostart.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "feld.wacheOrchAn.name": "Das Hauptfenster \xFCberwachen",
    "feld.wacheOrchAn.wirkung": "An: die Wache sieht auch dem Hauptfenster \xFCber die Schulter, nicht nur den Workern.",
    "feld.wacheOrchAn.info": "Getrennt schaltbar, weil beide Seiten verschieden teuer sind: ein Orchestrator, der mitten in einer \xDCbergabe kompaktiert wird, verliert den Faden, ein Worker selten. Wer die Aufsicht \xFCber sich selbst nicht will, schaltet hier ab und l\xE4sst sie f\xFCr die Worker weiterlaufen. Abschalten verlangt einen Grund und einen Menschen \u2013 aus einem Worker-Pane heraus geht es nicht.",
    "feld.wacheOrchAn.etikett": "gilt f\xFCr die n\xE4chste Wache",
    "feld.wacheWorkerAn.name": "Die Worker \xFCberwachen",
    "feld.wacheWorkerAn.wirkung": "An: jeder Worker-Pane wird mitgelesen und bei vollem Kontext gemahnt.",
    "feld.wacheWorkerAn.info": "Ein Worker, der ohne \xDCbergabe kompaktiert wird, liefert seinen Auftrag halb ab \u2013 die Mahnung sorgt daf\xFCr, dass er vorher schreibt, was er wei\xDF. Ein Pane, der schmaler ist als die Mindestbreite, l\xE4sst sich nicht lesen; die Wache meldet ihn dann ausdr\xFCcklich als blind, statt ihn stillschweigend auszulassen. Fertigmeldungen laufen auch dann weiter, wenn die Wache hier aus ist.",
    "feld.wacheWorkerAn.etikett": "gilt f\xFCr die n\xE4chste Wache",
    "feld.wacheWorkerMahnenAb.name": "Worker mahnen ab",
    "feld.wacheWorkerMahnenAb.wirkung": "Ab diesem F\xFCllstand fordert die Wache einen Worker auf, eine \xDCbergabe zu schreiben und zu kompaktieren.",
    "feld.wacheWorkerMahnenAb.info": "Prozent des Kontextfensters seines Modells. Zu fr\xFCh gemahnt kostet Arbeit, zu sp\xE4t kostet das Ergebnis: was nach dem Kompaktieren nicht aufgeschrieben ist, ist weg. 80 l\xE4sst genug Platz f\xFCr die \xDCbergabe selbst. Eine h\xF6here Zahl hei\xDFt sp\xE4ter mahnen, also weniger Sicherung \u2013 daf\xFCr verlangt das Werkzeug einen Grund.",
    "feld.wacheWorkerMahnenAb.etikett": "gilt f\xFCr die n\xE4chste Wache",
    "feld.wacheOrchMahnenAb.name": "Hauptfenster mahnen ab",
    "feld.wacheOrchMahnenAb.wirkung": "Ab diesem F\xFCllstand soll der Orchestrator Zustandsdatei und Wissensspeicher nachziehen.",
    "feld.wacheOrchMahnenAb.info": "Niedriger als bei den Workern, weil er mehr zu sichern hat: Sitzungsstand, offene Auftr\xE4ge, das, was in den Kbase geh\xF6rt. F\xFCnf Prozentpunkte Vorsprung sind rund eine Viertelstunde Arbeit.",
    "feld.wacheOrchMahnenAb.etikett": "gilt f\xFCr die n\xE4chste Wache",
    "feld.wacheOrchEingreifen.name": "Die Wache greift selbst ein",
    "feld.wacheOrchEingreifen.wirkung": "An: sie mahnt nicht nur, sie tippt notfalls selbst /compact \u2013 sie hat die Stimme und die Hand.",
    "feld.wacheOrchEingreifen.info": "Die Wache kompaktiert die Orchestrator-Sitzung notfalls selbst, indem sie /compact in ein fremdes Fenster tippt. Wer das nicht will, aber weiter gewarnt werden m\xF6chte, schaltet hier ab: die Mahnung bleibt, der Eingriff f\xE4llt weg. Das ist die mildere Stufe zwischen \u201Ealles\u201C und \u201EWache aus\u201C.",
    "feld.wacheOrchEingreifen.etikett": "gilt f\xFCr die n\xE4chste Wache",
    "feld.wacheOrchNotbremseAb.name": "Notbremse ab",
    "feld.wacheOrchNotbremseAb.wirkung": "Ab hier kompaktiert die Wache den Orchestrator selbst \u2013 auch ohne sein Zeichen.",
    "feld.wacheOrchNotbremseAb.info": "Sie tippt /compact in eine fremde Sitzung, nie mitten in einem Zug. Bis zum 06.08. stand diese Zahl fest im Quelltext und war nirgends zu sehen; wer das nicht wusste, hielt das pl\xF6tzliche Kompaktieren f\xFCr einen Fehler. Sie greift nur, solange \u201EDie Wache greift selbst ein\u201C an ist.",
    "feld.wacheOrchNotbremseAb.etikett": "gilt f\xFCr die n\xE4chste Wache",
    "feld.stallMinutes.name": "Als \u201Eh\xE4ngt\u201C melden nach",
    "feld.stallMinutes.wirkung": "So lange darf ein Worker still sein, bevor die Leiste ihn als h\xE4ngend markiert.",
    "feld.stallMinutes.info": "Gemessen an 11.070 Pausen aus 17 Sitzungen, die durchgearbeitet und abgeliefert haben: bei 5 Minuten h\xE4tten 8 dieser 17 f\xE4lschlich \u201Eh\xE4ngt\u201C getragen, bei 10 Minuten noch 4. Ein Kindprozess, der j\xFCnger ist als die Stille, unterdr\xFCckt die Meldung ohnehin \u2013 ein langer Testlauf z\xE4hlt also nicht als Stillstand.",
    "feld.stallMinutes.etikett": "sofort",
    "feld.guardMeldetWorkerStatus.name": "Die Wache schreibt Worker-Meldungen ins Hauptfenster",
    "feld.guardMeldetWorkerStatus.wirkung": "An: die Wache tippt \u201EWorker fertig\u201C und \u201EWorker h\xE4ngt\u201C selbst in den Orchestrator-Pane.",
    "feld.guardMeldetWorkerStatus.info": "Vorgabe aus, und das ist eigene des Nutzers Entscheidung: die Meldung sieht aus wie sein eigenes Wort, sie unterbricht ihn mitten im Satz, und dieselbe Information steht ohnehin in der rechten Leiste. Nicht betroffen ist alles, was nie verstummen darf: die Kontext-Warnung des Hauptfensters, das getippte /compact und alles, was an Worker-Panes geht. Dieser Schalter wird an neun Stellen gelesen und hatte bis zum 11.08. in keiner der beiden Oberfl\xE4chen ein Feld.",
    "feld.guardMeldetWorkerStatus.etikett": "gilt f\xFCr die n\xE4chste Wache",
    "satz.guardsWohnenAnderswo": "Die Sicherungen, die vor jedem Befehl laufen, stehen auf der Seite \u201EErlaubnisse\u201C \u2013 dort, wo alles steht, was ein Agent darf. Sie ein zweites Mal hier anzubieten hie\xDFe, zwei Orte f\xFCr dieselbe Entscheidung zu haben.",
    "feld.meldungenAn.name": "Sich au\xDFerhalb des Fensters melden",
    "feld.meldungenAn.wirkung": "An: das Programm sagt Bescheid, auch wenn du gerade etwas anderes tust. Aus: es schweigt.",
    "feld.meldungenAn.info": "Bis zum 11.08. meldete sich das Programm nie nach au\xDFen \u2013 kein Systemhinweis, kein Ton, nichts aufs Handy. Wer nebenbei etwas anderes tat, merkte erst beim n\xE4chsten Hinsehen, dass ein Worker fertig war oder eine Freigabe wartete. Dieser Schalter ist die eine Frage, an der alles h\xE4ngt; was und wie gemeldet wird, steht darunter. Vorgabe ist aus, weil ein Programm, das ungefragt anf\xE4ngt zu klingeln, schlechter w\xE4re als eines, das schweigt.",
    "feld.meldungenAn.etikett": "sofort",
    "feld.meldungenEreignisse.name": "Wor\xFCber gemeldet wird",
    "feld.meldungenEreignisse.wirkung": "Nur diese vier Ereignisse k\xF6nnen eine Meldung ausl\xF6sen \u2013 jedes einzeln abw\xE4hlbar.",
    "feld.meldungenEreignisse.info": "Vier Ereignisse, und jedes hat einen anderen Grund: ein fertiger Worker hei\xDFt, dass Arbeit auf dich wartet; eine wartende Freigabe hei\xDFt, dass eine Kette steht, bis du antwortest; eine gestorbene Sitzung hei\xDFt, dass etwas abgebrochen ist, das du f\xFCr laufend h\xE4ltst; ein fast volles Kontingent hei\xDFt, dass die n\xE4chste Stunde teuer wird. Wer alles abw\xE4hlt, bekommt nichts \u2013 dann ist der Schalter dar\xFCber der ehrlichere Weg.",
    "feld.meldungenEreignisse.etikett": "sofort",
    "feld.meldungenWege.name": "Auf welchem Weg",
    "feld.meldungenWege.wirkung": "Systemhinweis, Ton, Handy \u2013 einzeln oder zusammen. Der Weg bestimmt, wie aufdringlich es ist.",
    "feld.meldungenWege.info": "Ein Systemhinweis ist leise und bleibt in der Mitteilungszentrale liegen; ein Ton holt dich sofort, auch wenn der Bildschirm aus ist; das Handy erreicht dich au\xDFer Haus. E-Mail steht bewusst nicht zur Wahl: eine Mail zu senden ist eine au\xDFenwirksame Handlung mit eigener Freigaberegel, und ein Haken im Men\xFC w\xE4re der stille Weg daran vorbei.",
    "feld.meldungenWege.etikett": "sofort",
    "feld.meldungenHandyUrl.name": "Adresse f\xFCr das Handy",
    "feld.meldungenHandyUrl.wirkung": "Der Webhook, an den eine Meldung geschickt wird. Leer hei\xDFt: kein Weg aufs Handy.",
    "feld.meldungenHandyUrl.info": "Ein Webhook ist eine Adresse, die ein Dienst dir gibt und die eine Nachricht auf dein Telefon bringt. Welchen Dienst du nimmst, entscheidest du \u2013 das Programm kennt nur die Adresse und schickt einen Text dorthin. Diese Adresse verl\xE4sst den Rechner bei jeder Meldung, und was sie enth\xE4lt, entscheidet der Dienst dahinter: trag hier nichts ein, dem du das nicht zutraust.",
    "feld.meldungenHandyUrl.etikett": "sofort",
    "feld.meldungenTonDatei.name": "Eigener Ton",
    "feld.meldungenTonDatei.wirkung": "Der Pfad zu einer Klangdatei. Leer hei\xDFt: der Ton des Betriebssystems.",
    "feld.meldungenTonDatei.info": "Ein eigener Ton ist mehr als Geschmack: wer mehrere Programme laufen hat, erkennt an einem eigenen Klang, dass die Meldung von hier kommt, ohne hinzusehen. Leer ist die sichere Wahl \u2013 der Systemton existiert immer, eine Datei kann verschwinden.",
    "feld.meldungenTonDatei.etikett": "sofort",
    "feld.meldungenLimitSchwelle.name": "Ab wann das Kontingent als fast voll gilt",
    "feld.meldungenLimitSchwelle.wirkung": "Ab diesem Anteil des Kontingents meldet sich das Programm \u2013 sofern das Ereignis oben angehakt ist.",
    "feld.meldungenLimitSchwelle.info": "Prozent des Kontingents im laufenden Zeitfenster. Zu fr\xFCh gewarnt hei\xDFt: man gew\xF6hnt sich daran und \xFCbersieht die Meldung, die z\xE4hlt. Zu sp\xE4t hei\xDFt: die Warnung kommt, wenn nichts mehr zu retten ist. 85 l\xE4sst genug Raum, eine laufende Arbeit noch geordnet zu Ende zu bringen.",
    "feld.meldungenLimitSchwelle.etikett": "sofort",
    "feld.meldungTesten.name": "Test senden",
    "feld.meldungTesten.wirkung": "Schickt eine Probemeldung \xFCber genau die Wege, die oben gew\xE4hlt sind, und zeigt darunter, was je Weg passiert ist.",
    "feld.meldungTesten.info": "Der Knopf sendet eine einzige echte Probemeldung \u2013 Systemhinweis, Ton, Webhook, je nachdem, was oben angehakt ist \u2013 und meldet danach je Weg, ob es geklappt hat: beim Webhook den HTTP-Status, sonst den Grund, warum nicht. Steht der Hauptschalter aus, sagt der Knopf das und sendet nichts.",
    "knopf.meldungTesten": "Test senden",
    "meldungTesten.hauptschalterAus": "Der Hauptschalter oben ist aus \u2013 es wurde nichts gesendet.",
    "meldungTesten.keinWeg": "Kein Weg ist ausgew\xE4hlt \u2013 es wurde nichts gesendet.",
    "meldungTesten.laeuft": "Probe wird gesendet \u2026",
    "meldungTesten.system.ok": "Systemhinweis: abgesetzt",
    "meldungTesten.system.fehler": "Systemhinweis: fehlgeschlagen \u2013 {grund}",
    "meldungTesten.ton.ok": "Ton: abgespielt",
    "meldungTesten.ton.fehler": "Ton: fehlgeschlagen \u2013 {grund}",
    "meldungTesten.handy.ok": "Handy: Webhook antwortete mit HTTP {status}",
    "meldungTesten.handy.fehler": "Handy: fehlgeschlagen \u2013 {grund}",
    "meldung.workerFertig": "Ein Worker ist fertig",
    "meldung.freigabeWartet": "Eine Freigabe wartet auf dich",
    "meldung.sitzungTot": "Eine Sitzung ist gestorben",
    "meldung.limitFastVoll": "Das Kontingent ist fast voll",
    "weg.system": "Systemhinweis",
    "weg.ton": "Ton",
    "weg.handy": "Handy",
    "platzhalter.handyUrl": "https://\u2026  (leer = kein Weg aufs Handy)",
    "platzhalter.tonDatei": "~/Musik/melden.aiff  (leer = Systemton)",
    // --- Seite 6: Aussehen ---------------------------------------------------
    "feld.thema.name": "Hell oder dunkel",
    "feld.thema.wirkung": "Ob das Programm hell, dunkel oder so aussieht, wie das Betriebssystem gerade eingestellt ist.",
    "feld.thema.info": "\u201EWie das System\u201C folgt der Umstellung des Betriebssystems, auch mitten in der Arbeit. Die Terminal-Panes selbst folgen nicht: ihre Farben kommen aus tmux und der jeweiligen CLI, und eine zweite Stelle daf\xFCr h\xE4tte zwei Wahrheiten. Heute richtet sich dieses Fenster danach; die \xFCbrigen Fenster ziehen nach, sobald ihre Farben aus derselben Quelle kommen.",
    "feld.thema.etikett": "sofort",
    "wort.thema.system": "wie das System",
    "wort.thema.hell": "hell",
    "wort.thema.dunkel": "dunkel",
    "feld.zustandsfarben.name": "Die Farben der Sitzungszust\xE4nde",
    "feld.zustandsfarben.wirkung": "Woran du in der Leiste erkennst, ob eine Sitzung arbeitet, wartet, fertig ist oder nicht mehr l\xE4uft.",
    "feld.zustandsfarben.info": "Vier Zust\xE4nde, vier Farben, und sie m\xFCssen sich f\xFCr dich unterscheiden \u2013 nicht f\xFCr einen Katalog. Wer Rot und Gr\xFCn schlecht auseinanderh\xE4lt, stellt hier zwei Farben ein, die er sieht. Zur\xFCck auf die Auslieferung geht \xFCber das Zeichen neben der \xDCberschrift.",
    "feld.zustandsfarben.etikett": "sofort",
    "zustand.laeuft": "arbeitet",
    "zustand.wartet": "wartet auf dich",
    "zustand.fertig": "fertig",
    "zustand.tot": "l\xE4uft nicht mehr",
    "feld.terminalFontSize.name": "Schriftgr\xF6\xDFe im Terminal",
    "feld.terminalFontSize.wirkung": "Wie gro\xDF die Schrift in allen Terminal-Panes steht. Die \xC4nderung ist sofort zu sehen.",
    "feld.terminalFontSize.info": "Sie entscheidet mit, wie viele Spalten und Zeilen in ein Pane passen: gr\xF6\xDFere Schrift hei\xDFt weniger Spalten auf derselben Fl\xE4che. Unter 80 Spalten kann die Kontextwache die Statuszeile eines Workers nicht mehr sicher lesen \u2013 wer die Schrift stark vergr\xF6\xDFert, bekommt deshalb eher einen zweiten Worker-Tab als schmalere Panes. Erlaubt sind 8 bis 32; ein Wert au\xDFerhalb wird abgelehnt und der alte bleibt stehen.",
    "feld.terminalFontSize.etikett": "sofort",
    "feld.terminalScrollLines.name": "Zeilen je Rad-Rasterung",
    "feld.terminalScrollLines.wirkung": "Wie weit ein Rasterschritt des Mausrads rollt \u2013 im R\xFCckblick des Fensters und in der Anwendung im Pane gleich.",
    "feld.terminalScrollLines.info": "Bis zum 06.08. fiel diese Zahl aus der Zellh\xF6he: der zur\xFCckgelegte Weg eines Rad-Ereignisses wurde durch die H\xF6he einer Zeile geteilt. Das hing am Ger\xE4t (ein Trackpad schickt viele kleine Ereignisse, eine Maus wenige gro\xDFe) und an der Schriftgr\xF6\xDFe und wurde deshalb als \u201Eviel zu schnell\u201C gemeldet. Jetzt z\xE4hlt nur diese Zahl: eine Rasterung bewegt so viele Zeilen. Ein Trackpad-Wisch sammelt seine Bruchteile auf, und ein einzelnes Ereignis bewegt nie mehr als sechs Zeilen. Erlaubt sind 1 bis 20.",
    "feld.terminalScrollLines.etikett": "sofort",
    "feld.minWorkerPaneWidth.name": "Schmalster Worker-Pane",
    "feld.minWorkerPaneWidth.wirkung": "So schmal darf ein Worker-Pane werden. Darunter legt das Fenster lieber einen zweiten Tab an.",
    "feld.minWorkerPaneWidth.info": "Gemessen am 04.08.: bei 60 Spalten fiel die Statuszeile einer echten Claude-CLI auf den blo\xDFen Balken zur\xFCck oder schlechter; 80 ist die best\xE4tigte Untergrenze, bei der sie mit einem realistischen Pfad noch genau zu lesen ist. Darunter meldet die Kontextwache den Pane als blind und \xFCberwacht ihn nicht \u2013 ein schmalerer Wert bringt also keine dichtere Ansicht, sondern blinde Wachen. Erlaubt sind 20 bis 1000.",
    "feld.minWorkerPaneWidth.etikett": "sofort",
    "feld.maxWorkerPanesPerTab.name": "Worker je Tab",
    "feld.maxWorkerPanesPerTab.wirkung": "Ab dieser Zahl legt das Fenster einen weiteren Worker-Tab an, statt die Panes weiter zu verkleinern.",
    "feld.maxWorkerPanesPerTab.info": "Gemessen am 04.08.: auf dem Bezugsfenster (197 \xD7 54) passen zwei Spalten \xE0 80 Spalten neben drei Reihen lesbarer H\xF6he \u2013 also 6. Unter 80 Spalten kann die Kontextwache die Statuszeile nicht mehr sicher lesen und meldet den Pane als blind. 0 hei\xDFt: keine eigene Obergrenze; wie viele wirklich nebeneinander passen, rechnet das Fenster ohnehin aus seiner Gr\xF6\xDFe und der Mindestbreite dar\xFCber.",
    "feld.maxWorkerPanesPerTab.etikett": "beim n\xE4chsten Neuanordnen",
    "feld.workerLayout.name": "Wo die Worker-Panes sitzen",
    "feld.workerLayout.wirkung": "Unter dem Hauptfenster geteilt, oder in einem eigenen Fenster daneben.",
    "feld.workerLayout.info": "Geteilt hei\xDFt: die Worker liegen als Panes unter dem Orchestrator, alles in einem Blick, jeder Pane schmaler. Eigenes Fenster hei\xDFt: die Worker bekommen ihr eigenes Fenster, das man auf einen zweiten Bildschirm schieben kann. Das ist eine Frage des Bildschirms und keine des Modells. Diese Einstellung war bis zum 11.08. nur in der VS-Code-Erweiterung erreichbar, obwohl vier Werkzeuge sie lesen.",
    "feld.workerLayout.etikett": "beim n\xE4chsten Neuanordnen",
    "wort.workerLayout.split": "geteilt unter dem Hauptfenster",
    "wort.workerLayout.window": "eigenes Fenster",
    // Die sechs Werte von `claude --permission-mode`, uebersetzt und nicht
    // ausgelegt: was jede Stufe im Einzelnen zulaesst, steht in der Info-Zeile
    // des Feldes, nicht in der Beschriftung des Abteils. Der Rohwert haengt als
    // Titel am Abteil.
    "wort.permissionMode.acceptEdits": "\xC4nderungen annehmen",
    "wort.permissionMode.auto": "automatisch",
    "wort.permissionMode.bypassPermissions": "Erlaubnisse \xFCbergehen",
    "wort.permissionMode.manual": "von Hand",
    "wort.permissionMode.dontAsk": "nicht nachfragen",
    "wort.permissionMode.plan": "nur planen",
    "feld.sprache.name": "Sprache der Oberfl\xE4che",
    "feld.sprache.wirkung": "In welcher Sprache die Beschriftungen dieses Programms stehen.",
    "feld.sprache.info": "Alle Beschriftungen dieses Fensters kommen aus einer einzigen Tabelle und nicht mehr aus dem Quelltext \u2013 das ist die Voraussetzung daf\xFCr, dass eine zweite Sprache eine zweite Tabelle ist und kein Durchgang durch zweitausend Zeilen. Englisch ist die Auslieferungssprache; Deutsch bleibt vollst\xE4ndig gepflegt daneben.",
    "feld.sprache.etikett": "sofort",
    "wort.sprache.de": "Deutsch",
    "wort.sprache.en": "English",
    "satz.spracheNochNichtDa": "F\xFCr diese Sprache liegt noch keine Tabelle vor. Solange die zweite Tabelle fehlt, bleibt die Oberfl\xE4che englisch \u2013 halb \xFCbersetzt w\xE4re schlechter als gar nicht.",
    "feld.chatAnsichtVorgabe.name": "Neue Sitzungen zeigen das Gespr\xE4ch",
    "feld.chatAnsichtVorgabe.wirkung": "An: neue Panes starten in der Chat-Ansicht, wo ihr Programm das kann \u2013 getrennt f\xFCr den Orchestrator und f\xFCr seine Worker.",
    "feld.chatAnsichtVorgabe.info": "Das ist die Vorgabe je Rolle und keine Aussage dar\xFCber, was ein Programm kann \u2013 das steht je Programm auf der Seite \u201EProgramme und Modelle\u201C. Ein Programm ohne Weg zum Gespr\xE4chsverlauf bleibt beim Terminalbild, ganz gleich, was hier steht. F\xFCr eine einzelne Sitzung schl\xE4gt der Rechtsklick auf sie diese Vorgabe: er stellt ihren Orchestrator sofort um, und zwar nur ihn. Die Worker folgen weiter dem, was hier steht.",
    "feld.chatAnsichtVorgabe.etikett": "gilt f\xFCr die n\xE4chste Sitzung",
    "wort.rolle.orchestrator": "Orchestrator",
    "wort.rolle.worker": "Worker",
    // --- Seite 7: Programm ---------------------------------------------------
    "feld.pfade.name": "Dateien dieses Programms",
    "feld.pfade.wirkung": "Wo die beiden Konfigurationsdateien, die Registry und der Oberfl\xE4chen-Zustand liegen.",
    "feld.pfade.info": `Zwei Dateien, getrennt nach Zust\xE4ndigkeit: was Programm und Werkzeuge gemeinsam meinen, steht in den Einstellungen (~/.claude/workbench/settings.json) \u2013 dort sitzt die Sperre, und geschrieben wird nur \xFCber wb-state, das jede \xC4nderung mit Urheber protokolliert. Was nur dieses Programm zum Hochfahren braucht (Pfade, Socket, Maschinenkennung), steht in der Programm-Konfiguration. Kein Schl\xFCssel steht in beiden. Die Pfade sind aus der Konfiguration dieses Laufs gelesen, nicht fest verdrahtet. Welche Protokolle die Protokoll-Ansicht zeigt, ist bewusst nur \xFCber die Befehlszeile zu \xE4ndern: wb-state settings set logPaths '[{"label":"\u2026","path":"\u2026"}]'.`,
    "feld.erststartZeigen.name": "Gef\xFChrter erster Start",
    "feld.erststartZeigen.wirkung": "\xD6ffnet dasselbe Fenster, das beim allerersten Start dieser Werkbank von selbst erscheint.",
    "feld.erststartZeigen.info": "Derselbe Ablauf wie beim ersten Start, nur von Hand aufgerufen \u2013 zum Nachlesen, oder um ihn einem zweiten Menschen an diesem Rechner zu zeigen. Der Knopf setzt nichts zur\xFCck: dass der erste Start schon einmal gelaufen ist, bleibt vermerkt, und beim n\xE4chsten eigentlichen Programmstart erscheint das Fenster deshalb weiterhin nicht von selbst.",
    "feld.erststartZeigen.etikett": "sofort",
    "feld.abweichungen.name": "Abweichungen von der Auslieferung",
    "feld.abweichungen.wirkung": "Alles, was du verstellt hast, in einer Liste \u2013 mit dem Weg zur\xFCck.",
    "feld.abweichungen.info": "F\xFCr ein Programm, das weitergegeben werden soll, ist das die einzige ehrliche Antwort auf die Frage, warum es bei zwei Leuten verschieden l\xE4uft. Verglichen wird gegen die mitgelieferte Vorgabe, nicht gegen den Stand von gestern. Ein Wert, der nie angefasst wurde, steht hier nicht \u2013 auch dann nicht, wenn er zuf\xE4llig gleich aussieht.",
    "feld.abweichungen.etikett": "sofort",
    "satz.keineAbweichung": "Nichts \u2013 alles steht so, wie es ausgeliefert wurde.",
    "feld.sicherung.name": "Sichern, zur\xFCcksetzen, \xFCbertragen",
    "feld.sicherung.wirkung": "Der ganze Stand als Text: kopieren und wegheben, hier wieder einsetzen, oder alles auf die Auslieferung stellen.",
    "feld.sicherung.info": "Bis zum 11.08. lie\xDF sich nur jeder Schl\xFCssel einzeln zur\xFCckstellen; vor einem gr\xF6\xDFeren Umbau gab es keinen Weg, den vorherigen Stand zu sichern. Der Text unten ist genau das, was von der Auslieferung abweicht \u2013 nicht die ganze Datei, denn Vorgaben zu sichern hie\xDFe, sie beim Einsetzen auf einem anderen Rechner festzuschreiben. Eingesetzt wird Schl\xFCssel f\xFCr Schl\xFCssel \xFCber denselben Schreibweg wie jeder Haken; was das Werkzeug ablehnt, wird nicht gespeichert und steht danach in der Fu\xDFzeile.",
    "feld.sicherung.etikett": "sofort",
    "wort.kopieren": "in die Zwischenablage",
    "wort.einsetzen": "einsetzen",
    "wort.allesZurueck": "alles auf Auslieferung",
    "satz.sicherungKopiert": "Der Stand liegt in der Zwischenablage ({zeichen} Zeichen).",
    "satz.sicherungKeinText": "Es steht nichts im Feld \u2013 nichts einzusetzen.",
    "satz.sicherungKeinJson": "Das ist kein JSON-Objekt. Erwartet wird genau das, was der Knopf dar\xFCber liefert.",
    "satz.sicherungEingesetzt": "{anzahl} Einstellungen eingesetzt.",
    "satz.sicherungLeer": "Nichts weicht ab \u2013 es gibt nichts zu sichern.",
    // --- Bedienung, quer über alle Seiten ------------------------------------
    "wort.hinzufuegen": "Hinzuf\xFCgen",
    "wort.entfernen": "entfernen",
    "wort.pruefen": "pr\xFCfen",
    "wort.zuruecksetzen": "zur\xFCcksetzen",
    "wort.speichern": "speichern",
    "wort.erneutZeigen": "erneut zeigen",
    "wort.frage": "frage \u2026",
    "wort.erreichbar": "erreichbar",
    "wort.nichtErreichbar": "nicht erreichbar: {grund}",
    "wort.an": "an",
    "wort.aus": "aus",
    "wort.einEintrag": "1 Eintrag",
    "wort.mehrereEintraege": "{anzahl} Eintr\xE4ge",
    "wort.leereListe": "leere Liste",
    // Der Schalter je Maschinenzeile (04.09.). Der lange Satz bleibt als Titel
    // des Hakens; die kurze Aufschrift daneben kam am 05.09. dazu, weil ein
    // blankes Kaestchen sich als „ausgewaehlt“ liest und nicht als
    // „Sitzungen laden“.
    "wort.maschineLaden": "Sitzungen dieser Maschine laden",
    "wort.sitzungenLaden": "Sitzungen laden",
    "wort.nichtsGesetzt": "nichts gesetzt",
    "wort.alleModelle": "Alle {anzahl}",
    "wort.leerListe": "leer \u2013 es wird nichts ausgelassen",
    "platzhalter.modellsuche": "zus\xE4tzlich nach Name oder Kennung filtern \u2026",
    "platzhalter.suche": "nach Name oder Kennung filtern \u2026",
    "platzhalter.maschine": "SSH-Alias, z. B. host2",
    "platzhalter.musterBefehl": "Befehl, z. B. rsync",
    "platzhalter.musterUnterbefehl": "Unterbefehl (darf leer bleiben)",
    "platzhalter.musterGrund": "Warum gefragt wird",
    "platzhalter.ordner": "Ordnername",
    "platzhalter.dateimuster": "Dateimuster",
    "platzhalter.startordner": "~/AI",
    "platzhalter.ollama": "http://127.0.0.1:11434",
    "platzhalter.sicherung": "Hier einen gesicherten Stand einsetzen \u2026",
    "platzhalter.schluesselEingabe": "Wert einf\xFCgen \u2026",
    "satz.schluesselLeer": "Kein Wert eingegeben \u2013 nichts gespeichert.",
    "satz.schluesselGespeichert": "F\xFCr {anbieter} abgelegt.",
    "satz.schluesselFehler": "Fehler beim Ablegen.",
    "satz.keinTreffer": "Kein Modell passt auf Filter und Suche.",
    "satz.keinTrefferSuche": "Kein Modell passt auf die Suche.",
    "satz.zuVieleTreffer": "{anzahl} Modelle passen \u2013 gezeigt werden die ersten 60. Such nach Name oder Kennung.",
    "satz.keineMuster": "Keine Muster \u2013 es wird bei keinem Befehl zur\xFCckgefragt.",
    "satz.keineGuards": "Die Liste der Sicherungen ist nicht zu lesen \u2013 wb-state antwortet nicht. Solange gilt: alle laufen.",
    "satz.abgeschaltet": "Abgeschaltet",
    "satz.abgeschaltetFuer": "Abgeschaltet f\xFCr {rolle}",
    "satz.seit": " seit {datum}",
    "satz.stehtAufVorgabe": "Steht auf der Vorgabe aus der Auslieferung.",
    "satz.zurueckAufVorgabe": "Zur\xFCck auf die Vorgabe: {wert}",
    "satz.infoTitel": "Was macht \u201E{feld}\u201C?",
    "satz.musterOhneBefehl": "Ein Muster ohne Befehlsnamen w\xE4re eine Textsuche \xFCber die ganze Zeile \u2013 es wird nicht angelegt.",
    "satz.musterVonHand": "Von Hand eingetragen.",
    "satz.schreibe": "schreibe {schluessel} \u2026",
    "satz.oberflaeche": "Oberfl\xE4che: {schluessel} = {wert}",
    "satz.fehler": "Fehler: {aufruf} \u2013 {ausgabe}",
    "satz.ohneGrundNichts": "Ohne Grund wird nichts ge\xE4ndert \u2013 schreib in einem Satz, warum.",
    // --- Rückfragen ----------------------------------------------------------
    "frage.wacheAus.text": "Die Kontextwache wird nicht mehr von selbst gestartet. Danach l\xE4uft eine Sitzung ohne Aufsicht \xFCber ihren Kontext: niemand mahnt vor dem Volllaufen, niemand kompaktiert, und eine \xDCbergabe entsteht nur, wenn jemand von Hand daran denkt.",
    "frage.wacheAus.tun": "Wache abschalten",
    "frage.wacheOrchAus.text": "Die Kontextwache l\xE4sst den Orchestrator danach in Ruhe: keine Mahnung, keine Notbremse, kein /compact \u2013 auch nicht kurz vor dem \xDCberlauf. F\xFCr die Worker l\xE4uft sie weiter.",
    "frage.wacheOrchAus.tun": "F\xFCr das Hauptfenster abschalten",
    "frage.wacheWorkerAus.text": "Kein Worker wird danach mehr gemahnt oder kompaktiert. Ein volllaufender Worker verliert dann still, was er nicht aufgeschrieben hat.",
    "frage.wacheWorkerAus.tun": "F\xFCr Worker abschalten",
    "frage.mahnenHoch.worker": "Sp\xE4ter mahnen hei\xDFt weniger Vorlauf: ab {wert} % bleibt einem Worker weniger Platz, seine \xDCbergabe noch zu schreiben, bevor kompaktiert wird.",
    "frage.mahnenHoch.orch": "Ab {wert} % wird der Orchestrator erst sp\xE4ter gemahnt \u2013 er hat dann weniger Platz, Zustand und Wissen zu sichern, bevor kompaktiert wird.",
    "frage.mahnenHoch.tun": "Schwelle anheben",
    "frage.eingreifenAus.text": "Die Wache mahnt danach weiter, greift aber nicht mehr ein: sie tippt kein /compact, auch nicht an der Notbremse. Wer die Mahnung \xFCbersieht, l\xE4uft in den vollen Kontext.",
    "frage.eingreifenAus.tun": "Eingreifen abschalten",
    "frage.notbremseHoch.text": "Die Notbremse greift erst ab {wert} %. Je h\xF6her sie steht, desto n\xE4her am \xDCberlauf wird kompaktiert.",
    "frage.notbremseHoch.tun": "Notbremse anheben",
    "frage.guardAus.text": "\u201E{name}\u201C greift danach nicht mehr. {wirkung} Was diese Sicherung bisher angehalten hat, l\xE4uft ab sofort ohne Frage durch \u2013 die \xFCbrigen bleiben davon unber\xFChrt.",
    "frage.guardAus.tun": "Sicherung abschalten",
    "frage.musterAus.text": "\u201E{name}\u201C l\xF6st danach keine R\xFCckfrage mehr aus. {grund} Der Befehl l\xE4uft ab sofort ohne Nachfrage durch, sofern kein Guard ihn ohnehin hart ablehnt.",
    "frage.musterAus.tun": "Muster abschalten",
    "frage.musterWeg.text": "Das Muster \u201E{name}\u201C wird aus der Liste gel\xF6scht. Danach sieht man nicht mehr, dass es es gab \u2013 wer es nur vor\xFCbergehend loswerden will, schaltet es stattdessen ab.",
    "frage.musterWeg.tun": "Muster l\xF6schen",
    "frage.skipAn.text": "Jeder neue Worker startet danach mit unterdr\xFCckter Berechtigungsabfrage seiner CLI: er schreibt Dateien, ohne zu fragen. Die Sicherungen und die R\xFCckfrage-Stufe bleiben davon unber\xFChrt, die Abfrage der CLI nicht.",
    "frage.skipAn.tun": "R\xFCckfragen unterdr\xFCcken",
    "frage.permissionModeAn.text": "Die CLI der n\xE4chsten Orchestrator-Sitzung h\xE4lt danach bei nichts mehr an -- kein Bearbeiten, kein Ausf\xFChren, keine R\xFCckfrage. Das ist die st\xE4rkste der sechs Stufen und braucht deshalb einen Grund.",
    "frage.permissionModeAn.tun": "Auf bypassPermissions anheben",
    "frage.listeLeer.text": "Die Liste ist danach leer: {was} werden nirgends mehr ausgelassen. Dateibaum, Schnell\xF6ffner, Inhaltssuche und Editor zeigen dann auch das, was hier bisher fehlte.",
    "frage.listeLeer.tun": "Liste leeren",
    "frage.deckel.text": "Der Deckel von \u201E{modell}\u201C steht danach auf {stufe}. Er gilt f\xFCr Worker, die der Orchestrator ohne R\xFCckfrage startet \u2013 deine eigene Wahl bleibt frei. Ein Deckel ohne Grund liest sich in einem halben Jahr wie eine technische Grenze, deshalb geh\xF6rt einer dazu.",
    "frage.deckel.tun": "Deckel setzen",
    "frage.allesZurueck.text": "Jede der {anzahl} Abweichungen wird auf die Auslieferung zur\xFCckgestellt \u2013 auch abgeschaltete Sicherungen, gelockerte Wachen und gesetzte Deckel. Sicher den Stand vorher, wenn du ihn wiederhaben willst.",
    "frage.allesZurueck.tun": "Alles zur\xFCcksetzen",
    "frage.einsetzen.text": "{anzahl} Einstellungen werden aus dem Text \xFCbernommen und \xFCberschreiben, was jetzt gilt. Was das Werkzeug ablehnt, bleibt stehen.",
    "frage.einsetzen.tun": "Einsetzen",
    // --- Die Namen in „was bei dir anders ist“ --------------------------------
    // 30 der 37 Namen hier sind wortgleich mit dem `name` des zugehoerigen
    // Feldes (`feld.<schluessel>.name`) -- test-app-bezeichnung-paritaet.sh
    // haelt das zusammen, nicht bloss dieser Kommentar. Zwei weichen ABSICHTLICH
    // ab, weil die Abweichungsliste einen ZUSTAND meldet und die Seite ein
    // BEDIENELEMENT beschriftet:
    //   effortCaps  Feld „Höchste Stufe ohne Rückfrage“, hier „Gesetzte Effort-Deckel“
    //   guards      Feld „Welche Sicherungen mitlaufen“, hier „Abgeschaltete Sicherungen“
    // Fuenf haben KEIN Gegenstueck (kein `feld.<schluessel>.name`), weil der
    // Einstellungsschluessel nicht auf genau ein Feld abbildet: workerEffort und
    // workerModel stehen nicht im Menü (siehe deren eigene Zeile, „nicht im
    // Menü"), logPaths und meldungen zerfallen auf der Seite in mehrere
    // Einzelfelder statt eines, kontextwache zeigt sich nicht als Feld, sondern
    // ueber `wb-state guard|wache`.
    // Zwei Zaehlerstaende sind hier nachgetragen, nicht neu erfunden: der
    // Kommentar stand bis zum 20.08. auf 28 von 35 und hatte
    // orchestratorPermissionMode (16.08.) nie mitgezaehlt; die Suite fuehrte
    // laengst 29 von 36. Dazu kommt workerZustellung (20.08.) -- machte
    // 30 von 37. Am 03.09. kommen vier dazu, die als Einstellung laengst in der
    // Abweichungstabelle standen und dort als "[fehlender Text: ...]" erschienen:
    // orchestratorVorhersage und workerVorhersage (beide wortgleich mit ihrem
    // Feldnamen) sowie orchestratorVorhersageWeg und erststartErledigt (beide
    // ohne Feld auf einer Seite). Macht 32 von 41; die zwei angemeldeten
    // Abweichungen sind unveraendert, die Schluessel ohne Gegenstueck sind
    // jetzt sieben. Am 04.09. kommt workerTransport dazu, wortgleich mit seinem
    // Feldnamen -- 33 von 42, die beiden anderen Listen unveraendert.
    "bezeichnung.closeSessionOnWindowClose": "Terminal mit dem Fenster beenden",
    "bezeichnung.orchestratorHarness": "Programm im Hauptfenster",
    "bezeichnung.orchestratorModel": "Modell der Sitzung",
    "bezeichnung.orchestratorEffort": "Wie tief die Sitzung denkt",
    "bezeichnung.workerEffort": "Denkstufe eines Workers ohne eigene Angabe (nicht im Men\xFC)",
    "bezeichnung.workerModel": "Modell eines Workers ohne eigene Angabe (nicht im Men\xFC)",
    "bezeichnung.workerLayout": "Wo die Worker-Panes sitzen",
    "bezeichnung.orchestratorVorhersage": "Multi-Token-Vorhersage f\xFCr den Orchestrator",
    "bezeichnung.orchestratorVorhersageWeg": "Weg der Multi-Token-Vorhersage f\xFCr den Orchestrator",
    "bezeichnung.workerVorhersage": "Multi-Token-Vorhersage f\xFCr Worker",
    "bezeichnung.erststartErledigt": "Der gef\xFChrte erste Start ist durchlaufen",
    "bezeichnung.newSessionDefaultDir": "Ordner, in dem eine neue Sitzung anf\xE4ngt",
    "bezeichnung.modelDiscoveryAuto": "Modell-Kataloge von selbst abrufen",
    "bezeichnung.maxWorkers": "Worker gleichzeitig auf dieser Maschine",
    "bezeichnung.workerWorktrees": "Jeder Worker bekommt einen eigenen Arbeitsbaum",
    "bezeichnung.defaultWorkerMachine": "Wo ein Worker l\xE4uft, wenn nichts gesagt wird",
    "bezeichnung.workerZustellung": "Wie ein Auftrag beim Worker ankommt",
    "bezeichnung.workerTransport": "Woran ein Worker-Pane h\xE4ngt",
    "bezeichnung.maxWorkerPanesPerTab": "Worker je Tab",
    "bezeichnung.minWorkerPaneWidth": "Schmalster Worker-Pane",
    "bezeichnung.contextGuardAutostart": "Kontextwache l\xE4uft mit",
    "bezeichnung.guardMeldetWorkerStatus": "Die Wache schreibt Worker-Meldungen ins Hauptfenster",
    "bezeichnung.stallMinutes": "Als \u201Eh\xE4ngt\u201C melden nach",
    "bezeichnung.workerSkipPermissions": "Worker arbeiten ohne R\xFCckfrage ihrer CLI",
    "bezeichnung.orchestratorPermissionMode": "Wie viel der Orchestrator ohne R\xFCckfrage tun darf",
    "bezeichnung.askPatterns": "Befehle, bei denen zur\xFCckgefragt wird",
    "bezeichnung.secretExcludeDirs": "Ordner, die keine Ansicht betritt",
    "bezeichnung.secretExcludePatterns": "Dateinamen, die keine Ansicht zeigt",
    "bezeichnung.terminalFontSize": "Schriftgr\xF6\xDFe im Terminal",
    "bezeichnung.terminalScrollLines": "Zeilen je Rad-Rasterung",
    "bezeichnung.logPaths": "Protokoll-Pfade (nur Anzeige)",
    "bezeichnung.effortCaps": "Gesetzte Effort-Deckel",
    "bezeichnung.guards": "Abgeschaltete Sicherungen",
    "bezeichnung.kontextwache": "Verstellte Kontextwache",
    "bezeichnung.remoteMachines": "Rechner, die mitarbeiten",
    "bezeichnung.remoteMachinesPausiert": "Pausierte Maschinen",
    "bezeichnung.ollamaEndpoint": "Adresse des lokalen Modell-Servers",
    "bezeichnung.meldungen": "Wor\xFCber du au\xDFerhalb des Fensters Bescheid bekommst",
    "bezeichnung.sprache": "Sprache der Oberfl\xE4che",
    "bezeichnung.thema": "Hell oder dunkel",
    "bezeichnung.zustandsfarben": "Die Farben der Sitzungszust\xE4nde",
    "bezeichnung.chatAnsicht": "Gespr\xE4ch statt Terminal anzeigen",
    "bezeichnung.chatAnsichtVorgabe": "Neue Sitzungen zeigen das Gespr\xE4ch"
  };
  var EN = {
    "fenster.titel": "Agent Workbench \u2014 Settings",
    // --- The seven pages ---------------------------------------------------
    "seite.sitzung.titel": "Session",
    "seite.sitzung.wofuer": "What a new session starts with",
    "seite.sitzung.unterzeile": "What a new session starts with, where it starts working, and how its bar behaves. Workers are not set here: the orchestrator sets those up for you.",
    "seite.erlaubnisse.titel": "Permissions",
    "seite.erlaubnisse.wofuer": "What agents are allowed to do",
    "seite.erlaubnisse.unterzeile": "What an agent may do without asking, and where it gets stopped. Every row here removes a safeguard or adds one; each carries a mark that explains why.",
    "seite.harnesses.titel": "Programs and models",
    "seite.harnesses.wofuer": "Sign in, connect, cap",
    "seite.harnesses.unterzeile": "Which agent programs run on this machine, whether they are signed in, how the local models are reached, and how far the orchestrator may go without asking.",
    "seite.maschinen.titel": "Machines",
    "seite.maschinen.wofuer": "Machines and load",
    "seite.maschinen.unterzeile": "How much work this machine may carry at once.",
    "seite.aufsicht.titel": "Oversight and notifications",
    "seite.aufsicht.wofuer": "Guard, stall, notices",
    "seite.aufsicht.unterzeile": "What the program watches on its own, when it steps in, and what it tells you outside the window.",
    "seite.aussehen.titel": "Appearance",
    "seite.aussehen.wofuer": "Colors, font, language",
    "seite.aussehen.unterzeile": "How the program looks and how much fits on the screen. None of this changes what the agents do.",
    "seite.programm.titel": "Program",
    "seite.programm.wofuer": "Files, deviations, backup",
    "seite.programm.unterzeile": "Where this program's files live, what differs from the shipped defaults on your machine, and how you back up, reset, or carry the whole state to another machine.",
    // --- Group headings ------------------------------------------------------
    "gruppe.sitzung.start": "What a new session starts with",
    "gruppe.sitzung.leiste": "The session bar",
    "gruppe.sitzung.schliessen": "On closing the window",
    "gruppe.erlaubnisse.vorsicht": "Working without asking",
    "gruppe.erlaubnisse.guards": "Safeguards before every command",
    "gruppe.erlaubnisse.rueckfragen": "Commands that ask first",
    "gruppe.erlaubnisse.geheimnisse": "What is never read",
    "gruppe.erlaubnisse.werkzeuge": "Tools and MCP servers",
    "gruppe.harnesses.programme": "The programs on this machine",
    "gruppe.harnesses.lokal": "Local models",
    "gruppe.harnesses.schluessel": "Access to the providers",
    "gruppe.harnesses.deckel": "How far the orchestrator may go without asking",
    "gruppe.maschinen.liste": "Machines in this list",
    "gruppe.maschinen.last": "How much this machine carries",
    "gruppe.aufsicht.wache": "The context guard",
    "gruppe.aufsicht.stillstand": "Stall",
    "gruppe.aufsicht.meldungen": "Notifications",
    "gruppe.aussehen.thema": "Light and dark",
    "gruppe.aussehen.terminal": "Font and scrolling",
    "gruppe.aussehen.panes": "How workers sit in the window",
    "gruppe.aussehen.sprache": "Language and view",
    "gruppe.programm.dateien": "What lives where",
    "gruppe.programm.abweichungen": "What differs on your machine",
    "gruppe.programm.sicherung": "Back up, reset, transfer",
    "gruppe.programm.erststart": "The guided first start",
    // --- Page 1: Session -------------------------------------------------
    "feld.orchestratorHarness.name": "Program in the main window",
    "feld.orchestratorHarness.wirkung": "Which agent CLI the orchestrator pane starts. The number next to it names the models that fit.",
    "feld.orchestratorHarness.info": `Every registered adapter is on offer, not just Claude Code and pi. "missing here" means: this adapter's program does not exist on {maschine}, and starting it would run into nothing. What is checked is exactly what wb-state checks before a start: the binary on the path.`,
    "feld.orchestratorHarness.etikett": "takes effect on the next session",
    "feld.orchestratorModel.name": "Model of the session",
    "feld.orchestratorModel.wirkung": "What the orchestrator thinks with, as long as nothing else is said at start.",
    "feld.orchestratorModel.info": '{anzahl} models carrying the "orchestrator" role for this program. The id on the right is the same one the tools start with. A model whose program is missing here stays in the list, marked red -- so you can see why it will not start instead of having to look for it.',
    "feld.orchestratorModel.etikett": "takes effect on the next session",
    "feld.orchestratorModel.leerName": "Model",
    "feld.orchestratorModel.leerWirkung": 'No model with the role "orchestrator" is registered for this program.',
    "feld.orchestratorModel.leerInfo": "Add a model with this role: wb-state models add-model \u2026 --roles orchestrator. Until one exists, the session starts with whatever the CLI defaults to on its own.",
    "satz.keinModellFuerProgramm": 'No model with program "{harness}" and role "orchestrator".',
    "feld.orchestratorEffort.name": "How deep the session thinks",
    "feld.orchestratorEffort.wirkung": "The level the orchestrator starts at. Your choice -- every level the program accepts.",
    "feld.orchestratorEffort.info": "This is a human's choice, and no cap binds a human: every level is selectable, even the ones above the cap -- they just carry a mark. The cap is something else -- the orchestrator's own commitment for workers it starts without asking. Which levels even exist is something the program states itself, measured against its own help text, not copied from a list. Higher levels cost more time and more of the quota.",
    "feld.orchestratorEffort.etikett": "takes effect on the next session",
    "feld.orchestratorKontext.name": "Context window",
    "feld.orchestratorKontext.wirkung": 'How much text "{modell}" keeps in mind at once. Only for a model that runs here on this machine -- for a model in the cloud that number belongs to the provider.',
    "feld.orchestratorKontext.info": "A larger window holds more context but permanently occupies more GPU memory: the demand grows with every token, and what no longer fits makes the start fail. That is why every level states what it needs and what is free right now. Nothing is locked: levels the memory does not cover today stay selectable and carry a note -- the decision is yours, not the program's. It is measured by wb-kontext, together with the free memory of this very moment. The choice applies to the orchestrator; the windows of its workers are the orchestrator's own call.",
    "feld.orchestratorKontext.etikett": "takes effect on the next session",
    "wort.kontextToken": "{tokens} tokens",
    "wort.kontextEmpfohlen": "recommended",
    "satz.kontextBedarf": "Needs {bedarf} GiB.",
    "satz.kontextSpeicher": "Free: {frei} GiB, of which the model weights take {gewichte} GB.",
    "satz.kontextFremderWert": "Stored: {tokens} tokens \u2014 the chosen model does not offer that level. As long as no level is selected, the session starts with the stored value.",
    "satz.kontextWirdErmittelt": "Determining the levels \u2026",
    "satz.kontextNichtErmittelt": "The levels could not be determined: {grund}. Until that changes, the session starts with the window registered for this model.",
    "feld.newSessionDefaultDir.name": "Folder a new session starts in",
    "feld.newSessionDefaultDir.wirkung": "The plus button suggests this folder, as long as you do not pick another one.",
    "feld.newSessionDefaultDir.info": 'A suggestion, nothing more: the choice happens in the folder dialog, and picking something else there gets you that instead. "~" stands for your home directory. Until 11.08. this setting was only reachable in the VS Code extension, even though this program has long read it -- so now it lives here.',
    "feld.newSessionDefaultDir.etikett": "takes effect on the next session",
    "feld.showStopped.name": "Show stopped sessions too",
    "feld.showStopped.wirkung": "On: the bar also shows sessions whose terminal is no longer running -- marked red.",
    "feld.showStopped.info": "Off (default) keeps the bar short: only what is alive right now. On is useful for picking up a session from yesterday -- it shows up with its folder and is clickable. This is a setting, not a daily action, which is why it lives here and not as a button in the bar.",
    "feld.showStopped.etikett": "immediately",
    "feld.sort.name": "Order in the bar",
    "feld.sort.wirkung": "What the sessions are ordered by, as long as no order has been dragged by hand.",
    "feld.sort.info": 'A manual drag always wins over this default -- whoever drags a session to a spot wants it there. The default applies to everything added after that. "recently used" orders by the last activity in the terminal, not by when the session was created.',
    "feld.sort.etikett": "immediately",
    "wort.sort.recent": "recently used",
    "wort.sort.folder": "by folder",
    "wort.sort.name": "by name",
    "wort.einheit.punkt": "pt",
    "wort.einheit.zeilen": "lines",
    "wort.einheit.spalten": "columns",
    "wort.einstellungen": "Settings",
    "feld.closeSessionOnWindowClose.name": "Close the terminal with the window",
    "feld.closeSessionOnWindowClose.wirkung": "Off (default): the window closes, the tmux session behind it keeps running -- it gets closed via the right-click on the session. On: closing the window also ends the session.",
    "feld.closeSessionOnWindowClose.info": "Measured on 04.08.: three closed windows kept their tmux sessions alive and held 6.0 GB together. A reload never ends anything -- a session only counts as orphaned after a grace period, and a returning window takes the mark back off. If a worker is still running, it stays open regardless. Since 07.08. the default is still off anyway: reclaimed memory can always be gotten back, a session ended by accident, along with the work running in it, cannot.",
    "feld.closeSessionOnWindowClose.etikett": "immediately",
    // --- Page 2: Permissions ------------------------------------------------
    "feld.workerSkipPermissions.name": "Workers work without their CLI asking first",
    "feld.workerSkipPermissions.wirkung": "On: a worker does not stop at a write access, it works through.",
    "feld.workerSkipPermissions.info": "This is the most consequential quiet decision in the whole setup, and until 06.08. it lived in a single line of shell code. The guards and the ask-first tier still apply -- the CLI's own permission prompt does not. Off means: every worker stops at every write access and waits for a human; an overnight run then sits until morning.",
    "feld.workerSkipPermissions.etikett": "takes effect on the next worker",
    "feld.orchestratorPermissionMode.name": "How much the orchestrator may do without asking",
    "feld.orchestratorPermissionMode.wirkung": "Sets the confirmation level the CLI of the next orchestrator session starts with.",
    "feld.orchestratorPermissionMode.info": "The six levels of claude --permission-mode, measured from claude --help. Lowering -- any change away from bypassPermissions -- goes through at once, no reason needed; raising it back to bypassPermissions, the default, needs a real human at this interface and a reason, checked by wb-state itself. shell/wb-code reads the value when the next orchestrator session starts, not the running one. Workers stay unaffected -- the orchestrator sets those for itself.",
    "feld.orchestratorPermissionMode.etikett": "takes effect on the next session",
    "feld.workerWorktrees.name": "Every worker gets its own worktree",
    "feld.workerWorktrees.wirkung": "On: every worker works in a git repo in its own folder and branch instead of the shared one.",
    "feld.workerWorktrees.info": "The tree lives under ~/.pi-workers/worktrees/<name>, the branch is called wb/<name>. Off means: every worker works in the given directory and runs into each other there -- two touching the same file overwrite one another. Outside a git repo the switch changes nothing. It acts globally, because neither claude-worker nor pi-worker has a per-call switch today.",
    "feld.workerWorktrees.etikett": "takes effect on the next worker",
    "feld.guards.name": "Which safeguards run",
    "feld.guards.wirkung": "Every safeguard can be switched off on its own. A switched-off one stays in the list, with a reason and a date.",
    "feld.guards.info": "They run before every command an agent issues, in this order; the last one is the ask-first tier below. Whatever one of them flatly refuses never reaches the ask-first tier. Two of them (live config, media from the cloud) only warn and stop nothing. Switching one off requires a reason and a human; it is noted with a date next to it, so someone six months from now still knows why the safeguard is missing.",
    "feld.guards.etikett": "immediately",
    "feld.askPatterns.name": "Commands that ask first",
    "feld.askPatterns.wirkung": "These commands are held, show up in the approval view, and go through after a one-time approval.",
    "feld.askPatterns.info": 'Neither harmless nor forbidden -- this is the tier in between. A pattern matches a spot in the parsed command line, not a string anywhere in the text -- otherwise a paragraph merely mentioning "git clean -fd" would already trip the guard (as happened on 05.08.). Switched off instead of deleted keeps it visible that the pattern exists. One approval lasts fifteen minutes, hard-capped in the module.',
    "feld.askPatterns.etikett": "immediately",
    "feld.secretExcludeDirs.name": "Folders no view enters",
    "feld.secretExcludeDirs.wirkung": "No view enters these folders -- they are skipped, not just hidden.",
    "feld.secretExcludeDirs.info": "File tree, quick-open, content search and editor all ask the same spot; a filter a view can bypass is no filter. Every path segment is checked, not just the last one -- otherwise project/.ssh/config would slip through. The list lives here and not in source, because it should be visible and checkable.",
    "feld.secretExcludeDirs.etikett": "immediately",
    "feld.secretExcludePatterns.name": "Filenames no view shows",
    "feld.secretExcludePatterns.wirkung": "Files whose name matches one of these patterns show up in no view.",
    "feld.secretExcludePatterns.info": "A glob on a single path segment, no path separator: * stands for any number of characters, ? for one. Deliberately kept small -- a full glob dialect with ** and {a,b} invites patterns whose effect is no longer visible. Case does not matter.",
    "feld.secretExcludePatterns.etikett": "immediately",
    "feld.werkzeuge.name": "An agent's tools and MCP servers",
    "feld.werkzeuge.wirkung": "What tools an agent gets today lives in its own configuration -- this program reads it, but does not yet set it.",
    "feld.werkzeuge.info": "The hooks below come from ~/.claude/settings.json and apply to every Claude session on this machine; the MCP servers hang off the services mcp-shared manages. Both are shown here, not written: a switch that half-overwrites a foreign configuration is worse than no switch. The way there is described (the workbench writes harness configurations via wb-harness-run) and not yet built.",
    "satz.werkzeugeOhneHooks": "No hook is set in ~/.claude/settings.json. An agent gets whatever tools its CLI brings along on its own.",
    "satz.werkzeugeMcp": "MCP servers are kept as background services by mcp-shared, not by this program. As long as that holds, there is no switch for it here, just this sentence.",
    // The eleven guards -- ids from hooks/bash-guard.py, text from here.
    "guard.secrets.name": "Secrets",
    "guard.secrets.wirkung": "Holds any command that touches a key, a certificate, or the secrets folder.",
    "guard.secrets.info": "Covers ~/work/brain/90-secrets, ~/.ssh, and the usual credential files -- the same list the folder view also skips. Off means: an agent can read, copy, and write these files into an output without anyone being asked.",
    "guard.git-add.name": "Staging everything at once",
    "guard.git-add.wirkung": 'Holds a "git add" that sweeps up a whole directory or the working tree.',
    "guard.git-add.info": `Whoever commits names their paths. A directory add looks harmless and on 16 Aug pulled a second session's half-finished work into two commits that were not its own. Off means: "git add -A" goes through again.`,
    "guard.kill-pattern.name": "Killing other processes",
    "guard.kill-pattern.wirkung": "Holds commands that shoot down processes that do not belong to the agent.",
    "guard.kill-pattern.info": "A pkill with too broad an expression has already taken running workers out of the grid. The guard tells apart what the agent started itself from what was already running.",
    "guard.live-config.name": "Live configuration",
    "guard.live-config.wirkung": "Warns when a command touches the files the running setup depends on.",
    "guard.live-config.info": "A warning only, no stop: the chain keeps running. The reason is an incident where a test overwrote the real settings file and made four running workers invisible.",
    "guard.push-gate.name": "Push gate for workers",
    "guard.push-gate.wirkung": "A worker may not push, open pull requests, or publish anything.",
    "guard.push-gate.info": "The orchestrator decides on pushes, because only it knows the whole state. The guard recognizes the role by the pane, not by the name. Off means: any worker can push into a public repo.",
    "guard.media-cloud.name": "Media from the cloud",
    "guard.media-cloud.wirkung": "Warns when an image, a video, or a voice comes from a paid service instead of locally.",
    "guard.media-cloud.info": "A warning only. The local tools (bild, video, tts, stt) cost nothing and never leave the machine; a cloud call does both, and should therefore happen on purpose.",
    "guard.screencapture.name": "Screen captures",
    "guard.screencapture.wirkung": "Holds commands that photograph or record the screen.",
    "guard.screencapture.info": "A screenshot takes everything that is currently open along with it -- including things that are nobody's business. For evidence images there is the path through the window itself, which captures only its own window.",
    "guard.snapshot.name": "Backup before deleting",
    "guard.snapshot.wirkung": "Holds delete commands as long as no copy of the data has been made.",
    "guard.snapshot.info": "The copy lands under ~/.local/trash-snapshots/<date>-<name>/. The guard checks whether it exists before the delete goes through -- it does not create it.",
    "guard.commit-trailer.name": "A commit's author",
    "guard.commit-trailer.wirkung": "Holds a commit that has a foreign co-author slipped into it.",
    "guard.commit-trailer.info": "In these repos there is one author and nobody else. This guard is the only one that aborts with an error code instead of an answer -- it sits right in front of the commit.",
    "guard.muster.name": "Ask-first tier",
    "guard.muster.wirkung": "The pattern list further below: commands that are neither harmless nor forbidden get held.",
    "guard.muster.info": "The last tier, and the only one that does not refuse but asks. It sits behind all the others: whatever a guard flatly refuses never reaches here. Switched off here means: no pattern triggers an ask-first prompt anymore -- including the ones still checked further below.",
    "guard.pane-write.name": "Typing into other panes",
    "guard.pane-write.wirkung": "Holds commands that write into an orchestrator pane with tmux directly.",
    "guard.pane-write.info": "The second layer next to wb-pane-write: it catches the route around the tool. A test works on its own socket and is not affected.",
    // --- Page 3: Programs and models --------------------------------
    "feld.harnessTabelle.name": "Programs, sign-in and chat view",
    "feld.harnessTabelle.wirkung": "For every agent program: whether it starts here, whether it is signed in, which effort levels it accepts, and whether it can carry a chat view.",
    "feld.harnessTabelle.info": `The levels are measured against each program's own help text, not copied off a list. Sign-in is not a guessing game: it checks whether the evidence the registry names for this provider is present -- if none is named, it says "not checkable", not "not signed in". The chat view depends on the program, not on taste; what a program cannot do gets no gray field here, it gets the plain reason instead.`,
    "wort.startbar": "starts here",
    "wort.nichtStartbar": "does not start on {maschine}",
    "wort.fehltHier": "not installed here",
    "wort.angemeldet": "signed in",
    "wort.nichtAngemeldet": "not signed in",
    "wort.anmeldungUnbekannt": "not checkable",
    "wort.stufenNichtErmittelt": "not determined",
    "wort.keineStufen": "has no levels",
    "spalte.programm": "Program",
    "spalte.stufen": "Levels",
    "spalte.modelle": "Models",
    "spalte.hier": "On this machine",
    "spalte.anmeldung": "Sign-in",
    "spalte.installiert": "Installed",
    "spalte.neueste": "Latest",
    "spalte.zuletztGeprueft": "Last checked",
    "wort.nochNichtGeprueft": "not checked yet",
    "wort.stunden": "hours",
    "wort.minuten": "minutes",
    "spalte.chat": "Chat view",
    "spalte.modell": "Model",
    "spalte.deckel": "Cap",
    "spalte.herkunft": "Source",
    "spalte.grund": "Reason",
    "spalte.einstellung": "Setting",
    "spalte.beiDir": "On your machine",
    "spalte.auslieferung": "Default",
    "spalte.anbieter": "Provider",
    "spalte.zugang": "Access",
    "spalte.eingabe": "Enter",
    "spalte.maschine": "Machine",
    "spalte.wert": "Value",
    "satz.chatKannNicht": "No path to the conversation history is registered -- so there is no switch here.",
    "satz.chatOhneMessung": "Registered, but without a measurement date -- without one, the entry does not count.",
    "satz.chatKannLive": "reads along while the session runs",
    "satz.chatKannNichtLive": "only reads once the session has stopped",
    "satz.chatZeigtNicht": "Does not show: {liste}.",
    "feld.chatAnsicht.name": "Show conversation instead of terminal",
    "feld.chatAnsicht.wirkung": "On: the workbench draws the conversation history for this program instead of the terminal image.",
    "feld.chatAnsicht.info": "The switch is per program, not global, because the ability depends on the program, not on taste. The terminal pane keeps running and is still parsed either way -- that is the only way the workbench knows whether the program is currently asking, answering, or waiting; only the display differs. Whatever is in no transcript (approval dialogs, context usage, progress) shows up in the line next to it.",
    "feld.chatAnsicht.etikett": "takes effect on the next session",
    "feld.workerTransport.name": "What a worker pane hangs on",
    "feld.workerTransport.wirkung": 'On tmux as before, or on a pseudo-terminal the workbench holds itself. "pty" is a prototype: one worker per pseudo-terminal, the context guard and the return channel run over the control socket, and several pty panes side by side in one tab are not built yet.',
    "feld.workerTransport.info": `The way since V1 is tmux: every worker is a pane in a tmux session, and this house's tools are built on that. "pty" comes out of the 2026-09-04 probe (app/src/main/pty.ts): the workbench starts the worker itself on its own pseudo-terminal and mirrors its byte stream into a headless terminal model. The screen the context guard reads from it was byte-for-byte the same as the tmux one in the measurement, and after a restart of the workbench the worker was back with the same conversation. Two spots stay open: the tab view still draws only a single pty pane, and the workbench passes its whole environment down to the worker. With the switch on "tmux" the prototype is not even loaded; an unknown value counts as "tmux" and not as an error.`,
    "feld.workerTransport.etikett": "takes effect on the next worker",
    "feld.ollamaEndpoint.name": "Address of the local model server",
    "feld.ollamaEndpoint.wirkung": "Local models are looked for at this address -- Ollama, vLLM, or MLX, whichever answers there.",
    "feld.ollamaEndpoint.info": "Until 11.08. http://127.0.0.1:11434 was fixed in source in seven places and could not be set anywhere; running Ollama on another machine meant editing seven files by hand. This field is the one place for it. Expected is a full address with http:// or https:// and no path at the end. A server on the network instead of this machine means: the requests leave the machine -- that is a decision, not a detail.",
    "feld.ollamaEndpoint.etikett": "takes effect on the next lookup",
    "satz.ollamaNochNichtVerdrahtet": "The value is stored and shown here. The seven spots in source that still hard-code the address today do not read it yet -- they will be caught up in a separate step.",
    "feld.modelDiscoveryAuto.name": "Fetch model catalogs on their own",
    "feld.modelDiscoveryAuto.wirkung": "On: the providers' catalogs are fetched from the network on their own. Off: only on demand.",
    "feld.modelDiscoveryAuto.info": "Off means only that the network is no longer reached on its own. The local sources -- ollama, the CLIs' own model lists, files -- keep discovering automatically regardless, and the manual fetch button always stays usable. Until 11.08. this setting was only reachable in the VS Code extension, even though wb-state has long read it.",
    "feld.modelDiscoveryAuto.etikett": "immediately",
    "feld.harnessUpdateAuto.name": "Keep agent programs up to date automatically",
    "feld.harnessUpdateAuto.wirkung": "On: the workbench checks and updates the installed harness CLIs on its own.",
    "feld.harnessUpdateAuto.info": "Off prevents even the catalog lookup and therefore all automatic network access. Updates that could endanger a running process are queued and only applied when no live session remains.",
    "feld.harnessUpdateAuto.etikett": "on the next check",
    "feld.harnessUpdateIntervalHours.name": "Harness check interval",
    "feld.harnessUpdateIntervalHours.wirkung": "After the delayed startup check, the workbench checks again at this interval in hours.",
    "feld.harnessUpdateIntervalHours.info": "The interval runs between checks. A lock file prevents two workbench instances from updating at the same time.",
    "feld.harnessUpdateIntervalHours.etikett": "after the next check",
    "feld.orchestratorVorhersage.name": "Multi-token prediction for the orchestrator",
    "feld.orchestratorVorhersage.wirkung": "On: if one is registered for its model, the orchestrator additionally loads a drafter or a build with a built-in prediction head -- faster per reply, but without shared concurrency on the MLX server.",
    "feld.orchestratorVorhersage.info": "Which paths exist is set in the registry: only what is registered and measured there can be picked, never a free-form path. If the registry lists more than one path for the model, they appear below the switch, each with its provenance -- including where nothing was measured. Speculative decoding and the MLX server's shared concurrency are mutually exclusive (mlx_lm.server turns off batching the moment a drafter is set) -- that is why this switch defaults to off.",
    "feld.workerVorhersage.name": "Multi-token prediction for workers",
    "feld.workerVorhersage.wirkung": "On: a worker on a local model loads, if one is registered for it, the same drafter or built-in head -- separate from the orchestrator's switch.",
    "feld.workerVorhersage.info": "Which model gets used is set in the registry and is not selectable here -- this is a read-only display only. Independent of the orchestrator switch: one can be on while the other is off.",
    "wort.vorhersageEntwerfer": "external drafter",
    "wort.vorhersageEingebaut": "built-in head",
    "satz.vorhersageModell": "Model: {modell} ({bauart})",
    "satz.vorhersageKeine": "No prediction is registered for the currently selected model.",
    "satz.vorhersageWegVorgabe": "{weg} (default)",
    "feld.anbieter.name": "Access to the providers",
    "feld.anbieter.wirkung": "For every provider: where its access comes from, and whether it is present on this machine.",
    "feld.anbieter.info": "A key is entered here, but not written into the settings file -- that file is shared plain text that workers write to as well, and a key inside it would be a key in plain text. The value takes its own path instead and is never read back afterward to display it. So all that is shown remains whether access is present -- never its value, never its location. A provider with a subscription instead of a key reports whether sign-in has happened instead.",
    "wort.zugangDa": "present",
    "wort.zugangFehlt": "missing",
    "wort.zugangUnbekannt": "not checkable",
    "wort.zugangAbo": "subscription, no key",
    "wort.zugangLokal": "runs locally, no access needed",
    "feld.effortCaps.name": "Highest level without asking",
    "feld.effortCaps.wirkung": "This is as far as the orchestrator may go when it starts a worker on its own.",
    "feld.effortCaps.info": '"Default" means: the value comes from the registry, as the model shipped. As soon as you set a cap, it shows "set by you" with a date and a reason -- and the reason is required, because a self-imposed commitment without one looks like a technical limit six months from now. Anyone can lower it; raising it requires a human, judged by where the call came from. Back to the shipped default goes through the first entry of the picker.',
    "feld.effortCaps.etikett": "takes effect on the next automatic start",
    "satz.deckelLeitsatzFett": "A cap binds the orchestrator, not you. ",
    "satz.deckelLeitsatz": "When you start something yourself, every level the program accepts is open to you. The cap here applies to workers the orchestrator starts without asking: it should not hand itself the most expensive level on its own.",
    "satz.deckelDieses": "Cap of this model: ",
    "satz.deckelGilt": ". It applies when the orchestrator starts a worker on its own -- it does not apply to your own choice here. ",
    "satz.deckelDarueber": "Dashed outline: the levels above it ({stufen}).",
    "satz.deckelGrund": "Reason for the cap: {grund}",
    "satz.deckelKeiner": "No cap is set for this model -- the orchestrator hands out any level.",
    "satz.deckelUeber": "Above the cap ({deckel}). Selectable: the cap binds the orchestrator, not you.",
    "wort.vonDir": "set by you",
    "wort.ausAuslieferung": "default",
    "wort.vonDirAm": "by you, {datum}",
    "satz.deckelAuslieferungWahl": "Default ({deckel})",
    "wort.ohne": "none",
    "satz.stufenKeineWahl": '"{harness}" has no levels -- there is nothing to choose here.',
    "satz.stufenErstModell": "Pick a model first; the levels depend on its program.",
    // --- Page 4: Machines --------------------------------------------------
    "feld.remoteMachines.name": "Machines that work along",
    "feld.remoteMachines.wirkung": "Every machine here shows up in the session bar and is selectable as a target for a worker.",
    "feld.remoteMachines.info": 'The name is the SSH alias, exactly as "ssh host2" knows it -- there is no second address list next to it. Another host name or an IP works the same way, as long as ssh can handle it; anyone with a gate in front enters the alias that gets through the gate. More than two are explicitly supported. The list stays empty until someone adds an entry: an SSH target is real network access and must never fire on its own. The check button asks exactly once (ssh <name> true).',
    "feld.remoteMachines.etikett": "immediately",
    // The mobile workbench (package 10): server, pairing and devices -- only here on the Mac.
    "gruppe.maschinen.mobil": "Mobile device",
    "feld.mobileServer.name": "Mobile workbench",
    "feld.mobileServer.wirkung": "Starts the server for the workbench app on iPhone and iPad (127.0.0.1, behind an HTTPS proxy). Off: no connection from the phone; paired devices stay stored.",
    "feld.mobileServer.info": "Every request from the phone is signed with the key of a paired device; without a signature the server accepts nothing, not even from this computer. Pairing and revoking only work here with a real click. Addresses and port live in the program configuration (mobileOrigins, mobileOrigin, mobilePort).",
    "mobil.stand.aus": "Off.",
    "mobil.stand.laeuft": "Running on 127.0.0.1:{port} for {origin}.",
    "mobil.stand.fehler": "Not started: {grund}",
    "mobil.koppeln": "Pair device",
    "mobil.code": "Enter this code on the phone: {code}",
    "mobil.codeAblauf": "Valid until {zeit}, at most five attempts. The code appears only here.",
    "mobil.codeAbgelaufen": "The code has expired. Pair again for another device.",
    "mobil.ausblenden": "Hide",
    "mobil.geraeteLeer": "No device paired yet.",
    "mobil.geraetAktiv": "paired on {datum}",
    "mobil.geraetWiderrufen": "revoked on {datum}",
    "mobil.widerrufen": "Revoke",
    "feld.remoteMachinesPausiert.name": "Paused machines",
    "feld.remoteMachinesPausiert.wirkung": "The sessions on a paused machine keep running there undisturbed -- pausing only affects this workbench's view of it: no polling, no sessions in the bar, no mirror panes.",
    "feld.remoteMachinesPausiert.info": 'The name stays entered in "Machines that work along" -- the switch is reversible, without retyping the address. A paused machine does not count as "not reachable": those are two different states.',
    "satz.eigeneMaschine": "This machine -- it is always in the list and cannot be removed.",
    "satz.fremdeMaschine": "Reached via ssh {name} -- the name is also the SSH alias.",
    "satz.keineMaschine": "No further machine is registered. Without an entry the program never reaches the network on its own.",
    "satz.maschineSchonDa": '"{name}" is already in the list.',
    "satz.fremdeLast": "How many workers another machine carries at once lives in the settings file of that machine and is set there: ssh {name} wb-state settings set maxWorkers <number>. Two numbers in two places for the same question would be two truths, one of which is wrong.",
    "feld.maxWorkers.name": "Workers at once on this machine",
    "feld.maxWorkers.wirkung": "A session accepts no more than this many workers -- the next start is refused.",
    "feld.maxWorkers.info": 'Refused, not queued: a start that overflows the window costs more than a start that says "too many". Existing panes keep getting reused, so a finished worker immediately frees up room again. What is counted is worker panes, not subagents. This number belongs to the machine, not the session: what a 48 GB machine carries, a smaller one does not.',
    "feld.maxWorkers.etikett": "immediately",
    "feld.schlafNachMinuten.name": "Put idle sessions to sleep after",
    "feld.schlafNachMinuten.wirkung": "A session that does nothing for this long releases its memory; a click on its tile, a key or a new task wakes it and the conversation continues. 0 turns this off.",
    "feld.schlafNachMinuten.info": "Applies to every harness that can resume its conversation (Claude, pi, Codex, opencode \u2026); one without that stays awake. Idle means: content unchanged, no running tool call, no CPU load. 60 minutes is the prompt cache lifetime \u2013 after that, waking costs no extra tokens. A message from another Claude session does not reach a sleeping one; run wb-schlaf wecken first.",
    "feld.schlafNachMinuten.etikett": "at the next round",
    "feld.defaultWorkerMachine.name": "Where a worker runs when nothing is said",
    "feld.defaultWorkerMachine.wirkung": "Which machine a worker goes to when none is named at start.",
    "feld.defaultWorkerMachine.info": 'The choice comes from the list above: every machine registered there is selectable here. "This machine" means: the worker runs in the same terminal server as the session. A target that does not answer fails the start instead of redirecting it -- hence the check button next to it.',
    "feld.defaultWorkerMachine.etikett": "takes effect on the next worker",
    "wort.dieseMaschine": "This machine ({name})",
    "feld.workerZustellung.name": "How a task reaches the worker",
    "feld.workerZustellung.wirkung": "Through the session inbox, or typed into the pane input line.",
    "feld.workerZustellung.info": 'Typing puts the task into the worker terminal character by character -- visible, but fragile: on the night of 20.08. five panes froze that way and tasks vanished silently. Claude Code ships an inbox for the same purpose that does not go through the input line and therefore cannot overwrite or block anything. "Automatic" uses the inbox where there is one and types otherwise; it is the default because only Claude Code ships an inbox today -- the other programs in the registry type either way, and a default that does not apply to them must not break anything for them. "Inbox only" requires it and lets delivery fail audibly instead of typing as a substitute: meant for test runs and for the case that nothing should be written into an input line at all. For a worker on any other program that choice therefore means it gets no task. "Typing only" is the way back, should the inbox break on a future version of the CLI. Whether a task arrived is checked the same way on all three routes and reported in plain words.',
    "feld.workerZustellung.etikett": "takes effect on the next task",
    "wort.workerZustellung.auto": "automatic",
    "wort.workerZustellung.socket": "inbox only",
    "wort.workerZustellung.paste": "typing only",
    // --- Page 5: Oversight and notifications -------------------------
    "feld.contextGuardAutostart.name": "Context guard starts along",
    "feld.contextGuardAutostart.wirkung": "On: the program starts the guard itself as soon as a session exists -- nobody has to remember it.",
    "feld.contextGuardAutostart.info": `Until 06.08. the orchestrator started its own guard. alice's decision to hand it to the program instead: "If someone picks a weaker model as orchestrator that is not as reliable, the context guard should still be reliable." That way it no longer depends on the diligence of the one it is watching. Off means: no guard runs unless someone starts it by hand.`,
    "feld.contextGuardAutostart.etikett": "takes effect on the next session",
    "feld.wacheOrchAn.name": "Watch the main window",
    "feld.wacheOrchAn.wirkung": "On: the guard also looks over the main window's shoulder, not just the workers'.",
    "feld.wacheOrchAn.info": "Switchable separately, because the two sides cost differently: an orchestrator compacted mid- handoff loses the thread, a worker rarely does. Anyone who does not want oversight over themselves switches it off here and leaves it running for the workers. Switching off requires a reason and a human -- it cannot be done from a worker pane.",
    "feld.wacheOrchAn.etikett": "takes effect on the next guard run",
    "feld.wacheWorkerAn.name": "Watch the workers",
    "feld.wacheWorkerAn.wirkung": "On: every worker pane is read along and nudged when its context fills up.",
    "feld.wacheWorkerAn.info": "A worker compacted without a handoff delivers its task only half done -- the nudge makes sure it writes down what it knows first. A pane narrower than the minimum width cannot be read; the guard then explicitly reports it as blind instead of silently skipping it. Done notifications keep running even while the guard here is off.",
    "feld.wacheWorkerAn.etikett": "takes effect on the next guard run",
    "feld.wacheWorkerMahnenAb.name": "Nudge workers from",
    "feld.wacheWorkerMahnenAb.wirkung": "From this fill level on, the guard asks a worker to write a handoff and compact.",
    "feld.wacheWorkerMahnenAb.info": "Percent of its model's context window. Nudged too early costs work, too late costs the result: whatever is not written down before compacting is gone. 80 leaves enough room for the handoff itself. A higher number means a later nudge, so less of a safety margin -- the tool requires a reason for that.",
    "feld.wacheWorkerMahnenAb.etikett": "takes effect on the next guard run",
    "feld.wacheOrchMahnenAb.name": "Nudge the main window from",
    "feld.wacheOrchMahnenAb.wirkung": "From this fill level on, the orchestrator should catch up its state file and knowledge store.",
    "feld.wacheOrchMahnenAb.info": "Lower than for workers, because it has more to secure: session state, open tasks, whatever belongs in the kbase. Five percentage points of lead time is roughly a quarter hour of work.",
    "feld.wacheOrchMahnenAb.etikett": "takes effect on the next guard run",
    "feld.wacheOrchEingreifen.name": "The guard steps in itself",
    "feld.wacheOrchEingreifen.wirkung": "On: it does not only nudge, it types /compact itself when it has to -- it has the voice and the hand.",
    "feld.wacheOrchEingreifen.info": 'The guard compacts the orchestrator session itself if needed, by typing /compact into a foreign window. Anyone who does not want that but still wants to be warned switches this off: the nudge stays, the intervention goes away. This is the milder tier between "everything" and "guard off".',
    "feld.wacheOrchEingreifen.etikett": "takes effect on the next guard run",
    "feld.wacheOrchNotbremseAb.name": "Emergency brake from",
    "feld.wacheOrchNotbremseAb.wirkung": "From here on, the guard compacts the orchestrator itself -- even without its signal.",
    "feld.wacheOrchNotbremseAb.info": 'It types /compact into a foreign session, never mid-turn. Until 06.08. this number was fixed in source and nowhere visible; anyone who did not know took the sudden compacting for a bug. It only fires while "the guard steps in itself" is on.',
    "feld.wacheOrchNotbremseAb.etikett": "takes effect on the next guard run",
    "feld.stallMinutes.name": 'Report as "stalled" after',
    "feld.stallMinutes.wirkung": "A worker may stay quiet this long before the bar marks it as stalled.",
    "feld.stallMinutes.info": 'Measured against 11,070 pauses from 17 sessions that worked through and delivered: at 5 minutes, 8 of those 17 would have wrongly carried "stalled", at 10 minutes still 4. A child process younger than the silence suppresses the notice regardless -- so a long test run does not count as a stall.',
    "feld.stallMinutes.etikett": "immediately",
    "feld.guardMeldetWorkerStatus.name": "The guard types worker notices into the main window",
    "feld.guardMeldetWorkerStatus.wirkung": 'On: the guard types "worker done" and "worker stalled" itself into the orchestrator pane.',
    "feld.guardMeldetWorkerStatus.info": "Off by default, and this is alice's own decision: the notice looks like his own words, it interrupts him mid-sentence, and the same information already sits in the right-hand sidebar anyway. Unaffected is everything that must never fall silent: the main window's context warning, the typed /compact, and anything sent to worker panes. This switch is read in nine places and, until 11.08., had no field in either interface.",
    "feld.guardMeldetWorkerStatus.etikett": "takes effect on the next guard run",
    "satz.guardsWohnenAnderswo": 'The safeguards that run before every command live on the "Permissions" page -- where everything an agent may do is listed. Offering them here a second time would mean two places for the same decision.',
    "feld.meldungenAn.name": "Notify outside the window",
    "feld.meldungenAn.wirkung": "On: the program lets you know, even while you are doing something else. Off: it stays quiet.",
    "feld.meldungenAn.info": "Until 11.08. the program never reached outward -- no system notice, no sound, nothing to the phone. Anyone doing something else in the meantime only noticed a worker was done or an approval was waiting on the next glance. This switch is the one question everything else hangs on; what and how is notified sits below it. The default is off, because a program that starts ringing unasked would be worse than one that stays quiet.",
    "feld.meldungenAn.etikett": "immediately",
    "feld.meldungenEreignisse.name": "What triggers a notification",
    "feld.meldungenEreignisse.wirkung": "Only these four events can trigger a notification -- each one deselectable on its own.",
    "feld.meldungenEreignisse.info": "Four events, each for a different reason: a finished worker means work is waiting on you; a pending approval means a chain is stuck until you answer; a dead session means something stopped that you think is still running; a nearly exhausted quota means the next hour gets expensive. Deselecting all of them gets you nothing -- then the switch above is the more honest way to say so.",
    "feld.meldungenEreignisse.etikett": "immediately",
    "feld.meldungenWege.name": "Through which channel",
    "feld.meldungenWege.wirkung": "System notice, sound, phone -- alone or together. The channel decides how intrusive it is.",
    "feld.meldungenWege.info": "A system notice is quiet and sits in the notification center; a sound gets you right away, even with the screen off; the phone reaches you away from home. Email is deliberately not an option: sending an email is an outward-facing action with its own approval rule, and a checkbox in a menu would be a quiet way around it.",
    "feld.meldungenWege.etikett": "immediately",
    "feld.meldungenHandyUrl.name": "Address for the phone",
    "feld.meldungenHandyUrl.wirkung": "The webhook a notification is sent to. Empty means: no path to the phone.",
    "feld.meldungenHandyUrl.info": "A webhook is an address a service gives you that gets a message to your phone. Which service you use is up to you -- the program only knows the address and sends text there. This address leaves the machine with every notification, and what it contains is up to the service behind it: do not enter anything here you do not trust it with.",
    "feld.meldungenHandyUrl.etikett": "immediately",
    "feld.meldungenTonDatei.name": "Custom sound",
    "feld.meldungenTonDatei.wirkung": "Path to a sound file. Empty means: the operating system's sound.",
    "feld.meldungenTonDatei.info": "A custom sound is more than taste: with several programs running, a distinct sound tells you a notification came from here without looking. Empty is the safe choice -- the system sound always exists, a file can disappear.",
    "feld.meldungenTonDatei.etikett": "immediately",
    "feld.meldungenLimitSchwelle.name": "When the quota counts as nearly full",
    "feld.meldungenLimitSchwelle.wirkung": "From this share of the quota on, the program notifies you -- provided the event above is checked.",
    "feld.meldungenLimitSchwelle.info": "Percent of the quota in the running window. Warned too early means: you get used to it and miss the one that counts. Too late means: the warning arrives once there is nothing left to save. 85 leaves enough room to still bring running work to an orderly close.",
    "feld.meldungenLimitSchwelle.etikett": "immediately",
    "feld.meldungTesten.name": "Send a test",
    "feld.meldungTesten.wirkung": "Sends a test notification over exactly the channels selected above, and shows below what happened on each one.",
    "feld.meldungTesten.info": "This button sends a single real test notification -- system notice, sound, webhook, whichever is checked above -- and then reports per channel whether it worked: the HTTP status for the webhook, otherwise the reason it did not. If the main switch is off, the button says so and sends nothing.",
    "knopf.meldungTesten": "Send a test",
    "meldungTesten.hauptschalterAus": "The main switch above is off -- nothing was sent.",
    "meldungTesten.keinWeg": "No channel is selected -- nothing was sent.",
    "meldungTesten.laeuft": "Sending test \u2026",
    "meldungTesten.system.ok": "System notice: delivered",
    "meldungTesten.system.fehler": "System notice: failed -- {grund}",
    "meldungTesten.ton.ok": "Sound: played",
    "meldungTesten.ton.fehler": "Sound: failed -- {grund}",
    "meldungTesten.handy.ok": "Phone: webhook answered with HTTP {status}",
    "meldungTesten.handy.fehler": "Phone: failed -- {grund}",
    "meldung.workerFertig": "A worker is done",
    "meldung.freigabeWartet": "An approval is waiting on you",
    "meldung.sitzungTot": "A session has died",
    "meldung.limitFastVoll": "The quota is nearly full",
    "weg.system": "System notice",
    "weg.ton": "Sound",
    "weg.handy": "Phone",
    "platzhalter.handyUrl": "https://\u2026  (empty = no path to the phone)",
    "platzhalter.tonDatei": "~/Music/notify.aiff  (empty = system sound)",
    // --- Page 6: Appearance ---------------------------------------------------
    "feld.thema.name": "Light or dark",
    "feld.thema.wirkung": "Whether the program looks light, dark, or however the operating system is currently set.",
    "feld.thema.info": `"Follow system" tracks the operating system's switch, even mid-work. The terminal panes themselves do not follow: their colors come from tmux and the given CLI, and a second place for that would mean two truths. Today this window follows it; the other windows will catch up once their colors come from the same source.`,
    "feld.thema.etikett": "immediately",
    "wort.thema.system": "follow system",
    "wort.thema.hell": "light",
    "wort.thema.dunkel": "dark",
    "feld.zustandsfarben.name": "The session-state colors",
    "feld.zustandsfarben.wirkung": "How you tell in the bar whether a session is working, waiting, done, or no longer running.",
    "feld.zustandsfarben.info": "Four states, four colors, and they need to be distinguishable for you, not for a catalog. Anyone who has trouble telling red from green sets two colors here they can actually see. Back to default goes through the mark next to the heading.",
    "feld.zustandsfarben.etikett": "immediately",
    "zustand.laeuft": "working",
    "zustand.wartet": "waiting on you",
    "zustand.fertig": "done",
    "zustand.tot": "no longer running",
    "feld.terminalFontSize.name": "Terminal font size",
    "feld.terminalFontSize.wirkung": "How large the font is in every terminal pane. The change shows immediately.",
    "feld.terminalFontSize.info": "It also decides how many columns and rows fit in a pane: a larger font means fewer columns on the same area. Below 80 columns the context guard can no longer reliably read a worker's status line -- so a strongly enlarged font tends to earn a second worker tab rather than narrower panes. 8 to 32 is allowed; a value outside that is refused and the old one stays.",
    "feld.terminalFontSize.etikett": "immediately",
    "feld.terminalScrollLines.name": "Lines per scroll notch",
    "feld.terminalScrollLines.wirkung": "How far one notch of the mouse wheel scrolls -- the same in the window's scrollback and in the application inside the pane.",
    "feld.terminalScrollLines.info": `Until 06.08. this number fell out of the cell height: a wheel event's travelled distance was divided by the height of one line. That depended on the device (a trackpad sends many small events, a mouse a few large ones) and on the font size, and was reported as "way too fast" because of it. Now only this number counts: one notch moves this many lines. A trackpad swipe accumulates its fractions, and a single event never moves more than six lines. 1 to 20 is allowed.`,
    "feld.terminalScrollLines.etikett": "immediately",
    "feld.minWorkerPaneWidth.name": "Narrowest worker pane",
    "feld.minWorkerPaneWidth.wirkung": "This is how narrow a worker pane may get. Below that, the window would rather open a second tab.",
    "feld.minWorkerPaneWidth.info": "Measured on 04.08.: at 60 columns a real Claude CLI status line fell back to a bare bar or worse; 80 is the confirmed floor at which it still reads exactly right with a realistic path. Below that the context guard reports the pane as blind and does not watch it -- so a narrower value does not buy a denser view, it buys blind guards. 20 to 1000 is allowed.",
    "feld.minWorkerPaneWidth.etikett": "immediately",
    "feld.maxWorkerPanesPerTab.name": "Workers per tab",
    "feld.maxWorkerPanesPerTab.wirkung": "From this count on, the window opens another worker tab instead of shrinking the panes further.",
    "feld.maxWorkerPanesPerTab.info": "Measured on 04.08.: on the reference window (197 \xD7 54), two columns of 80 columns fit next to three rows of readable height -- so 6. Below 80 columns the context guard can no longer reliably read the status line and reports the pane as blind. 0 means: no cap of its own; how many really fit side by side is worked out by the window from its size and the minimum width above anyway.",
    "feld.maxWorkerPanesPerTab.etikett": "takes effect on the next re-layout",
    "feld.workerLayout.name": "Where the worker panes sit",
    "feld.workerLayout.wirkung": "Split under the main window, or in a window of their own next to it.",
    "feld.workerLayout.info": "Split means: the workers sit as panes under the orchestrator, everything in one view, each pane narrower. Own window means: the workers get their own window, which can be moved to a second screen. This is a question of screen space, not of the model. Until 11.08. this setting was only reachable in the VS Code extension, even though four tools read it.",
    "feld.workerLayout.etikett": "takes effect on the next re-layout",
    "wort.workerLayout.split": "split under the main window",
    "wort.workerLayout.window": "own window",
    "wort.permissionMode.acceptEdits": "Accept edits",
    "wort.permissionMode.auto": "Automatic",
    "wort.permissionMode.bypassPermissions": "Bypass permissions",
    "wort.permissionMode.manual": "By hand",
    "wort.permissionMode.dontAsk": "Do not ask",
    "wort.permissionMode.plan": "Plan only",
    "feld.sprache.name": "Interface language",
    "feld.sprache.wirkung": "What language this program's labels are in.",
    "feld.sprache.info": "Every label in this window comes from a single table, no longer from source -- that is what makes a second language a second table instead of a pass through two thousand lines. English is the shipped default; German stays fully maintained alongside it.",
    "feld.sprache.etikett": "immediately",
    "wort.sprache.de": "Deutsch",
    "wort.sprache.en": "English",
    "satz.spracheNochNichtDa": "This language has no table yet. Until the second table exists, the interface stays English -- half-translated would be worse than not at all.",
    "feld.chatAnsichtVorgabe.name": "New sessions show the conversation",
    "feld.chatAnsichtVorgabe.wirkung": "On: new panes start in the chat view, wherever its program can do that -- set separately for the orchestrator and for its workers.",
    "feld.chatAnsichtVorgabe.info": `This is the default per role, not a statement of what a program can do -- that lives per program on the "Programs and models" page. A program with no path to the conversation history stays on the terminal image regardless of what is set here. For a single session, right-clicking it beats this default: it switches that session's orchestrator immediately, and only it. The workers keep following what is set here.`,
    "feld.chatAnsichtVorgabe.etikett": "takes effect on the next session",
    "wort.rolle.orchestrator": "Orchestrator",
    "wort.rolle.worker": "Worker",
    // --- Page 7: Program ---------------------------------------------------
    "feld.pfade.name": "This program's files",
    "feld.pfade.wirkung": "Where the two configuration files, the registry, and the interface state live.",
    "feld.pfade.info": `Two files, split by responsibility: what the program and the tools mean together lives in the settings (~/.claude/workbench/settings.json) -- the lock sits there, and writes only ever go through wb-state, which logs every change with its author. What only this program needs to boot (paths, socket, machine id) lives in the program configuration. No key lives in both. The paths are read from this run's own configuration, not hard-wired. Which logs the log view shows is deliberately only changeable from the command line: wb-state settings set logPaths '[{"label":"\u2026","path":"\u2026"}]'.`,
    "feld.erststartZeigen.name": "Guided first start",
    "feld.erststartZeigen.wirkung": "Opens the same window that appears on its own the very first time this workbench starts.",
    "feld.erststartZeigen.info": "The same walkthrough as the first start, just called by hand -- to read it again, or to show it to a second person on this machine. The button resets nothing: the fact that the first start already ran stays on record, so the window still will not appear on its own the next time the program actually starts.",
    "feld.erststartZeigen.etikett": "immediately",
    "feld.abweichungen.name": "Deviations from the shipped defaults",
    "feld.abweichungen.wirkung": "Everything you have changed, in one list -- with the way back.",
    "feld.abweichungen.info": "For a program meant to be passed on, this is the one honest answer to why it behaves differently for two people. Compared against is the shipped default, not yesterday's state. A value that was never touched does not show up here -- not even when it happens to look the same.",
    "feld.abweichungen.etikett": "immediately",
    "satz.keineAbweichung": "Nothing -- everything stands as it shipped.",
    "feld.sicherung.name": "Back up, reset, transfer",
    "feld.sicherung.wirkung": "The whole state as text: copy it and put it aside, paste it back in here, or reset everything to defaults.",
    "feld.sicherung.info": "Until 11.08. only single keys could be reset one at a time; before a bigger change there was no way to back up the prior state. The text below is exactly what differs from the shipped defaults -- not the whole file, because backing up defaults would mean locking them in when pasted on another machine. Pasting in goes key by key through the same write path as any checkbox; whatever the tool rejects is not stored, and shows up in the footer afterward.",
    "feld.sicherung.etikett": "immediately",
    "wort.kopieren": "to clipboard",
    "wort.einsetzen": "paste in",
    "wort.allesZurueck": "reset everything to default",
    "satz.sicherungKopiert": "The state is on the clipboard ({zeichen} characters).",
    "satz.sicherungKeinText": "The field is empty -- nothing to paste in.",
    "satz.sicherungKeinJson": "That is not a JSON object. What is expected is exactly what the button above produces.",
    "satz.sicherungEingesetzt": "{anzahl} settings pasted in.",
    "satz.sicherungLeer": "Nothing deviates -- there is nothing to back up.",
    // --- Controls, shared across all pages ------------------------------
    "wort.hinzufuegen": "Add",
    "wort.entfernen": "remove",
    "wort.pruefen": "check",
    "wort.zuruecksetzen": "reset",
    "wort.speichern": "save",
    "wort.erneutZeigen": "show again",
    "wort.frage": "ask \u2026",
    "wort.erreichbar": "reachable",
    "wort.nichtErreichbar": "not reachable: {grund}",
    "wort.an": "on",
    "wort.aus": "off",
    "wort.einEintrag": "1 entry",
    "wort.mehrereEintraege": "{anzahl} entries",
    "wort.leereListe": "empty list",
    "wort.maschineLaden": "Load sessions from this machine",
    "wort.sitzungenLaden": "Load sessions",
    "wort.nichtsGesetzt": "nothing set",
    "wort.alleModelle": "All {anzahl}",
    "wort.leerListe": "empty -- nothing gets skipped",
    "platzhalter.modellsuche": "further filter by name or id \u2026",
    "platzhalter.suche": "filter by name or id \u2026",
    "platzhalter.maschine": "SSH alias, e.g. host2",
    "platzhalter.musterBefehl": "command, e.g. rsync",
    "platzhalter.musterUnterbefehl": "subcommand (may stay empty)",
    "platzhalter.musterGrund": "Why it asks first",
    "platzhalter.ordner": "folder name",
    "platzhalter.dateimuster": "file pattern",
    "platzhalter.startordner": "~/AI",
    "platzhalter.ollama": "http://127.0.0.1:11434",
    "platzhalter.sicherung": "Paste a saved state in here \u2026",
    "platzhalter.schluesselEingabe": "Paste value \u2026",
    "satz.schluesselLeer": "No value entered -- nothing saved.",
    "satz.schluesselGespeichert": "Stored for {anbieter}.",
    "satz.schluesselFehler": "Failed to store it.",
    "satz.keinTreffer": "No model matches the filter and search.",
    "satz.keinTrefferSuche": "No model matches the search.",
    "satz.zuVieleTreffer": "{anzahl} models match -- showing the first 60. Search by name or id.",
    "satz.keineMuster": "No patterns -- no command asks first.",
    "satz.keineGuards": "The list of safeguards cannot be read -- wb-state is not answering. Until then, assume all of them run.",
    "satz.abgeschaltet": "Switched off",
    "satz.abgeschaltetFuer": "Switched off for {rolle}",
    "satz.seit": " since {datum}",
    "satz.stehtAufVorgabe": "Stands at the shipped default.",
    "satz.zurueckAufVorgabe": "Back to default: {wert}",
    "satz.infoTitel": 'What does "{feld}" do?',
    "satz.musterOhneBefehl": "A pattern without a command name would be a text search over the whole line -- it is not created.",
    "satz.musterVonHand": "Entered by hand.",
    "satz.schreibe": "writing {schluessel} \u2026",
    "satz.oberflaeche": "Interface: {schluessel} = {wert}",
    "satz.fehler": "Error: {aufruf} \u2014 {ausgabe}",
    "satz.ohneGrundNichts": "Nothing changes without a reason -- write in one sentence why.",
    // --- Confirmation prompts ----------------------------------------------------------
    "frage.wacheAus.text": "The context guard is no longer started on its own after this. A session then runs without any oversight of its context: nobody nudges before it fills up, nobody compacts, and a handoff only happens if someone remembers to write one by hand.",
    "frage.wacheAus.tun": "Switch off the guard",
    "frage.wacheOrchAus.text": "The context guard leaves the orchestrator alone after this: no nudge, no emergency brake, no /compact -- not even right before overflow. It keeps running for the workers.",
    "frage.wacheOrchAus.tun": "Switch off for the main window",
    "frage.wacheWorkerAus.text": "No worker gets nudged or compacted after this. A worker that fills up quietly loses whatever it did not write down.",
    "frage.wacheWorkerAus.tun": "Switch off for workers",
    "frage.mahnenHoch.worker": "Nudging later means less lead time: from {wert}% on, a worker has less room left to write its handoff before compacting happens.",
    "frage.mahnenHoch.orch": "From {wert}% on, the orchestrator only gets nudged later -- it then has less room to secure state and knowledge before compacting happens.",
    "frage.mahnenHoch.tun": "Raise the threshold",
    "frage.eingreifenAus.text": "The guard keeps nudging after this, but no longer steps in: it types no /compact, not even at the emergency brake. Missing the nudge runs you straight into a full context.",
    "frage.eingreifenAus.tun": "Switch off stepping in",
    "frage.notbremseHoch.text": "The emergency brake only fires from {wert}% on. The higher it sits, the closer to overflow compacting happens.",
    "frage.notbremseHoch.tun": "Raise the emergency brake",
    "frage.guardAus.text": '"{name}" no longer fires after this. {wirkung} Whatever this safeguard held until now goes through unasked from this point on -- the others are unaffected.',
    "frage.guardAus.tun": "Switch off the safeguard",
    "frage.musterAus.text": '"{name}" no longer triggers an ask-first prompt after this. {grund} The command goes through unasked from now on, unless some guard flatly refuses it regardless.',
    "frage.musterAus.tun": "Switch off the pattern",
    "frage.musterWeg.text": 'The pattern "{name}" is deleted from the list. After that there is no sign it ever existed -- anyone who only wants it gone for now should switch it off instead.',
    "frage.musterWeg.tun": "Delete the pattern",
    "frage.skipAn.text": "Every new worker starts with its CLI's permission prompt suppressed after this: it writes files without asking. The safeguards and the ask-first tier are unaffected -- the CLI's own prompt is not.",
    "frage.skipAn.tun": "Suppress the prompts",
    "frage.permissionModeAn.text": "The CLI of the next orchestrator session will stop asking for anything after this -- no edit, no run, no confirmation. That is the strongest of the six levels, and it needs a reason.",
    "frage.permissionModeAn.tun": "Raise to bypassPermissions",
    "frage.listeLeer.text": "The list is empty after this: {was} are no longer skipped anywhere. File tree, quick-open, content search and editor then also show what used to be missing here.",
    "frage.listeLeer.tun": "Clear the list",
    "frage.deckel.text": 'The cap of "{modell}" is set to {stufe} after this. It applies to workers the orchestrator starts without asking -- your own choice stays free. A cap without a reason reads like a technical limit six months from now, which is why one belongs with it.',
    "frage.deckel.tun": "Set the cap",
    "frage.allesZurueck.text": "Every one of the {anzahl} deviations is reset to the shipped default -- including switched-off safeguards, loosened guards, and set caps. Back up the current state first if you want it back.",
    "frage.allesZurueck.tun": "Reset everything",
    "frage.einsetzen.text": "{anzahl} settings are taken from the text and overwrite whatever applies now. Whatever the tool rejects stays as it was.",
    "frage.einsetzen.tun": "Paste in",
    // --- The names in "what differs on your machine" --------------------------
    // They live here and not a second time in source: the same table, the same
    // words as on the pages.
    "bezeichnung.closeSessionOnWindowClose": "Close the terminal with the window",
    "bezeichnung.orchestratorHarness": "Program in the main window",
    "bezeichnung.orchestratorModel": "Model of the session",
    "bezeichnung.orchestratorEffort": "How deep the session thinks",
    "bezeichnung.workerEffort": "Effort level of a worker with none of its own (not in the menu)",
    "bezeichnung.workerModel": "Model of a worker with none of its own (not in the menu)",
    "bezeichnung.workerLayout": "Where the worker panes sit",
    "bezeichnung.orchestratorVorhersage": "Multi-token prediction for the orchestrator",
    "bezeichnung.orchestratorVorhersageWeg": "Route of multi-token prediction for the orchestrator",
    "bezeichnung.workerVorhersage": "Multi-token prediction for workers",
    "bezeichnung.erststartErledigt": "The guided first run has been completed",
    "bezeichnung.newSessionDefaultDir": "Folder a new session starts in",
    "bezeichnung.modelDiscoveryAuto": "Fetch model catalogs on their own",
    "bezeichnung.maxWorkers": "Workers at once on this machine",
    "bezeichnung.workerWorktrees": "Every worker gets its own worktree",
    "bezeichnung.defaultWorkerMachine": "Where a worker runs when nothing is said",
    "bezeichnung.workerZustellung": "How a task reaches the worker",
    "bezeichnung.workerTransport": "What a worker pane hangs on",
    "bezeichnung.maxWorkerPanesPerTab": "Workers per tab",
    "bezeichnung.minWorkerPaneWidth": "Narrowest worker pane",
    "bezeichnung.contextGuardAutostart": "Context guard starts along",
    "bezeichnung.guardMeldetWorkerStatus": "The guard types worker notices into the main window",
    "bezeichnung.stallMinutes": 'Report as "stalled" after',
    "bezeichnung.workerSkipPermissions": "Workers work without their CLI asking first",
    "bezeichnung.orchestratorPermissionMode": "How much the orchestrator may do without asking",
    "bezeichnung.askPatterns": "Commands that ask first",
    "bezeichnung.secretExcludeDirs": "Folders no view enters",
    "bezeichnung.secretExcludePatterns": "Filenames no view shows",
    "bezeichnung.terminalFontSize": "Terminal font size",
    "bezeichnung.terminalScrollLines": "Lines per scroll notch",
    "bezeichnung.logPaths": "Log paths (display only)",
    "bezeichnung.effortCaps": "Set effort caps",
    "bezeichnung.guards": "Switched-off safeguards",
    "bezeichnung.kontextwache": "Adjusted context guard",
    "bezeichnung.remoteMachines": "Machines that work along",
    "bezeichnung.remoteMachinesPausiert": "Paused machines",
    "bezeichnung.ollamaEndpoint": "Address of the local model server",
    "bezeichnung.meldungen": "What you get notified about outside the window",
    "bezeichnung.sprache": "Interface language",
    "bezeichnung.thema": "Light or dark",
    "bezeichnung.zustandsfarben": "The session-state colors",
    "bezeichnung.chatAnsicht": "Show conversation instead of terminal",
    "bezeichnung.chatAnsichtVorgabe": "New sessions show the conversation"
  };
  var TABELLEN = { de: DE, en: EN };
  var aktuelleSprache = "en";
  function setzeSprache(s) {
    aktuelleSprache = s === "de" ? "de" : "en";
  }
  function sprache() {
    return aktuelleSprache;
  }
  function spracheHatTabelle() {
    return TABELLEN[aktuelleSprache] !== void 0;
  }
  function t(schluessel, werte) {
    const tabelle = TABELLEN[aktuelleSprache] ?? DE;
    const roh = tabelle[schluessel] ?? DE[schluessel];
    if (roh === void 0) return `[fehlender Text: ${schluessel}]`;
    if (!werte) return roh;
    return roh.replace(/\{([A-Za-z][A-Za-z0-9]*)\}/g, (ganz, name) => {
      const w = werte[name];
      return w === void 0 ? ganz : String(w);
    });
  }
  function tOpt(schluessel, werte) {
    const tabelle = TABELLEN[aktuelleSprache] ?? DE;
    const roh = tabelle[schluessel] ?? DE[schluessel];
    if (roh === void 0) return "";
    if (!werte) return roh;
    return roh.replace(/\{([A-Za-z][A-Za-z0-9]*)\}/g, (ganz, name) => {
      const w = werte[name];
      return w === void 0 ? ganz : String(w);
    });
  }

  // src/einstellungen/einstellungen.ts
  function modellZu(modelle, wert) {
    return modelle.find((m) => m.id === wert) ?? modelle.find((m) => !!m.familie && m.familie === wert);
  }
  var daten = null;
  var aktuelleSeite = "sitzung";
  var filterStand = /* @__PURE__ */ new Map();
  var suchStand = /* @__PURE__ */ new Map();
  var offenesInfo = "";
  var sicherungsText = "";
  var schluesselStand = {};
  var kontextStand = {};
  var kontextLaeuft = /* @__PURE__ */ new Set();
  function kontextHolen(modellId) {
    if (!modellId || kontextLaeuft.has(modellId) || kontextStand[modellId]) return;
    kontextLaeuft.add(modellId);
    void window.awbEinstellungen.kontextStufen(modellId).then((a) => {
      kontextStand[modellId] = a;
    }).catch((e) => {
      kontextStand[modellId] = { ok: false, fehler: String(e) };
    }).then(() => {
      kontextLaeuft.delete(modellId);
      zeichne();
    });
  }
  async function schluesselStatusLaden() {
    try {
      schluesselStand = await window.awbEinstellungen.schluesselStatus();
    } catch {
      schluesselStand = {};
    }
    zeichne();
  }
  var seitenlisteEl = document.getElementById("seitenliste");
  var stapelEl = document.getElementById("stapel");
  var statusEl = document.getElementById("statuszeile");
  var infotextEl = document.getElementById("infotext");
  var rueckfrageEl = document.getElementById("rueckfrage");
  var rueckfrageTextEl = document.getElementById("rueckfrageText");
  function el(tag, klasse, text) {
    const e = document.createElement(tag);
    if (klasse) e.className = klasse;
    if (text !== void 0) e.textContent = text;
    return e;
  }
  function melde(text, art = "") {
    statusEl.textContent = text;
    statusEl.className = art;
  }
  function infoZu() {
    offenesInfo = "";
    infotextEl.classList.remove("offen");
    for (const b of document.querySelectorAll(".infozeichen.offen")) b.classList.remove("offen");
  }
  function infoAuf(knopf2, kennung, text) {
    infoZu();
    offenesInfo = kennung;
    infotextEl.textContent = text;
    infotextEl.classList.add("offen");
    knopf2.classList.add("offen");
    infotextEl.style.left = "0px";
    infotextEl.style.top = "0px";
    const zeichen = knopf2.getBoundingClientRect();
    const kasten = infotextEl.getBoundingClientRect();
    const links = Math.max(8, Math.min(zeichen.left, window.innerWidth - kasten.width - 10));
    let oben = zeichen.bottom + 6;
    if (oben + kasten.height > window.innerHeight - 8) oben = zeichen.top - kasten.height - 6;
    oben = Math.max(8, Math.min(oben, window.innerHeight - kasten.height - 8));
    infotextEl.style.left = `${Math.round(links)}px`;
    infotextEl.style.top = `${Math.round(oben)}px`;
  }
  function infozeichen(kennung, text) {
    const b = el("button", "infozeichen");
    b.type = "button";
    b.textContent = "i";
    b.dataset.info = kennung;
    b.title = text;
    b.setAttribute("aria-label", t("satz.infoTitel", { feld: kennung }));
    b.addEventListener("mouseenter", () => infoAuf(b, kennung, text));
    b.addEventListener("focus", () => infoAuf(b, kennung, text));
    b.addEventListener("mouseleave", () => {
      if (b.dataset.gehalten !== "1") infoZu();
    });
    b.addEventListener("blur", () => {
      if (b.dataset.gehalten !== "1") infoZu();
    });
    b.addEventListener("click", () => {
      const zu = offenesInfo === kennung && b.dataset.gehalten === "1";
      if (zu) {
        b.dataset.gehalten = "0";
        infoZu();
      } else {
        b.dataset.gehalten = "1";
        infoAuf(b, kennung, text);
      }
    });
    return b;
  }
  function texte(kennung, werte) {
    return {
      name: t(`feld.${kennung}.name`, werte),
      wirkung: t(`feld.${kennung}.wirkung`, werte),
      info: t(`feld.${kennung}.info`, werte),
      // Optional -- nicht jedes Feld hat eine Zeitfrage. tOpt() statt t(): ein
      // fehlender Schluessel darf hier nicht als sichtbarer Fehlertext erscheinen
      // (Befund 11.08.: 'anbieter', 'harnessTabelle', 'pfade', 'werkzeuge' zeigten
      // '[fehlender Text: feld.X.etikett]').
      etikett: tOpt(`feld.${kennung}.etikett`, werte)
    };
  }
  var gezeichneteFelder = [];
  function gleichwie(a, b) {
    return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
  }
  function gruppe(seite, titel, klasse = "gruppe") {
    const g = el("div", klasse);
    g.appendChild(el("h2", void 0, titel));
    const koerper = el("div", "koerper");
    g.appendChild(koerper);
    seite.appendChild(g);
    return koerper;
  }
  function klartext(g, text) {
    const p = el("div", "klartext", text);
    g.appendChild(p);
    return p;
  }
  function vorhersageAnzeige(modelle, modellId) {
    const m = modellZu(modelle, modellId);
    if (!m?.vorhersage) return t("satz.vorhersageKeine");
    const { bauart, modell, herkunft } = m.vorhersage;
    const kurz = modell.split("/").pop() ?? modell;
    const bauartText = bauart === "entwerfer" ? t("wort.vorhersageEntwerfer") : t("wort.vorhersageEingebaut");
    return t("satz.vorhersageModell", { modell: kurz, bauart: bauartText }) + (herkunft ? ` (${herkunft})` : "");
  }
  function vorhersageWegWahl(modelle, modellId, gewaehlt, setzen) {
    const m = modellZu(modelle, modellId);
    const wege = m?.vorhersage?.wege;
    if (!wege || wege.length < 2) return null;
    const vorgabe = m?.vorhersage?.wegVorgabe ?? wege[0].id;
    const wirksam = wege.some((w) => w.id === gewaehlt) ? gewaehlt : vorgabe;
    const box = el("div", "vorhersagewege");
    box.appendChild(segmente(
      "orchestratorVorhersageWeg",
      wirksam,
      wege.map((w) => ({
        wert: w.id,
        label: w.id === vorgabe ? t("satz.vorhersageWegVorgabe", { weg: w.label }) : w.label
      })),
      // Der Vorgabeweg wird als LEER gespeichert, nicht unter seiner id: dann
      // steht die Einstellung auf ihrem Vorgabewert, das Rueckstell-Zeichen der
      // Zeile ist stumpf, und ein spaeter gewechselter Vorgabeweg in der Registry
      // wirkt, ohne dass jemand hier nachstellen muss.
      (w) => setzen(w === vorgabe ? "" : w)
    ));
    const weg = wege.find((w) => w.id === wirksam);
    if (weg) {
      const bauartText = weg.bauart === "entwerfer" ? t("wort.vorhersageEntwerfer") : t("wort.vorhersageEingebaut");
      const kurz = weg.modell.split("/").pop() ?? weg.modell;
      box.appendChild(el(
        "div",
        "klartext",
        t("satz.vorhersageModell", { modell: kurz, bauart: bauartText })
      ));
      if (weg.herkunft) box.appendChild(el("div", "grund", weg.herkunft));
    }
    return box;
  }
  function feld(g, o) {
    const kennung = o.schluessel ?? o.uiSchluessel ?? o.name;
    const f = el("div", o.breit ? "feld breit" : "feld");
    f.dataset.feld = kennung;
    const kopf = el("div", "kopf");
    kopf.appendChild(el("span", "name", o.name));
    kopf.appendChild(infozeichen(kennung, o.info));
    if (o.schluessel && daten) {
      const vorgabe = daten.vorgaben[o.schluessel];
      const jetzt = daten.settings[o.schluessel];
      const steht = jetzt === void 0 || gleichwie(jetzt, vorgabe);
      const z = el("button", "zurueck");
      z.type = "button";
      z.textContent = "\u21BA";
      z.dataset.zurueck = o.schluessel;
      z.disabled = steht || vorgabe === void 0;
      z.title = steht ? t("satz.stehtAufVorgabe") : t("satz.zurueckAufVorgabe", { wert: kurzWert(vorgabe) });
      if (!z.disabled) z.addEventListener("click", () => void setze(o.schluessel, vorgabe));
      kopf.appendChild(z);
    }
    const etikett = o.etikett ? el("span", o.wartet ? "etikett wartet" : "etikett", o.etikett) : null;
    if (etikett && o.breit) kopf.appendChild(etikett);
    f.appendChild(kopf);
    const steuer = el("div", "steuer");
    steuer.appendChild(o.steuer);
    if (etikett && !o.breit) steuer.appendChild(etikett);
    f.appendChild(steuer);
    f.appendChild(el("div", "desc", o.wirkung));
    g.appendChild(f);
    gezeichneteFelder.push({ id: kennung, name: o.name, wirkung: o.wirkung, info: o.info });
    return f;
  }
  function wertZelle(schluessel, v) {
    const roh = kurzWert(v);
    const label = typeof v === "string" ? tOpt(`wort.${schluessel}.${v}`) : "";
    if (!label || label === roh) return el("td", "wert", roh);
    const td = el("td");
    td.appendChild(el("span", void 0, label));
    td.appendChild(el("code", "roh", roh));
    return td;
  }
  function kurzWert(v) {
    if (Array.isArray(v)) {
      if (v.length === 0) return t("wort.leereListe");
      return v.length === 1 ? t("wort.einEintrag") : t("wort.mehrereEintraege", { anzahl: v.length });
    }
    if (typeof v === "boolean") return v ? t("wort.an") : t("wort.aus");
    if (v && typeof v === "object") {
      const eintraege = Object.entries(v);
      if (eintraege.length === 0) return t("wort.nichtsGesetzt");
      const stueck = eintraege.slice(0, 3).map(([k, w]) => {
        if (!w || typeof w !== "object") return `${k}=${String(w)}`;
        const inner = Object.entries(w).filter(([ik]) => ik !== "grund" && ik !== "seit" && ik !== "gesetzt").slice(0, 3).map(([ik, iw]) => `${ik}=${String(iw)}`);
        return inner.length ? `${k} (${inner.join(", ")})` : k;
      });
      return eintraege.length > 3 ? `${stueck.join(" \xB7 ")} \u2026 (${eintraege.length})` : stueck.join(" \xB7 ");
    }
    return String(v);
  }
  function haken(id, wert, auf) {
    const c = el("input");
    c.type = "checkbox";
    c.id = id;
    c.checked = wert;
    c.addEventListener("change", (e) => auf(c.checked, e.isTrusted));
    return c;
  }
  function zahl(id, wert, min, max, einheit, auf) {
    const box = el("span", "steuerpaar");
    const i = el("input");
    i.type = "number";
    i.id = id;
    i.min = String(min);
    if (max !== void 0) i.max = String(max);
    i.step = "1";
    i.value = String(wert);
    i.addEventListener("change", (e) => auf(Number(i.value), e.isTrusted));
    box.appendChild(i);
    if (einheit) {
      box.appendChild(document.createTextNode(" "));
      box.appendChild(el("span", "einheit", einheit));
    }
    return box;
  }
  function textzeile(id, wert, platzhalter, auf) {
    const i = el("input", "textzeile");
    i.type = "text";
    i.id = id;
    i.value = wert;
    i.placeholder = platzhalter;
    i.spellcheck = false;
    i.addEventListener("change", (e) => auf(i.value.trim(), e.isTrusted));
    return i;
  }
  function aufklappliste(id, wahl, stufen, auf) {
    const w = el("select", "aufklapp");
    w.id = id;
    for (const s of stufen) {
      const o = el("option");
      o.value = s.wert;
      o.textContent = s.label;
      o.dataset.wert = s.wert;
      if (s.titel) o.title = s.titel;
      if (s.klasse) o.classList.add(s.klasse);
      if (s.gesperrt) o.disabled = true;
      if (s.wert === wahl) o.selected = true;
      w.appendChild(o);
    }
    const gewaehlt = stufen.find((s) => s.wert === wahl);
    if (gewaehlt) w.title = gewaehlt.label;
    else w.selectedIndex = -1;
    w.addEventListener("change", (e) => auf(w.value, e.isTrusted));
    return w;
  }
  function segmente(id, wahl, stufen, auf) {
    if (stufen.length > 6) return aufklappliste(id, wahl, stufen, auf);
    const box = el("div", "segmente");
    box.id = id;
    for (const s of stufen) {
      const b = el("button");
      b.type = "button";
      b.textContent = s.label;
      b.dataset.wert = s.wert;
      if (s.titel) b.title = s.titel;
      if (s.klasse) b.classList.add(s.klasse);
      if (s.wert === wahl) b.classList.add("gewaehlt");
      if (s.gesperrt) b.disabled = true;
      else b.addEventListener("click", (e) => auf(s.wert, e.isTrusted));
      box.appendChild(b);
    }
    return box;
  }
  function knopf(text, auf, warnend = false) {
    const b = el("button", warnend ? "knopf warnend" : "knopf");
    b.type = "button";
    b.textContent = text;
    b.addEventListener("click", (e) => auf(e.isTrusted));
    return b;
  }
  async function setze(key, value) {
    melde(t("satz.schreibe", { schluessel: key }));
    const r = await window.awbEinstellungen.setzen(key, value);
    melde(
      r.ok ? `${r.aufruf} \u2014 ${r.ausgabe}` : t("satz.fehler", { aufruf: r.aufruf, ausgabe: r.ausgabe }),
      r.ok ? "gut" : "fehler"
    );
  }
  async function werkzeug(nachricht, echt) {
    melde(`${String(nachricht.command ?? "")} \u2026`);
    const r = await window.awbEinstellungen.werkzeug(nachricht, echt === true);
    melde(
      r.ok ? `${r.aufruf} \u2014 ${r.ausgabe}` : t("satz.fehler", { aufruf: r.aufruf, ausgabe: r.ausgabe }),
      r.ok ? "gut" : "fehler"
    );
  }
  async function setzeUi(key, value) {
    await window.awbEinstellungen.ui(key, value);
    melde(t("satz.oberflaeche", { schluessel: key, wert: JSON.stringify(value) }), "gut");
  }
  function frage(text, tunText, ja, mitGrund = false) {
    rueckfrageTextEl.textContent = text;
    rueckfrageEl.classList.add("offen");
    const knopfJa = document.getElementById("rueckfrageJa");
    const knopfNein = document.getElementById("rueckfrageNein");
    const grundFeld = document.getElementById("rueckfrageGrund");
    const grundZeile = document.getElementById("rueckfrageGrundZeile");
    const hinweisEl = document.getElementById("rueckfrageHinweis");
    knopfJa.textContent = tunText;
    grundFeld.value = "";
    hinweisEl.textContent = "";
    grundZeile.hidden = !mitGrund;
    const zu = () => {
      rueckfrageEl.classList.remove("offen");
      knopfJa.onclick = null;
      knopfNein.onclick = null;
    };
    knopfJa.onclick = (e) => {
      const grund = grundFeld.value.trim();
      if (mitGrund && !grund) {
        hinweisEl.textContent = t("satz.ohneGrundNichts");
        grundFeld.focus();
        return;
      }
      zu();
      ja(grund, e.isTrusted);
    };
    knopfNein.onclick = () => {
      zu();
      zeichne();
    };
    if (mitGrund) grundFeld.focus();
  }
  function modellwahl(g, schluessel, o, modelle, gewaehlt, auf) {
    const box = el("div");
    const filter = filterStand.get(schluessel) ?? "alle";
    const suche = (suchStand.get(schluessel) ?? "").trim().toLowerCase();
    const proHarness = /* @__PURE__ */ new Map();
    for (const m of modelle) proHarness.set(m.harness, (proHarness.get(m.harness) ?? 0) + 1);
    const filterzeile = el("div", "filterzeile");
    const chips = proHarness.size < 2 ? [] : [
      { wert: "alle", label: t("wort.alleModelle", { anzahl: modelle.length }) },
      ...[...proHarness.entries()].sort((a, b) => b[1] - a[1]).map(([h, n]) => ({
        wert: h,
        label: `${modelle.find((m) => m.harness === h)?.harnessLabel ?? h} ${n}`
      }))
    ];
    for (const c of chips) {
      const b = el("button");
      b.type = "button";
      b.textContent = c.label;
      b.dataset.filter = c.wert;
      b.dataset.fuer = schluessel;
      if (c.wert === filter) b.classList.add("gewaehlt");
      b.addEventListener("click", () => {
        filterStand.set(schluessel, c.wert);
        zeichne();
      });
      filterzeile.appendChild(b);
    }
    box.appendChild(filterzeile);
    const suchfeld = el("input", "modellsuche");
    suchfeld.type = "text";
    suchfeld.placeholder = t("platzhalter.modellsuche");
    suchfeld.value = suchStand.get(schluessel) ?? "";
    suchfeld.dataset.suche = schluessel;
    suchfeld.spellcheck = false;
    suchfeld.addEventListener("input", () => {
      suchStand.set(schluessel, suchfeld.value);
      zeichne();
      const neu = document.querySelector(`input[data-suche="${schluessel}"]`);
      if (neu) {
        neu.focus();
        neu.setSelectionRange(neu.value.length, neu.value.length);
      }
    });
    box.appendChild(suchfeld);
    const passt = (m) => (filter === "alle" || m.harness === filter) && (!suche || m.label.toLowerCase().includes(suche) || m.id.toLowerCase().includes(suche));
    const dasGewaehlte = modellZu(modelle, gewaehlt);
    const treffer = modelle.filter((m) => m !== dasGewaehlte && passt(m));
    const liste = el("div", "modelliste");
    const zeigen = dasGewaehlte ? [dasGewaehlte, ...treffer] : treffer;
    if (zeigen.length === 0) {
      liste.appendChild(el("div", "leerhinweis", t("satz.keinTreffer")));
    }
    for (const m of zeigen) {
      const b = el("button", "modelleintrag");
      b.type = "button";
      b.dataset.modell = m.id;
      b.dataset.fuer = schluessel;
      if (!m.startbar) {
        b.dataset.status = "binary-missing";
        b.dataset.model = m.id;
      }
      if (m === dasGewaehlte) b.classList.add("gewaehlt");
      const z1 = el("div", "zeile1");
      z1.appendChild(el("span", void 0, `${m === dasGewaehlte ? "\u25CF " : "\u25CB "}${m.label}`));
      z1.appendChild(el("span", "kennung", m.familie ? `${m.familie} \xB7 ${m.id}` : m.id));
      b.appendChild(z1);
      const z2 = el("div", "zeile2");
      const stuecke = [m.harnessLabel];
      if (m.kontext) stuecke.push(`${Math.round(m.kontext / 1e3)}k Kontext`);
      z2.textContent = stuecke.join(" \xB7 ");
      if (!m.startbar) {
        const marke = el("span", "marke tot", t("wort.nichtStartbar", { maschine: daten?.machine ?? "" }));
        marke.classList.add("statusLabel");
        z2.appendChild(marke);
      }
      b.appendChild(z2);
      b.addEventListener("click", () => auf(m.familie || m.id));
      liste.appendChild(b);
    }
    box.appendChild(liste);
    feld(g, { ...o, schluessel, steuer: box, breit: true });
  }
  function stufenwahl(g, schluessel, o, modell, deckel, stufen, wert) {
    if (stufen.length === 0) {
      feld(g, {
        ...o,
        schluessel,
        breit: true,
        steuer: el(
          "div",
          "leerhinweis",
          modell ? t("satz.stufenKeineWahl", { harness: modell.harnessLabel }) : t("satz.stufenErstModell")
        )
      });
      return;
    }
    const deckelStufe = deckel?.cap ?? modell?.deckelRegistry ?? "";
    const grenze = deckelStufe ? stufen.indexOf(deckelStufe) : -1;
    const box = el("div");
    box.appendChild(segmente(
      schluessel,
      wert,
      stufen.map((s, i) => ({
        wert: s,
        label: s,
        // NICHTS ist gesperrt. Ueber dem Deckel steht eine Markierung, kein Riegel.
        titel: grenze >= 0 && i > grenze ? t("satz.deckelUeber", { deckel: deckelStufe }) : void 0,
        klasse: grenze >= 0 && i > grenze ? "ueberDeckel" : void 0
      })),
      (w) => void setze(schluessel, w)
    ));
    const zeile = el("div", "deckelzeile");
    if (deckelStufe) {
      const quelle = deckel?.quelle === "einstellung" ? t("wort.vonDir") : t("wort.ausAuslieferung");
      zeile.appendChild(document.createTextNode(t("satz.deckelDieses")));
      zeile.appendChild(el("b", void 0, `${deckelStufe} (${quelle})`));
      zeile.appendChild(document.createTextNode(
        t("satz.deckelGilt") + (grenze >= 0 && grenze < stufen.length - 1 ? t("satz.deckelDarueber", { stufen: stufen.slice(grenze + 1).join(", ") }) : "")
      ));
      if (deckel?.grund) zeile.appendChild(el("div", void 0, t("satz.deckelGrund", { grund: deckel.grund })));
    } else {
      zeile.textContent = t("satz.deckelKeiner");
    }
    box.appendChild(zeile);
    feld(g, { ...o, schluessel, breit: true, steuer: box });
  }
  function kontextwahl(g, modell, gewaehlt) {
    if (!modell?.lokal) return;
    const o = { ...texte("orchestratorKontext", { modell: modell.label }), wartet: true };
    const antwort = kontextStand[modell.id];
    if (!antwort) {
      kontextHolen(modell.id);
      feld(g, {
        ...o,
        schluessel: "orchestratorKontext",
        breit: true,
        steuer: el("div", "leerhinweis", t("satz.kontextWirdErmittelt"))
      });
      return;
    }
    if (!antwort.ok) {
      feld(g, {
        ...o,
        schluessel: "orchestratorKontext",
        breit: true,
        steuer: el("div", "leerhinweis", t("satz.kontextNichtErmittelt", { grund: antwort.fehler }))
      });
      return;
    }
    const s = antwort.sicht;
    const wert = typeof gewaehlt === "number" && gewaehlt > 0 ? gewaehlt : s.vorgabe;
    const box = el("div");
    const liste = el("div", "kontextliste");
    for (const stufe of s.stufen) {
      const b = el("button", "kontexteintrag");
      b.type = "button";
      b.dataset.kontext = String(stufe.tokens);
      b.dataset.passt = stufe.passt ? "ja" : "nein";
      if (stufe.tokens === wert) b.classList.add("gewaehlt");
      if (stufe.tokens === s.empfehlung) b.dataset.empfohlen = "ja";
      const z1 = el("div", "zeile1");
      z1.appendChild(el(
        "span",
        void 0,
        `${stufe.tokens === wert ? "\u25CF " : "\u25CB "}${stufe.label}`
      ));
      if (stufe.tokens === s.empfehlung) {
        z1.appendChild(el("span", "marke empfohlen", t("wort.kontextEmpfohlen")));
      }
      z1.appendChild(el("span", "kennung", t("wort.kontextToken", { tokens: stufe.tokens })));
      b.appendChild(z1);
      const z2 = el("div", !stufe.passt && stufe.hinweis ? "zeile2 kontexthinweis" : "zeile2");
      z2.textContent = !stufe.passt && stufe.hinweis ? stufe.hinweis : t("satz.kontextBedarf", { bedarf: stufe.bedarfGib.toFixed(1) });
      b.appendChild(z2);
      b.addEventListener("click", () => void setze("orchestratorKontext", stufe.tokens));
      liste.appendChild(b);
    }
    box.appendChild(liste);
    const gewaehlteStufe = s.stufen.find((x) => x.tokens === wert);
    const fuss = el("div", "kontextfuss");
    if (!gewaehlteStufe) {
      fuss.classList.add("warnt");
      fuss.textContent = t("satz.kontextFremderWert", { tokens: wert });
    } else if (!gewaehlteStufe.passt && gewaehlteStufe.hinweis) {
      fuss.classList.add("warnt");
      fuss.textContent = gewaehlteStufe.hinweis;
    } else {
      fuss.textContent = t("satz.kontextSpeicher", {
        frei: (s.freiMib / 1024).toFixed(1),
        gewichte: s.gewichteGb.toFixed(1)
      });
    }
    box.appendChild(fuss);
    feld(g, { ...o, schluessel: "orchestratorKontext", breit: true, steuer: box });
  }
  function seiteSitzung(d) {
    const s = el("section", "seite");
    s.dataset.seite = "sitzung";
    s.appendChild(el("h1", void 0, t("seite.sitzung.titel")));
    s.appendChild(el("p", "unterzeile", t("seite.sitzung.unterzeile")));
    const harness = String(d.settings.orchestratorHarness ?? "claude");
    const setzeHarness = async (id) => {
      await setze("orchestratorHarness", id);
      const modell = d.harnesses.find((h) => h.id === id)?.orchestratorDefaultModel;
      if (modell) await setze("orchestratorModel", modell);
    };
    const g1 = gruppe(s, t("gruppe.sitzung.start"));
    feld(g1, {
      ...texte("orchestratorHarness", { maschine: d.machine }),
      wartet: true,
      schluessel: "orchestratorHarness",
      steuer: segmente(
        "orchestratorHarness",
        harness,
        d.harnesses.map((h) => ({
          wert: h.id,
          label: `${h.label} ${h.modelle}${h.binaer ? "" : ` \xB7 ${t("wort.fehltHier")}`}`,
          titel: h.binaer ? void 0 : t("wort.nichtStartbar", { maschine: d.machine })
        })),
        (w) => void setzeHarness(w)
      )
    });
    const eigene = d.orchestratorModelle.filter((m) => m.harness === harness);
    const gewaehlt = String(d.settings.orchestratorModel ?? "");
    if (eigene.length === 0) {
      feld(g1, {
        name: t("feld.orchestratorModel.leerName"),
        wirkung: t("feld.orchestratorModel.leerWirkung"),
        info: t("feld.orchestratorModel.leerInfo"),
        schluessel: "orchestratorModel",
        breit: true,
        steuer: el("div", "leerhinweis", t("satz.keinModellFuerProgramm", { harness }))
      });
    } else {
      modellwahl(
        g1,
        "orchestratorModel",
        { ...texte("orchestratorModel", { anzahl: eigene.length }), wartet: true },
        eigene,
        gewaehlt,
        (id) => void setze("orchestratorModel", id)
      );
    }
    const orchModell = modellZu(d.orchestratorModelle, gewaehlt);
    stufenwahl(
      g1,
      "orchestratorEffort",
      { ...texte("orchestratorEffort"), wartet: true },
      orchModell,
      d.deckel[gewaehlt],
      d.deckel[gewaehlt]?.efforts ?? d.harnessStufen[orchModell?.harness ?? ""] ?? [],
      String(d.settings.orchestratorEffort ?? "xhigh")
    );
    kontextwahl(g1, orchModell, d.settings.orchestratorKontext);
    feld(g1, {
      ...texte("newSessionDefaultDir"),
      wartet: true,
      schluessel: "newSessionDefaultDir",
      steuer: textzeile(
        "newSessionDefaultDir",
        String(d.settings.newSessionDefaultDir ?? d.vorgaben.newSessionDefaultDir ?? ""),
        t("platzhalter.startordner"),
        (w) => void setze("newSessionDefaultDir", w)
      )
    });
    const g2 = gruppe(s, t("gruppe.sitzung.leiste"));
    feld(g2, {
      ...texte("showStopped"),
      uiSchluessel: "showStopped",
      steuer: haken("showStopped", d.ui.showStopped, (an) => void setzeUi("showStopped", an))
    });
    feld(g2, {
      ...texte("sort"),
      uiSchluessel: "sort",
      steuer: segmente(
        "sort",
        d.ui.sort,
        [
          { wert: "recent", label: t("wort.sort.recent") },
          { wert: "folder", label: t("wort.sort.folder") },
          { wert: "name", label: t("wort.sort.name") }
        ],
        (w) => void setzeUi("sort", w)
      )
    });
    const g3 = gruppe(s, t("gruppe.sitzung.schliessen"));
    feld(g3, {
      ...texte("closeSessionOnWindowClose"),
      schluessel: "closeSessionOnWindowClose",
      // `=== true` und nicht `!== false`: seit dem 07.08. ist die Vorgabe AUS,
      // und ein Schlüssel, der in der Datei fehlt, muss denselben Haken zeigen
      // wie die Vorgabe — sonst verspricht das Menü das Gegenteil dessen, was
      // das Programm tut.
      steuer: haken(
        "closeSessionOnWindowClose",
        d.settings.closeSessionOnWindowClose === true,
        (an) => void setze("closeSessionOnWindowClose", an)
      )
    });
    return s;
  }
  function seiteErlaubnisse(d) {
    const s = el("section", "seite");
    s.dataset.seite = "erlaubnisse";
    s.appendChild(el("h1", void 0, t("seite.erlaubnisse.titel")));
    s.appendChild(el("p", "unterzeile", t("seite.erlaubnisse.unterzeile")));
    const v = gruppe(s, t("gruppe.erlaubnisse.vorsicht"), "vorsicht");
    feld(v, {
      ...texte("workerSkipPermissions"),
      wartet: true,
      // Wie beim Erlaubnismodus kein generisches Rueckstell-Zeichen: das
      // Anheben braucht den Grund und den echten Bestaetigungsklick.
      steuer: haken("workerSkipPermissions", d.settings.workerSkipPermissions !== false, (an, echt) => {
        if (!an) {
          void werkzeug({ command: "worker-skip-permissions-set", value: false }, echt);
          return;
        }
        frage(
          t("frage.skipAn.text"),
          t("frage.skipAn.tun"),
          (grund, echtJa) => void werkzeug({ command: "worker-skip-permissions-set", value: true, grund }, echtJa),
          true
        );
      })
    });
    feld(v, {
      ...texte("workerWorktrees"),
      wartet: true,
      schluessel: "workerWorktrees",
      steuer: haken(
        "workerWorktrees",
        d.settings.workerWorktrees !== false,
        (an) => void setze("workerWorktrees", an)
      )
    });
    const permissionModi = ["acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan"];
    const permissionModeWert = String(d.settings.orchestratorPermissionMode ?? "bypassPermissions");
    feld(v, {
      ...texte("orchestratorPermissionMode"),
      wartet: true,
      breit: true,
      steuer: segmente(
        "orchestratorPermissionMode",
        permissionModeWert,
        permissionModi.map((wert) => ({ wert, label: t(`wort.permissionMode.${wert}`), titel: wert })),
        (wert, echt) => {
          if (wert === permissionModeWert) return;
          if (wert !== "bypassPermissions") {
            void werkzeug({ command: "permission-mode-set", value: wert }, echt);
            return;
          }
          frage(
            t("frage.permissionModeAn.text"),
            t("frage.permissionModeAn.tun"),
            (grund, echtJa) => void werkzeug({ command: "permission-mode-set", value: wert, grund }, echtJa),
            true
          );
        }
      )
    });
    const g1 = gruppe(s, t("gruppe.erlaubnisse.guards"));
    const guardListe = el("div", "zeilen");
    guardListe.id = "guardListe";
    for (const zeileDaten of d.guards) {
      const name = t(`guard.${zeileDaten.id}.name`);
      const wirkung = t(`guard.${zeileDaten.id}.wirkung`);
      const info = t(`guard.${zeileDaten.id}.info`);
      const z = el("div", zeileDaten.an ? "zeile" : "zeile abgeschaltet");
      z.dataset.guard = zeileDaten.id;
      z.appendChild(haken(`guard-${zeileDaten.id}`, zeileDaten.an, (an, echt) => {
        if (an) {
          void werkzeug({ command: "guard-set", guard: zeileDaten.id, an: true }, echt);
          return;
        }
        frage(
          t("frage.guardAus.text", { name, wirkung }),
          t("frage.guardAus.tun"),
          (grund, echtJa) => void werkzeug({ command: "guard-set", guard: zeileDaten.id, an: false, grund }, echtJa),
          true
        );
      }));
      z.appendChild(el("span", "titel", name));
      z.appendChild(el("span", "grund", zeileDaten.an ? wirkung : (zeileDaten.rolle && zeileDaten.rolle !== "alle" ? t("satz.abgeschaltetFuer", { rolle: zeileDaten.rolle }) : t("satz.abgeschaltet")) + (zeileDaten.seit ? t("satz.seit", { datum: zeileDaten.seit.slice(0, 10) }) : "") + (zeileDaten.grund ? `: ${zeileDaten.grund}` : "")));
      const rechts = el("div", "rechts");
      rechts.appendChild(infozeichen(`guard-${zeileDaten.id}`, info));
      z.appendChild(rechts);
      guardListe.appendChild(z);
    }
    if (d.guards.length === 0) {
      guardListe.appendChild(el("div", "leerhinweis", t("satz.keineGuards")));
    }
    feld(g1, { ...texte("guards"), breit: true, steuer: guardListe });
    const g2 = gruppe(s, t("gruppe.erlaubnisse.rueckfragen"));
    const musterListe = el("div", "zeilen");
    musterListe.id = "musterListe";
    if (d.askMuster.length === 0) {
      musterListe.appendChild(el("div", "leerhinweis", t("satz.keineMuster")));
    }
    d.askMuster.forEach((m, i) => {
      const aus = m.aus === true;
      const z = el("div", aus ? "zeile abgeschaltet" : "zeile");
      z.dataset.muster = String(i);
      const bezeichnung = [m.befehl, m.unterbefehl].filter(Boolean).join(" ");
      z.appendChild(haken(`muster-${i}`, !aus, (an) => {
        const neu = d.askMuster.map((x, j) => j === i ? { ...x, aus: !an } : { ...x });
        for (const x of neu) if (!x.aus) delete x.aus;
        if (an) {
          void setze("askPatterns", neu);
          return;
        }
        frage(
          t("frage.musterAus.text", { name: bezeichnung, grund: m.grund }),
          t("frage.musterAus.tun"),
          () => void setze("askPatterns", neu)
        );
      }));
      z.appendChild(el("span", "titel", bezeichnung));
      z.appendChild(el("span", "grund", m.grund));
      const rechts = el("div", "rechts");
      if (m.muster) rechts.appendChild(el("code", void 0, m.muster));
      rechts.appendChild(knopf(t("wort.entfernen"), () => {
        frage(
          t("frage.musterWeg.text", { name: bezeichnung }),
          t("frage.musterWeg.tun"),
          () => void setze("askPatterns", d.askMuster.filter((_x, j) => j !== i))
        );
      }, true));
      z.appendChild(rechts);
      musterListe.appendChild(z);
    });
    const anlegen = el("div", "anlegen");
    const nBefehl = el("input");
    nBefehl.type = "text";
    nBefehl.id = "musterBefehl";
    nBefehl.placeholder = t("platzhalter.musterBefehl");
    nBefehl.spellcheck = false;
    const nUnter = el("input");
    nUnter.type = "text";
    nUnter.id = "musterUnterbefehl";
    nUnter.placeholder = t("platzhalter.musterUnterbefehl");
    nUnter.spellcheck = false;
    const nGrund = el("input");
    nGrund.type = "text";
    nGrund.id = "musterGrund";
    nGrund.placeholder = t("platzhalter.musterGrund");
    nGrund.spellcheck = false;
    anlegen.append(nBefehl, nUnter, nGrund, knopf(t("wort.hinzufuegen"), () => {
      const befehl = nBefehl.value.trim();
      if (!befehl) {
        melde(t("satz.musterOhneBefehl"), "fehler");
        return;
      }
      const neu = { befehl, grund: nGrund.value.trim() || t("satz.musterVonHand") };
      if (nUnter.value.trim()) neu.unterbefehl = nUnter.value.trim();
      void setze("askPatterns", [...d.askMuster, neu]);
    }));
    const musterBox = el("div");
    musterBox.append(musterListe, anlegen);
    feld(g2, { ...texte("askPatterns"), schluessel: "askPatterns", breit: true, steuer: musterBox });
    const g3 = gruppe(s, t("gruppe.erlaubnisse.geheimnisse"));
    const chipListe = (werte, id, schluessel, was) => {
      const box = el("div");
      const chips = el("div", "chips");
      chips.id = id;
      if (werte.length === 0) {
        chips.appendChild(el("span", "leerhinweis", t("wort.leerListe")));
      }
      for (const w of werte) {
        const c = el("span", "chip");
        c.appendChild(el("code", void 0, w));
        const weg = el("button");
        weg.type = "button";
        weg.textContent = "\xD7";
        weg.dataset.weg = w;
        weg.title = t("wort.entfernen");
        weg.addEventListener("click", () => {
          const neu = werte.filter((x) => x !== w);
          if (neu.length === 0) {
            frage(
              t("frage.listeLeer.text", { was }),
              t("frage.listeLeer.tun"),
              () => void setze(schluessel, neu)
            );
            return;
          }
          void setze(schluessel, neu);
        });
        c.appendChild(weg);
        chips.appendChild(c);
      }
      box.appendChild(chips);
      const anlegenBox = el("div", "anlegen");
      const feldNeu = el("input");
      feldNeu.type = "text";
      feldNeu.id = `${id}Neu`;
      feldNeu.placeholder = was;
      feldNeu.spellcheck = false;
      anlegenBox.append(feldNeu, knopf(t("wort.hinzufuegen"), () => {
        const wert = feldNeu.value.trim();
        if (!wert || werte.includes(wert)) return;
        void setze(schluessel, [...werte, wert]);
      }));
      box.appendChild(anlegenBox);
      return box;
    };
    feld(g3, {
      ...texte("secretExcludeDirs"),
      schluessel: "secretExcludeDirs",
      breit: true,
      steuer: chipListe(d.ausschluss.ordner, "secretExcludeDirs", "secretExcludeDirs", t("platzhalter.ordner"))
    });
    feld(g3, {
      ...texte("secretExcludePatterns"),
      schluessel: "secretExcludePatterns",
      breit: true,
      steuer: chipListe(
        d.ausschluss.muster,
        "secretExcludePatterns",
        "secretExcludePatterns",
        t("platzhalter.dateimuster")
      )
    });
    const g4 = gruppe(s, t("gruppe.erlaubnisse.werkzeuge"));
    const werkzeugBox = el("div");
    const hookListe = el("div", "zeilen");
    hookListe.id = "hookListe";
    if (d.hooks.length === 0) {
      hookListe.appendChild(el("div", "leerhinweis", t("satz.werkzeugeOhneHooks")));
    }
    for (const h of d.hooks) {
      const z = el("div", "zeile");
      z.dataset.hook = h.name;
      z.appendChild(el("span", "titel", h.name));
      z.appendChild(el("span", "grund", h.ereignis));
      const rechts = el("div", "rechts");
      if (h.lehntAb) rechts.appendChild(el("span", "marke", "lehnt ab"));
      z.appendChild(rechts);
      hookListe.appendChild(z);
    }
    werkzeugBox.appendChild(hookListe);
    werkzeugBox.appendChild(el("div", "klartext", t("satz.werkzeugeMcp")));
    feld(g4, { ...texte("werkzeuge"), breit: true, steuer: werkzeugBox });
    return s;
  }
  function seiteHarnesses(d) {
    const s = el("section", "seite");
    s.dataset.seite = "harnesses";
    s.appendChild(el("h1", void 0, t("seite.harnesses.titel")));
    s.appendChild(el("p", "unterzeile", t("seite.harnesses.unterzeile")));
    const g1 = gruppe(s, t("gruppe.harnesses.programme"));
    const st = el("table");
    st.id = "harnessTabelle";
    const sk = el("tr");
    for (const h of [
      t("spalte.programm"),
      t("spalte.hier"),
      t("spalte.anmeldung"),
      t("spalte.installiert"),
      t("spalte.neueste"),
      t("spalte.zuletztGeprueft"),
      t("spalte.stufen"),
      t("spalte.modelle"),
      t("spalte.chat")
    ]) sk.appendChild(el("th", void 0, h));
    sk.children[1].title = d.machine;
    st.appendChild(sk);
    for (const h of d.harnesses) {
      const stufen = d.harnessStufen[h.id];
      const r = el("tr");
      r.dataset.harness = h.id;
      if (!h.binaer) r.className = "warnung";
      r.appendChild(el("td", void 0, h.label));
      r.appendChild(el(
        "td",
        void 0,
        h.binaer ? t("wort.startbar") : t("wort.nichtStartbar", { maschine: d.machine })
      ));
      const an = d.anmeldung[h.id];
      const anZelle = el(
        "td",
        an?.stand === "ja" ? "gesetzt" : "stufenzelle",
        an?.stand === "ja" ? t("wort.angemeldet") : an?.stand === "nein" ? t("wort.nichtAngemeldet") : t("wort.anmeldungUnbekannt")
      );
      if (an?.grund) anZelle.title = an.grund;
      r.appendChild(anZelle);
      const letztePruefung = h.lastChecked ? new Date(h.lastChecked).toLocaleString([], { dateStyle: "short", timeStyle: "short" }) : t("wort.nochNichtGeprueft");
      const installiert = el("td", "wert", h.installedVersion || "\u2013");
      const neueste = el("td", "wert", h.latestVersion || "\u2013");
      const geprueft = el("td", "wert", letztePruefung);
      if (h.updateStatus) {
        installiert.title = h.updateStatus;
        neueste.title = h.updateStatus;
        geprueft.title = h.updateStatus;
      }
      r.appendChild(installiert);
      r.appendChild(neueste);
      r.appendChild(geprueft);
      r.appendChild(el("td", "stufenzelle stufenspalte", stufen === void 0 ? t("wort.stufenNichtErmittelt") : stufen.length ? stufen.join(" ") : t("wort.keineStufen")));
      r.appendChild(el("td", void 0, String(h.modelle)));
      const quelle = d.chatQuellen[h.id];
      const chatZelle = el("td");
      if (quelle && quelle.via && quelle.probe) {
        const kasten = el("div", "chatzelle");
        kasten.appendChild(haken(`chat-${h.id}`, d.chatAnsicht[h.id] === true, (anAus) => {
          void setze("chatAnsicht", { ...d.chatAnsicht, [h.id]: anAus });
        }));
        const wie = el(
          "span",
          "grund",
          quelle.live ? t("satz.chatKannLive") : t("satz.chatKannNichtLive")
        );
        if (quelle.zeigtNicht.length) {
          wie.title = t("satz.chatZeigtNicht", { liste: quelle.zeigtNicht.join(", ") });
        }
        kasten.appendChild(wie);
        chatZelle.appendChild(kasten);
      } else {
        chatZelle.className = "stufenzelle";
        chatZelle.appendChild(el("div", "chatzelle-text", quelle && quelle.via && !quelle.probe ? t("satz.chatOhneMessung") : quelle?.grund || t("satz.chatKannNicht")));
      }
      r.appendChild(chatZelle);
      st.appendChild(r);
    }
    feld(g1, { ...texte("harnessTabelle"), breit: true, steuer: st });
    feld(g1, {
      ...texte("chatAnsicht"),
      wartet: true,
      schluessel: "chatAnsicht",
      breit: true,
      steuer: el("div", "klartext", t("satz.chatKannNicht"))
    });
    feld(g1, {
      ...texte("workerTransport"),
      wartet: true,
      schluessel: "workerTransport",
      steuer: segmente(
        "workerTransport",
        String(d.settings.workerTransport ?? "tmux"),
        [
          // Die beiden Werte heissen im ganzen Haus so und werden nicht
          // uebersetzt -- 'tmux' und 'pty' stehen genauso in der
          // Einstellungsdatei, im Protokoll und in der Pane-Kennung `pty:<n>`.
          { wert: "tmux", label: "tmux" },
          { wert: "pty", label: "pty" }
        ],
        (w) => void setze("workerTransport", w)
      )
    });
    const g2 = gruppe(s, t("gruppe.harnesses.lokal"));
    const ollamaBox = el("div");
    ollamaBox.appendChild(textzeile(
      "ollamaEndpoint",
      d.ollamaEndpunkt,
      t("platzhalter.ollama"),
      (w) => void setze("ollamaEndpoint", w)
    ));
    ollamaBox.appendChild(el("div", "klartext", t("satz.ollamaNochNichtVerdrahtet")));
    feld(g2, {
      ...texte("ollamaEndpoint"),
      wartet: true,
      schluessel: "ollamaEndpoint",
      breit: true,
      steuer: ollamaBox
    });
    feld(g2, {
      ...texte("harnessUpdateAuto"),
      schluessel: "harnessUpdateAuto",
      steuer: haken(
        "harnessUpdateAuto",
        d.settings.harnessUpdateAuto === true,
        (an) => void setze("harnessUpdateAuto", an)
      )
    });
    const intervalRoh = Number(d.settings.harnessUpdateIntervalHours);
    const interval = Number.isInteger(intervalRoh) && intervalRoh >= 1 && intervalRoh <= 168 ? intervalRoh : 6;
    feld(g2, {
      ...texte("harnessUpdateIntervalHours"),
      schluessel: "harnessUpdateIntervalHours",
      steuer: zahl(
        "harnessUpdateIntervalHours",
        interval,
        1,
        168,
        t("wort.stunden"),
        (n) => void setze("harnessUpdateIntervalHours", Math.max(1, Math.min(168, Math.floor(n))))
      )
    });
    feld(g2, {
      ...texte("modelDiscoveryAuto"),
      schluessel: "modelDiscoveryAuto",
      steuer: haken(
        "modelDiscoveryAuto",
        d.settings.modelDiscoveryAuto !== false,
        (an) => void setze("modelDiscoveryAuto", an)
      )
    });
    const orchVorhersage = el("div");
    orchVorhersage.appendChild(haken(
      "orchestratorVorhersage",
      d.settings.orchestratorVorhersage === true,
      (an) => void setze("orchestratorVorhersage", an)
    ));
    const orchModellId = String(d.settings.orchestratorModel ?? "");
    const orchWege = vorhersageWegWahl(
      d.orchestratorModelle,
      orchModellId,
      String(d.settings.orchestratorVorhersageWeg ?? ""),
      (weg) => void setze("orchestratorVorhersageWeg", weg)
    );
    if (orchWege) orchVorhersage.appendChild(orchWege);
    else orchVorhersage.appendChild(el(
      "div",
      "klartext",
      vorhersageAnzeige(d.orchestratorModelle, orchModellId)
    ));
    feld(g2, {
      ...texte("orchestratorVorhersage"),
      schluessel: "orchestratorVorhersage",
      breit: true,
      steuer: orchVorhersage
    });
    const workerVorhersage = el("div");
    workerVorhersage.appendChild(haken(
      "workerVorhersage",
      d.settings.workerVorhersage === true,
      (an) => void setze("workerVorhersage", an)
    ));
    workerVorhersage.appendChild(el(
      "div",
      "klartext",
      vorhersageAnzeige(d.workerModelle, String(d.settings.workerModel ?? ""))
    ));
    feld(g2, {
      ...texte("workerVorhersage"),
      schluessel: "workerVorhersage",
      breit: true,
      steuer: workerVorhersage
    });
    const g3 = gruppe(s, t("gruppe.harnesses.schluessel"));
    const at = el("table");
    at.id = "anbieterTabelle";
    const ak = el("tr");
    for (const h of [t("spalte.anbieter"), t("spalte.zugang"), t("spalte.eingabe")]) {
      ak.appendChild(el("th", void 0, h));
    }
    at.appendChild(ak);
    for (const p2 of d.anbieter) {
      const r = el("tr");
      r.dataset.anbieter = p2.id;
      r.appendChild(el("td", void 0, p2.label));
      const imSchluesselbund = p2.art === "schluessel" && schluesselStand[p2.id] === true;
      const stand = imSchluesselbund ? "ja" : p2.stand;
      const wort = p2.art === "lokal" ? t("wort.zugangLokal") : stand === "ja" ? t("wort.zugangDa") : stand === "nein" ? p2.art === "abo" ? t("wort.zugangAbo") : t("wort.zugangFehlt") : t("wort.zugangUnbekannt");
      r.appendChild(el("td", stand === "ja" ? "gesetzt" : "stufenzelle", wort));
      const eingabeZelle = el("td");
      if (p2.art === "schluessel") {
        const eingabe = el("input");
        eingabe.type = "password";
        eingabe.autocomplete = "off";
        eingabe.spellcheck = false;
        eingabe.placeholder = t("platzhalter.schluesselEingabe");
        eingabe.dataset.schluesselEingabe = p2.id;
        const paar = el("span", "steuerpaar");
        const speichern = knopf(t("wort.speichern"), () => {
          const wert = eingabe.value;
          eingabe.value = "";
          if (!wert.trim()) {
            melde(t("satz.schluesselLeer"), "fehler");
            return;
          }
          melde(t("satz.schreibe", { schluessel: p2.id }));
          void window.awbEinstellungen.schluesselSetzen(p2.id, wert).then((antwort) => {
            melde(
              antwort.ok ? t("satz.schluesselGespeichert", { anbieter: p2.label }) : t("satz.schluesselFehler"),
              antwort.ok ? "gut" : "fehler"
            );
            void schluesselStatusLaden();
          });
        });
        speichern.dataset.schluesselSpeichern = p2.id;
        paar.append(eingabe, speichern);
        eingabeZelle.appendChild(paar);
      }
      r.appendChild(eingabeZelle);
      at.appendChild(r);
    }
    feld(g3, { ...texte("anbieter"), breit: true, steuer: at });
    const g4 = gruppe(s, t("gruppe.harnesses.deckel"));
    const satz = el("div", "reserviert");
    satz.dataset.leitsatz = "deckel";
    const p = el("p");
    p.appendChild(el("strong", void 0, t("satz.deckelLeitsatzFett")));
    p.appendChild(document.createTextNode(t("satz.deckelLeitsatz")));
    p.style.margin = "0";
    satz.appendChild(p);
    g4.appendChild(satz);
    const alle = [...d.orchestratorModelle];
    for (const m of d.workerModelle) if (!alle.some((x) => x.id === m.id)) alle.push(m);
    alle.sort((a, b) => a.harness.localeCompare(b.harness) || a.label.localeCompare(b.label));
    const suche = (suchStand.get("deckel") ?? "").trim().toLowerCase();
    const suchfeld = el("input", "modellsuche");
    suchfeld.type = "text";
    suchfeld.placeholder = t("platzhalter.suche");
    suchfeld.value = suchStand.get("deckel") ?? "";
    suchfeld.dataset.suche = "deckel";
    suchfeld.spellcheck = false;
    suchfeld.addEventListener("input", () => {
      suchStand.set("deckel", suchfeld.value);
      zeichne();
      const neu = document.querySelector('input[data-suche="deckel"]');
      if (neu) {
        neu.focus();
        neu.setSelectionRange(neu.value.length, neu.value.length);
      }
    });
    const dt = el("table");
    dt.id = "deckelTabelle";
    const dk = el("tr");
    for (const h of [
      t("spalte.modell"),
      t("spalte.programm"),
      t("spalte.deckel"),
      t("spalte.herkunft"),
      t("spalte.grund")
    ]) dk.appendChild(el("th", void 0, h));
    dt.appendChild(dk);
    const treffer = alle.filter((m) => !suche || m.label.toLowerCase().includes(suche) || m.id.toLowerCase().includes(suche));
    for (const m of treffer.slice(0, 60)) {
      const gesetzt = d.effortCaps[m.id];
      const quelle = gesetzt ? "einstellung" : m.deckelRegistry ? "registry" : "-";
      const stufen = d.harnessStufen[m.harness];
      const r = el("tr");
      r.dataset.modell = m.id;
      const erste = el("td");
      erste.appendChild(el("div", void 0, m.label));
      erste.appendChild(el("div", "wert", m.id));
      r.appendChild(erste);
      r.appendChild(el("td", "wert", m.harnessLabel));
      const wahlZelle = el("td");
      if (stufen === void 0) {
        wahlZelle.appendChild(el("span", "stufenzelle", t("wort.stufenNichtErmittelt")));
      } else if (stufen.length === 0) {
        wahlZelle.appendChild(el("span", "stufenzelle", t("wort.keineStufen")));
      } else {
        const wahl = el("select");
        wahl.dataset.deckel = m.id;
        const aus = el("option");
        aus.value = "";
        aus.textContent = t("satz.deckelAuslieferungWahl", { deckel: m.deckelRegistry || t("wort.ohne") });
        wahl.appendChild(aus);
        for (const st2 of stufen) {
          const o = el("option");
          o.value = st2;
          o.textContent = st2;
          if (gesetzt && gesetzt.cap === st2) o.selected = true;
          wahl.appendChild(o);
        }
        wahl.addEventListener("change", (e) => {
          const stufe = wahl.value;
          if (!stufe) {
            void werkzeug({ command: "effort-cap", model: m.id }, e.isTrusted);
            return;
          }
          frage(
            t("frage.deckel.text", { modell: m.label, stufe }),
            t("frage.deckel.tun"),
            (grund, echtJa) => void werkzeug({ command: "effort-cap", model: m.id, stufe, grund }, echtJa),
            true
          );
        });
        wahlZelle.appendChild(wahl);
      }
      r.appendChild(wahlZelle);
      const qz = el(
        "td",
        gesetzt ? "gesetzt" : "stufenzelle",
        quelle === "einstellung" ? t("wort.vonDirAm", { datum: (gesetzt?.gesetzt ?? "").slice(0, 10) }) : quelle
      );
      r.appendChild(qz);
      r.appendChild(el("td", "stufenzelle", gesetzt?.grund ?? ""));
      dt.appendChild(r);
    }
    if (treffer.length === 0) {
      const r = el("tr");
      const c = el("td", "wert", t("satz.keinTrefferSuche"));
      c.colSpan = 5;
      r.appendChild(c);
      dt.appendChild(r);
    }
    const deckelBox = el("div");
    deckelBox.append(suchfeld, dt);
    if (treffer.length > 60) {
      deckelBox.appendChild(el("div", "leerhinweis", t("satz.zuVieleTreffer", { anzahl: treffer.length })));
    }
    feld(g4, { ...texte("effortCaps"), wartet: true, breit: true, steuer: deckelBox });
    return s;
  }
  function seiteMaschinen(d) {
    const s = el("section", "seite");
    s.dataset.seite = "maschinen";
    s.appendChild(el("h1", void 0, t("seite.maschinen.titel")));
    s.appendChild(el("p", "unterzeile", t("seite.maschinen.unterzeile")));
    const g = gruppe(el("section"), t("gruppe.maschinen.liste"));
    const liste = el("div", "zeilen");
    liste.id = "maschinenListe";
    const eigen = el("div", "zeile");
    eigen.dataset.maschine = "local";
    eigen.appendChild(el("span", "titel", d.machine));
    eigen.appendChild(el("span", "grund", t("satz.eigeneMaschine")));
    liste.appendChild(eigen);
    if (d.maschinen.length === 0) {
      liste.appendChild(el("div", "leerhinweis", t("satz.keineMaschine")));
    }
    for (const m of d.maschinen) {
      const pausiert = d.maschinenPausiert.includes(m);
      const z = el("div", pausiert ? "zeile abgeschaltet" : "zeile");
      z.dataset.maschine = m;
      const schalter = haken(`maschinePause-${m}`, !pausiert, (an) => {
        const neu = an ? d.maschinenPausiert.filter((x) => x !== m) : [...d.maschinenPausiert, m];
        void setze("remoteMachinesPausiert", neu);
      });
      schalter.title = t("wort.maschineLaden");
      z.appendChild(schalter);
      z.appendChild(el("span", "titel", m));
      const aufschrift = el("label", "hakenwort", t("wort.sitzungenLaden"));
      aufschrift.htmlFor = schalter.id;
      z.appendChild(aufschrift);
      z.appendChild(el("span", "grund", t("satz.fremdeMaschine", { name: m })));
      const rechts = el("div", "rechts");
      const antwort = el("span", "antwort", "");
      antwort.dataset.antwort = m;
      rechts.appendChild(antwort);
      rechts.appendChild(knopf(t("wort.pruefen"), () => {
        antwort.textContent = t("wort.frage");
        antwort.className = "antwort";
        void window.awbEinstellungen.maschinePruefen(m).then((r) => {
          antwort.textContent = r.ok ? t("wort.erreichbar") : t("wort.nichtErreichbar", { grund: r.ausgabe });
          antwort.className = r.ok ? "antwort gut" : "antwort schlecht";
          melde(`ssh ${m}: ${r.ausgabe}`, r.ok ? "gut" : "fehler");
        });
      }));
      rechts.appendChild(knopf(t("wort.entfernen"), () => {
        void setze("remoteMachines", d.maschinen.filter((x) => x !== m));
      }, true));
      z.appendChild(rechts);
      liste.appendChild(z);
      const hinweis = el("div", "klartext", t("satz.fremdeLast", { name: m }));
      hinweis.dataset.fremdelast = m;
      liste.appendChild(hinweis);
    }
    const anlegen = el("div", "anlegen");
    const neuFeld = el("input");
    neuFeld.type = "text";
    neuFeld.id = "maschineNeu";
    neuFeld.placeholder = t("platzhalter.maschine");
    neuFeld.spellcheck = false;
    anlegen.append(neuFeld, knopf(t("wort.hinzufuegen"), () => {
      const name = neuFeld.value.trim();
      if (!name) return;
      if (d.maschinen.includes(name)) {
        melde(t("satz.maschineSchonDa", { name }), "fehler");
        return;
      }
      void setze("remoteMachines", [...d.maschinen, name]);
    }));
    const box = el("div");
    box.append(liste, anlegen);
    feld(g, { ...texte("remoteMachines"), schluessel: "remoteMachines", breit: true, steuer: box });
    g.appendChild(el("div", "klartext", t("feld.remoteMachinesPausiert.wirkung")));
    const g2 = gruppe(s, t("gruppe.maschinen.last"));
    feld(g2, {
      ...texte("maxWorkers"),
      schluessel: "maxWorkers",
      steuer: zahl(
        "maxWorkers",
        Number(d.settings.maxWorkers ?? 8),
        1,
        64,
        "Worker",
        (n) => void setze("maxWorkers", n)
      )
    });
    const schlafRoh = Number(d.settings.schlafNachMinuten);
    const schlaf = Number.isInteger(schlafRoh) && schlafRoh >= 0 && schlafRoh <= 10080 ? schlafRoh : 60;
    feld(g2, {
      ...texte("schlafNachMinuten"),
      schluessel: "schlafNachMinuten",
      steuer: zahl(
        "schlafNachMinuten",
        schlaf,
        0,
        10080,
        t("wort.minuten"),
        (n) => void setze("schlafNachMinuten", Math.max(0, Math.min(10080, Math.floor(n))))
      )
    });
    const maschinenwahl = [
      { wert: "local", label: t("wort.dieseMaschine", { name: d.machine }) },
      ...d.maschinen.map((m) => ({ wert: m, label: m }))
    ];
    feld(el("section"), {
      ...texte("defaultWorkerMachine"),
      wartet: true,
      schluessel: "defaultWorkerMachine",
      steuer: segmente(
        "defaultWorkerMachine",
        String(d.settings.defaultWorkerMachine ?? "local"),
        maschinenwahl,
        (w) => void setze("defaultWorkerMachine", w)
      )
    });
    feld(g2, {
      ...texte("workerZustellung"),
      wartet: true,
      schluessel: "workerZustellung",
      steuer: segmente(
        "workerZustellung",
        String(d.settings.workerZustellung ?? "auto"),
        [
          { wert: "auto", label: t("wort.workerZustellung.auto") },
          { wert: "socket", label: t("wort.workerZustellung.socket") },
          { wert: "paste", label: t("wort.workerZustellung.paste") }
        ],
        (w) => void setze("workerZustellung", w)
      )
    });
    return s;
  }
  function meldungTestZeile(weg, ergebnis) {
    const z = el("div", "zeile");
    z.dataset.meldungTest = weg;
    z.appendChild(el("span", "titel", t(`weg.${weg}`)));
    const antwort = el("span", ergebnis.ok ? "antwort gut" : "antwort schlecht");
    antwort.textContent = weg === "handy" ? ergebnis.ok ? t("meldungTesten.handy.ok", { status: ergebnis.status ?? 0 }) : t("meldungTesten.handy.fehler", { grund: ergebnis.grund ?? "" }) : t(`meldungTesten.${weg}.${ergebnis.ok ? "ok" : "fehler"}`, { grund: ergebnis.grund ?? "" });
    z.appendChild(antwort);
    return z;
  }
  function meldungTestErgebnisZeichnen(box, r, meldeWege) {
    box.textContent = "";
    if (!r.an) {
      box.className = "klartext";
      box.textContent = t("meldungTesten.hauptschalterAus");
      return;
    }
    const gewaehlt = meldeWege.filter((weg) => r.ergebnisse[weg] !== void 0);
    if (gewaehlt.length === 0) {
      box.className = "klartext";
      box.textContent = t("meldungTesten.keinWeg");
      return;
    }
    box.className = "zeilen";
    for (const weg of gewaehlt) box.appendChild(meldungTestZeile(weg, r.ergebnisse[weg]));
  }
  function seiteAufsicht(d) {
    const s = el("section", "seite");
    s.dataset.seite = "aufsicht";
    s.appendChild(el("h1", void 0, t("seite.aufsicht.titel")));
    s.appendChild(el("p", "unterzeile", t("seite.aufsicht.unterzeile")));
    const wacheAn = d.settings.contextGuardAutostart !== false;
    const g1 = gruppe(s, t("gruppe.aufsicht.wache"));
    feld(g1, {
      ...texte("contextGuardAutostart"),
      wartet: true,
      schluessel: "contextGuardAutostart",
      steuer: haken("contextGuardAutostart", wacheAn, (an) => {
        if (an) {
          void setze("contextGuardAutostart", true);
          return;
        }
        frage(
          t("frage.wacheAus.text"),
          t("frage.wacheAus.tun"),
          () => void setze("contextGuardAutostart", false)
        );
      })
    });
    const orch = d.wache.orchestrator ?? { an: true, mahnenAb: 75, eingreifen: true, notbremseAb: 80 };
    const wkr = d.wache.worker ?? { an: true, mahnenAb: 80, eingreifen: true };
    feld(g1, {
      ...texte("wacheOrchAn"),
      wartet: true,
      steuer: haken("wacheOrchAn", orch.an, (an, echt) => {
        if (an) {
          void werkzeug({ command: "wache-set", rolle: "orchestrator", an: true }, echt);
          return;
        }
        frage(
          t("frage.wacheOrchAus.text"),
          t("frage.wacheOrchAus.tun"),
          (grund, echtJa) => void werkzeug({ command: "wache-set", rolle: "orchestrator", an: false, grund }, echtJa),
          true
        );
      })
    });
    feld(g1, {
      ...texte("wacheWorkerAn"),
      wartet: true,
      steuer: haken("wacheWorkerAn", wkr.an, (an, echt) => {
        if (an) {
          void werkzeug({ command: "wache-set", rolle: "worker", an: true }, echt);
          return;
        }
        frage(
          t("frage.wacheWorkerAus.text"),
          t("frage.wacheWorkerAus.tun"),
          (grund, echtJa) => void werkzeug({ command: "wache-set", rolle: "worker", an: false, grund }, echtJa),
          true
        );
      })
    });
    feld(g1, {
      ...texte("wacheWorkerMahnenAb"),
      wartet: true,
      steuer: zahl("wacheWorkerMahnenAb", wkr.mahnenAb, 1, 99, "%", (n, echt) => {
        if (n <= wkr.mahnenAb) {
          void werkzeug({ command: "wache-set", rolle: "worker", mahnenAb: n }, echt);
          return;
        }
        frage(
          t("frage.mahnenHoch.worker", { wert: n }),
          t("frage.mahnenHoch.tun"),
          (grund, echtJa) => void werkzeug({ command: "wache-set", rolle: "worker", mahnenAb: n, grund }, echtJa),
          true
        );
      })
    });
    feld(g1, {
      ...texte("wacheOrchMahnenAb"),
      wartet: true,
      steuer: zahl("wacheOrchMahnenAb", orch.mahnenAb, 1, 99, "%", (n, echt) => {
        if (n <= orch.mahnenAb) {
          void werkzeug({ command: "wache-set", rolle: "orchestrator", mahnenAb: n }, echt);
          return;
        }
        frage(
          t("frage.mahnenHoch.orch", { wert: n }),
          t("frage.mahnenHoch.tun"),
          (grund, echtJa) => void werkzeug({ command: "wache-set", rolle: "orchestrator", mahnenAb: n, grund }, echtJa),
          true
        );
      })
    });
    feld(g1, {
      ...texte("wacheOrchEingreifen"),
      wartet: true,
      steuer: haken("wacheOrchEingreifen", orch.eingreifen, (an, echt) => {
        if (an) {
          void werkzeug({ command: "wache-set", rolle: "orchestrator", eingreifen: true }, echt);
          return;
        }
        frage(
          t("frage.eingreifenAus.text"),
          t("frage.eingreifenAus.tun"),
          (grund, echtJa) => void werkzeug({ command: "wache-set", rolle: "orchestrator", eingreifen: false, grund }, echtJa),
          true
        );
      })
    });
    feld(g1, {
      ...texte("wacheOrchNotbremseAb"),
      wartet: true,
      steuer: zahl("wacheOrchNotbremseAb", orch.notbremseAb ?? 80, 1, 99, "%", (n, echt) => {
        const alt = orch.notbremseAb ?? 80;
        if (n <= alt) {
          void werkzeug({ command: "wache-set", rolle: "orchestrator", notbremseAb: n }, echt);
          return;
        }
        frage(
          t("frage.notbremseHoch.text", { wert: n }),
          t("frage.notbremseHoch.tun"),
          (grund, echtJa) => void werkzeug({ command: "wache-set", rolle: "orchestrator", notbremseAb: n, grund }, echtJa),
          true
        );
      })
    });
    klartext(g1, t("satz.guardsWohnenAnderswo"));
    const g2 = gruppe(s, t("gruppe.aufsicht.stillstand"));
    feld(g2, {
      ...texte("stallMinutes"),
      schluessel: "stallMinutes",
      steuer: zahl(
        "stallMinutes",
        Number(d.settings.stallMinutes ?? 10),
        1,
        120,
        "Minuten Stille",
        (n) => void setze("stallMinutes", n)
      )
    });
    feld(g2, {
      ...texte("guardMeldetWorkerStatus"),
      wartet: true,
      schluessel: "guardMeldetWorkerStatus",
      steuer: haken(
        "guardMeldetWorkerStatus",
        d.settings.guardMeldetWorkerStatus === true,
        (an) => void setze("guardMeldetWorkerStatus", an)
      )
    });
    const g3 = gruppe(s, t("gruppe.aufsicht.meldungen"));
    const m = d.meldungen;
    const meldeSetzen = (aenderung) => {
      void setze("meldungen", { ...m, ...aenderung });
    };
    feld(g3, {
      ...texte("meldungenAn"),
      wartet: true,
      schluessel: "meldungen",
      // Wird der Schalter angelegt, waehrend weder Ereignisse noch Wege stehen
      // (die Vorgabe fuer beide ist LEER, Absicht -- siehe meldungen() in
      // main/einstellungen.ts), zeigte die Oberflaeche danach vier gehakte
      // Kaesten, ohne dass je etwas verschickt wuerde: der Sendeweg liest
      // dieselbe leere Liste. Deshalb schreibt EINMAL, beim Einschalten, der
      // volle Vorgabeblock auf die Platte -- kein Vorgabe-Ruckfall beim Lesen,
      // sondern ein einmaliges Schreiben beim Umlegen des Schalters. Wer die
      // Listen danach von Hand leert, meint es so: das Schreiben greift nur an
      // dieser einen Flanke.
      steuer: haken("meldungenAn", m.an, (an) => {
        if (an && m.ereignisse.length === 0 && m.wege.length === 0) {
          const vorgabe = d.vorgaben.meldungen;
          meldeSetzen({
            an,
            ereignisse: [...vorgabe.ereignisse],
            wege: [...vorgabe.wege],
            limitSchwelle: vorgabe.limitSchwelle
          });
        } else {
          meldeSetzen({ an });
        }
      })
    });
    const ereignisBox = el("div", "zeilen");
    ereignisBox.id = "meldeEreignisse";
    for (const ereignis of d.meldeEreignisse) {
      const gewaehlt = m.ereignisse.includes(ereignis);
      const z = el("div", gewaehlt ? "zeile" : "zeile abgeschaltet");
      z.dataset.meldung = ereignis;
      z.appendChild(haken(`meldung-${ereignis}`, gewaehlt, (an) => {
        meldeSetzen({
          ereignisse: an ? d.meldeEreignisse.filter((x) => x === ereignis || m.ereignisse.includes(x)) : m.ereignisse.filter((x) => x !== ereignis)
        });
      }));
      z.appendChild(el("span", "titel", t(`meldung.${ereignis}`)));
      ereignisBox.appendChild(z);
    }
    feld(g3, { ...texte("meldungenEreignisse"), wartet: true, breit: true, steuer: ereignisBox });
    const wegBox = el("div");
    for (const weg of d.meldeWege) {
      const marke = el("label", "wegwahl");
      marke.appendChild(haken(`weg-${weg}`, m.wege.includes(weg), (an) => {
        meldeSetzen({
          wege: an ? d.meldeWege.filter((x) => x === weg || m.wege.includes(x)) : m.wege.filter((x) => x !== weg)
        });
      }));
      marke.appendChild(el("span", void 0, t(`weg.${weg}`)));
      wegBox.appendChild(marke);
    }
    feld(g3, { ...texte("meldungenWege"), wartet: true, breit: true, steuer: wegBox });
    feld(g3, {
      ...texte("meldungenHandyUrl"),
      wartet: true,
      breit: true,
      steuer: textzeile(
        "meldungenHandyUrl",
        m.handyUrl,
        t("platzhalter.handyUrl"),
        (w) => meldeSetzen({ handyUrl: w })
      )
    });
    feld(g3, {
      ...texte("meldungenTonDatei"),
      wartet: true,
      breit: true,
      steuer: textzeile(
        "meldungenTonDatei",
        m.tonDatei,
        t("platzhalter.tonDatei"),
        (w) => meldeSetzen({ tonDatei: w })
      )
    });
    feld(g3, {
      ...texte("meldungenLimitSchwelle"),
      wartet: true,
      steuer: zahl(
        "meldungenLimitSchwelle",
        m.limitSchwelle,
        1,
        99,
        "%",
        (n) => meldeSetzen({ limitSchwelle: n })
      )
    });
    const testBox = el("div");
    const testErgebnisEl = el("div");
    testErgebnisEl.id = "meldungTestErgebnis";
    testBox.appendChild(knopf(t("knopf.meldungTesten"), () => {
      testErgebnisEl.className = "klartext";
      testErgebnisEl.textContent = t("meldungTesten.laeuft");
      void window.awbEinstellungen.meldungTesten().then((r) => {
        meldungTestErgebnisZeichnen(testErgebnisEl, r, d.meldeWege);
      });
    }));
    testBox.appendChild(testErgebnisEl);
    feld(g3, { ...texte("meldungTesten"), breit: true, steuer: testBox });
    return s;
  }
  function seiteAussehen(d) {
    const s = el("section", "seite");
    s.dataset.seite = "aussehen";
    s.appendChild(el("h1", void 0, t("seite.aussehen.titel")));
    s.appendChild(el("p", "unterzeile", t("seite.aussehen.unterzeile")));
    const g1 = gruppe(s, t("gruppe.aussehen.thema"));
    feld(g1, {
      ...texte("thema"),
      schluessel: "thema",
      steuer: segmente(
        "thema",
        d.thema,
        [
          { wert: "system", label: t("wort.thema.system") },
          { wert: "hell", label: t("wort.thema.hell") },
          { wert: "dunkel", label: t("wort.thema.dunkel") }
        ],
        (w) => void setze("thema", w)
      )
    });
    const farbBox = el("div", "farben");
    for (const zustand of ["laeuft", "wartet", "fertig", "tot"]) {
      const zelle = el("label", "farbe");
      const i = el("input");
      i.type = "color";
      i.id = `farbe-${zustand}`;
      i.value = d.zustandsfarben[zustand] ?? "#888888";
      i.addEventListener("change", () => {
        void setze("zustandsfarben", { ...d.zustandsfarben, [zustand]: i.value });
      });
      zelle.appendChild(i);
      zelle.appendChild(el("span", void 0, t(`zustand.${zustand}`)));
      farbBox.appendChild(zelle);
    }
    feld(g1, { ...texte("zustandsfarben"), schluessel: "zustandsfarben", breit: true, steuer: farbBox });
    const g2 = gruppe(s, t("gruppe.aussehen.terminal"));
    feld(g2, {
      ...texte("terminalFontSize"),
      schluessel: "terminalFontSize",
      steuer: zahl(
        "terminalFontSize",
        Number(d.settings.terminalFontSize ?? 13),
        8,
        32,
        t("wort.einheit.punkt"),
        (n) => void setze("terminalFontSize", n)
      )
    });
    feld(g2, {
      ...texte("terminalScrollLines"),
      schluessel: "terminalScrollLines",
      steuer: zahl(
        "terminalScrollLines",
        Number(d.settings.terminalScrollLines ?? 3),
        1,
        20,
        t("wort.einheit.zeilen"),
        (n) => void setze("terminalScrollLines", n)
      )
    });
    const g3 = gruppe(s, t("gruppe.aussehen.panes"));
    feld(g3, {
      ...texte("minWorkerPaneWidth"),
      schluessel: "minWorkerPaneWidth",
      steuer: zahl(
        "minWorkerPaneWidth",
        Number(d.settings.minWorkerPaneWidth ?? 80),
        20,
        1e3,
        t("wort.einheit.spalten"),
        (n) => void setze("minWorkerPaneWidth", n)
      )
    });
    feld(g3, {
      ...texte("maxWorkerPanesPerTab"),
      wartet: true,
      schluessel: "maxWorkerPanesPerTab",
      steuer: zahl(
        "maxWorkerPanesPerTab",
        Number(d.settings.maxWorkerPanesPerTab ?? 6),
        0,
        64,
        "Panes",
        (n) => void setze("maxWorkerPanesPerTab", n)
      )
    });
    feld(g3, {
      ...texte("workerLayout"),
      wartet: true,
      schluessel: "workerLayout",
      steuer: segmente(
        "workerLayout",
        String(d.settings.workerLayout ?? "split"),
        [
          { wert: "split", label: t("wort.workerLayout.split") },
          { wert: "window", label: t("wort.workerLayout.window") }
        ],
        (w) => void setze("workerLayout", w)
      )
    });
    const g4 = gruppe(s, t("gruppe.aussehen.sprache"));
    const sprachBox = el("div");
    sprachBox.appendChild(segmente(
      "sprache",
      d.sprache,
      [
        { wert: "de", label: t("wort.sprache.de") },
        { wert: "en", label: t("wort.sprache.en") }
      ],
      (w) => void setze("sprache", w)
    ));
    if (!spracheHatTabelle()) sprachBox.appendChild(el("div", "klartext", t("satz.spracheNochNichtDa")));
    feld(g4, { ...texte("sprache"), wartet: true, schluessel: "sprache", breit: true, steuer: sprachBox });
    const rollenBox = el("div", "rollen");
    for (const rolle of ["orchestrator", "worker"]) {
      const zelle = el("label", "rolle");
      zelle.appendChild(haken(
        `chatAnsichtVorgabe-${rolle}`,
        d.chatAnsichtVorgabe[rolle] === true,
        (an) => void setze("chatAnsichtVorgabe", { ...d.chatAnsichtVorgabe, [rolle]: an })
      ));
      zelle.appendChild(el("span", void 0, t(`wort.rolle.${rolle}`)));
      rollenBox.appendChild(zelle);
    }
    feld(g4, {
      ...texte("chatAnsichtVorgabe"),
      wartet: true,
      schluessel: "chatAnsichtVorgabe",
      breit: true,
      steuer: rollenBox
    });
    return s;
  }
  function abweichungen(d) {
    return Object.keys(d.vorgaben).filter((k) => d.settings[k] !== void 0 && !gleichwie(d.settings[k], d.vorgaben[k])).sort();
  }
  function seiteProgramm(d) {
    const s = el("section", "seite");
    s.dataset.seite = "programm";
    s.appendChild(el("h1", void 0, t("seite.programm.titel")));
    s.appendChild(el("p", "unterzeile", t("seite.programm.unterzeile")));
    const g1 = gruppe(s, t("gruppe.programm.abweichungen"));
    const liste = abweichungen(d);
    const abTabelle = el("table");
    abTabelle.id = "abweichungen";
    const abKopf = el("tr");
    for (const h of [t("spalte.einstellung"), t("spalte.beiDir"), t("spalte.auslieferung"), ""]) {
      abKopf.appendChild(el("th", void 0, h));
    }
    abTabelle.appendChild(abKopf);
    if (liste.length === 0) {
      const r = el("tr");
      const c = el("td", "wert", t("satz.keineAbweichung"));
      c.colSpan = 4;
      r.appendChild(c);
      abTabelle.appendChild(r);
    }
    for (const k of liste) {
      const r = el("tr");
      r.dataset.abweichung = k;
      r.appendChild(el("td", void 0, t(`bezeichnung.${k}`)));
      r.appendChild(wertZelle(k, d.settings[k]));
      r.appendChild(wertZelle(k, d.vorgaben[k]));
      const zelle = el("td");
      zelle.appendChild(knopf(t("wort.zuruecksetzen"), () => void setze(k, d.vorgaben[k])));
      r.appendChild(zelle);
      abTabelle.appendChild(r);
    }
    feld(g1, { ...texte("abweichungen"), breit: true, steuer: abTabelle });
    const g2 = gruppe(s, t("gruppe.programm.sicherung"));
    const sicherBox = el("div");
    const stand = {};
    for (const k of liste) stand[k] = d.settings[k];
    const text = el("textarea", "sicherungsfeld");
    text.id = "sicherungsfeld";
    text.rows = 6;
    text.spellcheck = false;
    text.placeholder = t("platzhalter.sicherung");
    text.value = sicherungsText;
    text.addEventListener("input", () => {
      sicherungsText = text.value;
    });
    const reihe = el("div", "anlegen");
    reihe.appendChild(knopf(t("wort.kopieren"), () => {
      if (liste.length === 0) {
        melde(t("satz.sicherungLeer"), "fehler");
        return;
      }
      const roh = JSON.stringify(stand, null, 2);
      sicherungsText = roh;
      text.value = roh;
      void navigator.clipboard?.writeText(roh).then(
        () => melde(t("satz.sicherungKopiert", { zeichen: roh.length }), "gut"),
        // Ohne Zwischenablage steht der Text trotzdem im Feld und laesst sich von
        // Hand nehmen -- das ist der Punkt der Sicherung, nicht der Knopf.
        () => melde(t("satz.sicherungKopiert", { zeichen: roh.length }), "gut")
      );
    }));
    reihe.appendChild(knopf(t("wort.einsetzen"), () => {
      const roh = text.value.trim();
      if (!roh) {
        melde(t("satz.sicherungKeinText"), "fehler");
        return;
      }
      let geparst;
      try {
        geparst = JSON.parse(roh);
      } catch {
        melde(t("satz.sicherungKeinJson"), "fehler");
        return;
      }
      if (!geparst || typeof geparst !== "object" || Array.isArray(geparst)) {
        melde(t("satz.sicherungKeinJson"), "fehler");
        return;
      }
      const eintraege = Object.entries(geparst);
      frage(
        t("frage.einsetzen.text", { anzahl: eintraege.length }),
        t("frage.einsetzen.tun"),
        () => {
          void (async () => {
            for (const [k, w] of eintraege) await setze(k, w);
            melde(t("satz.sicherungEingesetzt", { anzahl: eintraege.length }), "gut");
          })();
        }
      );
    }));
    reihe.appendChild(knopf(t("wort.allesZurueck"), () => {
      if (liste.length === 0) {
        melde(t("satz.keineAbweichung"), "gut");
        return;
      }
      frage(
        t("frage.allesZurueck.text", { anzahl: liste.length }),
        t("frage.allesZurueck.tun"),
        () => {
          void (async () => {
            for (const k of liste) await setze(k, d.vorgaben[k]);
          })();
        }
      );
    }, true));
    sicherBox.append(text, reihe);
    feld(g2, { ...texte("sicherung"), breit: true, steuer: sicherBox });
    const g3 = gruppe(s, t("gruppe.programm.dateien"));
    const pt = el("table");
    pt.id = "pfadTabelle";
    for (const p of d.pfade) {
      const r = el("tr");
      r.appendChild(el("td", void 0, p.label));
      r.appendChild(el("td", "wert", p.wert));
      pt.appendChild(r);
    }
    for (const p of d.protokolle) {
      const r = el("tr");
      r.appendChild(el("td", void 0, `Protokoll: ${p.label}`));
      r.appendChild(el("td", "wert", p.path));
      pt.appendChild(r);
    }
    feld(g3, { ...texte("pfade"), breit: true, steuer: pt });
    const g4 = gruppe(s, t("gruppe.programm.erststart"));
    feld(g4, {
      ...texte("erststartZeigen"),
      steuer: knopf(t("wort.erneutZeigen"), (echt) => window.awbEinstellungen.erststartZeigen(echt))
    });
    return s;
  }
  var SEITENZEICHEN = {
    sitzung: { strich: "M2 3.4h12a1 1 0 0 1 1 1v7.2a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V4.4a1 1 0 0 1 1-1zM4.4 6.6l2 1.8-2 1.8M8.6 10.4h3.2" },
    erlaubnisse: { strich: "M8 1.6l5.2 1.9v3.7c0 3.1-2.2 5.5-5.2 6.9-3-1.4-5.2-3.8-5.2-6.9V3.5zM5.8 7.9l1.6 1.6 3-3.3" },
    harnesses: { strich: "M4.4 4.4h7.2v7.2H4.4zM6.4 1.4v3M9.6 1.4v3M6.4 11.6v3M9.6 11.6v3M1.4 6.4h3M1.4 9.6h3M11.6 6.4h3M11.6 9.6h3" },
    maschinen: { strich: "M1.6 3.2h12.8v7.4H1.6zM5.6 13.6h4.8M8 10.6v3" },
    aufsicht: { strich: "M1.4 8s2.5-4.4 6.6-4.4S14.6 8 14.6 8s-2.5 4.4-6.6 4.4S1.4 8 1.4 8zM8 6.1a1.9 1.9 0 1 0 0 3.8 1.9 1.9 0 0 0 0-3.8z" },
    aussehen: { strich: "M8 2.2a5.8 5.8 0 1 0 0 11.6 5.8 5.8 0 0 0 0-11.6z", flaeche: "M8 2.2a5.8 5.8 0 0 1 0 11.6z" },
    programm: { strich: "M1.6 2.4h12.8v2.8H1.6zM2.8 5.2h10.4v7.2a1 1 0 0 1-1 1H3.8a1 1 0 0 1-1-1zM6.4 8h3.2" }
  };
  function seitenzeichen(name) {
    const form = SEITENZEICHEN[name];
    if (!form) return null;
    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("class", "zeichen");
    svg.setAttribute("width", "16");
    svg.setAttribute("height", "16");
    svg.setAttribute("viewBox", "0 0 16 16");
    svg.setAttribute("aria-hidden", "true");
    if (form.flaeche) {
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", form.flaeche);
      p.setAttribute("fill", "currentColor");
      svg.appendChild(p);
    }
    if (form.strich) {
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", form.strich);
      p.setAttribute("fill", "none");
      p.setAttribute("stroke", "currentColor");
      p.setAttribute("stroke-width", "1.2");
      p.setAttribute("stroke-linecap", "round");
      p.setAttribute("stroke-linejoin", "round");
      svg.appendChild(p);
    }
    return svg;
  }
  var SEITEN = [
    { name: "sitzung", bau: seiteSitzung },
    { name: "erlaubnisse", bau: seiteErlaubnisse },
    { name: "harnesses", bau: seiteHarnesses },
    { name: "maschinen", bau: seiteMaschinen },
    { name: "aufsicht", bau: seiteAufsicht },
    { name: "aussehen", bau: seiteAussehen },
    { name: "programm", bau: seiteProgramm }
  ];
  function themaAnwenden(d) {
    document.documentElement.dataset.thema = d.thema;
    for (const [zustand, farbe] of Object.entries(d.zustandsfarben)) {
      if (/^#[0-9a-fA-F]{3,8}$/.test(farbe)) {
        document.documentElement.style.setProperty(`--zustand-${zustand}`, farbe);
      }
    }
  }
  var zeichnungen = 0;
  function zeichne() {
    if (!daten) return;
    zeichnungen += 1;
    infoZu();
    setzeSprache(daten.sprache);
    document.documentElement.lang = sprache();
    document.title = t("fenster.titel");
    themaAnwenden(daten);
    gezeichneteFelder = [];
    const kopfzeileEl = seitenlisteEl.querySelector(".kopfzeile");
    if (kopfzeileEl) kopfzeileEl.textContent = t("wort.einstellungen");
    for (const alt of seitenlisteEl.querySelectorAll("button")) alt.remove();
    for (const s of SEITEN) {
      const b = el("button");
      b.type = "button";
      b.dataset.seite = s.name;
      const zeichen = seitenzeichen(s.name);
      if (zeichen) b.appendChild(zeichen);
      b.appendChild(el("span", "name", t(`seite.${s.name}.titel`)));
      b.title = t(`seite.${s.name}.wofuer`);
      b.addEventListener("click", () => waehle(s.name));
      b.classList.toggle("gewaehlt", s.name === aktuelleSeite);
      seitenlisteEl.appendChild(b);
    }
    stapelEl.textContent = "";
    for (const s of SEITEN) {
      const seite = s.bau(daten);
      entdoppelteUeberschrift(seite);
      if (s.name === aktuelleSeite) seite.classList.add("offen");
      stapelEl.appendChild(seite);
    }
  }
  function entdoppelteUeberschrift(seite) {
    for (const g of Array.from(seite.querySelectorAll(".gruppe, .vorsicht"))) {
      const h2 = g.querySelector(":scope > h2");
      const felder = g.querySelectorAll(":scope > .koerper > .feld");
      if (!h2 || felder.length !== 1) continue;
      const name = felder[0].querySelector(":scope > .kopf > .name");
      if (!name) continue;
      if (name.textContent?.trim() !== h2.textContent?.trim()) continue;
      h2.remove();
    }
  }
  function waehle(name) {
    if (!SEITEN.some((s) => s.name === name)) return;
    aktuelleSeite = name;
    if (!stapelEl.children.length) {
      zeichne();
      stapelEl.scrollTop = 0;
      return;
    }
    infoZu();
    for (const b of seitenlisteEl.querySelectorAll("button")) {
      b.classList.toggle("gewaehlt", b.dataset.seite === name);
    }
    for (const seite of stapelEl.children) {
      seite.classList.toggle("offen", seite.dataset.seite === name);
    }
    stapelEl.scrollTop = 0;
  }
  window.__awbEin = {
    seiten: () => SEITEN.map((s) => s.name),
    offen: () => aktuelleSeite,
    zeige: (name) => {
      if (!SEITEN.some((s) => s.name === name)) return false;
      waehle(name);
      return true;
    },
    text: () => stapelEl.innerText,
    status: () => statusEl.textContent ?? "",
    klick: (auswahl) => {
      const e = document.querySelector(auswahl);
      if (!e) return false;
      e.click();
      return true;
    },
    // Lesen statt klicken. Ohne diesen Haken liesse sich "der Haken steht auf
    // aus" nur pruefen, indem man ihn drueckt -- und damit umlegt.
    zustand: (auswahl) => {
      const e = document.querySelector(auswahl);
      if (!e) return { da: false, gehakt: false, wert: "", text: "" };
      const i = e;
      return {
        da: true,
        gehakt: i.checked === true,
        wert: typeof i.value === "string" ? i.value : "",
        text: (e.innerText ?? "").replace(/\s+/g, " ").trim(),
        // Haengt nicht am gewaehlten Element, kommt aber ueber diesen einen
        // Lese-Weg nach draussen (main.ts reicht die Antwort unveraendert
        // weiter): wie oft die sieben Seiten seit dem Start neu gebaut wurden.
        // Ein Aufklappmenue kann nur zuschnappen, wenn neu gebaut wird -- diese
        // Zahl ist deshalb das Mass fuer den Befund vom 15.08.
        zeichnungen
      };
    },
    modelle: () => [...document.querySelectorAll(".modelleintrag")].map((b) => ({
      id: b.dataset.modell ?? "",
      text: b.innerText.replace(/\s+/g, " ").trim(),
      gewaehlt: b.classList.contains("gewaehlt")
    })),
    // Nicht "steht die Klasse dran", sondern: ist der Kasten wirklich zu sehen.
    // Ein Infozeichen, dessen Text hinter display:none liegt, hat keine Hoehe.
    info: () => ({
      feld: offenesInfo,
      text: infotextEl.textContent ?? "",
      sichtbar: getComputedStyle(infotextEl).display !== "none" && infotextEl.getBoundingClientRect().height > 0,
      hoehe: Math.round(infotextEl.getBoundingClientRect().height)
    }),
    felder: () => gezeichneteFelder.map((f) => ({ ...f }))
  };
  var gezeichneterStand = "";
  window.awbEinstellungen.onDaten((d) => {
    const stand = JSON.stringify(d);
    if (stand === gezeichneterStand) return;
    gezeichneterStand = stand;
    daten = d;
    kontextStand = {};
    zeichne();
  });
  void (async () => {
    daten = await window.awbEinstellungen.daten();
    gezeichneterStand = JSON.stringify(daten);
    zeichne();
    window.awbEinstellungen.bereit();
    void schluesselStatusLaden();
  })();
})();
