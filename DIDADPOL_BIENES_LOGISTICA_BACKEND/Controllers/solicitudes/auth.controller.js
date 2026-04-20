const {
  MAX_INTENTOS,
  findUserByUsername,
  findPinHashById,
  findUserForPinResetById,
  savePinResetToken,
  findPinResetTokenByUser,
  updatePinAndClearResetToken,
  findUserByIdentifier,
  findUserByUsernameAndEmail,
  incrementFailedAttempt,
  resetAttemptsAndUpdateAccess,
  getRolesPermisos,
  verifyPassword,
  createUserEnterprise,
  saveResetToken,
  findResetTokenByUser,
  updatePasswordAndClearToken
} = require('../../service/auth-service');

const {
  generateAuhtJWT,
  generateRefreshToken,
  invalidateJWT
} = require('../../Helpers/jwt');

const { registrarEvento } = require('../../Helpers/auditoria');
const { sendMail, buildResetTokenEmail, buildPinResetEmail } = require('../../Helpers/mailer');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const RESET_TOKEN_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateResetToken(len = 8) {
  const bytes = crypto.randomBytes(len);
  let out = '';
  for (let i = 0; i < len; i++) {
    out += RESET_TOKEN_ALPHABET[bytes[i] % RESET_TOKEN_ALPHABET.length];
  }
  return out;
}

function maskEmail(email) {
  if (!email || !email.includes('@')) return '';
  const [user, domain] = email.split('@');
  const visible = user.slice(0, 2);
  return `${visible}${'*'.repeat(Math.max(user.length - 2, 2))}@${domain}`;
}


/* – CON BLOQUEO AUTOMÁTICO + 2FA
    */
const login = async (req, res) => {
  try {
    const { username, password } = req.body;
    const ip_origen = req.ip;

    if (!username || !password) {
      return res.status(400).json({
        ok: false,
        message: 'Usuario o contraseña son obligatorios'
      });
    }

    const identifier = String(username).trim();
    let user = await findUserByIdentifier(identifier);

    // [!] Usuario no existe
    if (!user) {
      await registrarEvento({
        id_usuario: null,
        tipo_accion: 'LOGIN_FAILED',
        tabla_afectada: 'usuario',
        registro_afectado: null,
        ip_origen,
        descripcion_log: `Intento con usuario/correo inexistente: ${identifier}`
      });

      return res.status(401).json({
        ok: false,
        message: 'Usuario o contraseña incorrectos'
      });
    }

    // [!] Usuario inactivo
    if (user.estado_usuario !== 'ACTIVO') {
      return res.status(403).json({
        ok: false,
        message: 'Usuario inactivo'
      });
    }

    // [!] Usuario ya bloqueado
    if (user.bloqueado) {
      return res.status(423).json({
        ok: false,
        message: 'Usuario bloqueado',
        intentos_fallidos: user.intentos_fallidos
      });
    }

    // [AUTH] Verificar contrasena
    const passOk = await verifyPassword(password, user.contrasena_usuario);

    if (!passOk) {
      const updated = await incrementFailedAttempt(user.id_usuario);
      const fueBloqueado = updated?.bloqueado === true;

      await registrarEvento({
        id_usuario: user.id_usuario,
        tipo_accion: fueBloqueado ? 'AUTO_LOCK_USER' : 'LOGIN_FAILED',
        tabla_afectada: 'usuario',
        registro_afectado: user.id_usuario,
        ip_origen,
        descripcion_log: fueBloqueado
          ? 'Usuario bloqueado automáticamente por intentos fallidos'
          : 'Contraseña incorrecta'
      });

      if (fueBloqueado) {
        return res.status(423).json({
          ok: false,
          message: `Usuario bloqueado por ${MAX_INTENTOS} intentos fallidos`
        });
      }

      return res.status(401).json({
        ok: false,
        message: `Credenciales inválidas. Intento ${updated.intentos_fallidos} de ${MAX_INTENTOS}`
      });
    }

    // [OK] Login exitoso -> resetear intentos
    await resetAttemptsAndUpdateAccess(user.id_usuario);

    // [PIN 2FA] Si el usuario tiene PIN configurado, pedirlo antes de emitir tokens
    if (user.pin_hash) {
      const tempToken = jwt.sign(
        {
          id_usuario: user.id_usuario,
          id_empleado: user.id_empleado,
          purpose: 'pin_2fa'
        },
        process.env.ACCESS_JWT_SECRET,
        { expiresIn: '10m' }
      );

      await registrarEvento({
        id_usuario: user.id_usuario,
        tipo_accion: 'LOGIN_PENDING_PIN',
        tabla_afectada: 'usuario',
        registro_afectado: user.id_usuario,
        ip_origen,
        descripcion_log: 'Credenciales validas, esperando PIN 2FA'
      });

      return res.json({
        ok: true,
        requires2FA: true,
        channel: 'PIN',
        tempToken
      });
    }

    // Usuario sin PIN configurado 
    const { roles, permisos } = await getRolesPermisos(user.id_usuario);

    const payload = {
      id_usuario: user.id_usuario,
      id_empleado: user.id_empleado,
      roles,
      permisos
    };

    const accessToken = await generateAuhtJWT(payload);
    const refreshToken = await generateRefreshToken(payload);

    await registrarEvento({
      id_usuario: user.id_usuario,
      tipo_accion: 'LOGIN_SUCCESS',
      tabla_afectada: 'usuario',
      registro_afectado: user.id_usuario,
      ip_origen,
      descripcion_log: 'Login exitoso (sin PIN configurado)'
    });

    return res.json({
      ok: true,
      requires2FA: false,
      data: {
        accessToken,
        refreshToken,
        usuario: { id_usuario: user.id_usuario },
        roles,
        permisos
      }
    });

  } catch (error) {
    return res.status(500).json({
      ok: false,
      message: error.message
    });
  }
};


