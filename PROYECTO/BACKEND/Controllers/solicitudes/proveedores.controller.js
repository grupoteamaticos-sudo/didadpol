const pool = require('../../DB/db');

const listarProveedores = async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT id_proveedor, nombre_proveedor, rtn_proveedor, categoria_servicio,
             especialidad, contacto_representante, telefono_contacto, correo_contacto,
             estado_proveedor
      FROM proveedor
      WHERE estado_proveedor = 'ACTIVO'
      ORDER BY nombre_proveedor
    `);
    res.json({ ok: true, data: rows });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

const crearProveedor = async (req, res) => {
  try {
    const { nombre_proveedor, rtn_proveedor, categoria_servicio } = req.body;

    if (!nombre_proveedor || !String(nombre_proveedor).trim()) {
      return res.status(400).json({ ok: false, message: 'El nombre es obligatorio' });
    }

    const { rows } = await pool.query(
      `INSERT INTO proveedor (nombre_proveedor, rtn_proveedor, categoria_servicio, estado_proveedor)
       VALUES ($1, $2, $3, 'ACTIVO')
       RETURNING id_proveedor, nombre_proveedor`,
      [
        String(nombre_proveedor).trim(),
        rtn_proveedor || null,
        categoria_servicio || null
      ]
    );
    res.status(201).json({ ok: true, data: rows[0] });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

const eliminarProveedor = async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!id) {
      return res.status(400).json({ ok: false, message: 'ID invalido' });
    }

    const result = await pool.query(
      `UPDATE proveedor
         SET estado_proveedor = 'INACTIVO'
       WHERE id_proveedor = $1
       RETURNING id_proveedor`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ ok: false, message: 'Proveedor no encontrado' });
    }

    res.json({ ok: true, message: 'Proveedor eliminado' });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

module.exports = {
  listarProveedores,
  crearProveedor,
  eliminarProveedor
};
