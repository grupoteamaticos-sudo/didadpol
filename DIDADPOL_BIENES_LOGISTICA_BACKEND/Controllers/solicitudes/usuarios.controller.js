//const { inactivarUsuario } = require('../../service/usuarios-service');
const {
  listarUsuarios,
  obtenerUsuario,
  crearUsuario,
  actualizarUsuario,
  bloquearUsuario,
  inactivarUsuario,
  listarPermisosUsuario,
  asignarPermisoUsuario,
  quitarPermisoUsuario,
  getPerfilUsuario
} = require('../../service/usuarios-service');

const bcrypt = require('bcryptjs');

/* ============================================================
   LISTAR USUARIOS
   ============================================================ */
const getUsuarios = async (req, res) => {
  try {
    const data = await listarUsuarios();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

/* ============================================================
   OBTENER USUARIO
   ============================================================ */
const getUsuario = async (req, res) => {
  try {
    const user = await obtenerUsuario(req.params.id);

    if (!user) {
      return res.status(404).json({ ok: false, msg: 'Usuario no encontrado' });
    }

    res.json({ ok: true, user });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

/* ============================================================
   CREAR USUARIO (ENTERPRISE)
   ============================================================ */
const postUsuario = async (req, res) => {
  try {

    const { id_empleado, nombre_usuario, password, correo_login, id_rol, pin } = req.body;

    const pinTrim = String(pin || '').trim();
    if (!/^[0-9]{8}$/.test(pinTrim)) {
      return res.status(400).json({
        ok: false,
        msg: 'El PIN debe tener exactamente 8 digitos numericos'
      });
    }

    const id_usuario_accion = req.usuario?.id_usuario;
    const ip_origen = req.ip;

    const user = await crearUsuario({
      id_empleado,
      nombre_usuario,
      password,
      correo_login,
      id_rol,
      pin: pinTrim,
      id_usuario_accion,
      ip_origen
    });

    res.status(201).json({ ok: true, user });

  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

/* ============================================================
   ACTUALIZAR USUARIO
   ============================================================ */
const CAMPOS_EDITABLES = ['nombre_usuario', 'correo_login'];

const patchUsuario = async (req, res) => {
  try {
    const payload = {};

    for (const key of CAMPOS_EDITABLES) {
      if (req.body[key] !== undefined && req.body[key] !== null && String(req.body[key]).trim() !== '') {
        payload[key] = String(req.body[key]).trim();
      }
    }

    // PIN opcional: si viene, validar 8 digitos y hashearlo antes de persistir
    const pinRaw = req.body.pin;
    if (pinRaw !== undefined && pinRaw !== null && String(pinRaw).trim() !== '') {
      const pinTrim = String(pinRaw).trim();
      if (!/^[0-9]{8}$/.test(pinTrim)) {
        return res.status(400).json({
          ok: false,
          msg: 'El PIN debe tener exactamente 8 digitos numericos'
        });
      }
      payload.pin_hash = await bcrypt.hash(pinTrim, 10);
    }

    if (!Object.keys(payload).length) {
      return res.status(400).json({
        ok: false,
        msg: 'No hay campos validos para actualizar'
      });
    }

    if (payload.correo_login) {
      const ok = /^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/.test(payload.correo_login);
      if (!ok) {
        return res.status(400).json({
          ok: false,
          msg: 'Correo electronico invalido'
        });
      }
    }

    if (payload.nombre_usuario && payload.nombre_usuario.length < 3) {
      return res.status(400).json({
        ok: false,
        msg: 'El nombre de usuario debe tener al menos 3 caracteres'
      });
    }

    const data = await actualizarUsuario(req.params.id, payload);

    res.json({ ok: true, data });

  } catch (error) {
    if (error.code === '23505') {
      return res.status(409).json({
        ok: false,
        msg: 'El usuario o correo ya esta en uso'
      });
    }
    res.status(500).json({ ok: false, msg: error.message });
  }
};

/* ============================================================
   BLOQUEAR / DESBLOQUEAR
   ============================================================ */
const patchBloqueo = async (req, res) => {
  try {

    const data = await bloquearUsuario(req.params.id);

    res.json({ ok: true, data });

  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

/* ============================================================
   ELIMINAR USUARIO
   ============================================================ */
const inactivarUsuarioController = async (req, res) => {
  try {

    await inactivarUsuario(req.params.id);

    //res.json({ ok: true, msg: 'Usuario eliminado' });
    res.json({ ok: true, msg: 'Usuario inactivado correctamente' });

  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

/* ============================================================
   CAMBIAR CONTRASEÑA
   ============================================================ */
const cambiarPasswordUsuario = async (req, res) => {

  try {

    const id_usuario_objetivo = req.params.id;
    const id_usuario_accion = req.usuario.id_usuario;
    const ip_origen = req.ip;

    const { currentPassword, newPassword } = req.body;

    const esAdmin = req.usuario.roles?.some(
      r => r.nombre_rol === 'ADMIN' || r.nombre_rol === 'SUPERADMIN'
    );

    await cambiarPassword({
      id_usuario_objetivo,
      id_usuario_accion,
      currentPassword,
      newPassword,
      ip_origen,
      esAdmin
    });

    res.json({ ok: true, msg: 'Contraseña actualizada correctamente' });

  } catch (error) {

    res.status(400).json({
      ok: false,
      msg: error.message
    });
  }
};

/* ============================================================
   PERMISOS DE USUARIO
   ============================================================ */

const getPermisosUsuario = async (req, res) => {
  try {
    const data = await listarPermisosUsuario(req.params.id);
    res.json({ ok: true, permisos: data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

const postPermisoUsuario = async (req, res) => {
  try {
    const { id_permiso } = req.body;

    const data = await asignarPermisoUsuario(
      req.params.id,
      id_permiso
    );

    res.json({ ok: true, data });

  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

const deletePermisoUsuario = async (req, res) => {
  try {
    const { id_permiso } = req.body;

    await quitarPermisoUsuario(
      req.params.id,
      id_permiso
    );

    res.json({ ok: true });

  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

/* ============================================================
   PERFIL DE USUARIO
   ============================================================ */

const perfilUsuario = async (req, res) => {
  try {
    const { id } = req.params;

    const data = await getPerfilUsuario(id);

    if (!data) {
      return res.status(404).json({
        ok: false,
        msg: 'Usuario no encontrado'
      });
    }

    res.json({
      ok: true,
      perfil: data
    });

  } catch (error) {
    console.error('perfilUsuario:', error);

    res.status(500).json({
      ok: false,
      msg: 'Error obteniendo perfil'
    });
  }
};

module.exports = {
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
};