/*    Verificar OTP 
    */
const verifyOtp = async (req, res) => {
  try {
    const { tempToken, code } = req.body;

    if (!tempToken || !code) {
      return res.status(400).json({
        ok: false,
        message: 'tempToken y codigo son obligatorios'
      });
    }

    let decoded;
    try {
      decoded = jwt.verify(tempToken, process.env.ACCESS_JWT_SECRET);
    } catch {
      return res.status(401).json({
        ok: false,
        message: 'Sesion expirada. Vuelve a iniciar sesion.'
      });
    }

    if (decoded.purpose !== 'pin_2fa' || !decoded.id_usuario) {
      return res.status(401).json({
        ok: false,
        message: 'Token invalido para verificacion de PIN'
      });
    }

    const id_usuario = decoded.id_usuario;

    const pinHash = await findPinHashById(id_usuario);
    if (!pinHash) {
      return res.status(400).json({
        ok: false,
        message: 'El usuario no tiene PIN configurado'
      });
    }

    const match = await bcrypt.compare(String(code).trim(), pinHash);
    if (!match) {
      await registrarEvento({
        id_usuario,
        tipo_accion: 'LOGIN_PIN_FAILED',
        tabla_afectada: 'usuario',
        registro_afectado: id_usuario,
        ip_origen: req.ip,
        descripcion_log: 'PIN incorrecto'
      });

      return res.status(401).json({
        ok: false,
        message: 'PIN incorrecto'
      });
    }

    const { roles, permisos } = await getRolesPermisos(id_usuario);

    const payload = {
      id_usuario,
      id_empleado: decoded.id_empleado,
      roles,
      permisos
    };

    const accessToken = await generateAuhtJWT(payload);
    const refreshToken = await generateRefreshToken(payload);

    await registrarEvento({
      id_usuario,
      tipo_accion: 'LOGIN_SUCCESS',
      tabla_afectada: 'usuario',
      registro_afectado: id_usuario,
      ip_origen: req.ip,
      descripcion_log: 'Login exitoso con PIN 2FA'
    });

    return res.json({
      ok: true,
      data: {
        accessToken,
        refreshToken,
        usuario: { id_usuario },
        roles,
        permisos
      }
    });

  } catch (error) {
    console.error('[VERIFY_OTP] error:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error verificando PIN'
    });
  }
};


