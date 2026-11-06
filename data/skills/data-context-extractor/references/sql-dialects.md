# SQL Dialect Reference

Include the appropriate section in generated skills based on the user's data warehouse.

---

## BigQuery

```markdown
## SQL Dialect: BigQuery

- **Table references**: Use backticks: \`project.dataset.table\`
- **Safe division**: `SAFE_DIVIDE(a, b)` returns NULL instead of error
- **Date functions**:
  - `DATE_TRUNC(date_col, MONTH)`
  - `DATE_SUB(date_col, INTERVAL 1 DAY)`
  - `DATE_DIFF(end_date, start_date, DAY)`
- **Column exclusion**: `SELECT * EXCEPT(column_to_exclude)`
- **Arrays**: `UNNEST(array_column)` to flatten
- **Structs**: Access with dot notation `struct_col.field_name`
- **Timestamps**: `TIMESTAMP_TRUNC()`, times in UTC by default
- **String matching**: `LIKE`, `REGEXP_CONTAINS(col, r'pattern')`
- **NULLs in aggregations**: Most functions ignore NULLs; use `IFNULL()` or `COALESCE()`
```

---

## Snowflake

```markdown
## SQL Dialect: Snowflake

- **Table references**: `DATABASE.SCHEMA.TABLE` or with quotes for case-sensitive: `"Column_Name"`
- **Safe division**: `DIV0(a, b)` returns 0, `DIV0NULL(a, b)` returns NULL
- **Date functions**:
  - `DATE_TRUNC('MONTH', date_col)`
  - `DATEADD(DAY, -1, date_col)`
  - `DATEDIFF(DAY, start_date, end_date)`
- **Column exclusion**: `SELECT * EXCLUDE (column_to_exclude)`
- **Arrays**: `FLATTEN(array_column)` to flatten, access with `value`
- **Variants/JSON**: Access with colon notation `variant_col:field_name`
- **Timestamps**: `TIMESTAMP_NTZ` (no timezone), `TIMESTAMP_TZ` (with timezone)
- **String matching**: `LIKE`, `REGEXP_LIKE(col, 'pattern')`
- **Case sensitivity**: Identifiers are uppercase by default unless quoted
```

---

## PostgreSQL / Redshift

```markdown
## SQL Dialect: PostgreSQL/Redshift

- **Table references**: `schema.table` (lowercase convention)
- **Safe division**: `NULLIF(b, 0)` pattern: `a / NULLIF(b, 0)`
- **Date functions**:
  - `DATE_TRUNC('month', date_col)`
  - `date_col - INTERVAL '1 day'`
  - `DATE_PART('day', end_date - start_date)`
- **Column selection**: No EXCEPT; must list columns explicitly
- **Arrays**: `UNNEST(array_column)` (PostgreSQL), limited in Redshift
- **JSON**: `json_col->>'field_name'` for text, `json_col->'field_name'` for JSON
- **Timestamps**: `AT TIME ZONE 'UTC'` for timezone conversion
- **String matching**: `LIKE`, `col ~ 'pattern'` for regex
- **Boolean**: Native BOOLEAN type; use `TRUE`/`FALSE`
```

---

## Databricks / Spark SQL

```markdown
## SQL Dialect: Databricks/Spark SQL

- **Table references**: `catalog.schema.table` (Unity Catalog) or `schema.table`
- **Safe division**: Use `NULLIF`: `a / NULLIF(b, 0)` or `TRY_DIVIDE(a, b)`
- **Date functions**:
  - `DATE_TRUNC('MONTH', date_col)`
  - `DATE_SUB(date_col, 1)`
  - `DATEDIFF(end_date, start_date)`
- **Column exclusion**: `SELECT * EXCEPT (column_to_exclude)` (Databricks SQL)
- **Arrays**: `EXPLODE(array_column)` to flatten
- **Structs**: Access with dot notation `struct_col.field_name`
- **JSON**: `json_col:field_name` or `GET_JSON_OBJECT()`
- **String matching**: `LIKE`, `RLIKE` for regex
- **Delta features**: `DESCRIBE HISTORY`, time travel with `VERSION AS OF`
```

---

## MySQL

```markdown
## SQL Dialect: MySQL

- **Table references**: \`database\`.\`table\` with backticks
- **Safe division**: Manual: `IF(b = 0, NULL, a / b)` or `a / NULLIF(b, 0)`
- **Date functions**:
  - `DATE_FORMAT(date_col, '%Y-%m-01')` for truncation
  - `DATE_SUB(date_col, INTERVAL 1 DAY)`
  - `DATEDIFF(end_date, start_date)`
- **Column selection**: No EXCEPT; must list columns explicitly
- **Arrays**: Limited native support; often stored as JSON
- **JSON**: `JSON_EXTRACT(col, '$.field')` or `col->>'$.field'`
- **Timestamps**: `CONVERT_TZ()` for timezone conversion
- **String matching**: `LIKE`, `REGEXP` for regex
- **Case sensitivity**: Table names case-sensitive on Linux, not on Windows
```

---

## SQL Server / T-SQL

Also applies to Azure SQL Database and SQL Server Express. The outer fence uses four backticks because the section contains a nested SQL block.

````markdown
## SQL Dialect: SQL Server (T-SQL)

