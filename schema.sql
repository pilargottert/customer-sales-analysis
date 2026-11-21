-- ============================================================
-- Harbor Line Industrial — Quote-to-Order Sales Database
-- Fictional B2B supplier of industrial air & fluid equipment.
-- All company, customer, and rep names are invented.
-- Engine: SQLite (also runs in DuckDB with no changes)
-- Currency: USD. Dates stored as ISO text: 'YYYY-MM-DD'.
-- ============================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS quote_items;
DROP TABLE IF EXISTS quotes;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS sales_reps;

-- ------------------------------------------------------------
-- Sales reps: each covers one region.
-- ------------------------------------------------------------
CREATE TABLE sales_reps (
    rep_id      INTEGER PRIMARY KEY,
    rep_name    TEXT    NOT NULL,
    region      TEXT    NOT NULL,
    hire_date   TEXT    NOT NULL
);

-- ------------------------------------------------------------
-- Customers: industrial clients.
-- NOTE: loaded "as exported from the old CRM" — expect some
-- data-quality issues (this is intentional; clean before use).
-- ------------------------------------------------------------
CREATE TABLE customers (
    customer_id     INTEGER PRIMARY KEY,
    customer_name   TEXT    NOT NULL,
    industry        TEXT,               -- may be NULL
    region          TEXT,               -- free text in the old CRM
    created_date    TEXT    NOT NULL
);

-- ------------------------------------------------------------
-- Products: catalog with cost and list price.
-- list_price is the price as of 2023-01-01; see ANSWER_KEY
-- only if you want spoilers about price changes.
-- ------------------------------------------------------------
CREATE TABLE products (
    product_id      INTEGER PRIMARY KEY,
    product_name    TEXT    NOT NULL,
    category        TEXT    NOT NULL,
    standard_cost   REAL    NOT NULL,   -- unit cost to the company
    list_price      REAL    NOT NULL,   -- unit list price (original)
    launch_date     TEXT    NOT NULL
);

-- ------------------------------------------------------------
-- Quotes: every commercial proposal sent to a customer.
-- status: 'won' | 'lost' | 'pending'
-- decided_date: when the customer accepted/rejected (NULL if pending)
-- ------------------------------------------------------------
CREATE TABLE quotes (
    quote_id        INTEGER PRIMARY KEY,
    customer_id     INTEGER NOT NULL REFERENCES customers(customer_id),
    rep_id          INTEGER NOT NULL REFERENCES sales_reps(rep_id),
    quote_date      TEXT    NOT NULL,
    status          TEXT    NOT NULL CHECK (status IN ('won','lost','pending')),
    decided_date    TEXT
);

-- ------------------------------------------------------------
-- Quote line items: what was offered, at what price.
-- ------------------------------------------------------------
CREATE TABLE quote_items (
    quote_id        INTEGER NOT NULL REFERENCES quotes(quote_id),
    line_no         INTEGER NOT NULL,
    product_id      INTEGER NOT NULL REFERENCES products(product_id),
    quantity        INTEGER NOT NULL,
    quoted_price    REAL    NOT NULL,   -- unit price offered (after discount)
    PRIMARY KEY (quote_id, line_no)
);

-- ------------------------------------------------------------
-- Orders: created when a quote is won.
-- ------------------------------------------------------------
CREATE TABLE orders (
    order_id        INTEGER PRIMARY KEY,
    quote_id        INTEGER NOT NULL REFERENCES quotes(quote_id),
    customer_id     INTEGER NOT NULL REFERENCES customers(customer_id),
    rep_id          INTEGER NOT NULL REFERENCES sales_reps(rep_id),
    order_date      TEXT    NOT NULL
);

-- ------------------------------------------------------------
-- Order line items: what was actually sold.
-- NOTE: no primary key here on purpose — the ERP export this
-- came from occasionally duplicated lines. Check for that.
-- ------------------------------------------------------------
CREATE TABLE order_items (
    order_id        INTEGER NOT NULL REFERENCES orders(order_id),
    line_no         INTEGER NOT NULL,
    product_id      INTEGER NOT NULL REFERENCES products(product_id),
    quantity        INTEGER NOT NULL,
    unit_price      REAL    NOT NULL
);

CREATE INDEX idx_quotes_customer  ON quotes(customer_id);
CREATE INDEX idx_quotes_date      ON quotes(quote_date);
CREATE INDEX idx_orders_customer  ON orders(customer_id);
CREATE INDEX idx_orders_date      ON orders(order_date);
CREATE INDEX idx_oi_order         ON order_items(order_id);
CREATE INDEX idx_qi_quote         ON quote_items(quote_id);
