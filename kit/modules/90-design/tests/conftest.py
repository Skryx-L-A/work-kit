import pytest


@pytest.fixture(autouse=True)
def refs_home(tmp_path, monkeypatch):
    """Every test gets its own empty design-refs folder."""
    home = tmp_path / "design-refs"
    for c in ("brand", "web", "slides", "documents", "diagrams"):
        (home / c).mkdir(parents=True)
        (home / c / "README.md").write_text("kit readme\n")
    monkeypatch.setenv("DESIGN_REFS", str(home))
    return home
