# Métricas

Definiciones del modelo de Power BI (`Medidas Ventas`, `Medidas Costos`) y su equivalente en SQL. "Sin NO VALIDO" = filtro por mes de SKILL.md (en Power BI, las columnas calculadas `Es NO VALIDO` de VENTAS, COSTOS y COSTOS_SALDO_MENSUAL).

Convención de respuesta: cuando pregunten por ventas, dar **con IVA y sin IVA**, y decir cuál es cuál.

## Ventas

### Total Ventas (con IVA)
- **Definición**: lo que pagaron los clientes.
- **Fórmula**: `SUM(VENTAS.ValorFinal)` sin NO VALIDO.
- **Grano**: mes.
- **Notas**: cifra principal del dashboard y la que se compara con la meta.

### Ventas sin IVA
- **Definición**: venta neta de descuento, sin IVA.
- **Fórmula**: `SUM(VENTAS.NetoDocumento)` sin NO VALIDO.
- **Notas**: base del margen y de la validación. Una versión anterior del modelo sumaba `PrecioTotal` (sin restar descuentos).

### Unidades Vendidas
- **Fórmula**: `SUM(VENTAS.Cantidad)` sin NO VALIDO.
- **Notas**: los discos de pesas se venden por decenas y distorsionan los gráficos de unidades.

### Facturas
- **Fórmula**: `COUNT(DISTINCT TipoDocumento + '|' + NumeroDocumento)`.
- **Notas**: el modelo usa `DISTINCTCOUNT(NumeroDocumento)`; hoy no hay números repetidos entre 880 y 882, pero en SQL se usa la llave completa.

### Ticket Promedio
- **Fórmula**: Total Ventas **con IVA** / Facturas.

### Clientes únicos
- **Fórmula**: `COUNT(DISTINCT CodigoCliente)`.

### Cliente nuevo / recurrente
- **Definición**: nuevo si su primera compra en VENTAS (en todo el historial) cae en el mismo mes analizado; si no, recurrente.
- **Notas**: el modelo tiene dos definiciones distintas (medida "mismo día", columna "mismo mes"); usar "mismo mes". Consulta 11.8.

### Meta mensual y cumplimiento
- **Definición**: meta mensual fija en el modelo de Power BI (parámetro `@meta`; 8.000.000 en los ejemplos).
- **Fórmula**: Total Ventas **con IVA** / `@meta`.

## Costos y margen

### Costo de lo Vendido
- **Fórmula**: `SUM(COSTOS.CostoTotal)` con `TipoMovimiento = 'V'`, sin NO VALIDO.
- **Notas**: una versión anterior del modelo filtraba `TipoDocumento = '880'` y dejaba fuera las ventas 882. Hay ventas sin costo (fletes, servicios) y ventas con costo $0 (inventario negativo).

### Margen Bruto y Margen Bruto %
- **Fórmula**: `Ventas sin IVA − Costo de lo Vendido`; `% = Margen Bruto / Ventas sin IVA`.
- **Notas**: para el margen **mensual** no hace falta cruzar línea por línea (consulta 11.2). Para margen por producto o por factura, cruzar con la llave agregada (consulta 11.3).

### Alerta de rentabilidad
- **Definición**: "ALERTA" si el Costo de lo Vendido del mes supera las Ventas sin IVA del mes.
- **Notas**: una línea con costo > precio es normal (promociones). En el cierre también se compara el margen con los meses anteriores.

### Costo Unitario Promedio
- **Fórmula**: Costo de lo Vendido / `SUM(COSTOS.Cantidad)` de ventas.
- **Notas**: antes dividía por `SalidaUnidades` (error).

### Costo Compras
- **Fórmula**: `SUM(COSTOS.CostoTotal)` con `TipoDocumento IN ('830','825','833')`, sin NO VALIDO.

## Inventario

### Valor Inventario Válido
- **Fórmula**: `SUM(COSTOS_SALDO_MENSUAL.FinalPesos)` del periodo, sin NO VALIDO.
- **Notas**: solo desde que se carga el inv0260.

### Meses de Inventario
- **Fórmula**: Valor Inventario Válido / Costo de lo Vendido del mes.

### Inventario sin rotación
- **Definición**: inventario final (con valor) de productos sin ventas en los últimos 90 días.
- **Notas**: en Power BI el nombre sale de `COSTOS_SALDO_MENSUAL[Producto]` y la última venta se busca por código exacto. Consulta 11.9.

## Validación y devoluciones

### Diferencia de validación
- **Fórmula**: `SUM(VENTAS.NetoDocumento) − SUM(VENTAS_VALIDACION_DIARIA.ValorRealEsperado)`, **sin** excluir NO VALIDO.
- **Notas**: primero el mes, luego el día. Las diferencias ya explicadas se documentan como conocidas y no se vuelven a investigar.

### Devoluciones del mes
- **Fórmula**: `SUM(CantidadDevuelta)`, `SUM(ValorDevuelto)` de VENTAS_VALIDACION_DIARIA.
- **Notas**: pueden inflarse en meses con ajustes de inventario de DreamSoft; advertirlo al reportarlas.
