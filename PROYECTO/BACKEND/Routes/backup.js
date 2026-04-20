const { Router } = require('express');
const { validarJWT } = require('../Middlewares/validar-jwt');
const { soloSuperAdmin } = require('../Middlewares/validar-rol');
const {
  crearBackup,
  restaurarBackup,
  listarBackups,
  eliminarBackup,
  descargarBackup,
} = require('../service/backup-service');

const router = Router();

// Listar backups disponibles
router.get('/', validarJWT, soloSuperAdmin, async (req, res) => {
  try {
    const data = listarBackups();
    res.json({ ok: true, data });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});

// Crear nuevo backup
router.post('/', validarJWT, soloSuperAdmin, async (req, res) => {
  try {
    const result = await crearBackup();
    res.status(201).json({ ok: true, data: result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});

// Restaurar backup
router.post('/restore', validarJWT, soloSuperAdmin, async (req, res) => {
  try {
    const { nombre } = req.body;
    if (!nombre) {
      return res.status(400).json({ ok: false, message: 'Debe indicar el nombre del archivo' });
    }
    const result = await restaurarBackup(nombre);
    res.json({ ok: true, data: result });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});

// Descargar backup
router.get('/download/:nombre', validarJWT, soloSuperAdmin, (req, res) => {
  try {
    const filePath = descargarBackup(req.params.nombre);
    res.download(filePath);
  } catch (error) {
    res.status(404).json({ ok: false, message: error.message });
  }
});

// Eliminar backup
router.delete('/:nombre', validarJWT, soloSuperAdmin, async (req, res) => {
  try {
    eliminarBackup(req.params.nombre);
    res.json({ ok: true, message: 'Backup eliminado' });
  } catch (error) {
    res.status(500).json({ ok: false, message: error.message });
  }
});

module.exports = router;
