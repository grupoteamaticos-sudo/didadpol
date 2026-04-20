const {
  reservar,
  liberar,
  consumir,
  listarReservas,
  listarHistorial
} = require('../../service/reservas-service');

const postReservar = async (req, res) => {
  try {
    const result = await reservar(req.body);
    return res.status(201).json({ ok: true, data: result });
  } catch (error) {
    return res.status(500).json({ ok: false, message: error.message });
  }
};

const patchLiberar = async (req, res) => {
  try {
    const result = await liberar(req.body);
    return res.json({ ok: true, data: result });
  } catch (error) {
    return res.status(500).json({ ok: false, message: error.message });
  }
};

const patchConsumir = async (req, res) => {
  try {
    const result = await consumir(req.body);
    return res.json({ ok: true, data: result });
  } catch (error) {
    return res.status(500).json({ ok: false, message: error.message });
  }
};

const getReservas = async (req, res) => {
  try {
    const result = await listarReservas();
    return res.json({ ok: true, data: result });
  } catch (error) {
    return res.status(500).json({ ok: false, message: error.message });
  }
};

const getHistorial = async (req, res) => {
  try {
    console.log('[DEBUG] ENTRANDO A HISTORIAL');
    const result = await listarHistorial();
    return res.json({ ok: true, data: result });
  } catch (error) {
    console.error('[ERROR] ERROR HISTORIAL CONTROLLER:', error);
    return res.status(500).json({
      ok: false,
      message: error.message
    });
  }
};

module.exports = {
  postReservar,
  patchLiberar,
  patchConsumir,
  getReservas,
  getHistorial
};