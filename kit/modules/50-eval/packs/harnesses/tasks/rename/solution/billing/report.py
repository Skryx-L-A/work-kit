from billing.calc import calculate_total


def line(customer, items):
    return f"{customer}: {calculate_total(items):.2f} EUR"
