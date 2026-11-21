"""
generate_data.py — builds the Harbor Line Industrial sales database.

Harbor Line Industrial is a FICTIONAL B2B supplier of fans, ducting,
filtration, pumps, controls, and (from mid-2024) solar pumping kits,
selling across five Argentine regions. Every name is invented.

Run:
    python generate_data.py

Output:
    harbor_line.db          SQLite database (schema from schema.sql)
    data/*.csv              one CSV per table, for Tableau / Excel

Only the Python standard library is used, and the random seed is
fixed, so everyone who runs this gets exactly the same data.

The data contains realistic business patterns (and some realistic
data-quality problems) for the analysis to discover. They are listed
in ANSWER_KEY.md — read that only after you've done the analysis.
"""

import csv
import math
import random
import sqlite3
from datetime import date, timedelta
from pathlib import Path

import os
SEED = int(os.environ.get("SEED", 3))   # change only if you want a different dataset
random.seed(SEED)

HERE = Path(__file__).parent
DB_PATH = HERE / "harbor_line.db"
CSV_DIR = HERE / "data"

START = date(2023, 1, 1)
END = date(2026, 6, 30)          # data extract date
PRICE_INCREASE_DATE = date(2025, 3, 1)
PRICE_INCREASE = 0.12            # +12% on all list prices


# ------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------
def poisson(lam):
    """Knuth's Poisson sampler (fine for the small rates used here)."""
    if lam <= 0:
        return 0
    l, k, p = math.exp(-lam), 0, 1.0
    while True:
        k += 1
        p *= random.random()
        if p <= l:
            return k - 1


def rand_date(a, b):
    return a + timedelta(days=random.randint(0, (b - a).days))


def month_iter(a, b):
    y, m = a.year, a.month
    while date(y, m, 1) <= b:
        yield date(y, m, 1)
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)


def month_end(d):
    nxt = date(d.year + 1, 1, 1) if d.month == 12 else date(d.year, d.month + 1, 1)
    return nxt - timedelta(days=1)


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


# ------------------------------------------------------------------
# Reference data
# ------------------------------------------------------------------
REGIONS = ["AMBA", "Centro", "Cuyo", "Norte", "Patagonia"]

# rep_id, name, region, hire_date, win_bonus, mean_days_to_decide, discount_style
REPS = [
    (1, "Martín Ferreyra",  "AMBA",      date(2019, 4, 1),  0.06, 16, 0.07),
    (2, "Lucía Benítez",    "AMBA",      date(2021, 8, 16), 0.00, 21, 0.09),
    (3, "Diego Arrieta",    "Centro",    date(2018, 2, 5),  0.02, 24, 0.12),
    (4, "Valentina Sosa",   "Centro",    date(2024, 3, 4),  -0.08, 30, 0.10),  # new hire
    (5, "Nicolás Quiroga",  "Cuyo",      date(2020, 6, 1),  0.01, 38, 0.08),   # slow closer
    (6, "Camila Ortiz",     "Norte",     date(2022, 1, 10), -0.02, 22, 0.13),  # heavy discounter
    (7, "Tomás Lescano",    "Patagonia", date(2019, 11, 4), 0.03, 19, 0.06),
]
REP_BY_REGION = {}
for r in REPS:
    REP_BY_REGION.setdefault(r[2], []).append(r)

