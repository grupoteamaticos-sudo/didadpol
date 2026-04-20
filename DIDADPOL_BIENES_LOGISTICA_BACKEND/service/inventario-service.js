const pool = require('../DB/db');
const { reservar } = require('./reservas-service');

async function obtenerInventario({ id_bodega = null, id_bien = null }) {

  let sql = `
  SELECT 
    i.id_inventario,
    i.id_bodega,
    bodega.nombre_bodega,
    i.id_bien,
    bien.nombre_bien,

    ROUND(i.stock_actual,2) AS stock_actual,
    ROUND(i.stock_reservado,2) AS stock_reservado,
    ROUND(i.stock_actual - i.stock_reservado,2) AS stock_disponible,

    i.stock_minimo,
    i.estado_inventario,

    ROUND(COALESCE(bien.valor_unitario,0),2) AS valor_unitario,
    ROUND(i.stock_actual * COALESCE(bien.valor_unitario,0),2) AS valor_total

  FROM inventario i
  JOIN bodega ON bodega.id_bodega = i.id_bodega
  JOIN bien ON bien.id_bien = i.id_bien
  WHERE 1=1
`;

  const params = [];
  let index = 1;

  if (id_bodega) {
    sql += ` AND i.id_bodega = $${index++}`;
    params.push(id_bodega);
  }

  if (id_bien) {
    sql += ` AND i.id_bien = $${index++}`;
    params.push(id_bien);
  }

  sql += ` ORDER BY bodega.nombre_bodega, bien.nombre_bien`;

  const { rows } = await pool.query(sql, params);
  return rows;
}

const reservarInventario = async ({ id_bodega, id_bien, id_bien_lote, cantidad }) => {

  const query = `
    CALL sp_inventario_reservar($1, $2, $3, $4)
  `;

  return await db.query(query, [
    id_bodega,
    id_bien || null,
    id_bien_lote || null,
    cantidad
  ]);
};

module.exports = {
  obtenerInventario,
  reservarInventario
};