---
name: tiendagym-data-analyst
description: "Contexto de datos de TiendaGymBI para consultar SQL Server (T-SQL, base TiendaGymBI): tablas de ventas, costos e inventario, métricas oficiales y trampas conocidas. Usar al analizar datos de TiendaGymBI para: (1) ventas del mes contra la meta (con y sin IVA), (2) margen bruto mensual o por producto, (3) top de productos y clientes, o cualquier consulta sobre dbo.VENTAS, dbo.COSTOS o dbo.COSTOS_SALDO_MENSUAL que necesite las reglas de la tienda (NO VALIDO por mes, NetoDocumento, TipoMovimiento = 'V', ceros iniciales en los códigos)."
---

# TiendaGymBI – Análisis de datos

Tienda de equipos de gimnasio (máquinas, pesas, accesorios). Ventas, costos e inventario salen del sistema de facturación DreamSoft (exportación mensual a Excel), se cargan con Python a SQL Server y se publican en un dashboard de Power BI. Moneda: COP. IVA: 19 %. Periodo estándar: mes calendario (`'AAAA-MM'`).

> **Versión pública.** Todos los códigos, facturas, clientes, fechas y montos de esta skill son sintéticos y coinciden con los CSV de `sample-data/` del repositorio. Las reglas y las trampas son las reales del proyecto.

## Cómo trabajar

- Base `TiendaGymBI`, esquema `dbo`, SQL Server (Express). Sin conector MCP: consultar con `sqlcmd -S "<servidor>\<instancia>" -E -C -d TiendaGymBI -W -s "|" -Q "..."` (`-C` confía en el certificado del servidor) o con Python + pyodbc. En Windows usar `py` si `python` abre la Microsoft Store.
- **Solo SELECT de forma autónoma.** DELETE/UPDATE/INSERT nunca sin evidencia de 2 fuentes y el OK del usuario, dentro de una transacción con `@@ROWCOUNT` (plantilla 11.12 en `references/consultas.md`).
- **Quién lee:** el dueño de la tienda (decide compras y precios, mira Power BI) y el analista. Responder primero con la cifra, la comparación y una línea de interpretación; el SQL va después o a pedido.
- **"¿Cuánto vendimos?" → dar siempre las dos cifras:** con IVA (`Total Ventas`, la del dashboard y la meta) y sin IVA (`Ventas sin IVA`, la base del margen). Decir cuál es cuál.
- Preguntas más frecuentes: (1) ventas del mes contra la meta y contra meses anteriores, (2) margen mensual, (3) top productos y clientes. Tienen consulta lista abajo.
- Los datos llegan **por cierre mensual**: el mes en curso no está en la base. Revisar la frescura antes de responder sobre "este mes".

---

## SQL Dialect: SQL Server (T-SQL)

- **Referencias**: `dbo.VENTAS` (esquema.tabla). Corchetes solo para nombres con espacios o reservados.
- **Límite de filas**: `SELECT TOP 10 ... ORDER BY ...` (no existe `LIMIT`).
- **División segura**: `a / NULLIF(b, 0)`. Entero / entero trunca (`7 / 2 = 3`); los valores de esta base son `decimal(18,2)`, así que no aplica salvo con `COUNT`.
- **Periodo**: `CONVERT(char(7), FechaDocumento, 120)` → `'2025-03'`, el mismo formato de `COSTOS_SALDO_MENSUAL.Periodo`. `DATETRUNC(month, d)` y `EOMONTH(d)` también existen (SQL Server 2022+).
- **Rangos de fecha**: `WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)`. `FechaDocumento` es `date` (sin hora) en VENTAS, COSTOS y VENTAS_VALIDACION_DIARIA; el patrón semiabierto sirve igual si algún día pasa a `datetime`.
- **Antijoin**: `NOT EXISTS`, nunca `NOT IN (subconsulta)` (un solo NULL deja el resultado vacío). `NOT IN ('ES-01')` con lista literal sí es seguro.
- **Totales**: `GROUP BY ROLLUP(col)` agrega la fila de total con `col` en NULL (así se lee el total del mes en la validación).
- **NULL**: `ISNULL(x, 0)` o `COALESCE`. `'a' + NULL` es NULL; usar `CONCAT` si alguna parte puede ser NULL.
- **Variables**: `DECLARE @ini date = '2025-03-01';` en el mismo lote que la consulta.
- **Texto**: con la collation por defecto (`SQL_Latin1_General_CP1_CI_AS`) `LIKE '%NO VALIDO%'` no distingue mayúsculas y los espacios finales se ignoran en `=`. `PATINDEX('%[^0]%', s)` ubica el primer carácter distinto de cero.
- **Cambios de datos**: `SET XACT_ABORT ON; BEGIN TRAN; ... IF @@ROWCOUNT <> 1 BEGIN ROLLBACK TRAN; THROW ...; END COMMIT TRAN;` revisando `@@ROWCOUNT` justo después del UPDATE/DELETE.

