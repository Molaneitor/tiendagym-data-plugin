# Tablas de ventas

Ventas línea por línea (VENTAS) y totales diarios de DreamSoft para validarlas (VENTAS_VALIDACION_DIARIA).

---

## Referencia rápida

### Contexto
DreamSoft no marca anulaciones ni devoluciones por factura en el reporte de carga (fac0240): todo entra como venta válida. Las devoluciones solo se ven en los totales diarios (fac0533) y en el reporte por cliente y producto (fac0510). Por eso cada cierre valida VENTAS contra VENTAS_VALIDACION_DIARIA.

### Aclaración de entidades
**"Venta" puede significar:**
- **Línea**: una fila de VENTAS (`IdVenta`).
- **Factura**: `TipoDocumento + NumeroDocumento`.
- **Total diario de DreamSoft**: una fila de VENTAS_VALIDACION_DIARIA (`FechaDocumento`).

### Filtros estándar
Para métricas, excluir NO VALIDO por mes (ver SKILL.md). Para validar contra DreamSoft, **no** excluirlos.

---

## Tablas

### dbo.VENTAS
**Ubicación**: `TiendaGymBI.dbo.VENTAS`
**Descripción**: una fila por línea de factura. Fuente: fac0240.
**Llave primaria**: `IdVenta` (identidad). No hay llave natural única: un producto puede repetirse en la misma factura.
**Actualización**: en cada cierre mensual. `cargar_ventas.py` borra y recarga **todos los meses que traiga el archivo** (por `AnoDoc`, `PeriodoDoc`), así que recargar borra las correcciones manuales.

| Columna | Tipo | Descripción | Notas |
|---|---|---|---|
| **IdVenta** | int | Identificador interno | |
| **AnoDoc**, **PeriodoDoc** | int | Año y mes del documento | Unidad de borrado y recarga |
| **TipoDocumento** | varchar(20) | 880 (actual) / 882 (anterior, antes de un cambio de sistema) | Si aparece otro tipo, avisar |
| **NumeroDocumento** | varchar(50) | Número de factura, serie continua | En los datos de ejemplo, `F-1001`… |
| **FechaDocumento** | date | Fecha de la factura | Sin hora. En Power BI aparece como dateTime |
| **CodigoCliente** | varchar(50) | Cédula o NIT del cliente | Identifica al cliente |
| **Cliente** | varchar(200) | Nombre del cliente | Facturas de empleados = ajustes, no ventas |
| **CodigoProducto** | varchar(50) | Código del producto | Texto. Ceros iniciales significativos |
| **Producto** | varchar(300) | Nombre en la factura | Si contiene "NO VALIDO" es un código de ajuste |
| **Cantidad** | decimal(18,2) | Unidades | |
| **PrecioVenta** | decimal(18,2) | Precio unitario sin IVA | |
| **PrecioTotal** | decimal(18,2) | Valor de la línea **antes** del descuento, sin IVA | No usar para métricas |
| **ValorDescuento** | decimal(18,2) | Descuento de la línea | Poco frecuente (en los datos de ejemplo, `F-1006`) |
| **NetoDocumento** | decimal(18,2) | `PrecioTotal − ValorDescuento`, sin IVA | **Valor de la línea**, no del documento. Base de margen y validación |
| **ValorIVA** | decimal(18,2) | IVA de la línea | 19 % |
| **ValorFinal** | decimal(18,2) | `NetoDocumento + ValorIVA` | Lo que pagó el cliente. Base de Total Ventas |
| **Estado** | int | Siempre 0 | No sirve para detectar anulaciones |
| **CodigoVendedor**, **Vendedor** | varchar | Asesor que vendió | No confundir con el cliente |

**Relaciones**:
- `CodigoProducto` → `PRODUCTOS.CodigoProducto` (muchos a uno, sin FK; puede no tener ficha).
- Con COSTOS por `TipoDocumento + NumeroDocumento + CodigoProducto`, agregando ambos lados.
- Con VENTAS_VALIDACION_DIARIA por fecha, agrupando VENTAS por día.

---

### dbo.VENTAS_VALIDACION_DIARIA
**Ubicación**: `TiendaGymBI.dbo.VENTAS_VALIDACION_DIARIA`
**Descripción**: totales diarios de DreamSoft (fac0533), todo sin IVA. Solo existe para validar VENTAS.
**Llave primaria**: `IdValidacion`; **índice único** `UX_VALIDACION_Fecha` sobre `FechaDocumento` (una fila por día).
**Actualización**: en cada cierre. Una recarga **omite** los días que ya existen (no los actualiza): para reemplazar un día hay que borrarlo primero, con evidencia y OK.
**Cobertura**: solo los meses en que se cargó el fac0533 (en el proyecto real empezó varios meses después que VENTAS).

