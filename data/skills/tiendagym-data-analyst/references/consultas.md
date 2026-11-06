# Consultas T-SQL probadas

Verificadas contra la base real (SQL Server 2025) y contra los datos sintéticos de `sample-data/`: todas corren sin error. La 11.12 no se ejecutó porque es una plantilla de UPDATE. Fechas, códigos y la meta son los de los datos de ejemplo.

Reglas que todas respetan: `NetoDocumento` para ventas sin IVA, `TipoMovimiento = 'V'` para costo de ventas, NO VALIDO por mes con `NOT EXISTS` (la excepción `ES-01` siempre cuenta), códigos comparados como texto exacto y rangos de fecha semiabiertos.

| # | Para qué |
|---|---|
| 11.0 | Antes de cargar un mes: qué hay ya en la base |
| 11.1 | Validación del cierre (total del mes y por día) |
| 11.2 | Margen bruto mensual y alerta |
| 11.3 | Margen por producto / ventas sin costo (llave agregada) |
| 11.4 | Devoluciones y notas crédito (893) por mes |
| 11.5 | Facturas a nombre de empleados (revisar, no borrar) |
| 11.6 | Tipos de documento de venta distintos de 880 |
| 11.7 | Estado de las cargas |
| 11.8 | Clientes nuevos vs recurrentes y ticket promedio |
| 11.9 | Inventario sin rotación (90 días) |
| 11.10 | Cascada de inventario del mes |
| 11.11 | Calidad de PRODUCTOS |
| 11.12 | Plantilla de corrección segura (UPDATE con `@@ROWCOUNT`) |
| 11.13 | Códigos con y sin cero inicial |
| 11.14 | Ventas con costo $0 |
| 11.15 | Ventas del mes contra la meta, mes anterior y año anterior |
| 11.16 | Top productos y top clientes del periodo |


### 11.0 Antes de cargar un mes: qué hay ya en la base
```sql
DECLARE @ini date = '2025-04-01', @fin date = '2025-04-30';
SELECT 'VENTAS' AS tabla, COUNT(*) AS filas FROM dbo.VENTAS
 WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)
UNION ALL SELECT 'VENTAS_VALIDACION_DIARIA', COUNT(*) FROM dbo.VENTAS_VALIDACION_DIARIA
 WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)
UNION ALL SELECT 'COSTOS', COUNT(*) FROM dbo.COSTOS
 WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)
UNION ALL SELECT 'COSTOS_SALDO_MENSUAL', COUNT(*) FROM dbo.COSTOS_SALDO_MENSUAL
 WHERE Periodo = CONVERT(char(7), @ini, 120);

SELECT TOP 10 * FROM dbo.ETL_ARCHIVOS ORDER BY IdArchivo DESC;
```
Además, revisar qué meses trae el fac0240 (se borran y recargan todos) y cuadrar fac0240 contra fac0533 antes de cargar, con fac0510 como tercera fuente.

### 11.1 Validación del cierre (total del mes = fila con fecha NULL)
No se excluyen los NO VALIDO, porque DreamSoft sí los cuenta.
```sql
DECLARE @ini date = '2025-03-01', @fin date = '2025-03-31';
WITH v AS (
    SELECT CAST(FechaDocumento AS date) AS fecha, SUM(NetoDocumento) AS ventas_neto
    FROM dbo.VENTAS
    WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)
    GROUP BY CAST(FechaDocumento AS date)
), d AS (
    SELECT CAST(FechaDocumento AS date) AS fecha, ValorRealEsperado
    FROM dbo.VENTAS_VALIDACION_DIARIA
    WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)
)
SELECT COALESCE(v.fecha, d.fecha) AS fecha,
       SUM(ISNULL(v.ventas_neto, 0)) AS ventas_neto,
       SUM(ISNULL(d.ValorRealEsperado, 0)) AS esperado_dreamsoft,
       SUM(ISNULL(v.ventas_neto, 0) - ISNULL(d.ValorRealEsperado, 0)) AS diferencia
FROM v FULL OUTER JOIN d ON d.fecha = v.fecha
GROUP BY ROLLUP(COALESCE(v.fecha, d.fecha))
ORDER BY fecha;
```

