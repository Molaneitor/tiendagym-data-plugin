-- Esquema de los datos de ejemplo de TiendaGymBI (SQL Server 2017+).
-- Mismas tablas, columnas y tipos que la base real. Diferencias a propósito, para poder cargar los CSV:
--   * Los Id son int simples (en producción son IDENTITY).
--   * VENTAS_VALIDACION_DIARIA.ValorRealEsperado es una columna normal; en producción es calculada:
--       ValorRealEsperado AS (ValorVentaNeta - ValorDevuelto) PERSISTED
--
-- Uso (crear antes la base vacía):
--   sqlcmd -S "<servidor>\<instancia>" -E -C -d TiendaGymBI -i schema.sql -v SampleDir="<ruta completa de sample-data>"
-- CodigoProducto es texto: 0123456 y 123456 son productos distintos.

SET NOCOUNT ON;

CREATE TABLE dbo.VENTAS (
    IdVenta          int            NOT NULL PRIMARY KEY,
    AnoDoc           int            NULL,
    PeriodoDoc       int            NULL,
    TipoDocumento    varchar(20)    NULL,
    NumeroDocumento  varchar(50)    NULL,
    FechaDocumento   date           NULL,
    CodigoCliente    varchar(50)    NULL,
    Cliente          varchar(200)   NULL,
    CodigoProducto   varchar(50)    NULL,
    Producto         varchar(300)   NULL,
    Cantidad         decimal(18,2)  NULL,
    PrecioVenta      decimal(18,2)  NULL,
    ValorDescuento   decimal(18,2)  NULL,
    ValorIVA         decimal(18,2)  NULL,
    ValorFinal       decimal(18,2)  NULL,
    PrecioTotal      decimal(18,2)  NULL,
    Estado           int            NULL,
    CodigoVendedor   varchar(50)    NULL,
    Vendedor         varchar(200)   NULL,
    NetoDocumento    decimal(18,2)  NULL
);

CREATE TABLE dbo.COSTOS (
    IdCosto               int            NOT NULL PRIMARY KEY,
    TipoMovimiento        varchar(5)     NULL,
    CodigoProducto        varchar(50)    NULL,
    FechaDocumento        date           NULL,
    AnoDoc                int            NULL,
    TipoDocumento         varchar(20)    NULL,
    NumeroDocumento       varchar(50)    NULL,
    CodigoBodega          varchar(20)    NULL,
    Cantidad              decimal(18,2)  NULL,
    CostoUnitario         decimal(18,2)  NULL,
    CostoTotal            decimal(18,2)  NULL,
    SalidaUnidades        decimal(18,2)  NULL,
    SalidaPesos           decimal(18,2)  NULL,
    SaldoParcialUnidades  decimal(18,2)  NULL,
    SaldoParcialPesos     decimal(18,2)  NULL,
    NombreArchivo         varchar(300)   NULL,
    FechaCarga            datetime       NULL
);
CREATE UNIQUE INDEX UX_COSTOS_Movimiento
    ON dbo.COSTOS (CodigoProducto, FechaDocumento, NumeroDocumento, TipoMovimiento, Cantidad, CostoTotal);

CREATE TABLE dbo.COSTOS_SALDO_MENSUAL (
    IdSaldo          int            NOT NULL PRIMARY KEY,
    Periodo          char(7)        NOT NULL,
    CodigoProducto   varchar(50)    NOT NULL,
    Producto         varchar(300)   NULL,
    UnidadMedida     varchar(20)    NULL,
    InicialPesos     decimal(18,2)  NULL,
    EntradaPesos     decimal(18,2)  NULL,
    SalidaPesos      decimal(18,2)  NULL,
    FinalPesos       decimal(18,2)  NULL,
    InicialUnidades  decimal(18,2)  NULL,
    EntradaUnidades  decimal(18,2)  NULL,
    SalidaUnidades   decimal(18,2)  NULL,
    FinalUnidades    decimal(18,2)  NULL,
    NombreArchivo    varchar(300)   NULL,
    FechaCarga       datetime       NULL
);
CREATE UNIQUE INDEX UX_SaldoMensual_Periodo_Producto ON dbo.COSTOS_SALDO_MENSUAL (Periodo, CodigoProducto);

CREATE TABLE dbo.VENTAS_VALIDACION_DIARIA (
    IdValidacion       int            NOT NULL PRIMARY KEY,
    FechaDocumento     date           NOT NULL,
    CantidadVendida    int            NULL,
    ValorBruto         decimal(18,2)  NULL,
    ValorDescuento     decimal(18,2)  NULL,
    ValorVentaNeta     decimal(18,2)  NULL,
    CantidadDevuelta   int            NULL,
    ValorDevuelto      decimal(18,2)  NULL,
    ValorRealEsperado  decimal(19,2)  NULL,
    NombreArchivo      varchar(300)   NULL,
    FechaCarga         datetime       NULL
);
CREATE UNIQUE INDEX UX_VALIDACION_Fecha ON dbo.VENTAS_VALIDACION_DIARIA (FechaDocumento);

CREATE TABLE dbo.PRODUCTOS (
    IdProducto      int            NOT NULL PRIMARY KEY,
    CodigoProducto  varchar(50)    NULL,
    NombreProducto  varchar(300)   NULL,
    Categoria       varchar(150)   NULL,
    SubCategoria    varchar(150)   NULL,
    Marca           varchar(100)   NULL,
    PrecioActual    decimal(18,2)  NULL,
    Activo          bit            NULL
);
GO

-- Carga de los CSV (UTF-8, con encabezado, fin de línea LF: ver .gitattributes). La ruta se lee desde el servidor de SQL Server.
BULK INSERT dbo.VENTAS                   FROM '$(SampleDir)\ventas.csv'                   WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT dbo.COSTOS                   FROM '$(SampleDir)\costos.csv'                   WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT dbo.COSTOS_SALDO_MENSUAL     FROM '$(SampleDir)\costos_saldo_mensual.csv'     WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT dbo.VENTAS_VALIDACION_DIARIA FROM '$(SampleDir)\ventas_validacion_diaria.csv' WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT dbo.PRODUCTOS                FROM '$(SampleDir)\productos.csv'                WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
GO
