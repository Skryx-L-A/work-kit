from kitbrain.chunking import MAX_CHARS, chunk


def test_splits_at_headings_with_path():
    body = "intro\n\n# A\ntext a\n## B\ntext b\n# C\ntext c\n"
    got = [(c.heading, c.text) for c in chunk(body)]
    assert got == [("", "intro"), ("A", "text a"), ("A > B", "text b"), ("C", "text c")]


def test_heading_inside_code_fence_is_not_a_heading():
    body = "# Real\n```\n# comment in code\n```\n"
    chunks = chunk(body)
    assert len(chunks) == 1
    assert "# comment in code" in chunks[0].text


def test_long_section_is_split():
    para = "word " * 100
    body = "# Long\n" + "\n\n".join([para] * 10)
    chunks = chunk(body)
    assert len(chunks) > 1
    assert all(len(c.text) <= MAX_CHARS for c in chunks)
    assert all(c.heading == "Long" for c in chunks)


def test_empty_note_keeps_one_chunk():
    assert len(chunk("")) == 1
    assert chunk("# Only a heading\n")[0].heading == "Only a heading"