---

## Desambiguación de entidades

**"Venta" puede significar:**
- **Línea**: una fila de `dbo.VENTAS` (un producto dentro de una factura; `IdVenta`).
- **Factura**: `TipoDocumento + NumeroDocumento` (ej. `880` + `F-1005`). Un producto puede ir en varias líneas de la misma factura.
- **Valor**: con IVA (`ValorFinal`), sin IVA (`NetoDocumento`) o antes del descuento (`PrecioTotal`). Preguntar o dar las dos primeras.

**"Cliente"**: `VENTAS.CodigoCliente` (cédula o NIT); `Cliente` es el nombre. La tabla `CLIENTES` está vacía: el cliente solo existe en VENTAS. Una factura a nombre de un empleado **no es un cliente**: es un ajuste de inventario.

**"Vendedor" / "asesor"**: `VENTAS.CodigoVendedor`, `Vendedor`. La tabla `ASESORES` está vacía.

**"Producto"**: `CodigoProducto` (texto, comparar exacto). Nombre: `PRODUCTOS.NombreProducto` (maestro, nunca trae la marca NO VALIDO) o `VENTAS.Producto` / `COSTOS_SALDO_MENSUAL.Producto` (nombre en el documento, sí puede traerla). **0123456 y 123456 son productos distintos.**

**"Costo"**: costo de lo vendido = `COSTOS` con `TipoMovimiento = 'V'`. No confundir con compras (`TipoDocumento IN ('830','825','833')`) ni con el valor del inventario (`COSTOS_SALDO_MENSUAL.FinalPesos`).

**Relaciones** (no hay llaves foráneas declaradas):
- VENTAS → PRODUCTOS: muchos a uno por `CodigoProducto` exacto (puede haber ventas sin ficha).
- VENTAS ↔ COSTOS (ventas): `TipoDocumento + NumeroDocumento + CodigoProducto`, **agregando cada lado antes de unir**.
- VENTAS ↔ VENTAS_VALIDACION_DIARIA: por fecha, **agrupando VENTAS por día antes de unir**, con `FULL OUTER JOIN`.
- VENTAS/COSTOS ↔ COSTOS_SALDO_MENSUAL: `CodigoProducto` + `CONVERT(char(7), FechaDocumento, 120) = Periodo` (marca NO VALIDO del mes).

---

## Terminología del negocio

| Término | Significado | Notas |
|---|---|---|
| DreamSoft | Sistema de facturación e inventario | Fuente de todos los datos |
| fac0240, fac0533, fac0510, inv0101, inv0260 | Reportes de DreamSoft | fac0240 → VENTAS; inv0101 → COSTOS; inv0260 → COSTOS_SALDO_MENSUAL; fac0533 → VENTAS_VALIDACION_DIARIA; fac0510 solo para cuadrar |
| Kardex | Movimientos de inventario con costo | `dbo.COSTOS` |
| NO VALIDO | Código de ajuste de inventario o precio: no es venta ni costo | Vale **por mes** (marca del inv0260). En los datos de ejemplo: `AJ-01` en 2025-02 |
| Excepción NO VALIDO | Producto real marcado NO VALIDO por error en el inv0260 | Siempre cuenta. En los datos de ejemplo: `ES-01` (marcado en 2025-03) |
| Ajuste de inventario | Factura a nombre de un empleado para cuadrar cantidades | No es venta; se borra (con evidencia y OK) |
| 880 / 882 | Factura de venta actual / anterior (882 se dejó de usar por un cambio en el sistema) | Filtrar ventas en COSTOS por `TipoMovimiento = 'V'`, no por tipo. En los datos de ejemplo, enero 2025 es 882 |
| 893 | Nota crédito: devoluciones reales **y** correcciones de costo, mezcladas | En COSTOS entra como `TipoMovimiento = 'E'` |
| 830, 825, 833 | Documentos de compra | Base de `Costo Compras` |
| 800, 835, 850 | Otros movimientos de inventario (800 entrada; 835 y 850 salidas) | Sin documentar; no entran en ventas ni compras |
| Cierre | Carga y validación de un mes contra DreamSoft | Se hace en los primeros días del mes siguiente |
| Cuadre | Comparar fac0240, fac0533 y fac0510 entre sí y con la base | |
| Discos | Discos de pesas (nombre empieza por "DISCO") | Se venden por volumen: distorsionan los gráficos de unidades |
| Flete | Servicio de transporte facturado | Sin costo en el kardex (normal) |
| Meta | Meta mensual de ventas, fija en el modelo de Power BI | Se compara contra Total Ventas **con IVA**. Parámetro `@meta` (8.000.000 en los ejemplos) |