### 11.2 Margen bruto mensual y alerta (comparado mes a mes)
```sql
WITH nv AS (
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

### 11.3 Margen por producto / ventas sin costo (llave agregada)
```sql
DECLARE @ini date = '2025-03-01', @fin date = '2025-03-31';
WITH nv AS (
    SELECT DISTINCT CodigoProducto, Periodo FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
), v AS (
    SELECT TipoDocumento, NumeroDocumento, CodigoProducto, MAX(Producto) AS producto,
           SUM(Cantidad) AS und_vendidas, SUM(NetoDocumento) AS venta_neta
    FROM dbo.VENTAS v
    WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)
      AND Producto NOT LIKE '%NO VALIDO%'
      AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                      AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120))
    GROUP BY TipoDocumento, NumeroDocumento, CodigoProducto
), c AS (
    SELECT TipoDocumento, NumeroDocumento, CodigoProducto, SUM(Cantidad) AS und_costo, SUM(CostoTotal) AS costo
    FROM dbo.COSTOS
    WHERE TipoMovimiento = 'V'
    GROUP BY TipoDocumento, NumeroDocumento, CodigoProducto
), lineas AS (
    SELECT v.*, c.und_costo, c.costo,
           CASE WHEN c.costo IS NULL THEN 'sin costo'
                WHEN c.costo = 0 THEN 'costo en cero'
                WHEN c.und_costo <> v.und_vendidas THEN 'cantidades distintas' END AS alerta
    FROM v LEFT JOIN c ON c.TipoDocumento = v.TipoDocumento
                      AND c.NumeroDocumento = v.NumeroDocumento
                      AND c.CodigoProducto = v.CodigoProducto
)
-- Margen por producto (solo líneas con costo)
SELECT CodigoProducto, MAX(producto) AS producto, SUM(und_vendidas) AS unidades,
       SUM(venta_neta) AS venta_neta, SUM(costo) AS costo,
       SUM(venta_neta) - SUM(costo) AS ganancia,
       CAST((SUM(venta_neta) - SUM(costo)) / NULLIF(SUM(venta_neta), 0) AS decimal(9,4)) AS margen_pct
FROM lineas
WHERE costo IS NOT NULL
GROUP BY CodigoProducto
ORDER BY ganancia DESC;
-- Para ver las ventas sin costo o con costo en cero, cambiar el SELECT final por:
-- SELECT * FROM lineas WHERE alerta IS NOT NULL ORDER BY venta_neta DESC;
```

### 11.4 Devoluciones y notas crédito (893) por mes
```sql
SELECT CONVERT(char(7), FechaDocumento, 120) AS periodo,
       SUM(CantidadDevuelta) AS und_devueltas, SUM(ValorDevuelto) AS valor_devuelto
FROM dbo.VENTAS_VALIDACION_DIARIA
GROUP BY CONVERT(char(7), FechaDocumento, 120)
ORDER BY periodo;

SELECT CONVERT(char(7), FechaDocumento, 120) AS periodo, TipoMovimiento,
       COUNT(*) AS movimientos, SUM(CostoTotal) AS costo
FROM dbo.COSTOS
WHERE TipoDocumento = '893'
GROUP BY CONVERT(char(7), FechaDocumento, 120), TipoMovimiento
ORDER BY periodo;
```

### 11.5 Facturas a nombre de empleados (para revisar, no para borrar)
Se buscan en el cliente, no en el vendedor.
```sql
DECLARE @empleados TABLE (nombre nvarchar(200));
-- INSERT INTO @empleados VALUES (N'NOMBRE EMPLEADO 1'), (N'NOMBRE EMPLEADO 2');
SELECT v.TipoDocumento, v.NumeroDocumento, CAST(v.FechaDocumento AS date) AS fecha, v.Cliente,
       COUNT(*) AS lineas, SUM(v.NetoDocumento) AS venta_neta
FROM dbo.VENTAS v
WHERE EXISTS (SELECT 1 FROM @empleados e WHERE v.Cliente LIKE '%' + e.nombre + '%')
GROUP BY v.TipoDocumento, v.NumeroDocumento, CAST(v.FechaDocumento AS date), v.Cliente
ORDER BY fecha;
```

### 11.6 Alerta de tipos de documento de venta distintos de 880
```sql
SELECT TipoDocumento, CONVERT(char(7), FechaDocumento, 120) AS periodo,
       COUNT(*) AS movimientos, SUM(CostoTotal) AS costo