/*  REGISTRO   */
const userRegister = async (req, res) => {
  try {
    const { id_empleado, username, password, correo } = req.body;

    const id_usuario_accion = req.usuario.id_usuario;
    const ip_origen = req.ip;

    const result = await createUserEnterprise({
      id_empleado,
      username,
      password,
      correo,
      id_usuario_accion,
      ip_origen
    });

    return res.status(201).json({
      ok: true,
      message: 'Usuario creado',
      data: result
    });

  } catch (error) {
    return res.status(500).json({
      ok: false,
      message: error.message
    });
  }
};


/*    RESTO */
const renewToken = async (req, res) =>
  res.status(501).json({ ok: false, message: 'Pendiente implementación' });

/*    FORGOT PASSWORD */
const forgotPassword = async (req, res) => {
  try {
    const { username, email } = req.body;
    const ip_origen = req.ip;

    const u = String(username || '').trim();
    const e = String(email || '').trim();

    if (!u || u.length < 2) {
      return res.status(400).json({
        ok: false,
        message: 'Debes ingresar tu usuario'
      });
    }

    if (!e || !/^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/.test(e)) {
      return res.status(400).json({
        ok: false,
        message: 'Debes ingresar un correo valido'
      });
    }

    const user = await findUserByUsernameAndEmail(u, e);

    if (!user) {
      await registrarEvento({
        id_usuario: null,
        tipo_accion: 'FORGOT_PASSWORD_FAILED',
        tabla_afectada: 'usuario',
        registro_afectado: null,
        ip_origen,
        descripcion_log: `Intento de recuperacion fallido. usuario=${u} correo=${e}`
      });

      return res.status(404).json({
        ok: false,
        message: 'El usuario y correo no coinciden con ningun registro'
      });
    }

    if (user.estado_usuario !== 'ACTIVO') {
      return res.status(403).json({
        ok: false,
        message: 'Usuario inactivo'
      });
    }

    if (!user.correo_login) {
      return res.status(400).json({
        ok: false,
        message: 'El usuario no tiene correo registrado'
      });
    }

    const ttlMin = Number(process.env.RESET_TOKEN_TTL_MIN || 15);
    const token = generateResetToken(8);
    const expires = new Date(Date.now() + ttlMin * 60 * 1000);

    await saveResetToken(user.id_usuario, token, expires);

    const tempToken = jwt.sign(
      { id_usuario: user.id_usuario, purpose: 'password_reset' },
      process.env.ACCESS_JWT_SECRET,
      { expiresIn: `${ttlMin}m` }
    );

    // Responder inmediatamente al cliente y enviar el correo en background
    res.json({
      ok: true,
      tempToken,
      channel: 'EMAIL',
      destination: maskEmail(user.correo_login),
      message: 'Codigo enviado al correo registrado'
    });

    setImmediate(async () => {
      try {
        const mail = buildResetTokenEmail({
          nombre: user.nombre_usuario,
          token,
          ttlMin
        });

        await sendMail({
          to: user.correo_login,
          subject: mail.subject,
          text: mail.text,
          html: mail.html
        });

        await registrarEvento({
          id_usuario: user.id_usuario,
          tipo_accion: 'FORGOT_PASSWORD_REQUEST',
          tabla_afectada: 'usuario',
          registro_afectado: user.id_usuario,
          ip_origen,
          descripcion_log: `Codigo de recuperacion enviado a ${maskEmail(user.correo_login)}`
        });
      } catch (mailErr) {
        console.error('[MAIL] Error enviando correo de recuperacion:', mailErr.message);
      }
    });
    return;

  } catch (error) {
    console.error('[FORGOT] Error:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error al procesar la solicitud'
    });
  }
};


