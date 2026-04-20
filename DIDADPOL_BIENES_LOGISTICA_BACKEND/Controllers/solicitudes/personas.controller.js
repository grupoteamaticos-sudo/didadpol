const {
  listarPersonas,
  listarTodasPersonas,
  crearPersona,
  obtenerPersona,
  actualizarPersona
} = require('../../service/personas-service');

const getPersonas = async (req, res) => {
  try {
    const data = await listarPersonas();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

const postPersona = async (req, res) => {
  try {
    const payload = {
      ...req.body,
      id_usuario_accion: req.usuario?.id_usuario || null,
      ip_origen: req.ip
    };

    await crearPersona(payload);

    res.status(201).json({
      ok: true,
      msg: 'Persona creada correctamente'
    });

  } catch (error) {
    res.status(500).json({
      ok: false,
      msg: error.message
    });
  }
};

const getAllPersonas = async (req, res) => {
  try {
    const data = await listarTodasPersonas();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

const getPersonaById = async (req, res) => {
  try {
    const data = await obtenerPersona(req.params.id);
    if (!data) return res.status(404).json({ ok: false, msg: 'Persona no encontrada' });
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

const putPersona = async (req, res) => {
  try {
    await actualizarPersona(req.params.id, req.body);
    res.json({ ok: true, msg: 'Persona actualizada correctamente' });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

module.exports = {
  getPersonas,
  getAllPersonas,
  getPersonaById,
  postPersona,
  putPersona
};