FROM dbo.COSTOS
WHERE TipoMovimiento = 'V' AND TipoDocumento <> '880'
  AND FechaDocumento >= DATEADD(month, -3, CAST(GETDATE() AS date))
GROUP BY TipoDocumento, CONVERT(char(7), FechaDocumento, 120);
```

### 11.7 Estado de las cargas
```sql
SELECT TOP 20 * FROM dbo.ETL_ARCHIVOS ORDER BY IdArchivo DESC;
```

### 11.8 Clientes nuevos vs recurrentes y ticket promedio por mes
```sql
WITH nv AS (
    SELECT DISTINCT CodigoProducto, Periodo FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
), vtas AS (
    SELECT v.* FROM dbo.VENTAS v
    WHERE v.Producto NOT LIKE '%NO VALIDO%'
      AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                      AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120))
), primera AS (
    SELECT CodigoCliente, MIN(FechaDocumento) AS primera_compra FROM vtas GROUP BY CodigoCliente
), mes_cliente AS (
    SELECT DISTINCT CONVERT(char(7), v.FechaDocumento, 120) AS periodo, v.CodigoCliente,
           CASE WHEN CONVERT(char(7), p.primera_compra, 120) = CONVERT(char(7), v.FechaDocumento, 120)
                THEN 'Nuevo' ELSE 'Recurrente' END AS tipo
    FROM vtas v JOIN primera p ON p.CodigoCliente = v.CodigoCliente
)
SELECT periodo,
       SUM(CASE WHEN tipo = 'Nuevo' THEN 1 ELSE 0 END) AS clientes_nuevos,
       SUM(CASE WHEN tipo = 'Recurrente' THEN 1 ELSE 0 END) AS clientes_recurrentes
FROM mes_cliente
GROUP BY periodo
ORDER BY periodo;

-- Ticket promedio con IVA (cambiar la consulta final de arriba por esta):
-- SELECT CONVERT(char(7), FechaDocumento, 120) AS periodo,
--        SUM(ValorFinal) / NULLIF(COUNT(DISTINCT TipoDocumento + '|' + NumeroDocumento), 0) AS ticket_promedio_con_iva
-- FROM vtas GROUP BY CONVERT(char(7), FechaDocumento, 120) ORDER BY periodo;
```

### 11.9 Inventario sin rotación (90 días)
```sql
DECLARE @periodo char(7) = '2025-03', @corte date = '2025-03-31';
SELECT s.CodigoProducto, s.Producto, s.FinalUnidades, s.FinalPesos
FROM dbo.COSTOS_SALDO_MENSUAL s
WHERE s.Periodo = @periodo AND s.FinalPesos > 0
  AND NOT (s.Producto LIKE '%NO VALIDO%' AND s.CodigoProducto NOT IN ('ES-01'))
  AND NOT EXISTS (
      SELECT 1 FROM dbo.VENTAS v
      WHERE v.CodigoProducto = s.CodigoProducto AND v.Producto NOT LIKE '%NO VALIDO%'
        AND v.FechaDocumento > DATEADD(day, -90, @corte)
        AND v.FechaDocumento < DATEADD(day, 1, @corte))
ORDER BY s.FinalPesos DESC;
```

### 11.10 Cascada de inventario del mes (kardex + saldo final)
```sql
DECLARE @periodo char(7) = '2025-03', @ini date = '2025-03-01', @fin date = '2025-03-31';
WITH nv AS (
    SELECT DISTINCT CodigoProducto FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Periodo = @periodo AND Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
), fin AS (
    SELECT SUM(FinalPesos) AS final
    FROM dbo.COSTOS_SALDO_MENSUAL s
    WHERE s.Periodo = @periodo AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = s.CodigoProducto)
), mov AS (
    SELECT SUM(CASE WHEN TipoMovimiento IN ('C', 'E') THEN CostoTotal ELSE 0 END) AS entradas,
           SUM(CASE WHEN TipoMovimiento IN ('V', 'S') THEN CostoTotal ELSE 0 END) AS salidas
    FROM dbo.COSTOS c
    WHERE c.FechaDocumento >= @ini AND c.FechaDocumento < DATEADD(day, 1, @fin)
      AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = c.CodigoProducto)
)
SELECT fin.final - mov.entradas + mov.salidas AS inicial, mov.entradas, mov.salidas, fin.final
FROM fin CROSS JOIN mov;
```

### 11.11 Calidad de PRODUCTOS
```sql
SELECT CONVERT(char(7), v.FechaDocumento, 120) AS periodo,
       SUM(v.NetoDocumento) AS ventas_netas,
       SUM(CASE WHEN p.CodigoProducto IS NULL THEN v.NetoDocumento ELSE 0 END) AS ventas_sin_ficha