- **Table references**: `schema.table` (`dbo.sales`) or `database.schema.table`; `[brackets]` for names with spaces or reserved words
- **Row limit**: `SELECT TOP 10 ... ORDER BY ...` (there is no `LIMIT`). For paging: `ORDER BY ... OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY`. `TOP` without `ORDER BY` returns arbitrary rows
- **Safe division**: `a / NULLIF(b, 0)`. Integer / integer truncates (`7 / 2 = 3`): cast first, `CAST(a AS decimal(18,4)) / NULLIF(b, 0)`
- **Date functions**:
  - Month key `'YYYY-MM'`: `CONVERT(char(7), date_col, 120)` (style 120 = `yyyy-mm-dd hh:mi:ss`; works on every version)
  - First day of month: `DATEFROMPARTS(YEAR(d), MONTH(d), 1)`; `DATETRUNC(month, d)` only on SQL Server 2022+
  - Last day of month: `EOMONTH(d)`
  - Add/subtract: `DATEADD(day, -1, d)`, `DATEADD(month, -3, d)`
  - Difference: `DATEDIFF(day, start_date, end_date)` (counts boundaries crossed, not whole periods)
  - Today: `CAST(GETDATE() AS date)`; now: `GETDATE()` or `SYSDATETIME()`
- **Date ranges**: half-open ranges keep the whole last day even on `datetime` columns: `WHERE d >= @start AND d < DATEADD(day, 1, @end)`. Avoid `BETWEEN` with datetimes and avoid wrapping the column in a function in `WHERE` (not sargable)
- **Anti-joins**: use `NOT EXISTS (SELECT 1 FROM t2 WHERE t2.k = t1.k)`. `NOT IN (subquery)` returns **no rows at all** if the subquery yields a single NULL (`1 NOT IN (2, NULL)` is not true). `NOT IN` with a literal list is safe
- **Subtotals and grand totals**: `GROUP BY ROLLUP(col)` adds a total row with `col` = NULL; `GROUPING(col) = 1` tells it apart from a real NULL. `GROUPING SETS` and `CUBE` for other combinations
- **NULL handling**: `ISNULL(x, 0)` (two arguments, result takes the type of the first) or ANSI `COALESCE(...)`. `'a' + NULL` is NULL; `CONCAT()` treats NULL as `''`
- **Variables**: `DECLARE @start date = '2026-01-01';` must run in the same batch as the query (`GO` ends the batch)
- **Column exclusion**: no `EXCEPT`/`EXCLUDE`; list columns explicitly
- **String matching**: `LIKE` with `%`, `_` and character classes (`[0-9]`, `[^0]`); `PATINDEX('%[^0]%', s)` finds the first non-zero character. Regex (`REGEXP_LIKE`) only on SQL Server 2025+ / Azure SQL
- **Case sensitivity**: depends on the collation. The common default `SQL_Latin1_General_CP1_CI_AS` is case-insensitive and accent-sensitive; override per comparison with `COLLATE Latin1_General_CS_AS`. Trailing spaces are ignored in `=` comparisons
- **String aggregation**: `STRING_AGG(col, ', ')` (2017+)
- **Data changes (safe pattern)**: wrap them in a transaction and check `@@ROWCOUNT` right after the statement (any later statement resets it):
  ```sql
  SET XACT_ABORT ON;
  BEGIN TRAN;
      UPDATE dbo.costs SET total_cost = @new_cost WHERE cost_id = @cost_id;
      IF @@ROWCOUNT <> 1
      BEGIN
          ROLLBACK TRAN;
          THROW 50001, 'Expected exactly 1 row; rolled back.', 1;
      END
  COMMIT TRAN;
  ```
  Add `OUTPUT deleted.*, inserted.*` to the `UPDATE` to log the before/after values
- **Metadata**: `INFORMATION_SCHEMA.TABLES` / `INFORMATION_SCHEMA.COLUMNS`; indexes and computed columns in `sys.indexes` and `sys.computed_columns`
- **CLI**: `sqlcmd -S server\instance -E -d database -Q "query"`; recent ODBC drivers need `-C` to trust a self-signed server certificate
````

---

## Common Patterns Across Dialects

| Operation | BigQuery | Snowflake | PostgreSQL | Databricks | SQL Server |
|-----------|----------|-----------|------------|------------|------------|
| Current date | `CURRENT_DATE()` | `CURRENT_DATE()` | `CURRENT_DATE` | `CURRENT_DATE()` | `CAST(GETDATE() AS date)` |
| Current timestamp | `CURRENT_TIMESTAMP()` | `CURRENT_TIMESTAMP()` | `NOW()` | `CURRENT_TIMESTAMP()` | `GETDATE()` / `SYSDATETIME()` |
| String concat | `CONCAT()` or `\|\|` | `CONCAT()` or `\|\|` | `CONCAT()` or `\|\|` | `CONCAT()` or `\|\|` | `CONCAT()` or `+` |
| Coalesce | `COALESCE()` | `COALESCE()` | `COALESCE()` | `COALESCE()` | `COALESCE()` / `ISNULL()` |
| Case when | `CASE WHEN` | `CASE WHEN` | `CASE WHEN` | `CASE WHEN` | `CASE WHEN` / `IIF()` |
| Count distinct | `COUNT(DISTINCT x)` | `COUNT(DISTINCT x)` | `COUNT(DISTINCT x)` | `COUNT(DISTINCT x)` | `COUNT(DISTINCT x)` |
| Limit rows | `LIMIT n` | `LIMIT n` | `LIMIT n` | `LIMIT n` | `TOP n` |
