const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');
const { checkPermission } = require('../Middlewares/validar-permiso');
const { soloAdmin, soloSuperAdmin } = require('../Middlewares/validar-rol');

const {
  getUsuarios,
  getUsuario,
  postUsuario,
  patchUsuario,
  patchBloqueo,
  inactivarUsuarioController,
  cambiarPasswordUsuario,
  getPermisosUsuario,
  postPermisoUsuario,
  deletePermisoUsuario,
  perfilUsuario
} = require('../Controllers/solicitudes/usuarios.controller');
const { cambiarPassword } = require('../service/usuarios-service');

const router = Router();

/**
 * BASE: /api/usuarios
 */

// LISTAR
router.get(
  '/',
  validarJWT,
  checkPermission('USUARIO_VER'),
  getUsuarios
);

// OBTENER POR ID
router.get(
  '/:id',
  validarJWT,
  checkPermission('USUARIO_VER'),
  getUsuario
);

// CREAR
router.post(
  '/',
  validarJWT,
  soloAdmin,
  checkPermission('USUARIO_CREAR'),
  postUsuario
);

// ACTUALIZAR
router.patch(
  '/:id',
  validarJWT,
  soloAdmin,
  checkPermission('USUARIO_EDITAR'),
  patchUsuario
);

// BLOQUEAR / DESBLOQUEAR
router.patch(
  '/:id/bloqueo',
  validarJWT,
  soloAdmin,
  checkPermission('USUARIO_BLOQUEAR'),
  patchBloqueo
);

// INACTIVAR
router.patch(
  '/:id/inactivar',
  validarJWT,
  soloSuperAdmin,
  checkPermission('USUARIO_EDITAR'),
  inactivarUsuarioController
);

//CAMBIAR CONTRASEÑA
router.patch(
  '/:id/password',
  validarJWT,
  checkPermission('USUARIO_EDITAR'),
  cambiarPasswordUsuario
);

// ==========================
// PERMISOS DE USUARIO
// ==========================

// LISTAR
router.get(
  '/:id/permisos',
  validarJWT,
  getPermisosUsuario
);

// ASIGNAR
router.post(
  '/:id/permisos',
  validarJWT,
  postPermisoUsuario
);

// QUITAR
router.delete(
  '/:id/permisos',
  validarJWT,
  deletePermisoUsuario
);

//PERFIL
router.get('/:id/perfil', perfilUsuario);

module.exports = router;