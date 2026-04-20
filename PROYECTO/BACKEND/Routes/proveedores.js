const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');
const { listarProveedores, crearProveedor, eliminarProveedor } = require('../Controllers/solicitudes/proveedores.controller');

const router = Router();

router.get('/', validarJWT, listarProveedores);
router.post('/', validarJWT, crearProveedor);
router.delete('/:id', validarJWT, eliminarProveedor);

module.exports = router;
