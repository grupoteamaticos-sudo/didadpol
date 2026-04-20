const pool = require('../DB/db');
const { registrarEvento } = require('../Helpers/auditoria');

/**
 * Obtiene permisos desde BD (solo si no vienen en el token)
 */
async function obtenerPermisosDesdeBD(id_usuario) {
  const sql = `
    SELECT p.codigo_permiso
    FROM usuario_rol ur
    INNER JOIN rol r ON r.id_rol = ur.id_rol
    INNER JOIN rol_permiso rp ON rp.id_rol = r.id_rol
    INNER JOIN permiso p ON p.id_permiso = rp.id_permiso
    WHERE ur.id_usuario = $1
      AND r.estado_rol = 'ACTIVO'
      AND p.estado_permiso = 'ACTIVO';
  `;
  const { rows } = await pool.query(sql, [id_usuario]);
  return rows.map(r => r.codigo_permiso);
}

/**
 * Middleware: validar uno o varios permisos
 */
function checkPermission(...permisosRequeridos) {
  return async (req, res, next) => {
    try {
      const usuario = req.user;

      if (!usuario || !usuario.id_usuario) {
        return res.status(401).json({
          ok: false,
          message: 'Token inválido o usuario no identificado'
        });
      }

      const id_usuario = usuario.id_usuario;

      // ==========================================
      // SUPERADMIN BYPASS - tiene todos los permisos
      // ==========================================
      let roles = req.roles || [];
      if (!roles.length) {
        const rolSql = `
          SELECT r.nombre_rol FROM usuario_rol ur
          INNER JOIN rol r ON r.id_rol = ur.id_rol
          WHERE ur.id_usuario = $1 AND r.estado_rol = 'ACTIVO'
        `;
        const rolResult = await pool.query(rolSql, [id_usuario]);
        roles = rolResult.rows.map(r => r.nombre_rol);
      }
      if (roles.includes('SUPERADMIN')) {
        return next();
      }

      // ==========================================
      // NORMALIZAR PERMISOS
      // ==========================================
      let permisosUsuario = [];

      if (Array.isArray(usuario.permisos)) {
        permisosUsuario = usuario.permisos.map(p => {
          if (typeof p === 'string') return p;
          if (typeof p === 'object' && p.codigo_permiso) return p.codigo_permiso;
          return null;
        }).filter(Boolean);
      }

      // ==========================================
      // SI NO VIENEN EN TOKEN → CONSULTAR BD
      // ==========================================
      if (!permisosUsuario || permisosUsuario.length === 0) {
        permisosUsuario = await obtenerPermisosDesdeBD(id_usuario);
      }

      // DEBUG (puedes quitar después)
      console.log('PERMISOS USUARIO:', permisosUsuario);
      console.log('PERMISOS REQUERIDOS:', permisosRequeridos);

      // ==========================================
      // VALIDAR PERMISOS
      // ==========================================
      const tienePermiso = permisosRequeridos.some(p =>
        permisosUsuario.includes(p)
      );

      if (!tienePermiso) {
        await registrarEvento({
          id_usuario,
          tipo_accion: 'ACCESS_DENIED_PERMISSION',
          tabla_afectada: null,
          registro_afectado: null,
          ip_origen: req.ip,
          descripcion_log: `Intento sin permiso(s): ${permisosRequeridos.join(', ')}`
        });

        return res.status(403).json({
          ok: false,
          message: `No tienes permiso. Requiere: ${permisosRequeridos.join(', ')}`
        });
      }

      next();

    } catch (error) {
      return res.status(500).json({
        ok: false,
        message: 'Error verificando permisos',
        error: error.message
      });
    }
  };
}

module.exports = {
  checkPermission
};