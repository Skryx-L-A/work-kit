from billing import calc as calc_module
from billing.report import line

ORDERS = {"Nord AG": [(2, 10.0), (1, 5.5)], "Sued KG": [(10, 1.25)]}

if __name__ == "__main__":
    for customer, items in ORDERS.items():
        print(line(customer, items))
    print("total", calc_module.calculate_total([i for items in ORDERS.values() for i in items], vat=0))