# product_id, name, category, standard_cost, list_price, launch_date
PRODUCTS = [
    (1,  "Centrifugal Fan CF-300",        "Fans & Blowers",     1450, 2350, date(2020, 1, 1)),
    (2,  "Centrifugal Fan CF-600",        "Fans & Blowers",     2900, 4600, date(2020, 1, 1)),
    (3,  "Centrifugal Fan CF-1200",       "Fans & Blowers",     6100, 9400, date(2020, 1, 1)),
    (4,  "Axial Fan AX-450",              "Fans & Blowers",     980,  1590, date(2020, 1, 1)),
    (5,  "Galvanized Duct Section 1m",    "Ducting",            62,   84,   date(2020, 1, 1)),
    (6,  "Duct Elbow 90°",                "Ducting",            48,   66,   date(2020, 1, 1)),
    (7,  "Motorized Damper MD-200",       "Ducting",            310,  455,  date(2020, 1, 1)),
    (8,  "Flexible Duct 10m",             "Ducting",            120,  165,  date(2020, 1, 1)),
    (9,  "Bag Filter Unit BF-12",         "Filtration",         3400, 5300, date(2020, 1, 1)),
    (10, "Cartridge Filter CT-8",         "Filtration",         1750, 2750, date(2020, 1, 1)),
    (11, "Cyclone Separator CY-500",      "Filtration",         2600, 3900, date(2020, 1, 1)),
    (12, "Replacement Filter Bags (x20)", "Filtration",         280,  520,  date(2020, 1, 1)),
    (13, "Centrifugal Pump CP-50",        "Pumps",              1100, 1720, date(2020, 1, 1)),
    (14, "Submersible Pump SP-75",        "Pumps",              1650, 2580, date(2020, 1, 1)),
    (15, "Dosing Pump DP-10",             "Pumps",              540,  880,  date(2020, 1, 1)),
    (16, "Variable Frequency Drive 15kW", "Controls & Sensors", 890,  1480, date(2020, 1, 1)),
    (17, "Pressure Transmitter PT-1",     "Controls & Sensors", 140,  265,  date(2020, 1, 1)),
    (18, "Flow Meter FM-80",              "Controls & Sensors", 720,  1190, date(2020, 1, 1)),
    (19, "PLC Control Panel",             "Controls & Sensors", 2400, 4100, date(2020, 1, 1)),
    (20, "Installation (per day)",        "Services",           260,  640,  date(2020, 1, 1)),
    (21, "Annual Maintenance Contract",   "Services",           1900, 4200, date(2020, 1, 1)),
    (22, "Solar Pump Kit SPK-2kW",        "Solar Pumping",      2300, 3650, date(2024, 7, 1)),
    (23, "Solar Pump Kit SPK-5kW",        "Solar Pumping",      4700, 7300, date(2024, 7, 1)),
    (24, "PV Array Extension 1kW",        "Solar Pumping",      620,  1020, date(2024, 7, 1)),
]
PROD = {p[0]: p for p in PRODUCTS}

# typical quantity range per category
QTY = {
    "Fans & Blowers": (1, 4),
    "Ducting": (10, 120),
    "Filtration": (1, 4),
    "Pumps": (1, 6),
    "Controls & Sensors": (1, 8),
    "Services": (1, 10),
    "Solar Pumping": (1, 5),
}

# which categories each industry tends to buy (relative weights)
INDUSTRY_MIX = {
    "Mining":            {"Fans & Blowers": 5, "Ducting": 4, "Filtration": 5, "Pumps": 3, "Controls & Sensors": 2, "Services": 2},
    "Oil & Gas":         {"Fans & Blowers": 3, "Ducting": 2, "Filtration": 2, "Pumps": 5, "Controls & Sensors": 4, "Services": 3},
    "Food & Beverage":   {"Fans & Blowers": 3, "Ducting": 5, "Filtration": 3, "Pumps": 3, "Controls & Sensors": 3, "Services": 2},
    "Agriculture":       {"Fans & Blowers": 2, "Ducting": 1, "Filtration": 1, "Pumps": 5, "Controls & Sensors": 2, "Services": 1, "Solar Pumping": 6},
    "Manufacturing":     {"Fans & Blowers": 4, "Ducting": 5, "Filtration": 4, "Pumps": 2, "Controls & Sensors": 4, "Services": 2},
    "Water Utilities":   {"Fans & Blowers": 1, "Ducting": 1, "Filtration": 2, "Pumps": 6, "Controls & Sensors": 4, "Services": 3, "Solar Pumping": 3},
    "Construction":      {"Fans & Blowers": 3, "Ducting": 6, "Filtration": 2, "Pumps": 2, "Controls & Sensors": 1, "Services": 2},
}
INDUSTRIES = list(INDUSTRY_MIX)

# Argentine calendar: January summer break, July winter break, Q4 budget push
SEASON = {1: 0.50, 2: 0.80, 3: 1.05, 4: 1.00, 5: 1.00, 6: 0.95,
          7: 0.80, 8: 1.00, 9: 1.05, 10: 1.12, 11: 1.22, 12: 0.90}
GROWTH = {2023: 1.00, 2024: 1.04, 2025: 1.06, 2026: 1.10}  # on top of new-customer acquisition

