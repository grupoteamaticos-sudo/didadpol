const pool = require('../DB/db');

/* =========================
   DEPARTAMENTOS
========================= */
async function listarDepartamentos() {
  const { rows } = await pool.query(`
    SELECT id_departamento, nombre_departamento
    FROM departamento
    ORDER BY nombre_departamento;
  `);
  return rows;
}

/* =========================
   PUESTOS
========================= */
async function listarPuestos() {
  const { rows } = await pool.query(`
    SELECT id_puesto, nombre_puesto
    FROM puesto
    ORDER BY nombre_puesto;
  `);
  return rows;
}

/* =========================
   SUCURSALES
========================= */
async function listarSucursales() {
  const { rows } = await pool.query(`
    SELECT id_sucursal, nombre_sucursal
    FROM sucursal
    ORDER BY nombre_sucursal;
  `);
  return rows;
}

module.exports = {
  listarDepartamentos,
  listarPuestos,
  listarSucursales
};