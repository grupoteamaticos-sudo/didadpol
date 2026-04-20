const pool = require('../DB/db');
const bcrypt = require('bcryptjs');

const MAX_INTENTOS = parseInt(process.env.MAX_INTENTOS_LOGIN, 10) || 3;

async function findUserByUsername(nombre_usuario) {
  const sql = `
    SELECT
      id_usuario,
      id_empleado,
      nombre_usuario,
      contrasena_usuario,
      correo_login,
      pin_hash,
      ultimo_acceso,
      intentos_fallidos,
      bloqueado,
      estado_usuario
    FROM usuario
    WHERE nombre_usuario = $1
    LIMIT 1;
  `;
  const { rows } = await pool.query(sql, [nombre_usuario]);
  return rows[0] || null;
}

async function findPinHashById(id_usuario) {
  const { rows } = await pool.query(
    `SELECT pin_hash FROM usuario WHERE id_usuario = $1 LIMIT 1;`,
    [id_usuario]
  );
  return rows[0]?.pin_hash || null;
}

async function findUserForPinResetById(id_usuario) {
  const { rows } = await pool.query(
    `SELECT id_usuario, nombre_usuario, correo_login, estado_usuario
       FROM usuario
      WHERE id_usuario = $1
      LIMIT 1;`,
    [id_usuario]
  );
  return rows[0] || null;
}

async function savePinResetToken(id_usuario, token, expires) {
  await pool.query(
    `UPDATE usuario
        SET pin_reset_token = $2,
            pin_reset_token_expires = $3
      WHERE id_usuario = $1;`,
    [id_usuario, token, expires]
  );
}

async function findPinResetTokenByUser(id_usuario) {
  const { rows } = await pool.query(
    `SELECT pin_reset_token, pin_reset_token_expires
       FROM usuario
      WHERE id_usuario = $1
      LIMIT 1;`,
    [id_usuario]
  );
  return rows[0] || null;
}

async function updatePinAndClearResetToken(id_usuario, pinHash) {
  await pool.query(
    `UPDATE usuario
        SET pin_hash = $2,
            pin_reset_token = NULL,
            pin_reset_token_expires = NULL
      WHERE id_usuario = $1;`,
    [id_usuario, pinHash]
  );
}

async function incrementFailedAttempt(id_usuario) {
  const sql = `
    UPDATE usuario
    SET
      intentos_fallidos = intentos_fallidos + 1,
      bloqueado = CASE WHEN (intentos_fallidos + 1) >= $2 THEN TRUE ELSE bloqueado END
    WHERE id_usuario = $1
    RETURNING intentos_fallidos, bloqueado;
  `;
  const { rows } = await pool.query(sql, [id_usuario, MAX_INTENTOS]);
  return rows[0] || null;
}

async function resetAttemptsAndUpdateAccess(id_usuario) {
  const sql = `
    UPDATE usuario
    SET
      intentos_fallidos = 0,
      bloqueado = FALSE,
      ultimo_acceso = NOW()
    WHERE id_usuario = $1;
  `;
  await pool.query(sql, [id_usuario]);
}

async function getRolesPermisos(id_usuario) {
  const sql = `
    SELECT
      r.id_rol,
      r.nombre_rol,
      p.id_permiso,
      p.codigo_permiso,
      p.nombre_permiso
    FROM usuario_rol ur
    INNER JOIN rol r ON r.id_rol = ur.id_rol
    LEFT JOIN rol_permiso rp ON rp.id_rol = r.id_rol
    LEFT JOIN permiso p ON p.id_permiso = rp.id_permiso
    WHERE ur.id_usuario = $1
      AND r.estado_rol = 'ACTIVO'
      AND (p.id_permiso IS NULL OR p.estado_permiso = 'ACTIVO');
  `;
  const { rows } = await pool.query(sql, [id_usuario]);

  const rolesMap = new Map();
  const permisosMap = new Map();

  for (const row of rows) {
    if (row.id_rol) rolesMap.set(row.id_rol, { id_rol: row.id_rol, nombre_rol: row.nombre_rol });
    if (row.id_permiso) permisosMap.set(row.codigo_permiso, {
      id_permiso: row.id_permiso,
      codigo_permiso: row.codigo_permiso,
      nombre_permiso: row.nombre_permiso
    });
  }

  return {
    roles: Array.from(rolesMap.values()),
    permisos: Array.from(permisosMap.values())
  };
}

