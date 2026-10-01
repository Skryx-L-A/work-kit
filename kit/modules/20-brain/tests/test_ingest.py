import json
import zipfile

import pytest

import docfixtures as fx
from conftest import git
from kitbrain import cli, ingest, notes


def test_docx(tmp_path):
    p = fx.docx(tmp_path / "Handbook_v2.docx", title="Engineering handbook", label="Internal",
                paras=[("Heading1", "Branching"), ("", "Use short-lived branches."),
                       ("List", "rebase before merge"), ("Heading2", "Reviews"), ("", "Two eyes.")],
                table=[["Tool", "Use"], ["git", "versioning"]])
    d = ingest.convert(p)
    assert d.title == "Engineering handbook" and d.format == "docx" and d.labels == ["Internal"]
    assert "## Branching\n\nUse short-lived branches." in d.markdown
    assert "- rebase before merge" in d.markdown and "### Reviews" in d.markdown
    assert "| Tool | Use |\n|---|---|\n| git | versioning |" in d.markdown


def test_pptx_with_notes(tmp_path):
    p = fx.pptx(tmp_path / "deck.pptx", [("Kick-off", ["Scope", "Timeline"]), ("Risks", ["Budget"])],
                notes={2: "Mention the audit."})
    d = ingest.convert(p)
    assert d.title == "Kick-off" and d.pages == 2
    assert "## Slide 1: Kick-off\n\n- Scope\n- Timeline" in d.markdown
    assert "## Slide 2: Risks" in d.markdown and "Speaker notes: Mention the audit." in d.markdown


def test_xlsx(tmp_path):
    p = fx.xlsx(tmp_path / "costs.xlsx", [("Q3", [["Item", "EUR"], ["Licences", 1200], ["Travel", None]]),
                                          ("Empty", [])])
    d = ingest.convert(p)
    assert "## Sheet: Q3" in d.markdown
    assert "| Item | EUR |\n|---|---|\n| Licences | 1200 |\n| Travel |" in d.markdown
    assert d.title == "costs"


def test_pdf(tmp_path):
    p = fx.pdf(tmp_path / "policy.pdf", [["Travel policy", "Book trains early."], ["Page two text"]],
               title="Travel policy", keywords="Internal")
    d = ingest.convert(p)
    assert d.title == "Travel policy" and d.pages == 2 and d.labels == ["Internal"]
    assert "## Page 1" in d.markdown and "Book trains early." in d.markdown
    assert "## Page 2" in d.markdown


def test_pdf_without_text_is_refused(tmp_path):
    p = fx.pdf(tmp_path / "scan.pdf", [[]])
    with pytest.raises(ingest.IngestError, match="no extractable text"):
        ingest.convert(p)


def test_html(tmp_path):
    p = tmp_path / "page.html"
    p.write_text("<html><head><title>Wiki &amp; Co</title><style>x{}</style></head><body>"
                 "<nav>skip?</nav><h1>Setup</h1><p>Install <b>uv</b> and "
                 "<a href='https://example.org/uv'>read this</a>.</p><ul><li>one</li><li>two</li></ul>"
                 "<pre>make   build\n  indented</pre><table><tr><th>A</th><th>B</th></tr>"
                 "<tr><td>1</td><td>2</td></tr></table><script>alert(1)</script></body></html>")
    d = ingest.convert(p)
    assert d.title == "Wiki & Co"
    assert "# Setup" in d.markdown and "Install **uv** and [read this](https://example.org/uv)." in d.markdown
    assert "- one\n- two" in d.markdown and "make   build\n  indented" in d.markdown
    assert "| A | B |\n|---|---|\n| 1 | 2 |" in d.markdown
    assert "alert" not in d.markdown and "x{}" not in d.markdown


def test_markdown_and_unsupported(tmp_path):
    p = tmp_path / "n.md"
    p.write_text("---\ntitle: From front\n---\n# Heading\ntext\n")
    assert ingest.convert(p).title == "From front"
    with pytest.raises(ingest.IngestError, match="unsupported"):
        ingest.convert(tmp_path / "x.exe")


def test_zip_bomb_and_broken_file(tmp_path, monkeypatch):
    p = fx.docx(tmp_path / "big.docx", paras=[("", "x" * 1000)])
    monkeypatch.setattr(ingest, "MAX_UNZIPPED", 100)
    with pytest.raises(ingest.IngestError, match="expands"):
        ingest.convert(p)
    bad = tmp_path / "bad.docx"
    bad.write_text("not a zip")
    with pytest.raises(ingest.IngestError, match="cannot read"):
        ingest.convert(bad)


def test_cli_ingest_commits_and_is_searchable(env, tmp_path, capsys):
    src = fx.docx(tmp_path / "onboarding.docx", title="Onboarding guide",
                  paras=[("Heading1", "Laptop"), ("", "Pick up the laptop at the IT desk.")])
    assert cli.main(["ingest", str(src), "--project", "Intro", "--tags", "hr"]) == 0
    out = capsys.readouterr().out
    assert "ingested as reference/onboarding-guide.md" in out
    note = notes.load(env / "reference" / "onboarding-guide.md")
    assert note.meta["source"]["format"] == "docx" and note.meta["source"]["file"] == "onboarding.docx"
    assert note.meta["project"] == "intro" and note.meta["tags"] == ["hr"]
    assert git(env, "log", "-1", "--pretty=%s").strip() == 'brain: ingest "Onboarding guide" from onboarding.docx'

    cli.main(["search", "laptop IT desk", "--json"])
    assert json.loads(capsys.readouterr().out)["results"][0]["path"] == "reference/onboarding-guide.md"

    # Same content again: nothing new.
    cli.main(["ingest", str(src)])
    assert "already ingested as reference/onboarding-guide.md" in capsys.readouterr().out
    # Changed source: refused without --update, replaced with it.
    fx.docx(src, title="Onboarding guide", paras=[("", "Pick up the laptop at reception.")])
    assert cli.main(["ingest", str(src)]) == 1
    assert "--update" in capsys.readouterr().err
    assert cli.main(["ingest", str(src), "--update"]) == 0
    assert "reception" in (env / "reference" / "onboarding-guide.md").read_text()
    assert len(list((env / "reference").glob("*.md"))) == 1


def test_cli_ingest_stdout_writes_nothing(env, tmp_path, capsys):
    src = tmp_path / "a.txt"
    src.write_text("plain text")
    assert cli.main(["ingest", str(src), "--stdout"]) == 0
    assert "plain text" in capsys.readouterr().out
    assert not env.exists()