FROM dbo.VENTAS v
LEFT JOIN dbo.PRODUCTOS p ON p.CodigoProducto = v.CodigoProducto
WHERE v.Producto NOT LIKE '%NO VALIDO%'
GROUP BY CONVERT(char(7), v.FechaDocumento, 120)
ORDER BY periodo;

SELECT COUNT(*) AS productos_sin_subcategoria
FROM dbo.PRODUCTOS
WHERE SubCategoria IS NULL OR LTRIM(RTRIM(SubCategoria)) = '';
```

### 11.12 Plantilla de corrección segura (solo después de confirmar con evidencia)
```sql
-- Ejemplo: corregir el costo de un movimiento puntual del kardex.
DECLARE @IdCosto int = 0;               -- IdCosto confirmado con evidencia
DECLARE @CostoNuevo decimal(18,2) = 0;  -- valor confirmado

SET XACT_ABORT ON;
BEGIN TRAN;
    SELECT 'antes' AS momento, * FROM dbo.COSTOS WHERE IdCosto = @IdCosto;

    UPDATE dbo.COSTOS
       SET CostoTotal = @CostoNuevo,
           CostoUnitario = @CostoNuevo / NULLIF(Cantidad, 0)
     WHERE IdCosto = @IdCosto;

    IF @@ROWCOUNT <> 1
    BEGIN
        ROLLBACK TRAN;
        THROW 50001, 'La corrección no tocó exactamente 1 fila; se deshizo.', 1;
    END

    SELECT 'despues' AS momento, * FROM dbo.COSTOS WHERE IdCosto = @IdCosto;
COMMIT TRAN;
-- Guardar las dos filas (antes/después) en las notas del cierre.
```

### 11.13 Códigos con y sin cero inicial (posibles duplicados para revisar con administración)
```sql
SELECT a.CodigoProducto AS codigo_con_cero, a.NombreProducto AS nombre_con_cero,
       b.CodigoProducto AS codigo_sin_cero, b.NombreProducto AS nombre_sin_cero
FROM dbo.PRODUCTOS a
JOIN dbo.PRODUCTOS b
  ON a.CodigoProducto LIKE '0%'
 AND PATINDEX('%[^0]%', a.CodigoProducto) > 0
 AND b.CodigoProducto = SUBSTRING(a.CodigoProducto, PATINDEX('%[^0]%', a.CodigoProducto), 50)
ORDER BY a.CodigoProducto;
-- Solo para revisar: NO son el mismo producto mientras DreamSoft no lo confirme.
```

### 11.14 Ventas con costo en $0 por mes (patrón de inventario negativo)
```sql
SELECT CONVERT(char(7), c.FechaDocumento, 120) AS periodo, c.IdCosto, c.TipoDocumento, c.NumeroDocumento,
       c.CodigoProducto, c.Cantidad, c.CostoTotal, c.SaldoParcialUnidades
FROM dbo.COSTOS c
WHERE c.TipoMovimiento = 'V' AND ISNULL(c.CostoTotal, 0) = 0
  AND c.FechaDocumento >= '2025-01-01'