| Columna | Tipo | Descripción | Notas |
|---|---|---|---|
| **FechaDocumento** | date | Día | Única |
| **CantidadVendida** | int | Unidades vendidas del día | |
| **ValorBruto** | decimal(18,2) | `pre_tot`: bruto antes del descuento | |
| **ValorDescuento** | decimal(18,2) | `val_des` | |
| **ValorVentaNeta** | decimal(18,2) | `net_doc` = bruto − descuento | Equivale a `SUM(NetoDocumento)` del día |
| **CantidadDevuelta**, **ValorDevuelto** | int, decimal(18,2) | Devoluciones registradas ese día | Pueden corresponder a ventas de otros días |
| **ValorRealEsperado** | decimal(19,2) | Columna calculada persistida: `ValorVentaNeta − ValorDevuelto` | Contra esto se valida `SUM(NetoDocumento)` |

---

## Métricas

| Métrica | Tabla | Fórmula | Notas |
|---|---|---|---|
| Total Ventas (con IVA) | VENTAS | `SUM(ValorFinal)` sin NO VALIDO | Cifra del dashboard y la meta |
| Ventas sin IVA | VENTAS | `SUM(NetoDocumento)` sin NO VALIDO | Base del margen |
| Unidades Vendidas | VENTAS | `SUM(Cantidad)` sin NO VALIDO | Los discos inflan las unidades |
| Facturas | VENTAS | `COUNT(DISTINCT TipoDocumento + '\|' + NumeroDocumento)` | |
| Diferencia de validación | ambas | `SUM(NetoDocumento) − SUM(ValorRealEsperado)` | Mes primero, luego día. Con NO VALIDO incluidos |
| Devoluciones del mes | VALIDACION | `SUM(CantidadDevuelta)`, `SUM(ValorDevuelto)` | Pueden inflarse en meses con ajustes de inventario de DreamSoft |

---

## Consultas de ejemplo

### Ventas por mes, con y sin IVA
```sql
WITH nv AS (
    SELECT DISTINCT CodigoProducto, Periodo FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
)
SELECT CONVERT(char(7), v.FechaDocumento, 120) AS periodo,
       SUM(v.ValorFinal) AS ventas_con_iva,
       SUM(v.NetoDocumento) AS ventas_sin_iva,
       COUNT(DISTINCT v.TipoDocumento + '|' + v.NumeroDocumento) AS facturas
FROM dbo.VENTAS v
WHERE v.Producto NOT LIKE '%NO VALIDO%'
  AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                  AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120))
GROUP BY CONVERT(char(7), v.FechaDocumento, 120)
ORDER BY periodo;
```

### Validación del mes contra DreamSoft
Consulta 11.1 de `references/consultas.md`: agrupa VENTAS por día, `FULL OUTER JOIN` con la validación y `ROLLUP` para la fila de total (fecha NULL).

### Ventas por vendedor del mes
```sql
DECLARE @ini date = '2025-03-01';
SELECT v.CodigoVendedor, MAX(v.Vendedor) AS vendedor,
       COUNT(DISTINCT v.TipoDocumento + '|' + v.NumeroDocumento) AS facturas,
       SUM(v.ValorFinal) AS ventas_con_iva, SUM(v.NetoDocumento) AS ventas_sin_iva
FROM dbo.VENTAS v
WHERE v.FechaDocumento >= @ini AND v.FechaDocumento < DATEADD(month, 1, @ini)
  AND v.Producto NOT LIKE '%NO VALIDO%'
  AND NOT EXISTS (SELECT 1 FROM dbo.COSTOS_SALDO_MENSUAL s
                  WHERE s.CodigoProducto = v.CodigoProducto
                    AND s.Periodo = CONVERT(char(7), v.FechaDocumento, 120)
                    AND s.Producto LIKE '%NO VALIDO%' AND s.CodigoProducto NOT IN ('ES-01'))
GROUP BY v.CodigoVendedor
ORDER BY ventas_sin_iva DESC;
```

---

## Trampas

1. **Tres columnas de valor**: `PrecioTotal` (antes del descuento), `NetoDocumento` (después del descuento, sin IVA), `ValorFinal` (con IVA).
   - Mal: `SUM(ValorFinal)` contra `ValorRealEsperado` (sale un 19 % de diferencia falsa).
   - Bien: `SUM(NetoDocumento)` contra `ValorRealEsperado`.
2. **Unir con la validación sin agrupar**:
   - Mal: `FROM dbo.VENTAS v JOIN dbo.VENTAS_VALIDACION_DIARIA d ON d.FechaDocumento = v.FechaDocumento` y `SUM(d.ValorRealEsperado)`.
   - Bien: CTE con `SUM(NetoDocumento)` por día y luego `FULL OUTER JOIN`.
3. **Devoluciones en otra fecha**: validar primero el total del mes y después cada día; una devolución puede caer días después de la venta.
4. **Correcciones manuales**: nunca aparecen en DreamSoft. Un total del mes distinto de $0 puede ser una corrección conocida.
5. **`Estado` siempre es 0**: no detecta anulaciones.
6. **Facturas de empleados**: se buscan en `Cliente`, no en `Vendedor` (un empleado puede aparecer como vendedor en facturas normales).
7. **Recargar el fac0240 borra las correcciones** de todos los meses que traiga el archivo.
