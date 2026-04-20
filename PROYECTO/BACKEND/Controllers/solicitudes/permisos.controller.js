const {
  listarPermisos,
  obtenerPermiso,
  crearPermiso,
  actualizarPermiso,
  eliminarPermiso
} = require('../../service/permisos-service');

// -------------------------------------------
// LISTAR
// -------------------------------------------
const getPermisos = async (req, res) => {
  try {
    const permisos = await listarPermisos();
    res.json({ ok: true, permisos });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error listando permisos' });
  }
};

// -------------------------------------------
// OBTENER
// -------------------------------------------
const getPermiso = async (req, res) => {
  try {
    const permiso = await obtenerPermiso(req.params.id);
    if (!permiso) return res.status(404).json({ ok: false, msg: 'Permiso no encontrado' });

    res.json({ ok: true, permiso });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error obteniendo permiso' });
  }
};

// -------------------------------------------
// CREAR
// -------------------------------------------
const postPermiso = async (req, res) => {
  try {
    const permiso = await crearPermiso(req.body);
    res.json({ ok: true, permiso });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error creando permiso' });
  }
};

// -------------------------------------------
// ACTUALIZAR
// -------------------------------------------
const patchPermiso = async (req, res) => {
  try {
    const permiso = await actualizarPermiso(req.params.id, req.body);
    res.json({ ok: true, permiso });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error actualizando permiso' });
  }
};

// -------------------------------------------
// ELIMINAR
// -------------------------------------------
const deletePermiso = async (req, res) => {
  try {
    await eliminarPermiso(req.params.id);
    res.json({ ok: true, msg: 'Permiso eliminado' });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error eliminando permiso' });
  }
};

module.exports = {
  getPermisos,
  getPermiso,
  postPermiso,
  patchPermiso,
  deletePermiso
};