const { Router } = require('express');
const {
  getPersonas,
  getAllPersonas,
  getPersonaById,
  postPersona,
  putPersona
} = require('../Controllers/solicitudes/personas.controller');

const { validarJWT } = require('../Middlewares/validar-jwt');

const router = Router();

router.get('/', validarJWT, getPersonas);
router.get('/all', validarJWT, getAllPersonas);
router.get('/:id', validarJWT, getPersonaById);
router.post('/', validarJWT, postPersona);
router.put('/:id', validarJWT, putPersona);

module.exports = router;
