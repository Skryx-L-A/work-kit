from pathlib import Path

import pytest

from kitdesign.deck import DeckError, parse, runs

SAMPLE = """---
title: "Deck: test"
author: A. Person
---
# Title slide

Subtitle line

::: notes
Say hello.
:::

---
# Bullets

- one
  - nested
- two

---
<!-- layout: big-number -->
# Number

**42 %**

caption

---
<!-- layout: two-column -->
# Columns

left
<!-- column -->
right

---
# Picture only

![cap](img.png)
"""


def test_parse_layouts_and_meta():
    d = parse(SAMPLE, Path("/base"))
    assert d.meta["title"] == "Deck: test"
    assert [s.layout for s in d.slides] == ["title", "bullets", "big-number", "two-column", "image"]
    assert d.slides[0].notes == "Say hello."
    assert d.slides[1].blocks[0].items == [(0, "one"), (1, "nested"), (0, "two")]
    assert len(d.slides[3].columns) == 2
    assert d.slides[4].blocks[0].path == Path("/base/img.png")


def test_separator_inside_notes_is_not_a_slide_break():
    d = parse("# A\n::: notes\n---\n:::\n---\n# B\n", Path("."))
    assert len(d.slides) == 2


def test_unknown_layout_fails():
    with pytest.raises(DeckError):
        parse("# A\n<!-- layout: fancy -->\n", Path("."))


def test_runs():
    assert runs("a **b** `c` *d*") == [("", "a "), ("b", "b"), ("", " "), ("code", "c"), ("", " "), ("i", "d")]
