const { obtenerInventario, reservarInventario } = require('../../service/inventario-service');

// ==============================
// GET INVENTARIO
// ==============================
const getInventario = async (req, res) => {
  try {
    const filters = {
      id_bodega: req.query.id_bodega ? Number(req.query.id_bodega) : null,
      id_bien: req.query.id_bien ? Number(req.query.id_bien) : null
    };

    const data = await obtenerInventario(filters);

    return res.json({ ok: true, data });

  } catch (error) {
    return res.status(500).json({ ok: false, message: error.message });
  }
};

// ==============================
// POST RESERVAR INVENTARIO
// ==============================
const reservarInventarioController = async (req, res) => {
  try {
    const { id_bodega, id_bien, id_bien_lote, cantidad } = req.body;

    if (!id_bodega || !cantidad || (!id_bien && !id_bien_lote)) {
      return res.status(400).json({
        ok: false,
        message: 'Datos incompletos'
      });
    }

    await reservarInventario({
      id_bodega,
      id_bien,
      id_bien_lote,
      cantidad
    });

    return res.json({
      ok: true,
      message: 'Reserva realizada correctamente'
    });

  } catch (error) {
    console.error('Error reserva:', error);

    return res.status(400).json({
      ok: false,
      message: error.message
    });
  }
};

module.exports = {
  getInventario,
  reservarInventario: reservarInventarioController
};