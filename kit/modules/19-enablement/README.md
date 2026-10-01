# 19-enablement

AI enablement pack for non-technical and technical staff: facilitator guide, role-based
curriculum, EU AI Act Art. 4 literacy session, train-the-trainer track, completion
assessment, starter prompts, handouts. Plain Markdown, offline, no sudo, no other module needed.

```sh
cd ~/work/kit/modules/19-enablement && bash install.sh    # copies content/ to ~/work/enablement
bash uninstall.sh                                         # removes unedited files, keeps your edits
```

Start with `~/work/enablement/README.md`. Fill every `TODO(ask IT)` before a session.

Slides or PDF from a handout (needs 12-docs-tools, or use the `presentation-design` /
`document-design` skills):

```sh
cd ~/work/enablement
pandoc handouts/session-slides-art4.md -o art4.pptx
pandoc handouts/one-pager-ai-at-work.md -o one-pager.docx
```

Tests: `~/work/kit/docs/enablement.md`.