# ------------------------------------------------------------------
# Customers
# ------------------------------------------------------------------
# invariant place-style nouns (no gender agreement issues); all combos invented
NAME_A = ["Tandil", "Pehuén", "Lihué", "Nahuel", "Calchaquí", "Colorado", "Tres Cerros",
          "Cerro Chato", "Laguna Verde", "Los Tilos", "El Ceibo", "Las Tunas", "Quebracho",
          "Algarrobo", "Ñandú", "Cardón", "Arroyo Seco", "Los Álamos", "Piedra Negra",
          "Viento Sur", "Salinas", "Médanos", "Caldén", "Tala", "Jarilla", "Espinillo",
          "Maitén", "Coirón", "Ombú", "Molle"]
NAME_B = {
    "Mining":          ["Minera", "Minerales", "Recursos Mineros", "Metales"],
    "Oil & Gas":       ["Energía", "Petróleo", "Gas", "Servicios Petroleros"],
    "Food & Beverage": ["Alimentos", "Lácteos", "Bodegas", "Frigorífico"],
    "Agriculture":     ["Agro", "Agropecuaria", "Semillas", "Riego"],
    "Manufacturing":   ["Industrias", "Metalúrgica", "Plásticos", "Fundición"],
    "Water Utilities": ["Cooperativa de Agua", "Saneamiento", "Hídrica", "Servicios Hídricos"],
    "Construction":    ["Constructora", "Obras", "Estructuras", "Desarrollos"],
}
SUFFIX = ["S.A.", "S.R.L.", "S.A.", "S.A.", "S.R.L.", "Coop. Ltda."]

REGION_WEIGHTS = {"AMBA": 34, "Centro": 26, "Cuyo": 14, "Norte": 13, "Patagonia": 13}
# industries more common in some regions
REGION_INDUSTRY_BOOST = {
    "Patagonia": {"Oil & Gas": 4, "Mining": 2},
    "Cuyo": {"Mining": 3, "Food & Beverage": 2, "Agriculture": 2},
    "Norte": {"Mining": 3, "Agriculture": 3},
    "Centro": {"Agriculture": 3, "Manufacturing": 2, "Food & Beverage": 2},
    "AMBA": {"Manufacturing": 3, "Construction": 2, "Food & Beverage": 2, "Water Utilities": 2},
}

N_CUSTOMERS = 120


def weighted_choice(d):
    keys = list(d)
    return random.choices(keys, weights=[d[k] for k in keys])[0]


customers = []  # dicts
used_names = set()
for cid in range(1, N_CUSTOMERS + 1):
    region = weighted_choice(REGION_WEIGHTS)
    ind_w = {i: 1 for i in INDUSTRIES}
    for i, b in REGION_INDUSTRY_BOOST[region].items():
        ind_w[i] += b
    industry = weighted_choice(ind_w)
    while True:
        base = f"{random.choice(NAME_B[industry])} {random.choice(NAME_A)}"
        if base not in used_names:          # unique company name, ignoring legal suffix
            used_names.add(base)
            name = f"{base} {random.choice(SUFFIX)}"
            break
    # Customer "size": heavy-tailed so a few customers dominate revenue
    size = random.paretovariate(1.35)
    size = min(size, 12)
    # most customers already existed; the rest are acquired over time
    if random.random() < 0.55:
        created = rand_date(date(2019, 1, 1), date(2022, 12, 31))
    else:
        created = rand_date(date(2023, 1, 1), date(2026, 3, 31))
    customers.append(dict(
        customer_id=cid, name=name, industry=industry, region=region,
        created=created, size=size, churn_date=None, hoarder=False,
    ))

# Churn: some established mid/large customers stop buying in 2025
established = [c for c in customers if c["created"] < date(2023, 1, 1) and 1.6 < c["size"] < 6]
for c in random.sample(established, 9):
    c["churn_date"] = rand_date(date(2024, 12, 1), date(2025, 7, 31))

# Quote hoarders: request lots of quotes, rarely buy
candidates = [c for c in customers if c["churn_date"] is None and c["created"] < date(2024, 1, 1)]
for c in random.sample(candidates, 5):
    c["hoarder"] = True
    c["size"] = random.uniform(2.0, 3.5)   # mid-sized, not a key account