---

## Filtros estándar

Aplicar siempre en ventas, costos e inventario, salvo en la validación contra DreamSoft:

```sql
WITH nv AS (   -- códigos NO VALIDO por mes, según el inv0260 (ES-01 es excepción)
    SELECT DISTINCT CodigoProducto, Periodo
    FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
)
-- Ventas válidas
SELECT ...
FROM dbo.VENTAS v
WHERE v.Producto NOT LIKE '%NO VALIDO%'
  AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                  AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120))

-- Costo de lo vendido válido
-- FROM dbo.COSTOS c
-- WHERE c.TipoMovimiento = 'V'
--   AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = c.CodigoProducto
--                   AND nv.Periodo = CONVERT(char(7), c.FechaDocumento, 120))
--   AND NOT EXISTS (SELECT 1 FROM dbo.VENTAS x WHERE x.NumeroDocumento = c.NumeroDocumento
--                   AND x.CodigoProducto = c.CodigoProducto AND x.Producto LIKE '%NO VALIDO%')
```

**Cuándo no aplicarlos:**
- **Validación contra DreamSoft** (VENTAS vs VENTAS_VALIDACION_DIARIA, fac0240, fac0533, fac0510): no excluir NO VALIDO, porque DreamSoft sí los cuenta.
- **Meses sin inv0260 cargado**: la marca solo se detecta por el nombre de la venta. No es un error.
- Nunca excluir un código en todos los meses solo porque algún inv0260 lo marcó.

---

## Métricas clave

Todas excluyen NO VALIDO (filtro de arriba). Definiciones completas en `references/metricas.md`.

| Métrica | Fórmula | Nota |
|---|---|---|
| Total Ventas (con IVA) | `SUM(VENTAS.ValorFinal)` | Cifra del dashboard y de la meta |
| Ventas sin IVA | `SUM(VENTAS.NetoDocumento)` | Base del margen. Nunca `PrecioTotal` (está antes del descuento) |
| Costo de lo Vendido | `SUM(COSTOS.CostoTotal)` con `TipoMovimiento = 'V'` | Nunca `TipoDocumento = '880'` (deja fuera 882) ni `SalidaPesos` |
| Margen Bruto % | `(Ventas sin IVA − Costo de lo Vendido) / Ventas sin IVA` | Alerta solo si el costo del **mes** supera las ventas sin IVA del mes |
| Facturas | `COUNT(DISTINCT TipoDocumento + '\|' + NumeroDocumento)` | |
| Ticket Promedio | Total Ventas **con IVA** / Facturas | |
| Cliente nuevo | Primera compra (en todo el historial) en el mismo **mes** analizado | El modelo de Power BI tiene otra definición (mismo día): usar la de mes |
| Cumplimiento de meta | Total Ventas con IVA / `@meta` | |

---

## Frescura de los datos

| Tabla | Se actualiza | Nota |
|---|---|---|
| VENTAS | En cada cierre mensual | Hasta el último mes cerrado |
| COSTOS | En cada cierre mensual | |
| COSTOS_SALDO_MENSUAL | En cada cierre mensual | En el proyecto real empezó meses después que VENTAS: antes no hay marca NO VALIDO por mes |
| VENTAS_VALIDACION_DIARIA | En cada cierre mensual | Solo días con venta o devolución |
| PRODUCTOS | Al final de cada cierre | Muchos productos sin subcategoría (DreamSoft no la exporta) |

```sql
SELECT MAX(FechaDocumento) AS ultima_venta FROM dbo.VENTAS;
SELECT TOP 5 IdArchivo, NombreArchivo, FechaProcesamiento, PeriodosProcesados, Estado
FROM dbo.ETL_ARCHIVOS ORDER BY IdArchivo DESC;   -- ETL_ARCHIVOS no viene en los datos de ejemplo
```

---

## Navegación de referencias

| Dominio | Archivo | Para |
|---|---|---|
| Ventas | `references/tablas/ventas.md` | VENTAS y VENTAS_VALIDACION_DIARIA: columnas, valores, validación |
| Costos e inventario | `references/tablas/costos.md` | COSTOS (kardex) y COSTOS_SALDO_MENSUAL: tipos de movimiento, saldo, NO VALIDO |
| Maestros y control | `references/tablas/maestros.md` | PRODUCTOS, ETL_ARCHIVOS, vistas viejas y tablas excluidas |
| Entidades | `references/entidades.md` | Línea, factura, cliente, producto, vendedor |
| Métricas | `references/metricas.md` | Todas las métricas del dashboard con su SQL |
| Consultas | `references/consultas.md` | Consultas probadas 11.0 a 11.16 (cierre, margen, clientes, inventario, correcciones) |

