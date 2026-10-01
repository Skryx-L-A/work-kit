# Legacy code exercise (synthetic)

Fictional code in the style of an old order system. Used in C1 (explain), C2 (characterize)
and C3 (review a flawed AI patch).

```python
def calc_discount(total, cust_type, day):
    # 2009-03: weekend rule per Mr. K.
    d = 0
    if cust_type == "G":
        d = 0.1
    elif cust_type == "S":
        d = 0.05
    if day in (5, 6) and total > 100:
        d = d + 0.02
    amount = round(total * d, 1)
    if amount > 50:
        amount = 50
    return total - amount
```

C1: ask the AI to explain the function, then verify these by running the code, not by
trusting the explanation:
1. What does `day` count from? (5 and 6 are Saturday and Sunday if Monday is 0.)
2. What happens for `total = 100` exactly on a Saturday? (no weekend bonus: `>` not `>=`)
3. Is the discount rounded to cents? (no: to one decimal place)

C3: an AI proposed this "cleanup". Review it before reading the notes below.

```python
def calc_discount(total, cust_type, day):
    rates = {"G": 0.10, "S": 0.05}
    d = rates.get(cust_type, 0)
    if day >= 5 and total >= 100:
        d += 0.02
    return total - min(round(total * d, 2), 50)
```

Facilitator notes: `total >= 100` changes behavior at exactly 100; `round(..., 2)` changes
the rounding; `day >= 5` also matches invalid values such as 7. Three behavior changes in a
"cleanup" that should change none. The characterization tests from C2 must catch all three.
