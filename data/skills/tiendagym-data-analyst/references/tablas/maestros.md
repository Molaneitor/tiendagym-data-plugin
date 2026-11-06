# Maestros, control de cargas y tablas excluidas

---

## Referencia rápida

### Contexto
El único maestro con datos es PRODUCTOS. Clientes y vendedores solo existen dentro de VENTAS. ETL_ARCHIVOS registra cada carga del fac0240. Hay tablas y vistas que **no** deben usarse para el análisis.

---

## Tablas

### dbo.PRODUCTOS
**Ubicación**: `TiendaGymBI.dbo.PRODUCTOS`
**Descripción**: maestro de productos. `actualizar_productos.py` agrega los códigos nuevos al final de cada cierre (nombre del inv0260 más reciente o del fac0240, sin subcategoría).
**Llave primaria**: `IdProducto`. **No hay índice único sobre `CodigoProducto`** (hoy no hay repetidos; si se une por código y llega a haber uno, las sumas se duplican).

| Columna | Tipo | Descripción | Notas |
|---|---|---|---|
| **CodigoProducto** | varchar(50) | Código | Hay códigos con cero inicial que tienen gemelo sin cero (consulta 11.13): son productos distintos |
| **NombreProducto** | varchar(300) | Nombre real | No sirve para detectar NO VALIDO |
| **Categoria**, **SubCategoria** | varchar(150) | Clasificación | DreamSoft no exporta la subcategoría: muchos productos la tienen vacía y hay que asignarla a mano |
| **Marca** | varchar(100) | | |
| **PrecioActual** | decimal(18,2) | | |
| **Activo** | bit | | |

### dbo.ETL_ARCHIVOS
**Descripción**: control de cargas de `cargar_ventas.py`.
**Llave primaria**: `IdArchivo`; **índice único** sobre `HashArchivo` (SHA-256): el mismo archivo no se puede cargar dos veces.

| Columna | Tipo | Notas |
|---|---|---|
| **IdArchivo** | int | Orden de carga (`ORDER BY IdArchivo DESC` para ver lo último) |
| **NombreArchivo**, **HashArchivo** | varchar | |
| **FechaProcesamiento** | datetime | Cuándo se cargó |
| **RegistrosCargados** | int | Líneas insertadas |
| **PeriodosProcesados** | varchar(200) | Meses que se borraron y recargaron, ej. `'2025-03'` |
| **Estado**, **Mensaje** | varchar | `'EXITOSO'` o error |

---

## No usar para el análisis

| Objeto | Motivo |
|---|---|
| `vw_VentasMensuales`, `vw_TopProductos`, `vw_VentasAsesor` | Vistas viejas: no excluyen NO VALIDO y cuentan facturas solo por `NumeroDocumento`. Calcular desde VENTAS con los filtros estándar |
| `COTIZACIONES`, `DETALLECOTIZACIONES` | Datos mal registrados; excluidas hasta que el usuario las corrija |
| `INVENTARIO` | Datos mal registrados; usar COSTOS_SALDO_MENSUAL |
| `CLIENTES`, `ASESORES`, `COMPRAS` | Vacías. Clientes y vendedores: desde VENTAS. Compras: desde COSTOS (830, 825, 833) |

---

## Consultas de ejemplo

### Ventas de productos sin ficha y productos sin subcategoría
Consulta 11.11 de `references/consultas.md`.

### Estado de las últimas cargas
```sql
SELECT TOP 10 IdArchivo, NombreArchivo, FechaProcesamiento, RegistrosCargados, PeriodosProcesados, Estado
FROM dbo.ETL_ARCHIVOS
ORDER BY IdArchivo DESC;
```

---

## Trampas

1. **Ceros iniciales**: nunca `CAST(CodigoProducto AS int)` ni quitar ceros; 0123456 ≠ 123456 en los datos de ejemplo.
2. **Unir PRODUCTOS por código sin índice único**: si en algún cierre se cuela un código repetido, `LEFT JOIN dbo.PRODUCTOS` duplica las ventas. Para el nombre en reportes basta `MAX(VENTAS.Producto)`.