/*  RECOVER PASSWORD  */
const recoverPassword = async (req, res) => {
  try {
    const { tempToken, code, newPassword, passwordConfirm } = req.body;
    const ip_origen = req.ip;

    if (!tempToken || !code || !newPassword || !passwordConfirm) {
      return res.status(400).json({
        ok: false,
        message: 'Todos los campos son obligatorios'
      });
    }

    if (String(newPassword) !== String(passwordConfirm)) {
      return res.status(400).json({
        ok: false,
        message: 'Las contrasenas no coinciden'
      });
    }

    if (String(newPassword).length < 8) {
      return res.status(400).json({
        ok: false,
        message: 'La contrasena debe tener al menos 8 caracteres'
      });
    }

    let decoded;
    try {
      decoded = jwt.verify(tempToken, process.env.ACCESS_JWT_SECRET);
    } catch {
      return res.status(401).json({
        ok: false,
        message: 'Sesion de recuperacion invalida o expirada'
      });
    }

    if (decoded.purpose !== 'password_reset' || !decoded.id_usuario) {
      return res.status(401).json({
        ok: false,
        message: 'Token de recuperacion invalido'
      });
    }

    const record = await findResetTokenByUser(decoded.id_usuario);

    if (!record || !record.reset_token) {
      return res.status(401).json({
        ok: false,
        message: 'No hay un codigo activo. Solicita uno nuevo.'
      });
    }

    if (String(code).trim().toUpperCase() !== String(record.reset_token).toUpperCase()) {
      return res.status(401).json({
        ok: false,
        message: 'Codigo incorrecto'
      });
    }

    if (record.reset_token_expires && new Date(record.reset_token_expires) < new Date()) {
      return res.status(401).json({
        ok: false,
        message: 'El codigo ha expirado. Solicita uno nuevo.'
      });
    }

    const salt = await bcrypt.genSalt(10);
    const hash = await bcrypt.hash(String(newPassword), salt);

    await updatePasswordAndClearToken(decoded.id_usuario, hash);

    await registrarEvento({
      id_usuario: decoded.id_usuario,
      tipo_accion: 'PASSWORD_RESET',
      tabla_afectada: 'usuario',
      registro_afectado: decoded.id_usuario,
      ip_origen,
      descripcion_log: 'Contrasena actualizada via recuperacion'
    });

    return res.json({
      ok: true,
      message: 'Contrasena actualizada correctamente'
    });

  } catch (error) {
    console.error('[RECOVER] Error:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error al restablecer la contrasena'
    });
  }
};

const contactMessage = async (req, res) =>
  res.status(200).json({ ok: true, message: 'Mensaje recibido' });

const auditAccess = async (req, res) =>
  res.status(200).json({ ok: true, message: 'Acceso auditado' });

const logout = async (req, res) =>
  res.status(501).json({ ok: false, message: 'Pendiente implementación' });

const qrTFA = async (req, res) =>
  res.status(501).json({ ok: false, message: 'Pendiente implementación' });

const setTFA = async (req, res) =>
  res.status(501).json({ ok: false, message: 'Pendiente implementación' });

const disableTFA = async (req, res) =>
  res.status(501).json({ ok: false, message: 'Pendiente implementación' });


/*    FORGOT PIN — envia codigo de 6 digitos al correo del usuario
   
    */
