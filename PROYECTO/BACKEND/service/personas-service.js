const pool = require('../DB/db');

/* =========================================
   LISTAR PERSONAS
========================================= */
async function listarPersonas() {
  const { rows } = await pool.query(`
    SELECT 
      p.id_persona,
      CONCAT(
        p.primer_nombre, ' ',
        COALESCE(p.segundo_nombre, ''), ' ',
        p.primer_apellido, ' ',
        COALESCE(p.segundo_apellido, '')
      ) AS nombre_completo
    FROM persona p
    WHERE p.estado_persona = 'ACTIVO'
    AND NOT EXISTS (
      SELECT 1 
      FROM empleado e 
      WHERE e.id_persona = p.id_persona
    )
    ORDER BY p.primer_nombre;
  `);

  return rows;
}

/* =========================================
   CREAR PERSONA (SP)
========================================= */
async function crearPersona(data) {
  const {
    primer_nombre,
    segundo_nombre,
    primer_apellido,
    segundo_apellido,
    identidad,
    fecha_nacimiento,
    sexo,

    tipo_telefono,
    numero,

    pais,
    departamento,
    municipio,
    colonia_barrio,
    direccion_detallada,

    correo,

    id_usuario_accion,
    ip_origen
  } = data;

  // CALL al SP (OUT se pasa como NULL)
  await pool.query(
    `
    CALL sp_persona_crear(
      $1,$2,$3,$4,$5,$6,$7,
      $8,$9,
      $10,$11,$12,$13,$14,
      $15,
      $16,$17,
      $18
    );
    `,
    [
      primer_nombre,
      segundo_nombre,
      primer_apellido,
      segundo_apellido,
      identidad,
      fecha_nacimiento,
      sexo,

      tipo_telefono,
      numero,

      pais,
      departamento,
      municipio,
      colonia_barrio,
      direccion_detallada,

      correo,

      id_usuario_accion,
      ip_origen,

      null // OUT p_id_persona
    ]
  );

  return true;
}

/* =========================================
   OBTENER PERSONA POR ID
========================================= */
async function obtenerPersona(id) {
  const { rows } = await pool.query(`
    SELECT
      p.id_persona,
      p.primer_nombre,
      p.segundo_nombre,
      p.primer_apellido,
      p.segundo_apellido,
      p.identidad,
      p.fecha_nacimiento,
      p.sexo,
      (SELECT t.numero FROM telefono_persona t WHERE t.id_persona = p.id_persona LIMIT 1) AS numero,
      (SELECT c.correo_electronico FROM correo_persona c WHERE c.id_persona = p.id_persona LIMIT 1) AS correo
    FROM persona p
    WHERE p.id_persona = $1
  `, [id]);

  return rows[0] || null;
}

/* =========================================
   LISTAR TODAS LAS PERSONAS (PARA EDITAR)
========================================= */
async function listarTodasPersonas() {
  const { rows } = await pool.query(`
    SELECT
      p.id_persona,
      p.primer_nombre,
      COALESCE(p.segundo_nombre, '') AS segundo_nombre,
      p.primer_apellido,
      COALESCE(p.segundo_apellido, '') AS segundo_apellido,
      p.identidad,
      p.fecha_nacimiento,
      p.sexo,
      p.estado_persona,
      CONCAT(
        p.primer_nombre, ' ',
        COALESCE(p.segundo_nombre, ''), ' ',
        p.primer_apellido, ' ',
        COALESCE(p.segundo_apellido, '')
      ) AS nombre_completo,
      (SELECT t.numero FROM telefono_persona t WHERE t.id_persona = p.id_persona LIMIT 1) AS numero,
      (SELECT c.correo_electronico FROM correo_persona c WHERE c.id_persona = p.id_persona LIMIT 1) AS correo
    FROM persona p
    WHERE p.estado_persona = 'ACTIVO'
    ORDER BY p.primer_nombre;
  `);

  return rows;
}

/* =========================================
   ACTUALIZAR PERSONA
========================================= */
async function actualizarPersona(id, data) {
  const {
    primer_nombre,
    segundo_nombre,
    primer_apellido,
    segundo_apellido,
    identidad,
    fecha_nacimiento,
    sexo,
    numero,
    correo
  } = data;

  await pool.query(`
    UPDATE persona SET
      primer_nombre = $1,
      segundo_nombre = $2,
      primer_apellido = $3,
      segundo_apellido = $4,
      identidad = $5,
      fecha_nacimiento = $6,
      sexo = $7
    WHERE id_persona = $8
  `, [primer_nombre, segundo_nombre, primer_apellido, segundo_apellido, identidad, fecha_nacimiento, sexo, id]);

  // Actualizar telefono
  if (numero !== undefined) {
    const telExiste = await pool.query(
      `SELECT 1 FROM telefono_persona WHERE id_persona = $1 LIMIT 1`, [id]
    );
    if (telExiste.rows.length > 0) {
      await pool.query(`UPDATE telefono_persona SET numero = $1 WHERE id_persona = $2`, [numero, id]);
    } else if (numero) {
      await pool.query(`INSERT INTO telefono_persona(id_persona, tipo_telefono, numero) VALUES($1, 'CELULAR', $2)`, [id, numero]);
    }
  }

  // Actualizar correo
  if (correo !== undefined) {
    const correoExiste = await pool.query(
      `SELECT 1 FROM correo_persona WHERE id_persona = $1 LIMIT 1`, [id]
    );
    if (correoExiste.rows.length > 0) {
      await pool.query(`UPDATE correo_persona SET correo_electronico = $1 WHERE id_persona = $2`, [correo, id]);
    } else if (correo) {
      await pool.query(`INSERT INTO correo_persona(id_persona, correo_electronico, principal, estado_correo) VALUES($1, $2, true, 'ACTIVO')`, [id, correo]);
    }
  }

  return true;
}

module.exports = {
  listarPersonas,
  listarTodasPersonas,
  crearPersona,
  obtenerPersona,
  actualizarPersona
};