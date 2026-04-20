const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');

const {
  getMantenimientos,
  getCatalogos,
  postProgramar,
  postIniciar,
  postFinalizar
} = require('../Controllers/solicitudes/mantenimientos.controller');

const router = Router();

router.get('/', validarJWT, getMantenimientos);
router.get('/catalogos', validarJWT, getCatalogos);
router.post('/', validarJWT, postProgramar);
router.post('/:id/iniciar', validarJWT, postIniciar);
router.post('/:id/finalizar', validarJWT, postFinalizar);

module.exports = router;
