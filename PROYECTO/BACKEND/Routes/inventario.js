const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');
const { checkPermission } = require('../Middlewares/validar-permiso');

const { getInventario, reservarInventario } = require('../Controllers/solicitudes/inventario.controller');

const router = Router();

/**
 * BASE: /api/inventario
 */

// GET inventario
router.get(
  '/',
  validarJWT,
  //checkPermission('INVENTARIO_VER'),
  getInventario
);

// POST reservar
router.post(
  '/reservar',
  validarJWT,
  checkPermission('INVENTARIO_VER'),
  reservarInventario
);

module.exports = router;