# ------------------------------------------------------------------
# Quotes, quote items, orders, order items
# ------------------------------------------------------------------
quotes, quote_items, orders, order_items = [], [], [], []
qid, oid = 1, 1

total_size = sum(c["size"] for c in customers)
BASE_QUOTES_PER_MONTH = 105  # company-wide, before season/growth


def list_price_on(pid, d):
    base = PROD[pid][4]
    return base * (1 + PRICE_INCREASE) if d >= PRICE_INCREASE_DATE else base


def pick_rep(region, d):
    reps = [r for r in REP_BY_REGION[region] if r[3] <= d]
    # the new Centro rep gets more of the new accounts over time
    return random.choice(reps)


def pick_products(industry, d):
    mix = dict(INDUSTRY_MIX[industry])
    if "Solar Pumping" in mix:
        if d < date(2024, 7, 1):
            del mix["Solar Pumping"]
        else:
            # adoption ramps up over ~18 months after launch
            months = (d.year - 2024) * 12 + d.month - 7
            mix["Solar Pumping"] *= clamp(0.25 + months / 18, 0.25, 1.4)
    n_lines = random.choices([1, 2, 3, 4], weights=[40, 32, 18, 10])[0]
    chosen = []
    for _ in range(n_lines):
        cat = weighted_choice(mix)
        prods = [p for p in PRODUCTS if p[2] == cat and p[5] <= d]
        pid = random.choice(prods)[0]
        if pid not in chosen:
            chosen.append(pid)
    return chosen


for m in month_iter(START, END):
    season = SEASON[m.month]
    growth = GROWTH[m.year]
    for c in customers:
        if c["created"] > month_end(m):
            continue
        if c["churn_date"] and m > c["churn_date"]:
            continue
        rate = BASE_QUOTES_PER_MONTH * (c["size"] / total_size) * season * growth
        if c["hoarder"]:
            rate *= 2.6
        n = poisson(rate)
        for _ in range(n):
            lo = max(m, c["created"])
            hi = min(month_end(m), END, c["churn_date"] or END)
            if lo > hi:
                continue
            qdate = rand_date(lo, hi)
            rep = pick_rep(c["region"], qdate)
            rep_id, _, _, _, win_bonus, mean_days, disc_style = rep

            # discount: rep style + bigger customers negotiate harder
            discount = clamp(random.gauss(disc_style + 0.012 * math.log(c["size"] + 1), 0.04), 0.0, 0.30)

            lines = []
            for ln, pid in enumerate(pick_products(c["industry"], qdate), start=1):
                lo_q, hi_q = QTY[PROD[pid][2]]
                qty = random.randint(lo_q, hi_q)
                qty = max(1, round(qty * clamp(0.7 + c["size"] / 10, 0.7, 1.9)))
                price = round(list_price_on(pid, qdate) * (1 - discount), 2)
                lines.append((qid, ln, pid, qty, price))

            # win probability
            p = 0.40 + win_bonus + 1.1 * (discount - 0.09)
            if PRICE_INCREASE_DATE <= qdate < date(2025, 9, 1):
                p -= 0.09                          # customers push back on the new prices
            elif qdate >= date(2025, 9, 1):
                p -= 0.03                          # partial recovery
            if c["hoarder"]:
                p *= 0.30
            if any(PROD[l[2]][2] == "Solar Pumping" for l in lines):
                p += 0.06
            p = clamp(p, 0.03, 0.85)

            days = max(2, round(random.lognormvariate(math.log(mean_days), 0.45)))
            decided = qdate + timedelta(days=days)
            if decided > END:
                status, decided_s = "pending", None
            else:
                status = "won" if random.random() < p else "lost"
                decided_s = decided.isoformat()

            quotes.append((qid, c["customer_id"], rep_id, qdate.isoformat(), status, decided_s))
            quote_items.extend(lines)

            if status == "won":
                odate = decided + timedelta(days=random.randint(0, 5))
                if odate > END:
                    odate = END
                orders.append((oid, qid, c["customer_id"], rep_id, odate.isoformat()))
                for (_, ln, pid, qty, price) in lines:
                    order_items.append((oid, ln, pid, qty, price))
                oid += 1
            qid += 1

