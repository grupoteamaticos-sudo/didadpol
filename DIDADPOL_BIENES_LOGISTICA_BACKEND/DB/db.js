/* -----------------------------------------------------------------------
	Proyecto [ *** BIENES Y LOGISTICA ***]


Equipo:
Juan Cerrato .......... (grupoteamaticos@gmail.com)

-----------------------------------------------------------------------
---------------------------------------------------------------------

Programa:         
Fecha:              24/02/2026
Programador:        Juan Cerrato, Chris Morales
descripcion:        Conexion DB Postgres

-----------------------------------------------------------------------
-----------------------------------------------------------------------

                Historial de Cambio

-----------------------------------------------------------------------

Programador               Fecha                      Descripcion
CHRIS MORALES             20/04/2026                 VALIDACIONES EN GENERAL
                                                     AGREGO MODULOS
-----------------------------------------------------------------------
----------------------------------------------------------------------- */

const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_DATABASE,
  port: Number(process.env.DB_PORT),

  // SOLUCION CLAVE: fijar schema
  options: '-c search_path=public',

  // ssl: { rejectUnauthorized: false } // solo producción
});

// Mejor practica: probar conexion SIN dejarla abierta
pool.query('SELECT NOW()')
  .then(() => console.log('[OK] PostgreSQL conectado'))
  .catch(err => console.error('[ERROR] Error PostgreSQL:', err.message));

module.exports = pool;