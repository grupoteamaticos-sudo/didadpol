const pool = require('../DB/db');

async function obtenerKardex({
  id_bien = null,
  id_bodega = null,
  fecha_inicio = null,
  fecha_fin = null
}) {

  let sql = `
    SELECT
      id_bodega,
      id_bien,
      fecha,
      accion AS tipo,
      cantidad,
      usuario
    FROM historial_reservas
    WHERE 1=1
  `;

  const params = [];
  let index = 1;

  if (id_bien) {
    sql += ` AND id_bien = $${index++}`;
    params.push(id_bien);
  }

  if (id_bodega) {
    sql += ` AND id_bodega = $${index++}`;
    params.push(id_bodega);
  }

  if (fecha_inicio) {
    sql += ` AND fecha >= $${index++}`;
    params.push(fecha_inicio);
  }

  if (fecha_fin) {
    sql += ` AND fecha <= $${index++}`;
    params.push(fecha_fin);
  }

  sql += ` ORDER BY id_bodega, id_bien, fecha ASC`;

  const { rows } = await pool.query(sql, params);

  const saldoMap = new Map();

  return rows.map((r) => {
    const key = `${r.id_bodega}-${r.id_bien}`;
    const prevSaldo = saldoMap.get(key) || 0;

    const cantidad = Number(r.cantidad);
    let entrada = 0;
    let salida = 0;
    let saldo = prevSaldo;

    if (r.tipo === 'LIBERAR') {
      entrada = cantidad;
      saldo = prevSaldo + cantidad;
    } else if (r.tipo === 'RESERVAR' || r.tipo === 'CONSUMIR') {
      salida = cantidad;
      saldo = prevSaldo - cantidad;
    } else if (r.tipo === 'AJUSTE') {
      saldo = cantidad;
      const delta = cantidad - prevSaldo;
      if (delta >= 0) {
        entrada = delta;
      } else {
        salida = Math.abs(delta);
      }
    }

    saldoMap.set(key, saldo);

    return {
      id_bodega: r.id_bodega,
      id_bien: r.id_bien,
      fecha: r.fecha,
      tipo: r.tipo,
      entrada,
      salida,
      saldo,
      usuario: r.usuario
    };
  });
}

module.exports = {
  obtenerKardex
};
