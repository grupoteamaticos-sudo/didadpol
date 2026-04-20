const pool = require('../DB/db');

//Crear Asignacion

async function crearAsignacion(payload) {
  const {
    id_tipo_registro_asignacion,
    id_usuario,
    ip_origen,
    id_empleado,
    id_bodega_origen,
    id_bien,
    id_bien_item,
    cantidad,
    tipo_acta,
    numero_acta,
    fecha_emision_acta,
    motivo_asignacion,
    observaciones,
    archivo_pdf,
    firma_digital
  } = payload;

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // Construir query con valores inline para poder usar DO block con variables OUT
    const escape = (v) => v === null || v === undefined ? 'NULL' : typeof v === 'string' ? `'${v.replace(/'/g, "''")}'` : v;

    await client.query(`
      DO $$
      DECLARE
        v_id_asignacion BIGINT;
        v_id_registro BIGINT;
        v_id_log BIGINT;
      BEGIN
        CALL sp_asignacion_crear(
          ${escape(id_tipo_registro_asignacion)},
          ${escape(id_usuario)},
          ${escape(ip_origen)},
          ${escape(id_empleado)},
          ${escape(id_bodega_origen)},
          ${escape(id_bien)},
          ${escape(id_bien_item)},
          ${escape(cantidad)},
          ${escape(tipo_acta)},
          ${escape(numero_acta)},
          ${escape(fecha_emision_acta)},
          ${escape(motivo_asignacion)},
          ${escape(observaciones)},
          ${escape(archivo_pdf)},
          ${escape(firma_digital)},
          v_id_asignacion,
          v_id_registro,
          v_id_log
        );
      END $$;
    `);

    await client.query('COMMIT');

    return { ok: true };

  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

//Devolver Asignacion 

async function devolverAsignacion(payload) {
  const {
    id_asignacion,
    id_tipo_registro_devolucion,
    id_usuario,
    ip_origen,
    id_bodega_destino,
    id_bien_item,
    cantidad,
    observaciones
  } = payload;

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    await client.query(
      `CALL sp_asignacion_devolver(
        $1,$2,$3,$4,
        $5,$6,$7,$8,
        NULL,NULL
      );`,
      [
        id_asignacion,
        id_tipo_registro_devolucion,
        id_usuario,
        ip_origen,
        id_bodega_destino,
        id_bien_item,
        cantidad,
        observaciones
      ]
    );

    await client.query('COMMIT');

    return { ok: true };

  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function getAsignaciones() {
  const { rows } = await pool.query(`
    SELECT 
      ab.id_asignacion,
      ab.tipo_acta,
      ab.numero_acta,
      ab.fecha_entrega_bien,
      ab.estado_asignacion,

      b.nombre_bien,

      p.primer_nombre || ' ' || p.primer_apellido AS empleado

    FROM asignacion_bien ab
    LEFT JOIN bien b 
      ON b.id_bien = ab.id_bien
    LEFT JOIN empleado e 
      ON e.id_empleado = ab.id_empleado
    LEFT JOIN persona p 
      ON p.id_persona = e.id_persona

    ORDER BY ab.id_asignacion DESC
  `);

  return rows;
}

module.exports = {
  crearAsignacion,
  devolverAsignacion,
  getAsignaciones
};