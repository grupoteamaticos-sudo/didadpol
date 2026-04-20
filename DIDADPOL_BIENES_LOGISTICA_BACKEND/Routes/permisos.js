const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');
const { soloAdmin, soloSuperAdmin } = require('../Middlewares/validar-rol');
const { checkPermission } = require('../Middlewares/validar-permiso');

const {
  getPermisos,
  getPermiso,
  postPermiso,
  patchPermiso,
  deletePermiso,
} = require('../Controllers/solicitudes/permisos.controller');

const router = Router();

/**
 * BASE: /api/permisos
 */

// Listar permisos
router.get(
  '/',
  validarJWT,
  soloAdmin,
  checkPermission('PERMISO_VER'),
  getPermisos
);

// Obtener permiso
router.get(
  '/:id',
  validarJWT,
  soloAdmin,
  checkPermission('PERMISO_VER'),
  getPermiso
);

// Crear permiso
router.post(
  '/',
  validarJWT,
  soloAdmin,
  checkPermission('PERMISO_CREAR'),
  postPermiso
);

// Actualizar permiso
router.patch(
  '/:id',
  validarJWT,
  soloAdmin,
  checkPermission('PERMISO_EDITAR'),
  patchPermiso
);

// Eliminar permiso
router.delete(
  '/:id',
  validarJWT,
  soloSuperAdmin,
  checkPermission('PERMISO_ELIMINAR'),
  deletePermiso
);

module.exports = router;