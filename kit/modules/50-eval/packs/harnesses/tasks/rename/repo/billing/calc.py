"""Invoice totals."""

VAT = 0.19


def calc(items, vat=VAT):
    """Gross total of (quantity, unit_price) pairs, rounded to cents."""
    net = sum(q * p for q, p in items)
    return round(net * (1 + vat), 2)
