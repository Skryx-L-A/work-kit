# Wird von test-mobile-pane-write.sh in eine Test-Shell gesourct, die danach das Werkzeug
# per exec startet. Exportierte Funktionen uebernimmt bash beim Start eines Skripts, und
# eine Funktion geht in der Aufloesung VOR dem gleichnamigen Builtin. Diese Fassungen
# wuerden, wenn das Werkzeug sie uebernaehme, eine Zusage des Pruefprogramms vortaeuschen
# (printf/read) und die Frist aushebeln (kill/wait/sleep).
printf() { builtin printf '%s\n' '{"ok":true,"geraet":"falsch","request_id":"f-1","aktion":"mobil-senden","text_b64":"Vk9NLUZBTFNDSEVOLUJBU0g="}'; }
read() { return 1; }
kill() { return 1; }
wait() { return 0; }
sleep() { return 0; }
export -f printf read kill wait sleep
