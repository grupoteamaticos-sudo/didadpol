const { Router } = require('express');
const router = Router();

const {
  listarBienes,
  registrarBienes,
  crearBien,
  eliminarBien
} = require('../Controllers/solicitudes/bienes.controller');

// listar bienes
router.get('/', listarBienes);

// REGISTRO (KARDEX / MOVIMIENTO)
router.post('/registro', registrarBienes);

//CREAR BIEN
router.post('/crear', crearBien);

// ELIMINAR BIEN
router.delete('/:id', eliminarBien);

module.exports = router;
