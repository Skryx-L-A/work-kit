# 17-meeting-capture

Record a meeting locally, transcribe it with the local whisper engine, save a note. CLI `meeting`.
Offline, no sudo, audio never leaves the laptop. Needs `python3` or the kit CPython, and a
recorder (`pw-record` or `parecord`). Speech engine: install `80-quassel` (`meeting engine` checks).
Notes go to the brain (`20-brain`) if installed, else `~/work/meetings/`.

```sh
cd ~/work/kit/modules/17-meeting-capture && bash install.sh
bash uninstall.sh
```

Open a new terminal.

```sh
meeting policy --todo                  # read and complete the policy before the first recording
meeting engine                         # recorder, speech engine, note destination
meeting start --title "Sprint review" --participants "Sprint team"   # consent reminder first
meeting stop                           # transcribe, save note, delete audio
```

Then edit `~/.config/work-kit/meeting-ai-policy.md` and `meeting.conf`.

More commands and tests: `~/work/kit/docs/meeting-capture.md`.
