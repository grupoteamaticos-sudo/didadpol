const pool = require('../DB/db');

async function crearSolicitud(data) {
  const {
    id_empleado,
    id_tipo_solicitud,
    descripcion_solicitud,
    prioridad
  } = data;

  const { rows } = await pool.query(
    `INSERT INTO solicitud_logistica
     (id_empleado, id_tipo_solicitud, id_estado_solicitud, prioridad, descripcion_solicitud)
     VALUES ($1, $2, 1, $3, $4)
     RETURNING id_solicitud`,
    [id_empleado, id_tipo_solicitud, prioridad, descripcion_solicitud]
  );

  return rows[0];
}

async function agregarDetalle(data) {
  const {
    id_solicitud,
    id_bien,
    cantidad,
    descripcion_item,
    justificacion
  } = data;

  const { rows } = await pool.query(
    `INSERT INTO solicitud_detalle
     (id_solicitud, id_bien, cantidad, descripcion_item, justificacion)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id_solicitud_detalle`,
    [id_solicitud, id_bien, cantidad, descripcion_item, justificacion]
  );

  return rows[0];
}

async function cambiarEstado(data) {
  const {
    id_solicitud,
    id_estado_nuevo,
    id_bodega_reserva,
    id_usuario,
    ip_origen,
    observacion
  } = data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `CALL sp_solicitud_cambiar_estado_y_reservar(
        $1, $2, $3, $4, $5, $6, NULL
      )`,
      [
        id_solicitud,
        id_estado_nuevo,
        id_bodega_reserva,
        id_usuario,
        ip_origen,
        observacion
      ]
    );

    await client.query('COMMIT');
    return { ok: true };

  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function generarRegistroSalida(data) {
  const {
    id_solicitud,
    id_usuario,
    id_bodega_origen,
    ip_origen
  } = data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      `CALL sp_solicitud_generar_registro_salida(
        $1, 3, $2, $3, NULL, NULL, $4, NULL, NULL
      )`,
      [
        id_solicitud,
        id_usuario,
        id_bodega_origen,
        ip_origen
      ]
    );

    await client.query('COMMIT');
    return { ok: true };

  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function eliminarSolicitud(id_solicitud) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Si está APROBADA y tiene reserva activa, liberarla primero
    const { rows: est } = await client.query(
      `SELECT UPPER(COALESCE(es.nombre_estado,'')) AS estado
         FROM solicitud_logistica sl
         LEFT JOIN estado_solicitud es ON es.id_estado_solicitud = sl.id_estado_solicitud
        WHERE sl.id_solicitud = $1`,
      [id_solicitud]
    );

    if (est[0]?.estado?.includes('APROBAD')) {
      const { rows: detalles } = await client.query(
        `SELECT id_bien, cantidad FROM solicitud_detalle WHERE id_solicitud = $1`,
        [id_solicitud]
      );
      for (const d of detalles) {
        if (!d.id_bien) continue;
        await client.query(
          `UPDATE inventario
             SET stock_reservado = GREATEST(0, stock_reservado - $1),
                 fecha_ultima_actualizacion = NOW()
           WHERE id_bien = $2 AND stock_reservado >= $1`,
          [d.cantidad, d.id_bien]
        );
      }
    }

    await client.query('DELETE FROM solicitud_detalle WHERE id_solicitud=$1', [id_solicitud]);
    await client.query('DELETE FROM solicitud_logistica WHERE id_solicitud=$1', [id_solicitud]);

    await client.query('COMMIT');
    return { ok: true };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function getSolicitudes() {
  const { rows } = await pool.query(`
    SELECT 
      sl.id_solicitud,
      sl.fecha_solicitud,
      sl.descripcion_solicitud,
      sl.prioridad,

      es.nombre_estado,
      ts.nombre_tipo_solicitud,

      p.primer_nombre || ' ' || p.primer_apellido AS empleado

    FROM solicitud_logistica sl
    LEFT JOIN estado_solicitud es 
      ON es.id_estado_solicitud = sl.id_estado_solicitud
    LEFT JOIN tipo_solicitud ts 
      ON ts.id_tipo_solicitud = sl.id_tipo_solicitud
    LEFT JOIN empleado e 
      ON e.id_empleado = sl.id_empleado
    LEFT JOIN persona p 
      ON p.id_persona = e.id_persona

    ORDER BY sl.id_solicitud DESC
  `);

  return rows;
}

async function getEstadosSolicitud() {
  const { rows } = await pool.query(`
    SELECT id_estado_solicitud, nombre_estado
    FROM estado_solicitud
    ORDER BY id_estado_solicitud
  `);
  return rows;
}

async function getTiposSolicitud() {
  const { rows } = await pool.query(`
    SELECT id_tipo_solicitud, nombre_tipo_solicitud
    FROM tipo_solicitud
    WHERE estado_tipo_solicitud = 'ACTIVO'
    ORDER BY nombre_tipo_solicitud
  `);
  return rows;
}

module.exports = {
  crearSolicitud,
  agregarDetalle,
  cambiarEstado,
  generarRegistroSalida,
  eliminarSolicitud,
  getSolicitudes,
  getEstadosSolicitud,
  getTiposSolicitud
};