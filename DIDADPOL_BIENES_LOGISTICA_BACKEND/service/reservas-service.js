const pool = require('../DB/db');

// ==============================
// RESERVAR
// ==============================
async function reservar(data) {
  const {
    id_bodega,
    id_bien = null,
    id_bien_lote = null,
    cantidad,
    solicitante = null,
    motivo = null
  } = data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `CALL sp_inventario_reservar($1, $2, $3, $4);`,
      [id_bodega, id_bien, id_bien_lote, cantidad]
    );

    await client.query(
      `INSERT INTO historial_reservas
       (id_bodega, id_bien, cantidad, accion, usuario, solicitante, motivo)
       VALUES ($1, $2, $3, 'RESERVAR', $4, $5, $6);`,
      [
        id_bodega,
        id_bien,
        cantidad,
        data.usuario || 'sistema',
        solicitante,
        motivo
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


// ==============================
// LIBERAR
// ==============================
async function liberar(data) {
  const { id_bodega, id_bien = null, id_bien_lote = null, cantidad } = data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `CALL sp_inventario_liberar_reserva($1, $2, $3, $4);`,
      [id_bodega, id_bien, id_bien_lote, cantidad]
    );

    // HISTORIAL
    await client.query(
      `INSERT INTO historial_reservas
       (id_bodega, id_bien, cantidad, accion, usuario)
       VALUES ($1, $2, $3, 'LIBERAR', $4);`,
      [
        id_bodega,
        id_bien,
        cantidad,
        data.usuario || 'sistema'
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


// ==============================
// CONSUMIR
// ==============================
async function consumir(data) {
  const { id_bodega, id_bien = null, id_bien_lote = null, cantidad } = data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `CALL sp_inventario_consumir_reserva($1, $2, $3, $4);`,
      [id_bodega, id_bien, id_bien_lote, cantidad]
    );

    // HISTORIAL
    await client.query(
      `INSERT INTO historial_reservas
       (id_bodega, id_bien, cantidad, accion, usuario)
       VALUES ($1, $2, $3, 'CONSUMIR', $4);`,
      [
        id_bodega,
        id_bien,
        cantidad,
        data.usuario || 'sistema'
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


// ==============================
// LISTAR (ACTUAL)
// ==============================
async function listarReservas() {
  const client = await pool.connect();
  try {
    const result = await client.query(`
      SELECT
        i.id_bodega,
        i.id_bien,
        i.stock_reservado,
        hr.solicitante,
        hr.motivo
      FROM inventario i
      LEFT JOIN LATERAL (
        SELECT solicitante, motivo
        FROM historial_reservas
        WHERE id_bodega = i.id_bodega
          AND id_bien = i.id_bien
          AND accion = 'RESERVAR'
        ORDER BY fecha DESC
        LIMIT 1
      ) hr ON TRUE
      WHERE i.stock_reservado > 0
    `);

    return result.rows;

  } catch (error) {
    console.error('Error en listarReservas:', error);
    throw error;
  } finally {
    client.release();
  }
}

// ==============================
// LISTAR HISTORIAL
// ==============================

async function listarHistorial() {
  const client = await pool.connect();
  try {
    const result = await client.query(`
      SELECT 
        id_historial,
        id_bodega,
        id_bien,
        cantidad,
        accion,
        fecha,
        usuario
      FROM public.historial_reservas
      ORDER BY fecha DESC
    `);

    return result.rows;

  } catch (error) {
    console.error('[ERROR] ERROR HISTORIAL:', error.message, error.stack);
    throw new Error('Error consultando historial_reservas');
  } finally {
    client.release();
  }
}

module.exports = {
  reservar,
  liberar,
  consumir,
  listarReservas,
  listarHistorial
};