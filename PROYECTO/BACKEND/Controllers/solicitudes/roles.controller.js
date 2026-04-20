const {
  listarRoles,
  obtenerRol,
  crearRol,
  actualizarRol,
  eliminarRol,
  asignarPermiso,
  quitarPermiso
} = require('../../service/roles-service');

// -------------------------------------------
// LISTAR ROLES
// -------------------------------------------
const getRoles = async (req, res) => {
  try {
    const roles = await listarRoles();
    res.json({ ok: true, roles });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error listando roles' });
  }
};

// -------------------------------------------
// OBTENER ROL
// -------------------------------------------
const getRol = async (req, res) => {
  try {
    const rol = await obtenerRol(req.params.id);
    if (!rol) return res.status(404).json({ ok: false, msg: 'Rol no encontrado' });

    res.json({ ok: true, rol });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error obteniendo rol' });
  }
};

// -------------------------------------------
// CREAR ROL
// -------------------------------------------
const postRol = async (req, res) => {
  try {
    const rol = await crearRol(req.body);
    res.json({ ok: true, rol });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error creando rol' });
  }
};

// -------------------------------------------
// ACTUALIZAR ROL
// -------------------------------------------
const patchRol = async (req, res) => {
  try {
    const rol = await actualizarRol(req.params.id, req.body);
    res.json({ ok: true, rol });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error actualizando rol' });
  }
};

// -------------------------------------------
// ELIMINAR ROL
// -------------------------------------------
const deleteRol = async (req, res) => {
  try {
    await eliminarRol(req.params.id);
    res.json({ ok: true, msg: 'Rol eliminado' });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error eliminando rol' });
  }
};

// -------------------------------------------
// ASIGNAR PERMISO
// -------------------------------------------
const postPermisoToRol = async (req, res) => {
  try {
    const { id_permiso } = req.body;
    const result = await asignarPermiso(req.params.id, id_permiso);
    res.json({ ok: true, result });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error asignando permiso a rol' });
  }
};

// -------------------------------------------
// QUITAR PERMISO
// -------------------------------------------
const deletePermisoFromRol = async (req, res) => {
  try {
    const { id_permiso } = req.body;
    await quitarPermiso(req.params.id, id_permiso);
    res.json({ ok: true, msg: 'Permiso removido del rol' });
  } catch (error) {
    res.status(500).json({ ok: false, msg: 'Error removiendo permiso' });
  }
};

module.exports = {
  getRoles,
  getRol,
  postRol,
  patchRol,
  deleteRol,
  postPermisoToRol,
  deletePermisoFromRol
};