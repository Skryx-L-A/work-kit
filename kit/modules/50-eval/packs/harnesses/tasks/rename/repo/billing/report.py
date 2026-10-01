from billing.calc import calc


def line(customer, items):
    return f"{customer}: {calc(items):.2f} EUR"
