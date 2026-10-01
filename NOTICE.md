# Third-party notices

Original work-kit code, including the Agent Workbench (modules 70, 71 and 72), is Copyright (c) 2026 Skryx-L-A and licensed under the GNU Affero General Public License v3.0 only (AGPL-3.0-only, full text in `LICENSE`). These components retain their own licenses:

| Files in this repository | Upstream | License |
|---|---|---|
| `kit/modules/31-caveman/upstream/**` | Caveman skill and hooks | MIT; full text in `kit/modules/31-caveman/upstream/LICENSE` |
| `kit/modules/95-desktop/themes/*.toml`, `kit/modules/95-desktop/keys.tsv` | Omarchy theme colors and keyboard mappings | MIT; see `kit/modules/95-desktop/NOTICE.md` |
| `kit/modules/70-workbench/payload/app/dist/renderer/monaco-bootstrap.js` and `.css` | Monaco Editor, Microsoft | MIT; copyright Microsoft Corporation; https://github.com/microsoft/monaco-editor/blob/main/LICENSE.txt |
| DOMPurify code bundled in `monaco-bootstrap.js` | DOMPurify, Cure53 and contributors | Apache-2.0 OR MPL-2.0; this distribution uses Apache-2.0, with text in `licenses/Apache-2.0.txt` |
| `kit/modules/70-workbench/payload/app/dist/renderer/codicon-*.ttf` | VS Code Codicons, Microsoft | CC BY 4.0; attribution Microsoft; https://github.com/microsoft/vscode-codicons/blob/main/LICENSE |
| `00-README.pdf`, `03-for-IT.pdf` | Embedded IBM Plex Sans and IBM Plex Mono fonts | SIL Open Font License 1.1; license texts in `licenses/` |

The GNOME extension in `kit/modules/95-desktop/extensions/kit-tiling@work-kit/` is original work-kit code under AGPL-3.0-only. Offline packages, models, fonts and vendor CLIs are fetched separately; their licenses travel with the downloaded files or are supplied by their vendors. Proprietary vendor tools are downloaded from their vendors at pinned versions.
