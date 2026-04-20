const { Router } = require('express');
const {
  getDepartamentos,
  getPuestos,
  getSucursales
} = require('../Controllers/solicitudes/catalogos.controller');

const { validarJWT } = require('../Middlewares/validar-jwt');

const router = Router();

router.get('/departamentos', validarJWT, getDepartamentos);
router.get('/puestos', validarJWT, getPuestos);
router.get('/sucursales', validarJWT, getSucursales);

module.exports = router;