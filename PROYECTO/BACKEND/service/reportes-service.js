const pool = require('../DB/db');

// REPORTE 1 — Stock crítico
async function stockCritico() {
  const { rows } = await pool.query(`
    SELECT
      b.nombre_bodega,
      bi.nombre_bien,
      ROUND(i.stock_actual,2) AS stock_actual,
      ROUND(COALESCE(i.stock_minimo, bi.stock_minimo),2) AS stock_minimo,
      ROUND(i.stock_reservado,2) AS stock_reservado
    FROM inventario i
    JOIN bodega b ON b.id_bodega = i.id_bodega
    JOIN bien bi ON bi.id_bien = i.id_bien
    WHERE COALESCE(i.stock_minimo, bi.stock_minimo) IS NOT NULL
      AND i.stock_actual <= COALESCE(i.stock_minimo, bi.stock_minimo)
    ORDER BY b.nombre_bodega, bi.nombre_bien
  `);

  return rows;
}

// REPORTE 2 — Solicitudes por Estado
async function solicitudesPorEstado() {
  const { rows } = await pool.query(`
    SELECT 
      es.nombre_estado,
      COUNT(sl.id_solicitud)::INTEGER AS total
    FROM estado_solicitud es
    LEFT JOIN solicitud_logistica sl
      ON sl.id_estado_solicitud = es.id_estado_solicitud
    GROUP BY es.nombre_estado
    ORDER BY es.nombre_estado
  `);

  return rows;
}

// REPORTE 3 — Bienes Más Solicitados
async function bienesMasSolicitados() {
  const { rows } = await pool.query(`
    SELECT
      b.nombre_bien,
      ROUND(COALESCE(SUM(sd.cantidad),0),2) AS total_solicitado,
      COUNT(DISTINCT sl.id_solicitud)::INTEGER AS total_solicitudes
    FROM solicitud_detalle sd
    JOIN solicitud_logistica sl ON sl.id_solicitud = sd.id_solicitud
    JOIN estado_solicitud es ON es.id_estado_solicitud = sl.id_estado_solicitud
    JOIN bien b ON b.id_bien = sd.id_bien
    WHERE es.nombre_estado NOT IN ('RECHAZADA','CANCELADA')
    GROUP BY b.nombre_bien
    HAVING COALESCE(SUM(sd.cantidad),0) > 0
    ORDER BY total_solicitado DESC
  `);

  return rows;
}

// REPORTE 4 — Inventario Valorizado
async function inventarioValorizado() {
  const { rows } = await pool.query(`
    SELECT
      b.id_bodega,
      b.nombre_bodega,
      COUNT(DISTINCT i.id_bien)::INTEGER AS total_bienes,

      ROUND(COALESCE(SUM(i.stock_actual),0),2) AS total_stock,
      ROUND(COALESCE(SUM(i.stock_reservado),0),2) AS total_reservado,
      ROUND(COALESCE(SUM(GREATEST(i.stock_actual - i.stock_reservado, 0)),0),2) AS total_disponible,

      ROUND(COALESCE(SUM(i.stock_actual * COALESCE(bi.valor_unitario, 0)),0),2) AS valor_total_inventario,
      ROUND(COALESCE(SUM(i.stock_reservado * COALESCE(bi.valor_unitario, 0)),0),2) AS valor_total_reservado,
      ROUND(COALESCE(SUM(GREATEST(i.stock_actual - i.stock_reservado, 0) * COALESCE(bi.valor_unitario, 0)),0),2) AS valor_total_disponible

    FROM inventario i
    JOIN bodega b ON b.id_bodega = i.id_bodega
    JOIN bien bi ON bi.id_bien = i.id_bien
    WHERE i.estado_inventario = 'ACTIVO'
    GROUP BY b.id_bodega, b.nombre_bodega
    ORDER BY b.nombre_bodega
  `);

  return rows;
}

// REPORTE 5 — Ejecutivo Completo (DASHBOARD)
async function reporteEjecutivoCompleto() {
  const { rows } = await pool.query(`
    SELECT
      b.id_bodega,
      b.nombre_bodega,

      COUNT(DISTINCT i.id_bien)::INTEGER AS total_bienes,

      ROUND(COALESCE(SUM(i.stock_actual),0),2) AS total_stock,
      ROUND(COALESCE(SUM(i.stock_reservado),0),2) AS total_reservado,
      ROUND(COALESCE(SUM(GREATEST(i.stock_actual - i.stock_reservado, 0)),0),2) AS total_disponible,

      ROUND(COALESCE(SUM(i.stock_actual * COALESCE(bi.valor_unitario, 0)),0),2) AS valor_total_inventario,
      ROUND(COALESCE(SUM(i.stock_reservado * COALESCE(bi.valor_unitario, 0)),0),2) AS valor_total_reservado,
      ROUND(COALESCE(SUM(GREATEST(i.stock_actual - i.stock_reservado, 0) * COALESCE(bi.valor_unitario, 0)),0),2) AS valor_total_disponible,

      (
        SELECT COUNT(*)::INTEGER
        FROM asignacion_bien ab
        JOIN registro r ON r.id_registro = ab.id_registro
        WHERE ab.estado_asignacion = 'ACTIVA'
          AND r.id_bodega_origen = b.id_bodega
      ) AS total_asignaciones_activas,

      (
        SELECT ROUND(COALESCE(SUM(rd.cantidad),0),2)
        FROM asignacion_bien ab
        JOIN registro r ON r.id_registro = ab.id_registro
        JOIN registro_detalle rd
          ON rd.id_registro = r.id_registro
         AND rd.id_bien = ab.id_bien
        WHERE ab.estado_asignacion = 'ACTIVA'
          AND r.id_bodega_origen = b.id_bodega
      ) AS total_bienes_asignados,

      (
        SELECT ROUND(COALESCE(SUM(rd.cantidad),0),2)
        FROM registro r
        JOIN registro_detalle rd ON rd.id_registro = r.id_registro
        JOIN tipo_registro tr ON tr.id_tipo_registro = r.id_tipo_registro
        WHERE r.estado_registro = 'CONFIRMADO'
          AND r.id_bodega_origen = b.id_bodega
          AND tr.signo_movimiento < 0
      ) AS total_salidas,

      (
        SELECT ROUND(COALESCE(SUM(rd.cantidad),0),2)
        FROM registro r
        JOIN registro_detalle rd ON rd.id_registro = r.id_registro
        JOIN tipo_registro tr ON tr.id_tipo_registro = r.id_tipo_registro
        WHERE r.estado_registro = 'CONFIRMADO'
          AND (r.id_bodega_destino = b.id_bodega
               OR (r.id_bodega_origen = b.id_bodega AND tr.signo_movimiento > 0))
      ) AS total_entradas

    FROM inventario i
    JOIN bodega b ON b.id_bodega = i.id_bodega
    JOIN bien bi ON bi.id_bien = i.id_bien

    GROUP BY b.id_bodega, b.nombre_bodega
    ORDER BY b.nombre_bodega
  `);

  return rows;
}

module.exports = {
  stockCritico,
  solicitudesPorEstado,
  bienesMasSolicitados,
  inventarioValorizado,
  reporteEjecutivoCompleto
};