const forgotPin = async (req, res) => {
  try {
    const { tempToken } = req.body;
    const ip_origen = req.ip;

    if (!tempToken) {
      return res.status(400).json({
        ok: false,
        message: 'tempToken es obligatorio'
      });
    }

    let decoded;
    try {
      decoded = jwt.verify(tempToken, process.env.ACCESS_JWT_SECRET);
    } catch {
      return res.status(401).json({
        ok: false,
        message: 'Sesion expirada. Vuelve a iniciar sesion.'
      });
    }

    if (decoded.purpose !== 'pin_2fa' || !decoded.id_usuario) {
      return res.status(401).json({
        ok: false,
        message: 'Token invalido'
      });
    }

    const user = await findUserForPinResetById(decoded.id_usuario);
    if (!user || user.estado_usuario !== 'ACTIVO') {
      return res.status(404).json({
        ok: false,
        message: 'Usuario no encontrado o inactivo'
      });
    }

    if (!user.correo_login) {
      return res.status(400).json({
        ok: false,
        message: 'El usuario no tiene correo registrado'
      });
    }

    // Genera 6 digitos numericos
    const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
    const ttlMin = 10;
    const expires = new Date(Date.now() + ttlMin * 60 * 1000);

    await savePinResetToken(user.id_usuario, code, expires);

    // Responder inmediatamente y enviar correo en background
    res.json({
      ok: true,
      channel: 'EMAIL',
      message: 'Codigo enviado al correo registrado'
    });

    setImmediate(async () => {
      try {
        const mail = buildPinResetEmail({
          nombre: user.nombre_usuario,
          token: code,
          ttlMin
        });

        await sendMail({
          to: user.correo_login,
          subject: mail.subject,
          text: mail.text,
          html: mail.html
        });

        await registrarEvento({
          id_usuario: user.id_usuario,
          tipo_accion: 'FORGOT_PIN_REQUEST',
          tabla_afectada: 'usuario',
          registro_afectado: user.id_usuario,
          ip_origen,
          descripcion_log: `Codigo de restablecimiento de PIN enviado a ${maskEmail(user.correo_login)}`
        });
      } catch (mailErr) {
        console.error('[MAIL] Error enviando codigo de PIN:', mailErr.message);
      }
    });
    return;

  } catch (error) {
    console.error('[FORGOT_PIN] error:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error al procesar la solicitud'
    });
  }
};


/*    RESET PIN  */
const resetPin = async (req, res) => {
  try {
    const { tempToken, code, newPin } = req.body;
    const ip_origen = req.ip;

    if (!tempToken || !code || !newPin) {
      return res.status(400).json({
        ok: false,
        message: 'Todos los campos son obligatorios'
      });
    }

    if (!/^[0-9]{6}$/.test(String(code).trim())) {
      return res.status(400).json({
        ok: false,
        message: 'El codigo debe tener exactamente 6 digitos'
      });
    }

    if (!/^[0-9]{8}$/.test(String(newPin).trim())) {
      return res.status(400).json({
        ok: false,
        message: 'El nuevo PIN debe tener exactamente 8 digitos'
      });
    }

    let decoded;
    try {
      decoded = jwt.verify(tempToken, process.env.ACCESS_JWT_SECRET);
    } catch {
      return res.status(401).json({
        ok: false,
        message: 'Sesion expirada. Vuelve a iniciar sesion.'
      });
    }

    if (decoded.purpose !== 'pin_2fa' || !decoded.id_usuario) {
      return res.status(401).json({
        ok: false,
        message: 'Token invalido'
      });
    }

    const record = await findPinResetTokenByUser(decoded.id_usuario);
    if (!record || !record.pin_reset_token) {
      return res.status(401).json({
        ok: false,
        message: 'No hay un codigo activo. Solicita uno nuevo.'
      });
    }

    if (String(code).trim() !== String(record.pin_reset_token)) {
      return res.status(401).json({
        ok: false,
        message: 'Codigo incorrecto'
      });
    }

    if (record.pin_reset_token_expires && new Date(record.pin_reset_token_expires) < new Date()) {
      return res.status(401).json({
        ok: false,
        message: 'El codigo ha expirado. Solicita uno nuevo.'
      });
    }

    const pinHash = await bcrypt.hash(String(newPin).trim(), 10);
    await updatePinAndClearResetToken(decoded.id_usuario, pinHash);

    await registrarEvento({
      id_usuario: decoded.id_usuario,
      tipo_accion: 'PIN_RESET',
      tabla_afectada: 'usuario',
      registro_afectado: decoded.id_usuario,
      ip_origen,
      descripcion_log: 'PIN OTP restablecido via correo'
    });

    return res.json({
      ok: true,
      message: 'PIN actualizado correctamente'
    });

  } catch (error) {
    console.error('[RESET_PIN] error:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error al restablecer el PIN'
    });
  }
};


module.exports = {
  login,
  verifyOtp,
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
  disableTFA
};