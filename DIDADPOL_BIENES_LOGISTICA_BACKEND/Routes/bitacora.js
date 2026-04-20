const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');
const { checkPermission } = require('../Middlewares/validar-permiso');
const pool = require('../DB/db');

const router = Router();

// Listar logs de bitacora
router.get('/', validarJWT, checkPermission('BITACORA_VER'), async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT
        l.id_log_usuario,
        l.fecha_accion,
        l.hora_accion,
        l.tipo_accion,
        l.tabla_afectada,
        l.registro_afectado,
        l.ip_origen,
        l.descripcion_log,
        u.nombre_usuario
      FROM log_usuario l
      LEFT JOIN usuario u ON u.id_usuario = l.id_usuario
      ORDER BY l.id_log_usuario DESC
      LIMIT 500
    `);
    res.json({ ok: true, data: rows });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});

// Detalle de cambios de un log
router.get('/:id/cambios', validarJWT, checkPermission('BITACORA_VER'), async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT
        campo_modificado,
        valor_antes,
        valor_despues
      FROM log_cambios
      WHERE id_log_usuario = $1
    `, [req.params.id]);
    res.json({ ok: true, data: rows });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});

module.exports = router;
