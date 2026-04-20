const pool = require('../DB/db');
const bcrypt = require('bcryptjs');


/* ============================================================
   LISTAR USUARIOS
   ============================================================ */
async function listarUsuarios() {
  const sql = `
    SELECT 
      u.id_usuario,
      u.id_empleado,
      u.nombre_usuario,
      u.correo_login,
      u.ultimo_acceso,
      u.intentos_fallidos,
      u.bloqueado,
      u.estado_usuario,
      u.fecha_registro,

      r.id_rol,
      r.nombre_rol

    FROM usuario u
    LEFT JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    LEFT JOIN rol r ON r.id_rol = ur.id_rol

    ORDER BY u.id_usuario;
  `;

  const { rows } = await pool.query(sql);

  // AGRUPAR POR USUARIO
  const map = new Map();

  for (const row of rows) {
    const id = row.id_usuario;

    if (!map.has(id)) {
      map.set(id, {
        id_usuario: row.id_usuario,
        id_empleado: row.id_empleado,
        nombre_usuario: row.nombre_usuario,
        correo_login: row.correo_login,
        ultimo_acceso: row.ultimo_acceso,
        intentos_fallidos: row.intentos_fallidos,
        bloqueado: row.bloqueado,
        estado_usuario: row.estado_usuario,
        fecha_registro: row.fecha_registro,
        roles: []
      });
    }

    if (row.id_rol) {
      map.get(id).roles.push({
        id_rol: row.id_rol,
        nombre_rol: row.nombre_rol
      });
    }
  }

  return Array.from(map.values());
}

/* ============================================================
   OBTENER USUARIO POR ID
   ============================================================ */
async function obtenerUsuario(id_usuario) {
  const sql = `
    SELECT 
      id_usuario,
      id_empleado,
      nombre_usuario,
      correo_login,
      ultimo_acceso,
      intentos_fallidos,
      bloqueado,
      estado_usuario,
      fecha_registro
    FROM usuario
    WHERE id_usuario = $1;
  `;

  const { rows } = await pool.query(sql, [id_usuario]);
  return rows[0] || null;
}

/* ============================================================
   CREAR USUARIO (ENTERPRISE VERSION)
   ============================================================ */
async function crearUsuario({
  id_empleado,
  nombre_usuario,
  password,
  correo_login,
  id_rol,
  pin,
  id_usuario_accion,
  ip_origen
}) {

  const client = await pool.connect();

  try {

    await client.query('BEGIN');

    const hash = await bcrypt.hash(password, 10);
    const pinHash = pin ? await bcrypt.hash(String(pin), 10) : null;

    // Crear usuario vía SP
    await client.query(
      `
      CALL sp_usuario_crear(
        $1::bigint,
        $2::varchar,
        $3::text,
        $4::varchar,
        $5::bigint,
        $6::varchar,
        NULL,
        NULL
      );
      `,
      [
        id_empleado,
        nombre_usuario,
        hash,
        correo_login,
        id_usuario_accion,
        ip_origen
      ]
    );

    // Obtener ID recién generado (forma segura)
    const { rows } = await client.query(
      `SELECT currval(pg_get_serial_sequence('usuario','id_usuario')) AS id`
    );

    const id_usuario_nuevo = rows[0]?.id;

    if (!id_usuario_nuevo) {
      throw new Error('No se pudo obtener el id del usuario creado');
    }

    // Guardar PIN hasheado
    if (pinHash) {
      await client.query(
        `UPDATE usuario SET pin_hash = $1 WHERE id_usuario = $2`,
        [pinHash, id_usuario_nuevo]
      );
    }

    // Asignar rol CONSULTA automáticamente
    await client.query(
      `
      CALL sp_usuario_asignar_rol(
        $1::bigint,
        $2::bigint,
        $3::bigint,
        $4::varchar,
        NULL,
        NULL
      );
      `,
      [
        id_usuario_nuevo,
        id_rol,
        id_usuario_accion,
        ip_origen
      ]
    );

    await client.query('COMMIT');

    return {
      id_usuario: id_usuario_nuevo,
      nombre_usuario
    };

  } catch (error) {

    await client.query('ROLLBACK');
    throw error;

  } finally {
    client.release();
  }
}

/* ============================================================
   ACTUALIZAR USUARIO (actualización simple por ahora)
   ============================================================ */
async function actualizarUsuario(id_usuario, campos) {

  const columnas = [];
  const valores = [];
  let index = 1;

  for (let key in campos) {
    columnas.push(`${key} = $${index}`);
    valores.push(campos[key]);
    index++;
  }

  if (!columnas.length) {
    throw new Error('No hay campos para actualizar');
  }

  valores.push(id_usuario);

  const sql = `
    UPDATE usuario
    SET ${columnas.join(', ')}
    WHERE id_usuario = $${index}
    RETURNING *;
  `;

  const { rows } = await pool.query(sql, valores);

  if (!rows.length) {
    throw new Error('Usuario no encontrado');
  }

  return rows[0];
}