# ------------------------------------------------------------------
# Data-quality problems (the "old CRM / ERP export" mess)
# ------------------------------------------------------------------
# 1) Duplicate customer records: same company typed twice. Later
#    quotes/orders drift to the duplicate ID.
cust_by_id = {c["customer_id"]: c for c in customers}
orders_per_cust = {}
for o in orders:
    orders_per_cust[o[2]] = orders_per_cust.get(o[2], 0) + 1
dup_sources = sorted(
    [c for c in customers if c["churn_date"] is None and not c["hoarder"]],
    key=lambda c: -orders_per_cust.get(c["customer_id"], 0),
)[3:30]
dup_sources = random.sample(dup_sources, 4)
next_cid = N_CUSTOMERS + 1
dup_map = {}
for c in dup_sources:
    variant = (c["name"].replace("S.A.", "SA").replace("S.R.L.", "SRL")
               if ("S.A." in c["name"] or "S.R.L." in c["name"])
               else c["name"].upper())
    if variant == c["name"]:
        variant = c["name"] + " "
    cutoff = rand_date(date(2024, 3, 1), date(2025, 3, 1))
    dup = dict(c)
    dup.update(customer_id=next_cid, name=variant, created=cutoff)
    customers.append(dup)
    dup_map[c["customer_id"]] = (next_cid, cutoff)
    next_cid += 1

quotes = [
    (q[0], dup_map[q[1]][0], *q[2:])
    if q[1] in dup_map and date.fromisoformat(q[3]) >= dup_map[q[1]][1] and random.random() < 0.7
    else q
    for q in quotes
]
q_cust = {q[0]: q[1] for q in quotes}
orders = [(o[0], o[1], q_cust[o[1]], o[3], o[4]) for o in orders]

# 2) Inconsistent region spellings
REGION_VARIANTS = {
    "AMBA": ["amba", "Buenos Aires (AMBA)", "AMBA "],
    "Centro": ["centro", "CENTRO", "Centro "],
    "Cuyo": ["cuyo", "CUYO"],
    "Norte": ["norte", "NOA", "Norte "],
    "Patagonia": ["patagonia", "PATAGONIA", "Patagonia "],
}
for c in customers:
    if random.random() < 0.16:
        c["region"] = random.choice(REGION_VARIANTS[c["region"]])

# 3) Missing industry
for c in random.sample(customers, 8):
    c["industry"] = None

# 4) Duplicated order lines from the ERP export
for row in random.sample(order_items, 14):
    order_items.append(row)
random.shuffle(order_items)
order_items.sort(key=lambda r: (r[0], r[1]))

# ------------------------------------------------------------------
# Write database + CSVs
# ------------------------------------------------------------------
if DB_PATH.exists():
    DB_PATH.unlink()
con = sqlite3.connect(DB_PATH)
con.executescript((HERE / "schema.sql").read_text(encoding="utf-8"))

tables = {
    "sales_reps": (["rep_id", "rep_name", "region", "hire_date"],
                   [(r[0], r[1], r[2], r[3].isoformat()) for r in REPS]),
    "customers": (["customer_id", "customer_name", "industry", "region", "created_date"],
                  [(c["customer_id"], c["name"], c["industry"], c["region"], c["created"].isoformat())
                   for c in sorted(customers, key=lambda c: c["customer_id"])]),
    "products": (["product_id", "product_name", "category", "standard_cost", "list_price", "launch_date"],
                 [(p[0], p[1], p[2], p[3], p[4], p[5].isoformat()) for p in PRODUCTS]),
    "quotes": (["quote_id", "customer_id", "rep_id", "quote_date", "status", "decided_date"], quotes),
    "quote_items": (["quote_id", "line_no", "product_id", "quantity", "quoted_price"], quote_items),
    "orders": (["order_id", "quote_id", "customer_id", "rep_id", "order_date"], orders),
    "order_items": (["order_id", "line_no", "product_id", "quantity", "unit_price"], order_items),
}

CSV_DIR.mkdir(exist_ok=True)
for name, (cols, rows) in tables.items():
    ph = ",".join("?" * len(cols))
    con.executemany(f"INSERT INTO {name} ({','.join(cols)}) VALUES ({ph})", rows)
    with open(CSV_DIR / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        w.writerows(rows)
con.commit()

for name in tables:
    n = con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
    print(f"{name:<12} {n:>6} rows")
con.close()
print(f"\nWrote {DB_PATH.name} and {len(tables)} CSVs in {CSV_DIR.name}/")