async function verifyPassword(plain, hash) {
  return bcrypt.compare(plain, hash);
}

/* ============================================================
   REGISTRO ENTERPRISE
   ============================================================ */
async function createUserEnterprise({
  id_empleado,
  username,
  password,
  correo,
  id_usuario_accion,
  ip_origen
}) {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);

    const userResult = await client.query(
      `SELECT * FROM sp_usuario_crear(
        $1, $2, $3, $4, $5, $6
      )`,
      [
        id_empleado,
        username,
        passwordHash,
        correo,
        id_usuario_accion,
        ip_origen
      ]
    );

    const id_usuario = userResult.rows[0]?.p_id_usuario;

    if (!id_usuario) {
      throw new Error('No se pudo crear el usuario');
    }

    await client.query(
      `SELECT * FROM sp_usuario_asignar_rol(
        $1, $2, $3, $4
      )`,
      [
        id_usuario,
        4, // CONSULTA
        id_usuario_accion,
        ip_origen
      ]
    );

    await client.query(
      `SELECT * FROM sp_log_evento(
        $1, $2, $3, $4, $5, $6
      )`,
      [
        id_usuario_accion,
        'USUARIO_CREADO',
        'usuario',
        id_usuario,
        ip_origen,
        `Usuario creado: ${username}`
      ]
    );

    await client.query('COMMIT');

    return { id_usuario };

  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function findUserByIdentifier(identifier) {
  const sql = `
    SELECT
      id_usuario,
      id_empleado,
      nombre_usuario,
      contrasena_usuario,
      correo_login,
      intentos_fallidos,
      bloqueado,
      estado_usuario
    FROM usuario
    WHERE nombre_usuario = $1 OR correo_login = $1
    LIMIT 1;
  `;
  const { rows } = await pool.query(sql, [identifier]);
  return rows[0] || null;
}

async function findUserByUsernameAndEmail(nombre_usuario, correo_login) {
  const sql = `
    SELECT
      id_usuario,
      id_empleado,
      nombre_usuario,
      contrasena_usuario,
      correo_login,
      intentos_fallidos,
      bloqueado,
      estado_usuario
    FROM usuario
    WHERE LOWER(nombre_usuario) = LOWER($1)
      AND LOWER(correo_login)   = LOWER($2)
    LIMIT 1;
  `;
  const { rows } = await pool.query(sql, [nombre_usuario, correo_login]);
  return rows[0] || null;
}

async function saveResetToken(id_usuario, token, expires) {
  const sql = `
    UPDATE usuario
       SET reset_token = $2,
           reset_token_expires = $3
     WHERE id_usuario = $1;
  `;
  await pool.query(sql, [id_usuario, token, expires]);
}

async function findResetTokenByUser(id_usuario) {
  const sql = `
    SELECT reset_token, reset_token_expires
      FROM usuario
     WHERE id_usuario = $1
     LIMIT 1;
  `;
  const { rows } = await pool.query(sql, [id_usuario]);
  return rows[0] || null;
}

async function updatePasswordAndClearToken(id_usuario, hash) {
  const sql = `
    UPDATE usuario
       SET contrasena_usuario = $2,
           reset_token = NULL,
           reset_token_expires = NULL,
           intentos_fallidos = 0,
           bloqueado = FALSE
     WHERE id_usuario = $1;
  `;
  await pool.query(sql, [id_usuario, hash]);
}

module.exports = {
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
};