# TiendaGymBI data plugin

A customized fork of Anthropic's [`data` plugin](https://github.com/anthropics/knowledge-work-plugins/tree/main/data) for Claude, built for a real BI project: the sales, cost and inventory pipeline of a gym-equipment store.

The generic plugin knows SQL. It does not know that this store's "revenue" lives in three different columns, that an old invoice type disappeared mid-year, or that some product codes are inventory adjustments that only count as invalid in certain months. This fork writes that tribal knowledge down as a **data context skill**, so that Claude answers business questions the way the analyst would, with the right numbers the first time.

> All data in this repository is **synthetic**. Product codes, invoices, customers, dates and amounts are made up; the rules and gotchas are the real ones from the project.

## The project

```
DreamSoft (billing/ERP, monthly manual export)
   -> Excel reports: fac0240 (sales lines), inv0101 (inventory ledger), inv0260 (monthly stock), fac0533 (daily totals)
   -> Python loaders (one script per report, orchestrated by a monthly close script)
   -> SQL Server Express (T-SQL), database TiendaGymBI
   -> Power BI dashboard (sales, products, customers, costs)
```

Every month the analyst loads the new month, validates it against the ERP's own totals and refreshes the dashboard. The store owner reads the dashboard and asks follow-up questions; most of them are about **sales vs. target**, **gross margin** and **top products and customers**.

## Before and after

Both examples run against the synthetic data in [`sample-data/`](sample-data/). The SQL and the results are copied from real runs.

### "What was our gross margin by month?"

**Before: generic plugin (schema only).** With nothing but table and column names, the plugin has to guess what "revenue" and "cost of goods sold" mean. A reasonable schema-only answer looks like this, and it is not a strawman: the project's first Power BI model used exactly this logic until the rules were written down.

```sql
WITH revenue AS (
    SELECT FORMAT(FechaDocumento, 'yyyy-MM') AS month, SUM(PrecioTotal) AS revenue
    FROM dbo.VENTAS
    GROUP BY FORMAT(FechaDocumento, 'yyyy-MM')
), cogs AS (
    SELECT FORMAT(FechaDocumento, 'yyyy-MM') AS month, SUM(CostoTotal) AS cogs
    FROM dbo.COSTOS
    WHERE TipoDocumento = '880'          -- "880 is the sales invoice type"
    GROUP BY FORMAT(FechaDocumento, 'yyyy-MM')
)
SELECT r.month, r.revenue, c.cogs,
       r.revenue - ISNULL(c.cogs, 0) AS gross_margin,
       CAST((r.revenue - ISNULL(c.cogs, 0)) / NULLIF(r.revenue, 0) AS decimal(9,4)) AS gross_margin_pct
FROM revenue r
LEFT JOIN cogs c ON c.month = r.month
ORDER BY r.month;
```

| month | revenue | cogs | gross margin | margin % |
|---|---:|---:|---:|---:|
| 2025-01 | 5,500,000 | NULL | 5,500,000 | **100.0 %** |
| 2025-02 | 8,500,000 | 6,050,000 | 2,450,000 | 28.8 % |
| 2025-03 | 8,700,000 | 6,240,000 | 2,460,000 | 28.3 % |

