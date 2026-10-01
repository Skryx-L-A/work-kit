"""Split a list into pages."""


def page(items, number, size):
    """Return page `number` (1-based) of `items` with `size` entries per page."""
    if number < 1 or size < 1:
        raise ValueError("number and size must be positive")
    start = number * size
    return items[start:start + size]


def page_count(items, size):
    """Number of pages needed for `items`."""
    return (len(items) + size - 1) // size
