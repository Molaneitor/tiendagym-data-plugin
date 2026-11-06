# Connectors

## How tool references work

Plugin files use `~~category` as a placeholder for whatever tool the user connects in that category. For example, `~~data warehouse` might mean Snowflake, BigQuery, or any other warehouse with an MCP server.

Plugins are **tool-agnostic** — they describe workflows in terms of categories (data warehouse, notebook, product analytics, etc.) rather than specific products. The `.mcp.json` pre-configures specific MCP servers, but any MCP server in that category works.

## Connectors for this fork

This fork ships **no MCP connectors**: `.mcp.json` is empty. The upstream plugin pre-configures Snowflake, Databricks, BigQuery, Hex, Amplitude, Amplitude EU, Atlassian and Definite; this project uses none of them.

| Category | Placeholder | In this project | How Claude reaches it |
|----------|-------------|-----------------|-----------------------|
| Data warehouse | `~~data warehouse` | SQL Server Express (T-SQL), database `TiendaGymBI` | No MCP server: Claude runs read-only queries with `sqlcmd` or Python + `pyodbc` |
| Notebook | `~~notebook` | — | Not used |
| Product analytics | `~~product analytics` | — | Not used |
| Project tracker | `~~project tracker` | — | Not used |

To connect one of these tools, add its MCP server to `.mcp.json` (the upstream repository has the original entries).
