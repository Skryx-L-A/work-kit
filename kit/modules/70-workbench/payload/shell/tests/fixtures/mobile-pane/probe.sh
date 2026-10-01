#!/bin/bash
# Ein gewoehnliches bash-Skript, das nur `printf` benutzt. Beleg fuer die Gegenprobe in
# test-mobile-pane-write.sh: unter geerbten Funktionen (hostile-funktionen.sh) druckt es
# NICHT "echt", sondern die untergeschobene Antwort -- der Angriff greift also wirklich.
printf 'echt\n'
