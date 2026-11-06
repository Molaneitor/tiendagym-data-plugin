# Entidades

## Línea de venta
- **Definición**: un producto dentro de una factura.
- **Tabla principal**: `dbo.VENTAS`
- **ID**: `IdVenta` (interno). No hay llave natural: el mismo producto puede repetirse en una factura.
- **Relaciones**: pertenece a una factura; apunta a un producto, un cliente y un vendedor.
- **Filtros comunes**: sin NO VALIDO por mes.

## Factura
- **Definición**: documento de venta de DreamSoft.
- **Tabla principal**: `dbo.VENTAS` (no hay tabla de encabezados).
- **ID**: `TipoDocumento + NumeroDocumento` (880 actual; 882 anterior; numeración continua).
- **Relaciones**: 1 a muchos con líneas; con COSTOS por `TipoDocumento + NumeroDocumento` (+ `CodigoProducto`).
- **Filtros comunes**: las facturas a nombre de empleados son ajustes de inventario, no ventas (deberían estar borradas; si aparecen, proponer borrarlas con evidencia y OK).
- **Valor de la factura**: `SUM(NetoDocumento)` o `SUM(ValorFinal)` de sus líneas. `NetoDocumento` es valor de **línea**, no del documento.

## Cliente
- **Definición**: tercero al que se factura (personas, gimnasios, empresas).
- **Tabla principal**: `dbo.VENTAS` (`CLIENTES` está vacía).
- **ID**: `CodigoCliente` (cédula o NIT). `Cliente` es el nombre y puede variar entre facturas: agrupar por código.
- **Nuevo vs recurrente**: nuevo si su primera compra (en todo el historial) cae en el mes analizado. El modelo de Power BI tiene dos definiciones (la medida `Clientes Nuevos` usa "mismo día"; la columna `Tipo Cliente`, "mismo mes"): usar "mismo mes".
- **Filtros comunes**: excluir empleados (se buscan en el cliente, no en el vendedor).

## Producto
- **Definición**: artículo del inventario (máquina, pesa, accesorio) o servicio (flete).
- **Tabla principal**: `dbo.PRODUCTOS` (maestro); el nombre del documento está en `VENTAS.Producto` y `COSTOS_SALDO_MENSUAL.Producto`.
- **ID**: `CodigoProducto`, texto. **Ceros iniciales significativos**: 0123456 y 123456 son productos distintos (posibles duplicados pendientes de revisar en DreamSoft, pero se tratan como distintos).
- **Relaciones**: muchos a uno desde VENTAS y COSTOS (sin FK; puede haber ventas sin ficha).
- **Filtros comunes**: NO VALIDO por mes; las excepciones (`ES-01` en los datos de ejemplo) siempre cuentan.

## Vendedor (asesor)
- **Definición**: quien registró la venta.
- **Tabla principal**: `dbo.VENTAS` (`ASESORES` está vacía).
- **ID**: `CodigoVendedor`; nombre en `Vendedor`.
- **Ojo**: aparecer como vendedor no convierte una factura en ajuste; los ajustes se identifican por el **cliente**.

## Movimiento de inventario
- **Definición**: entrada, salida, venta o compra en el kardex.
- **Tabla principal**: `dbo.COSTOS`
- **ID**: `IdCosto`.
- **Relaciones**: los de venta (`TipoMovimiento = 'V'`) se cruzan con VENTAS por `TipoDocumento + NumeroDocumento + CodigoProducto`, agregando ambos lados.

## Saldo mensual
- **Definición**: inventario por producto al cierre de un mes.
- **Tabla principal**: `dbo.COSTOS_SALDO_MENSUAL`
- **ID**: `Periodo + CodigoProducto` (único).
- **Ojo**: omite productos que cierran en cero; solo `FinalPesos` es confiable. Existe solo desde que se carga el inv0260.
