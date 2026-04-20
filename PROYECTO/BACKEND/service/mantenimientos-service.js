const pool = require('../DB/db');

async function listarMantenimientos() {
  const { rows } = await pool.query(`
    SELECT
      m.id_mantenimiento,
      m.id_bien,
      b.codigo_inventario,
      b.nombre_bien,
      m.id_tipo_mantenimiento,
      tm.nombre_tipo_mantenimiento,
      m.id_proveedor,
      pr.nombre_proveedor,
      m.fecha_programada,
      m.fecha_inicio,
      m.fecha_fin,
      m.kilometraje,
      m.descripcion_mantenimiento,
      m.costo_mantenimiento,
      m.estado_mantenimiento,
      m.observaciones_mantenimiento,
      m.fecha_registro
    FROM mantenimiento m
    LEFT JOIN bien b ON b.id_bien = m.id_bien
    LEFT JOIN tipo_mantenimiento tm ON tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento
    LEFT JOIN proveedor pr ON pr.id_proveedor = m.id_proveedor
    ORDER BY m.id_mantenimiento DESC
  `);
  return rows;
}

async function catalogos() {
  const tipos = await pool.query(`
    SELECT id_tipo_mantenimiento, nombre_tipo_mantenimiento
    FROM tipo_mantenimiento
    WHERE estado_tipo_mantenimiento = 'ACTIVO'
    ORDER BY nombre_tipo_mantenimiento
  `);
  const proveedores = await pool.query(`
    SELECT id_proveedor, nombre_proveedor
    FROM proveedor
    WHERE estado_proveedor = 'ACTIVO'
    ORDER BY nombre_proveedor
  `);
  return { tipos: tipos.rows, proveedores: proveedores.rows };
}

async function programarMantenimiento(payload) {
  const {
    id_bien,
    id_tipo_mantenimiento,
    id_proveedor,
    fecha_programada,
    kilometraje,
    descripcion,
    observaciones,
    id_usuario,
    ip_origen
  } = payload;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `CALL sp_mantenimiento_programar(
        $1,$2,$3,NULL,$4,$5,$6,$7,$8,$9,NULL,NULL
      );`,
      [
        id_bien,
        id_tipo_mantenimiento || null,
        id_proveedor || null,
        fecha_programada || null,
        kilometraje || null,
        descripcion,
        observaciones || null,
        id_usuario,
        ip_origen
      ]
    );
    await client.query('COMMIT');
    return rows?.[0] || { ok: true };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function iniciarMantenimiento(payload) {
  const { id_mantenimiento, fecha_inicio, kilometraje, observaciones, id_usuario, ip_origen } = payload;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `CALL sp_mantenimiento_iniciar($1,$2,$3,$4,$5,$6,NULL);`,
      [
        id_mantenimiento,
        fecha_inicio || null,
        kilometraje || null,
        observaciones || null,
        id_usuario,
        ip_origen
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

async function finalizarMantenimiento(payload) {
  const { id_mantenimiento, fecha_fin, costo, observaciones, id_usuario, ip_origen } = payload;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `CALL sp_mantenimiento_finalizar($1,$2,$3,$4,$5,$6,NULL);`,
      [
        id_mantenimiento,
        fecha_fin || null,
        costo || null,
        observaciones || null,
        id_usuario,
        ip_origen
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

module.exports = {
  listarMantenimientos,
  catalogos,
  programarMantenimiento,
  iniciarMantenimiento,
  finalizarMantenimiento
};
