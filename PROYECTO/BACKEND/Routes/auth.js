const { Router } = require('express');
const { check } = require('express-validator');

const {
  validarJWT,
  validarCampos
} = require('../Middlewares');

const {
  login,
  userRegister,
  renewToken,
  forgotPassword,
  recoverPassword,
  forgotPin,
  resetPin,
  contactMessage,
  auditAccess,
  logout,
  qrTFA,
  setTFA,
  verifyOtp,
  disableTFA
} = require('../Controllers/solicitudes/auth.controller');

const router = Router();

/**
 * AUTH
 * Base: /api/auth
 */

// =========================
// LOGIN
// =========================
router.post('/login', [
  check('username', 'El usuario es obligatorio').not().isEmpty().isLength({ min: 2 }),
  check('password', 'La contraseña es obligatoria').not().isEmpty(),
  validarCampos
], login);


// =========================
// REGISTRO INSTITUCIONAL
// Solo ADMIN / SUPERADMIN
// =========================
router.post('/register', [
  validarJWT,

  check('id_empleado', 'El empleado es obligatorio').not().isEmpty(),
  check('username', 'El username es obligatorio').not().isEmpty().isLength({ min: 3 }),
  check('password', 'La contraseña es obligatoria').not().isEmpty().isLength({ min: 8 }),
  check('correo', 'El correo es obligatorio').not().isEmpty().isEmail(),

  validarCampos
], userRegister);


// =========================
// FORGOT PASSWORD
// =========================
router.post('/forgot-password', [
  check('username', 'Ingresa tu usuario').not().isEmpty().isLength({ min: 2 }),
  check('email', 'Ingresa un correo valido').not().isEmpty().isEmail(),
  validarCampos
], forgotPassword);


// =========================
// RECOVER PASSWORD
// =========================
router.post('/recover-password', [
  check('tempToken', 'tempToken es obligatorio').not().isEmpty(),
  check('code', 'El codigo es obligatorio').not().isEmpty().isLength({ min: 8, max: 8 }),
  check('newPassword', 'La contrasena es obligatoria').not().isEmpty().isLength({ min: 8 }),
  check('passwordConfirm', 'Confirmar la contrasena es obligatorio').not().isEmpty().isLength({ min: 8 }),
  validarCampos
], recoverPassword);


// =========================
// FORGOT PIN (envia codigo al correo del usuario que esta en 2FA)
// =========================
router.post('/forgot-pin', [
  check('tempToken', 'tempToken es obligatorio').not().isEmpty(),
  validarCampos
], forgotPin);


// =========================
// RESET PIN (valida codigo de 6 digitos y guarda nuevo PIN de 8)
// =========================
router.post('/reset-pin', [
  check('tempToken', 'tempToken es obligatorio').not().isEmpty(),
  check('code', 'El codigo es obligatorio').not().isEmpty().isLength({ min: 6, max: 6 }),
  check('newPin', 'El PIN es obligatorio').not().isEmpty().isLength({ min: 8, max: 8 }),
  validarCampos
], resetPin);


// =========================
// CONTACTO
// =========================
router.post('/contact', [
  check('email', 'El correo electrónico es obligatorio').not().isEmpty().isEmail(),
  check('name', 'El nombre es obligatorio').not().isEmpty().isLength({ min: 2 }),
  check('subject', 'El asunto es obligatorio').not().isEmpty().isLength({ min: 2 }),
  check('message', 'El mensaje es obligatorio').not().isEmpty().isLength({ min: 2 }),
  validarCampos
], contactMessage);


// =========================
// AUDITORÍA DE ACCESO
// =========================
router.post('/audit-access/:screenName', [
  validarJWT,
  check('screenName', 'screenName es obligatorio').not().isEmpty().isLength({ min: 2 }),
  validarCampos
], auditAccess);


// =========================
// 2FA
// =========================
router.get('/tfa', [validarJWT], qrTFA);
router.post('/tfa', [validarJWT], setTFA);
router.post('/verify-otp', verifyOtp);
router.delete('/tfa/:uid', [validarJWT], disableTFA);

module.exports = router;