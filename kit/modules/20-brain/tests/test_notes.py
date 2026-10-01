import pytest

from kitbrain import notes


def test_slugify_handles_german():
    assert notes.slugify("Größe & Maße: Übersicht") == "grosse-masse-ubersicht"
    assert notes.slugify("!!!") == "note"


@pytest.mark.parametrize("ntype,project,prefix", [
    ("note", None, "inbox/"),
    ("howto", None, "howto/"),
    ("reference", None, "reference/"),
    ("person", None, "people/"),
    ("decision", None, "decisions/0001-"),
    ("session", "Billing App", "projects/billing-app/sessions/"),
])
def test_create_places_by_type(tmp_path, ntype, project, prefix):
    p = notes.create(tmp_path, ntype, "My Title", project=project)
    rel = p.relative_to(tmp_path).as_posix()
    assert rel.startswith(prefix)
    meta = notes.load(p).meta
    assert meta["title"] == "My Title" and meta["type"] == ntype
    assert {"tags", "created", "updated"} <= set(meta)
    if ntype == "decision":
        assert meta["status"] == "proposed"


def test_kern_is_unique_per_project(tmp_path):
    p = notes.create(tmp_path, "kern", "Billing", project="billing")
    assert p.relative_to(tmp_path).as_posix() == "projects/billing/KERN.md"
    with pytest.raises(notes.NoteError):
        notes.create(tmp_path, "kern", "Billing again", project="billing")


def test_session_needs_project(tmp_path):
    with pytest.raises(notes.NoteError, match="--project"):
        notes.create(tmp_path, "session", "x")


def test_decisions_are_numbered_and_names_do_not_collide(tmp_path):
    a = notes.create(tmp_path, "decision", "Use X")
    b = notes.create(tmp_path, "decision", "Use X")
    assert a.name.startswith("0001-") and b.name.startswith("0002-")
    c = notes.create(tmp_path, "note", "Same")
    d = notes.create(tmp_path, "note", "Same")
    assert c != d and d.name == "same-2.md"


def test_append_keeps_frontmatter_formatting(tmp_path):
    p = tmp_path / "n.md"
    p.write_text("---\ntitle: T  # my comment\nupdated: '2000-01-01'\n---\n\nbody\n")
    notes.append(p, "more text")
    text = p.read_text()
    assert "# my comment" in text
    assert f"updated: '{notes.today()}'" in text
    assert text.endswith("body\n\nmore text\n")


def test_append_rejects_empty(tmp_path):
    p = notes.create(tmp_path, "note", "x")
    with pytest.raises(notes.NoteError):
        notes.append(p, "   ")


def test_safe_path_stays_inside_home(tmp_path):
    with pytest.raises(notes.NoteError):
        notes.safe_path(tmp_path, "../outside.md")
    with pytest.raises(notes.NoteError):
        notes.safe_path(tmp_path, ".brain/index")
    assert notes.safe_path(tmp_path, "inbox/a") == (tmp_path / "inbox" / "a.md").resolve()


def test_frontmatter_roundtrip_and_garbage():
    meta, body = notes.split_frontmatter("---\ntitle: A\n---\nbody")
    assert meta == {"title": "A"} and body == "body"
    meta, body = notes.split_frontmatter("---\n: [broken\n---\nbody")
    assert meta == {}