ORDER BY periodo, c.NumeroDocumento;
```

### 11.15 Ventas del mes contra la meta (con y sin IVA, mes anterior y año anterior)
La meta (`@meta`) se compara contra las ventas **con IVA**, como en el dashboard.
```sql
DECLARE @periodo char(7) = '2025-03', @meta decimal(18,2) = 8000000;
WITH nv AS (
    SELECT DISTINCT CodigoProducto, Periodo FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
), m AS (
    SELECT CONVERT(char(7), v.FechaDocumento, 120) AS periodo,
           SUM(v.ValorFinal) AS ventas_con_iva,
           SUM(v.NetoDocumento) AS ventas_sin_iva,
           COUNT(DISTINCT v.TipoDocumento + '|' + v.NumeroDocumento) AS facturas,
           COUNT(DISTINCT v.CodigoCliente) AS clientes
    FROM dbo.VENTAS v
    WHERE v.Producto NOT LIKE '%NO VALIDO%'
      AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                      AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120))
    GROUP BY CONVERT(char(7), v.FechaDocumento, 120)
)
SELECT m.periodo, m.ventas_con_iva, m.ventas_sin_iva, m.facturas, m.clientes,
       m.ventas_con_iva / NULLIF(m.facturas, 0) AS ticket_promedio_con_iva,
       CAST(m.ventas_con_iva / @meta AS decimal(9,4)) AS cumplimiento_meta,
       ant.ventas_con_iva AS mes_anterior_con_iva,
       CAST(m.ventas_con_iva / NULLIF(ant.ventas_con_iva, 0) - 1 AS decimal(9,4)) AS var_mes_anterior,
       aa.ventas_con_iva AS ano_anterior_con_iva,
       CAST(m.ventas_con_iva / NULLIF(aa.ventas_con_iva, 0) - 1 AS decimal(9,4)) AS var_ano_anterior
FROM m
LEFT JOIN m ant ON ant.periodo = CONVERT(char(7), DATEADD(month, -1, CAST(m.periodo + '-01' AS date)), 120)
LEFT JOIN m aa  ON aa.periodo  = CONVERT(char(7), DATEADD(year,  -1, CAST(m.periodo + '-01' AS date)), 120)
WHERE m.periodo = @periodo;
-- Para la serie completa, quitar el WHERE final y agregar ORDER BY m.periodo.
```

### 11.16 Top productos y top clientes del periodo
```sql
DECLARE @ini date = '2025-03-01', @fin date = '2025-03-31';
WITH nv AS (
    SELECT DISTINCT CodigoProducto, Periodo FROM dbo.COSTOS_SALDO_MENSUAL
    WHERE Producto LIKE '%NO VALIDO%' AND CodigoProducto NOT IN ('ES-01')
), vtas AS (
    SELECT v.* FROM dbo.VENTAS v
    WHERE v.Producto NOT LIKE '%NO VALIDO%'
      AND NOT EXISTS (SELECT 1 FROM nv WHERE nv.CodigoProducto = v.CodigoProducto
                      AND nv.Periodo = CONVERT(char(7), v.FechaDocumento, 120))
), primera AS (   -- primera compra de cada cliente en todo el historial
    SELECT CodigoCliente, MIN(FechaDocumento) AS primera_compra FROM vtas GROUP BY CodigoCliente
)
-- Top 10 clientes (nuevo = primera compra en el mes de @ini)
SELECT TOP 10 v.CodigoCliente, MAX(v.Cliente) AS cliente,
       CASE WHEN CONVERT(char(7), MIN(p.primera_compra), 120) = CONVERT(char(7), @ini, 120)
            THEN 'Nuevo' ELSE 'Recurrente' END AS tipo,
       COUNT(DISTINCT v.TipoDocumento + '|' + v.NumeroDocumento) AS facturas,
       SUM(v.ValorFinal) AS ventas_con_iva, SUM(v.NetoDocumento) AS ventas_sin_iva
FROM vtas v JOIN primera p ON p.CodigoCliente = v.CodigoCliente
WHERE v.FechaDocumento >= @ini AND v.FechaDocumento < DATEADD(day, 1, @fin)
GROUP BY v.CodigoCliente
ORDER BY ventas_sin_iva DESC;

-- Top 10 productos (cambiar el SELECT final por este):
-- SELECT TOP 10 CodigoProducto, MAX(Producto) AS producto, SUM(Cantidad) AS unidades,
--        SUM(ValorFinal) AS ventas_con_iva, SUM(NetoDocumento) AS ventas_sin_iva,
--        COUNT(DISTINCT TipoDocumento + '|' + NumeroDocumento) AS facturas
-- FROM vtas
-- WHERE FechaDocumento >= @ini AND FechaDocumento < DATEADD(day, 1, @fin)
-- GROUP BY CodigoProducto
-- ORDER BY ventas_sin_iva DESC;
-- Para el margen de cada producto, usar 11.3 (cruce con COSTOS por la llave agregada).
```
