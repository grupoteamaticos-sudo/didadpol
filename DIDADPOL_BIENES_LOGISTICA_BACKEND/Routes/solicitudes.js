const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');
const { checkPermission } = require('../Middlewares/validar-permiso');

const {
  postSolicitud,
  postSolicitudDetalle,
  patchEstadoSolicitud,
  postGenerarRegistro,
  deleteSolicitud,
  listarSolicitudes,
  listarEstados,
  listarTipos
} = require('../Controllers/solicitudes/solicitudes.controller');

const router = Router();

/**
 * BASE: /api/solicitudes
 */

router.post(
  '/',
  validarJWT,
  checkPermission('SOLICITUD_CREAR'),
  postSolicitud
);

router.post(
  '/:id/detalle',
  validarJWT,
  checkPermission('SOLICITUD_EDITAR'),
  postSolicitudDetalle
);

router.patch(
  '/:id/estado',
  validarJWT,
  checkPermission('SOLICITUD_EDITAR'),
  patchEstadoSolicitud
);

router.post(
  '/:id/generar-registro',
  validarJWT,
  checkPermission('SOLICITUD_EDITAR'),
  postGenerarRegistro
);

router.get(
  '/',
  validarJWT,
  checkPermission('SOLICITUD_VER'),
  listarSolicitudes
);

router.get(
  '/estados',
  validarJWT,
  listarEstados
);

router.get(
  '/tipos',
  validarJWT,
  listarTipos
);

router.delete(
  '/:id',
  validarJWT,
  checkPermission('SOLICITUD_EDITAR'),
  deleteSolicitud
);

module.exports = router;