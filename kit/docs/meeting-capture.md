# 17-meeting-capture: commands, files, tests

## Commands

```sh
meeting status                             # recording or idle
meeting cancel                             # stop and delete the recording
meeting stop --summarize                   # summary by a local model (see meeting.conf)
meeting transcribe file.wav                # 16 kHz mono WAV made elsewhere
meeting purge --days 90                    # delete old audio and old notes in ~/work/meetings
```

`meeting start` options: `--title T`, `--project P`, `--participants "A, B"`,
`--source mic|system|both`, `--consent-given`. `meeting stop` options: `--keep-audio`,
`--no-transcribe`, `--language de|en|...`, `--summarize`.

## Summary key

`meeting stop --summarize` sends `Authorization: Bearer <key>` to `summary_url` when it has a key:

- `MEETING_SUMMARY_KEY` (environment) is used for any `summary_url`. There is no `meeting.conf`
  entry for it on purpose: a key does not belong in a plain config file.
- When `summary_url` is the local kit-models proxy (`http://127.0.0.1:<port>/e/<endpoint>/v1`,
  written by `kit-models default <name> --also meeting`), the proxy token is used without any setting:
  `KIT_MODELS_PROXY_KEY`, else `~/.local/share/work-kit/model-endpoints/proxy.token`. That token is
  sent only to such a URL.
- The key is never printed, logged or written into a note. A `401` from the server ends in
  "Summary failed" and a hint to set `MEETING_SUMMARY_KEY`; the note gets an empty summary section.

## Files

- Policy and settings to edit: `~/.config/work-kit/meeting-ai-policy.md`, `meeting.conf`.
- Without a brain the notes go to `~/work/meetings/`; `meeting purge` cleans there.

## Tests

`python3 -m pytest tests/` (build host only: pytest is not shipped on the stick) and
`bash tests/test-install.sh` in the module folder.
