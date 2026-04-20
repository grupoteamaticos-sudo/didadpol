const {
  listarDepartamentos,
  listarPuestos,
  listarSucursales
} = require('../../service/catalogos-service');

const getDepartamentos = async (req, res) => {
  try {
    const data = await listarDepartamentos();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

const getPuestos = async (req, res) => {
  try {
    const data = await listarPuestos();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

const getSucursales = async (req, res) => {
  try {
    const data = await listarSucursales();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, msg: error.message });
  }
};

module.exports = {
  getDepartamentos,
  getPuestos,
  getSucursales
};