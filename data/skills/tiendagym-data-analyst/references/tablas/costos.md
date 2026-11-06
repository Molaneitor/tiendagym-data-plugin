# Tablas de costos e inventario

Kardex con costo (COSTOS) y saldo mensual por producto (COSTOS_SALDO_MENSUAL).

---

## Referencia rápida

### Contexto
El kardex (inv0101) registra cada movimiento de inventario con su costo: ventas, compras, entradas, salidas y notas crédito. De ahí sale el **costo de lo vendido**. El saldo mensual (inv0260) da el **valor del inventario** al cierre del mes y es la fuente de la marca "NO VALIDO" por mes.

### Aclaración de entidades
**"Costo" puede significar:**
- **Costo de lo vendido**: `COSTOS.CostoTotal` con `TipoMovimiento = 'V'`.
- **Costo de compras**: `COSTOS.CostoTotal` con `TipoDocumento IN ('830','825','833')`.
- **Valor del inventario**: `COSTOS_SALDO_MENSUAL.FinalPesos` del periodo.

### Filtros estándar
```sql
WHERE c.TipoMovimiento = 'V'   -- ventas; nunca TipoDocumento = '880'
-- más la exclusión NO VALIDO por mes (SKILL.md)
```

---

## Tablas

### dbo.COSTOS
**Ubicación**: `TiendaGymBI.dbo.COSTOS`
**Descripción**: una fila por movimiento del kardex. Fuente: inv0101.
**Llave primaria**: `IdCosto` (llave para correcciones puntuales). **Índice único** `UX_COSTOS_Movimiento` sobre `CodigoProducto, FechaDocumento, NumeroDocumento, TipoMovimiento, Cantidad, CostoTotal`: la carga omite movimientos repetidos.
**Actualización**: en cada cierre, fila por fila. Como `CostoTotal` es parte del índice único, si se corrige el costo de una fila y se recarga el inv0101 de ese mes, la fila original con costo $0 vuelve a entrar como un movimiento nuevo. No recargar meses corregidos.
**Cobertura**: desde el primer mes cargado. `CodigoBodega` siempre es `'1'`.

| Columna | Tipo | Descripción | Notas |
|---|---|---|---|
| **IdCosto** | int | Identificador interno | |
| **TipoMovimiento** | varchar(5) | V venta, C compra, E entrada, S salida (T traslado: no aparece hoy) | Filtro del costo de ventas |
| **TipoDocumento** | varchar(20) | Documento que generó el movimiento | Ver tabla de abajo |
| **NumeroDocumento** | varchar(50) | Número del documento | En ventas, el mismo de VENTAS |
| **CodigoProducto** | varchar(50) | Producto | Texto exacto |
| **FechaDocumento** | date | Fecha del movimiento | |
| **AnoDoc** | int | Año | |
| **Cantidad** | decimal(18,2) | Unidades del movimiento | Usar esta para unidades vendidas |
| **CostoUnitario**, **CostoTotal** | decimal(18,2) | Costo del movimiento | `CostoTotal` = costo de lo vendido en ventas |
| **SalidaUnidades**, **SalidaPesos** | decimal(18,2) | Se comportan como saldo **antes** del movimiento | **No** son lo vendido |
| **SaldoParcialUnidades**, **SaldoParcialPesos** | decimal(18,2) | Saldo después del movimiento | Negativo = inventario negativo en DreamSoft |
| **NombreArchivo**, **FechaCarga** | varchar, datetime | Trazabilidad de la carga | |

**TipoMovimiento × TipoDocumento** (lo que existe hoy en la base):

| TipoMovimiento | TipoDocumento | Qué es |
|---|---|---|
| V | 880 | Venta actual |
| V | 882 | Venta anterior (antes de un cambio de sistema) |
| C | 830, 833 | Compra |
| E | 825 | Compra registrada como entrada |
| E | 893 | Nota crédito (devolución real o corrección de costo) |
| E | 800 | Entrada sin documentar |
| S | 835, 850 | Salidas sin documentar |

**Relaciones**:
- Ventas: `TipoDocumento + NumeroDocumento + CodigoProducto` con VENTAS, **agregando ambos lados** (un producto puede ir en varias líneas de VENTAS y en un solo movimiento, o al revés).
- `CodigoProducto` + periodo con COSTOS_SALDO_MENSUAL para la marca NO VALIDO.

---

