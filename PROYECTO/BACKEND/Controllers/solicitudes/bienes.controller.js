const pool = require('../../DB/db');

// ============================
// LISTAR BIENES
// ============================
const listarBienes = async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT
        b.id_bien,
        b.codigo_inventario,
        b.nombre_bien,
        b.marca,
        b.modelo,
        b.valor_unitario,
        b.stock_minimo,
        b.estado_bien,
        b.requiere_mantenimiento,
        COALESCE(SUM(i.stock_actual), 0) AS stock_total
      FROM bien b
      LEFT JOIN inventario i ON i.id_bien = b.id_bien
      WHERE b.estado_bien = 'ACTIVO'
      GROUP BY b.id_bien
      ORDER BY b.id_bien DESC
    `);

    res.json({ ok: true, data: rows });

  } catch (error) {
    console.error(error);
    res.status(500).json({
      ok: false,
      message: 'Error al listar bienes'
    });
  }
};

// ============================
// CREAR BIEN
// ============================
const crearBien = async (req, res) => {
  try {
    const {
      codigo_inventario,
      nombre_bien,
      marca,
      modelo,
      valor_unitario,
      stock_minimo,
      requiere_mantenimiento
    } = req.body;

    if (!codigo_inventario || !nombre_bien) {
      return res.status(400).json({
        ok: false,
        message: 'Código y nombre son obligatorios'
      });
    }

    const stockMinimoParsed =
      stock_minimo === undefined || stock_minimo === null || stock_minimo === ''
        ? null
        : Number(stock_minimo);

    if (stockMinimoParsed !== null && (isNaN(stockMinimoParsed) || stockMinimoParsed < 0)) {
      return res.status(400).json({
        ok: false,
        message: 'El stock mínimo debe ser un número no negativo'
      });
    }

    // evitar duplicados
    const existe = await pool.query(
      `SELECT 1 FROM bien WHERE codigo_inventario = $1`,
      [codigo_inventario]
    );

    if (existe.rows.length > 0) {
      return res.status(400).json({
        ok: false,
        message: 'El código ya existe'
      });
    }

    await pool.query(`
      INSERT INTO bien (
        codigo_inventario,
        nombre_bien,
        marca,
        modelo,
        valor_unitario,
        stock_minimo,
        requiere_mantenimiento,
        estado_bien
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'ACTIVO')
    `, [
      codigo_inventario,
      nombre_bien,
      marca || null,
      modelo || null,
      valor_unitario || 0,
      stockMinimoParsed,
      !!requiere_mantenimiento
    ]);

    res.json({
      ok: true,
      message: 'Bien creado correctamente'
    });

  } catch (error) {
    console.error(error);
    res.status(500).json({
      ok: false,
      message: error.message
    });
  }
};



// ============================
// REGISTRAR MOVIMIENTO (KARDEX)
// ============================
const registrarBienes = async (req, res) => {
  const client = await pool.connect();

  try {
    const {
      tipo_registro,
      usuario,
      detalles,
      id_bodega
    } = req.body;

    if (!detalles || detalles.length === 0) {
      return res.status(400).json({
        ok: false,
        message: 'Debe enviar detalles'
      });
    }

    await client.query('BEGIN');

    for (const d of detalles) {

      // VALIDAR BIEN
      const bienRes = await client.query(
        `SELECT id_bien FROM bien WHERE codigo_inventario = $1`,
        [d.codigo_inventario]
      );

      if (bienRes.rows.length === 0) {
        throw new Error(`El bien no existe: ${d.codigo_inventario}`);
      }

      const id_bien = bienRes.rows[0].id_bien;

      // OBTENER STOCK
      const stockRes = await client.query(`
        SELECT stock_actual
        FROM inventario
        WHERE id_bien = $1 AND id_bodega = $2
      `, [id_bien, id_bodega]);

      const stockAnterior = Number(stockRes.rows[0]?.stock_actual || 0);

      // VALIDAR BAJA
      if (tipo_registro === 'BAJA') {
        if (!stockRes.rows.length) {
          throw new Error(`No existe inventario para ${d.codigo_inventario}`);
        }

        if (stockAnterior <= 0) {
          throw new Error(`No hay stock disponible para ${d.codigo_inventario}`);
        }

        if (stockAnterior < d.cantidad) {
          throw new Error(
            `Stock insuficiente para ${d.codigo_inventario} (actual: ${stockAnterior})`
          );
        }
      }

      // VALIDAR AJUSTE
      if (tipo_registro === 'AJUSTE') {
        if (!Number.isInteger(Number(d.cantidad)) || Number(d.cantidad) < 0) {
          throw new Error(`El stock debe ser un numero entero no negativo`);
        }
      }

      // INVENTARIO
      const existeInv = await client.query(`
        SELECT stock_actual
        FROM inventario
        WHERE id_bien = $1 AND id_bodega = $2
      `, [id_bien, id_bodega]);

      const cantidad = Math.floor(Number(d.cantidad));

      if (existeInv.rows.length === 0) {

        if (tipo_registro === 'BAJA') {
          throw new Error(`No existe inventario para ${d.codigo_inventario}`);
        }

        await client.query(`
          INSERT INTO inventario (
            id_bien,
            id_bodega,
            stock_actual,
            stock_reservado,
            stock_minimo,
            estado_inventario
          )
          VALUES (
            $1, $2, $3, 0,
            (SELECT stock_minimo FROM bien WHERE id_bien = $1),
            'ACTIVO'
          )
        `, [id_bien, id_bodega, cantidad]);

      } else {

        const stockActual = Math.floor(Number(existeInv.rows[0].stock_actual));
        let nuevoStock = stockActual;

        if (tipo_registro === 'ALTA') {
          nuevoStock = stockActual + cantidad;
        }

        if (tipo_registro === 'BAJA') {
          nuevoStock = stockActual - cantidad;
        }

        if (tipo_registro === 'AJUSTE') {
          nuevoStock = cantidad;
        }

        await client.query(`
          UPDATE inventario
          SET stock_actual = $1
          WHERE id_bien = $2 AND id_bodega = $3
        `, [nuevoStock, id_bien, id_bodega]);
      }

      // HISTORIAL (KARDEX)
      const accion = tipo_registro === 'ALTA' ? 'LIBERAR'
                   : tipo_registro === 'BAJA' ? 'CONSUMIR'
                   : 'AJUSTE';

      await client.query(`
        INSERT INTO historial_reservas (
          id_bien,
          id_bodega,
          accion,
          cantidad,
          usuario,
          fecha
        )
        VALUES ($1, $2, $3, $4, $5, NOW())
      `, [
        id_bien,
        id_bodega,
        accion,
        cantidad,
        usuario
      ]);
    }

    await client.query('COMMIT');

    res.json({
      ok: true,
      message: 'Registro aplicado correctamente (inventario + kardex)'
    });

  } catch (error) {
    await client.query('ROLLBACK');

    console.error('[ERROR] ERROR REGISTRO BIENES:', error);

    res.status(500).json({
      ok: false,
      message: error.message
    });

  } finally {
    client.release();
  }
};

// ============================
// ELIMINAR BIEN (INACTIVAR)
// ============================
const eliminarBien = async (req, res) => {
  try {
    const { id } = req.params;

    await pool.query(`
      UPDATE bien SET estado_bien = 'INACTIVO' WHERE id_bien = $1
    `, [id]);

    res.json({ ok: true, message: 'Bien eliminado correctamente' });

  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, message: error.message });
  }
};

module.exports = {
  listarBienes,
  registrarBienes,
  crearBien,
  eliminarBien
};