/* ============================================================
   BLOQUEAR / DESBLOQUEAR USUARIO
   ============================================================ */
async function bloquearUsuario(id_usuario) {

  const sql = `
    UPDATE usuario
    SET bloqueado = NOT bloqueado
    WHERE id_usuario = $1
    RETURNING id_usuario, bloqueado;
  `;

  const { rows } = await pool.query(sql, [id_usuario]);

  if (!rows.length) {
    throw new Error('Usuario no encontrado');
  }

  return rows[0];
}

/* ============================================================
   INACTIVAR USUARIO (NO DELETE FÍSICO)
   ============================================================ */
async function inactivarUsuario(id_usuario) {

  const sql = `
    UPDATE usuario
    SET estado_usuario = CASE WHEN estado_usuario = 'ACTIVO' THEN 'INACTIVO' ELSE 'ACTIVO' END
    WHERE id_usuario = $1
    RETURNING id_usuario, estado_usuario;
  `;

  const { rows } = await pool.query(sql, [id_usuario]);

  if (!rows.length) {
    throw new Error('Usuario no encontrado');
  }

  return rows[0];
}

/* ============================================================
   CAMBIAR CONTRASEÑA
   ============================================================ */
async function cambiarPassword({
  id_usuario_objetivo,
  id_usuario_accion,
  currentPassword,
  newPassword,
  ip_origen,
  esAdmin = false
}) {

  const client = await pool.connect();

  try {

    await client.query('BEGIN');

    const { rows } = await client.query(
      `SELECT contrasena_usuario FROM usuario WHERE id_usuario = $1`,
      [id_usuario_objetivo]
    );

    if (!rows.length) {
      throw new Error('Usuario no encontrado');
    }

    const passwordHashActual = rows[0].contrasena_usuario;

    // Si no es admin, validar contraseña actual
    if (!esAdmin) {

      const match = await bcrypt.compare(
        currentPassword,
        passwordHashActual
      );

      if (!match) {
        throw new Error('Contraseña actual incorrecta');
      }
    }

    const newHash = await bcrypt.hash(newPassword, 10);

    await client.query(
      `
      UPDATE usuario
      SET contrasena_usuario = $1
      WHERE id_usuario = $2
      `,
      [newHash, id_usuario_objetivo]
    );

    await client.query('COMMIT');

    return true;

  } catch (error) {

    await client.query('ROLLBACK');
    throw error;

  } finally {
    client.release();
  }
}

/* ============================================================
   LISTAR PERMISOS DE USUARIO (ROL + DIRECTOS)
   ============================================================ */
async function listarPermisosUsuario(id_usuario) {

  const sql = `
    -- permisos por rol
    SELECT p.id_permiso, p.nombre_permiso, p.codigo_permiso
    FROM usuario_rol ur
    JOIN rol_permiso rp ON rp.id_rol = ur.id_rol
    JOIN permiso p ON p.id_permiso = rp.id_permiso
    WHERE ur.id_usuario = $1

    UNION

    -- permisos directos
    SELECT p.id_permiso, p.nombre_permiso, p.codigo_permiso
    FROM usuario_permiso up
    JOIN permiso p ON p.id_permiso = up.id_permiso
    WHERE up.id_usuario = $1

    ORDER BY id_permiso;
  `;

  const { rows } = await pool.query(sql, [id_usuario]);
  return rows;
}

/* ============================================================
   ASIGNAR PERMISO A USUARIO
   ============================================================ */
async function asignarPermisoUsuario(id_usuario, id_permiso) {

  const sql = `
    INSERT INTO usuario_permiso (id_usuario, id_permiso)
    VALUES ($1, $2)
    ON CONFLICT DO NOTHING
    RETURNING *;
  `;

  const { rows } = await pool.query(sql, [id_usuario, id_permiso]);
  return rows[0] || null;
}

/* ============================================================
   QUITAR PERMISO DE USUARIO
   ============================================================ */
async function quitarPermisoUsuario(id_usuario, id_permiso) {

  const sql = `
    DELETE FROM usuario_permiso
    WHERE id_usuario = $1 AND id_permiso = $2;
  `;

  await pool.query(sql, [id_usuario, id_permiso]);
  return true;
}

/* ============================================================
   PERFIL DE USUARIO
   ============================================================ */

const getPerfilUsuario = async (id) => {
  const result = await pool.query(
    `SELECT * FROM fn_get_perfil_usuario($1)`,
    [id]
  );

  return result.rows[0];
};

module.exports = {
  listarUsuarios,
  obtenerUsuario,
  crearUsuario,
  actualizarUsuario,
  bloquearUsuario,
  inactivarUsuario,
  cambiarPassword,
  listarPermisosUsuario,
  asignarPermisoUsuario,
  quitarPermisoUsuario,
  getPerfilUsuario
};