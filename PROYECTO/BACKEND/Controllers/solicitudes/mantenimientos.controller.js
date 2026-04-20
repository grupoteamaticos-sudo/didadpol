const {
  listarMantenimientos,
  catalogos,
  programarMantenimiento,
  iniciarMantenimiento,
  finalizarMantenimiento
} = require('../../service/mantenimientos-service');

const getMantenimientos = async (req, res) => {
  try {
    const data = await listarMantenimientos();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

const getCatalogos = async (req, res) => {
  try {
    const data = await catalogos();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

const postProgramar = async (req, res) => {
  try {
    const payload = {
      ...req.body,
      id_usuario: req.user.id_usuario,
      ip_origen: req.ip
    };
    const result = await programarMantenimiento(payload);
    res.status(201).json({ ok: true, data: result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

const postIniciar = async (req, res) => {
  try {
    const payload = {
      ...req.body,
      id_mantenimiento: Number(req.params.id),
      id_usuario: req.user.id_usuario,
      ip_origen: req.ip
    };
    const result = await iniciarMantenimiento(payload);
    res.json({ ok: true, data: result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

const postFinalizar = async (req, res) => {
  try {
    const payload = {
      ...req.body,
      id_mantenimiento: Number(req.params.id),
      id_usuario: req.user.id_usuario,
      ip_origen: req.ip
    };
    const result = await finalizarMantenimiento(payload);
    res.json({ ok: true, data: result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
};

module.exports = {
  getMantenimientos,
  getCatalogos,
  postProgramar,
  postIniciar,
  postFinalizar
};