Three silent errors:
- **January has no cost at all.** January sales used the old invoice type `882`; filtering costs by `TipoDocumento = '880'` drops them. Sales costs must be filtered by movement type (`TipoMovimiento = 'V'`).
- **February includes an inventory adjustment** (`AJ-01`, marked "NO VALIDO" in that month's stock report): $3,000,000 of fake revenue and $2,950,000 of fake cost.
- **March revenue ignores a $400,000 discount.** `PrecioTotal` is the line value *before* discount; the net value is `NetoDocumento`.

**After: with the `tiendagym-data-analyst` skill.** Claude uses query 11.2 from the skill:

```sql
WITH nv AS (   -- codes marked NO VALIDO in each month's stock report (ES-01 is a known false positive)
    SELECT DISTINCT CodigoProducto, Periodo FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
), vtas AS (
    SELECT v.*, CONVERT(char(7), v.FechaDocumento, 120) AS periodo
    FROM dbo.VENTAS v
    WHERE v.Producto NOT LIKE '%NO VALIDO%'
      AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                      AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120))
), v AS (
    SELECT periodo, SUM(NetoDocumento) AS ventas_netas FROM vtas GROUP BY periodo
), c AS (
    SELECT CONVERT(char(7), c.FechaDocumento, 120) AS periodo, SUM(c.CostoTotal) AS costo
    FROM dbo.COSTOS c
    WHERE c.TipoMovimiento = 'V'
      AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = c.CodigoProducto
                      AND nv.Periodo = CONVERT(char(7), c.FechaDocumento, 120))
      AND NOT EXISTS (SELECT 1 FROM dbo.VENTAS x WHERE x.NumeroDocumento = c.NumeroDocumento
                      AND x.CodigoProducto = c.CodigoProducto AND x.Producto LIKE '%NO VALIDO%')
    GROUP BY CONVERT(char(7), c.FechaDocumento, 120)
)
SELECT COALESCE(v.periodo, c.periodo) AS periodo, v.ventas_netas, c.costo,
       v.ventas_netas - c.costo AS margen_bruto,
       CAST((v.ventas_netas - c.costo) / NULLIF(v.ventas_netas, 0) AS decimal(9,4)) AS margen_pct,
       CASE WHEN c.costo > v.ventas_netas THEN 'ALERTA' ELSE 'OK' END AS alerta
FROM v FULL OUTER JOIN c ON c.periodo = v.periodo
ORDER BY periodo;
```

| periodo | net sales (ex. VAT) | COGS | gross margin | margin % | alert |
|---|---:|---:|---:|---:|---|
| 2025-01 | 5,500,000 | 3,920,000 | 1,580,000 | **28.7 %** | OK |
| 2025-02 | 5,500,000 | 3,100,000 | 2,400,000 | **43.6 %** | OK |
| 2025-03 | 8,300,000 | 6,240,000 | 2,060,000 | **24.8 %** | OK |

Because the skill also documents the known oddities, Claude can flag them instead of letting them surprise the reader: *February's margin is overstated: invoice F-1005 sold 10 units of `DS-10` at $0 cost (negative stock in the ERP, see query 11.14). Fix the cost with purchase evidence before reporting it.*

### "How much did we sell in February?"

**Before:** `SELECT SUM(ValorFinal) FROM dbo.VENTAS WHERE FechaDocumento >= '2025-02-01' AND FechaDocumento < '2025-03-01'` → **10,115,000**. A single number, VAT included without saying so, and inflated by the inventory adjustment.

**After:** the skill tells Claude to always give both figures and compare against the monthly target:

| sales incl. VAT | sales ex. VAT | invoices | target (incl. VAT) | attainment |
|---:|---:|---:|---:|---:|
| 6,545,000 | 5,500,000 | 2 | 8,000,000 | 81.8 % |

*The inventory adjustment `AJ-01` ($3,570,000 incl. VAT) is excluded because February's stock report marks it as NO VALIDO.*

## What the context skill encodes

[`data/skills/tiendagym-data-analyst/`](data/skills/tiendagym-data-analyst/SKILL.md), generated with the plugin's own `data-context-extractor` (bootstrap mode) and verified against the database:

- **Three value columns per sales line**: `PrecioTotal` (before discount), `NetoDocumento` (after discount, ex. VAT), `ValorFinal` (incl. 19 % VAT). Margin and ERP validation use `NetoDocumento`; the dashboard and the target use `ValorFinal`.
- **"NO VALIDO" is monthly**: a product code is excluded only in the months where that month's stock report marks it, with an exception list for codes marked by mistake.
- **Sales costs come from `TipoMovimiento = 'V'`**, never from an invoice type, because the invoice type changed mid-history (`882` → `880`).
- **Leading zeros matter**: `0123456` and `123456` are different products. Never cast codes to numbers (and don't open the CSVs in Excel without importing that column as text).
- **Join keys are not unique**: a product can appear on several lines of one invoice but in a single inventory movement, so both sides are aggregated to `TipoDocumento + NumeroDocumento + CodigoProducto` before joining.
- **The monthly stock report omits products that end the month at zero**: only the closing value is reliable; inflows and outflows come from the ledger.
- **Validation**: the daily ERP totals are compared with `NetoDocumento` (month first, then day), aggregating sales per day before a `FULL OUTER JOIN`, and *without* excluding NO VALIDO codes, because the ERP counts them.
- **Safe changes**: SELECT freely; any UPDATE/DELETE needs two sources of evidence, the user's OK, and a transaction that checks `@@ROWCOUNT`.
- 17 tested T-SQL queries (monthly close, margin, customers, inventory, data quality).

The fork also adds a **SQL Server / T-SQL section** to the extractor's dialect guide ([`sql-dialects.md`](data/skills/data-context-extractor/references/sql-dialects.md)): `TOP`, `CONVERT(char(7), date, 120)`, `DATEADD`, `NOT EXISTS` instead of `NOT IN`, `GROUP BY ROLLUP` and transactions with `@@ROWCOUNT`.

## Repository layout

```
.
├── README.md                      this file
├── data/                          the plugin (fork of anthropics/knowledge-work-plugins/data)
│   ├── .claude-plugin/plugin.json
│   ├── .mcp.json                  empty: no MCP connectors
│   ├── CONNECTORS.md
│   └── skills/
│       ├── tiendagym-data-analyst/            NEW: data context skill (Spanish, like the database)
│       ├── data-context-extractor/            + SQL Server / T-SQL dialect
│       └── analyze, write-query, explore-data, ... (unchanged)
└── sample-data/                   synthetic CSVs with the production schema + schema.sql
```

The skill is written in Spanish because the business, the database and the people asking the questions are Spanish-speaking.

## Try it

You need SQL Server 2017 or later (Express is fine) and Claude Code.

1. Create the database and the tables, then load the CSVs (`schema.sql` ends with the `BULK INSERT` statements; pass the full path of `sample-data` as a variable):

   ```bash
   sqlcmd -S "<server>\<instance>" -E -C -Q "CREATE DATABASE TiendaGymBI"
   sqlcmd -S "<server>\<instance>" -E -C -d TiendaGymBI -i sample-data/schema.sql -v SampleDir="<full path to sample-data>"
   ```

2. Start Claude Code with the plugin and ask a question:

   ```bash
   claude --plugin-dir ./data
   ```

   ```
   /data:analyze ¿Cuál fue el margen bruto por mes?
   ```

The sample data contains every trap described above: the `882` → `880` switch, a discount, a monthly NO VALIDO code (`AJ-01`), a false positive (`ES-01`), a pair of codes with and without a leading zero, a sale without cost (`FL-01`, a freight charge), a sale at $0 cost (`DS-10`), a product split across two lines of one invoice (`MC-20`), a returned invoice that only shows up in the ERP's daily totals (`F-1009`) and a product that never sells (`BC-01`).

## Privacy

The real context file (with real figures, invoice numbers and closed cases) and the private version of the skill stay out of this repository through `.gitignore`. No connection strings, credentials, personal paths or real names are included.

## Changes from upstream

Based on `data` v1.1.0 from [anthropics/knowledge-work-plugins](https://github.com/anthropics/knowledge-work-plugins), licensed under the Apache License 2.0 ([`data/LICENSE`](data/LICENSE)). Modified or added files:

- `data/skills/tiendagym-data-analyst/` (added): data context skill for this project.
- `data/skills/data-context-extractor/references/sql-dialects.md` (modified): SQL Server / T-SQL section and SQL Server column in the cross-dialect table.
- `data/skills/data-context-extractor/SKILL.md` (modified): SQL Server listed as a warehouse option, with schema exploration queries.
- `data/.mcp.json` (modified): all MCP connectors removed (Snowflake, Databricks, BigQuery, Hex, Amplitude, Amplitude EU, Atlassian, Definite).
- `data/CONNECTORS.md`, `data/README.md`, `data/.claude-plugin/plugin.json` (modified): describe the fork.
- `sample-data/` and this README (added).

All other files are unchanged.