### dbo.COSTOS_SALDO_MENSUAL
**Ubicación**: `TiendaGymBI.dbo.COSTOS_SALDO_MENSUAL`
**Descripción**: saldo inicial, entradas, salidas y final por producto y mes. Fuente: inv0260 (renombrado `inv0260_AAAA-MM.xls`, porque el archivo no trae el periodo).
**Llave primaria**: `IdSaldo`; **índice único** `UX_SaldoMensual_Periodo_Producto` sobre `Periodo, CodigoProducto`.
**Cobertura**: desde que se empezó a cargar el inv0260 (en el proyecto real, meses después que VENTAS). Antes no hay saldo ni marca NO VALIDO por mes.

| Columna | Tipo | Descripción | Notas |
|---|---|---|---|
| **Periodo** | char(7) | `'AAAA-MM'` | Unir con `CONVERT(char(7), FechaDocumento, 120)` |
| **CodigoProducto** | varchar(50) | Producto | |
| **Producto** | varchar(300) | Nombre en el inv0260 | Trae la marca "NO VALIDO" o "… ( NO VALIDO )" |
| **FinalPesos**, **FinalUnidades** | decimal(18,2) | Inventario final | **Confiable** |
| **InicialPesos**, **EntradaPesos**, **SalidaPesos** (y unidades) | decimal(18,2) | | **Incompletos**: el inv0260 omite los productos que terminan el mes en cero |

---

## Métricas

| Métrica | Tabla | Fórmula | Notas |
|---|---|---|---|
| Costo de lo Vendido | COSTOS | `SUM(CostoTotal)` con `TipoMovimiento = 'V'`, sin NO VALIDO | |
| Costo Unitario Promedio | COSTOS | Costo de lo Vendido / `SUM(Cantidad)` de ventas | Nunca dividir por `SalidaUnidades` |
| Costo Compras | COSTOS | `SUM(CostoTotal)` con `TipoDocumento IN ('830','825','833')`, sin NO VALIDO | |
| Valor Inventario Válido | SALDO | `SUM(FinalPesos)` del periodo, sin NO VALIDO | |
| Meses de Inventario | ambas | Valor Inventario Válido / Costo de lo Vendido del mes | |
| Inventario sin rotación | ambas + VENTAS | Inventario final de productos sin ventas en los últimos 90 días | Consulta 11.9 |

---

## Consultas de ejemplo

### Costo de lo vendido por mes y tipo de documento
```sql
SELECT CONVERT(char(7), FechaDocumento, 120) AS periodo, TipoDocumento,
       SUM(Cantidad) AS unidades, SUM(CostoTotal) AS costo
FROM dbo.COSTOS
WHERE TipoMovimiento = 'V'
GROUP BY CONVERT(char(7), FechaDocumento, 120), TipoDocumento
ORDER BY periodo, TipoDocumento;
```

### Códigos NO VALIDO de cada mes
```sql
SELECT Periodo, CodigoProducto, Producto
FROM dbo.COSTOS_SALDO_MENSUAL
WHERE Producto LIKE '%NO VALIDO%'
ORDER BY CodigoProducto, Periodo;
-- ES-01 aparece marcado en 2025-03, pero es una excepción: sí cuenta.
```

### Cascada de inventario del mes
Consulta 11.10 de `references/consultas.md`: inicial = final − entradas + salidas, con entradas y salidas desde el kardex y el final desde el saldo.

---

## Trampas

1. **882 vs 880**:
   - Mal: `WHERE TipoDocumento = '880'` (deja fuera las ventas 882; en los datos de ejemplo, todo enero).
   - Bien: `WHERE TipoMovimiento = 'V'`.
2. **`SalidaUnidades` / `SalidaPesos` no son lo vendido**: usar `Cantidad` y `CostoTotal`.
3. **Costo $0 por inventario negativo**: si el producto tenía saldo negativo en DreamSoft, la venta entra con costo $0 (`SaldoParcialUnidades` negativo). Revisar `ISNULL(CostoTotal, 0) = 0` además de las ventas sin movimiento (consulta 11.14).
4. **El saldo omite productos en cero**: no sumar entradas ni salidas del saldo; tomarlas del kardex.
5. **NO VALIDO por mes**: el inv0260 omite los códigos que cierran el mes en cero, así que para COSTOS también hay que excluir los movimientos cuya venta se registró con nombre "NO VALIDO".
6. **893 mezcla devoluciones y correcciones de costo**: no tratarlo como devolución pura. Si aparece en un cierre, avisar.
7. **Correcciones manuales se pierden al recargar** el inv0101 del mes corregido.
