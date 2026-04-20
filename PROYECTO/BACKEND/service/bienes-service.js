const pool = require('../DB/db');

async function listarBienes() {
  const sql = `
    SELECT 
      id_bien,
      codigo_inventario,
      nombre_bien
    FROM bien
    ORDER BY nombre_bien ASC
  `;

  const { rows } = await pool.query(sql);
  return rows;
}

module.exports = {
  listarBienes
};