---

## Consultas frecuentes

### Ventas del mes contra la meta (con y sin IVA)
Consulta completa con mes anterior y mismo mes del año anterior: `references/consultas.md`, 11.15.
```sql
DECLARE @ini date = '2025-03-01', @meta decimal(18,2) = 8000000;
WITH nv AS (
    SELECT DISTINCT CodigoProducto, Periodo FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
)
SELECT SUM(v.ValorFinal) AS ventas_con_iva, SUM(v.NetoDocumento) AS ventas_sin_iva,
       COUNT(DISTINCT v.TipoDocumento + '|' + v.NumeroDocumento) AS facturas,
       CAST(SUM(v.ValorFinal) / @meta AS decimal(9,4)) AS cumplimiento_meta
FROM dbo.VENTAS v
WHERE v.FechaDocumento >= @ini AND v.FechaDocumento < DATEADD(month, 1, @ini)
  AND v.Producto NOT LIKE '%NO VALIDO%'
  AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                  AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120));
```

### Margen bruto mensual con alerta
`references/consultas.md`, 11.2: ventas sin IVA, costo de lo vendido (`TipoMovimiento = 'V'`), margen y alerta por mes, sin NO VALIDO. Para el margen **mensual** no hace falta cruzar VENTAS con COSTOS línea por línea.

### Top productos y clientes
`references/consultas.md`, 11.16 (top 10 del periodo, con y sin IVA, y si el cliente es nuevo o recurrente) y 11.3 (margen por producto con la llave agregada).

---

## Problemas frecuentes

### Errores comunes
- **Validar o medir margen con `ValorFinal` o `PrecioTotal`** → diferencia falsa del 19 % (IVA) o del descuento. Usar `NetoDocumento`.
- **Costo de ventas con `TipoDocumento = '880'`** → deja fuera las ventas 882. Usar `TipoMovimiento = 'V'`.
- **Costo con `SalidaUnidades` / `SalidaPesos`** → se comportan como saldo antes del movimiento. Usar `Cantidad` y `CostoTotal`.
- **Unir VENTAS con COSTOS por `NumeroDocumento + CodigoProducto` sin agregar** → filas duplicadas (en los datos de ejemplo, `MC-20` va en dos líneas de `F-1005` y en un solo movimiento). Agregar cada lado a `TipoDocumento + NumeroDocumento + CodigoProducto` y comparar cantidades.
- **Unir VENTAS con VENTAS_VALIDACION_DIARIA sin agrupar por día** → el valor esperado se multiplica por cada línea.
- **Normalizar códigos** (`CAST(CodigoProducto AS int)`, quitar ceros) → mezcla productos distintos (0123456 ≠ 123456). Ojo al abrir los CSV en Excel: quita los ceros iniciales.
- **Filtrar NO VALIDO con `PRODUCTOS.NombreProducto`** → no excluye nada (el maestro tiene el nombre real). Usar la marca por mes.
- **Usar las vistas viejas `vw_*`** (ventas mensuales, top productos, ventas por asesor) → no excluyen NO VALIDO y cuentan facturas solo por número. No usarlas para métricas.
- **Sumar `COSTOS_SALDO_MENSUAL.EntradaPesos` / `SalidaPesos`** → incompletos (el inv0260 omite productos que cierran el mes en cero; en los datos de ejemplo, `BN-01` falta en 2025-03). Usar solo `FinalPesos`; entradas y salidas desde COSTOS.
- **Tratar `Estado` como anulación** → siempre es 0.

### Valores raros que NO son errores
- **Ventas con costo $0**: producto con inventario negativo en DreamSoft (consulta 11.14; en los datos de ejemplo, `DS-10` en `F-1005`). Se corrige solo con evidencia de una compra 830 y del costo histórico.
- **Ventas sin movimiento en el kardex**: fletes y servicios (`FL-01` en `F-1002`).
- **Costo mayor que el precio en una línea**: promociones. Solo alertar si el total del mes da costo > ventas sin IVA.
- **Meses de validación que no dan $0 o con devoluciones enormes**: los ajustes de inventario de DreamSoft (facturas de empleados, códigos NO VALIDO) pasan por ventas y devoluciones. Cuando una diferencia ya está explicada, se documenta como conocida y no se vuelve a investigar.
- **Una devolución sin contrapartida en VENTAS**: la factura devuelta ya se borró de VENTAS, pero DreamSoft la sigue mostrando como venta y devolución del día (en los datos de ejemplo, `F-1009` el 2025-03-15). El neto del día cuadra.

### Rendimiento
- Las tablas son pequeñas (miles de filas): no hace falta optimizar. Igual filtrar por rango de fechas semiabierto y usar `TOP` al explorar.
