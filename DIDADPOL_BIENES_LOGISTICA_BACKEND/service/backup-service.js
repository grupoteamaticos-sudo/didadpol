const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');

const BACKUP_DIR = path.join(__dirname, '..', 'backups');

// Asegurar que exista la carpeta de backups
if (!fs.existsSync(BACKUP_DIR)) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
}

function getBackupFileName() {
  const now = new Date();
  const ts = now.toISOString().replace(/[:.]/g, '-').slice(0, 19);
  return `backup_${process.env.DB_DATABASE}_${ts}.sql`;
}

async function crearBackup() {
  const fileName = getBackupFileName();
  const filePath = path.join(BACKUP_DIR, fileName);

  const env = {
    ...process.env,
    PGPASSWORD: process.env.DB_PASSWORD,
  };

  const cmd = `pg_dump -h ${process.env.DB_HOST} -p ${process.env.DB_PORT} -U ${process.env.DB_USER} -d ${process.env.DB_DATABASE} -F p -f "${filePath}"`;

  return new Promise((resolve, reject) => {
    exec(cmd, { env }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(stderr || error.message));
        return;
      }

      const stats = fs.statSync(filePath);
      resolve({
        nombre: fileName,
        tamano: (stats.size / 1024).toFixed(2) + ' KB',
        fecha: new Date().toISOString(),
        ruta: filePath,
      });
    });
  });
}

async function restaurarBackup(fileName) {
  const filePath = path.join(BACKUP_DIR, fileName);

  if (!fs.existsSync(filePath)) {
    throw new Error('Archivo de backup no encontrado');
  }

  const env = {
    ...process.env,
    PGPASSWORD: process.env.DB_PASSWORD,
  };

  const cmd = `psql -h ${process.env.DB_HOST} -p ${process.env.DB_PORT} -U ${process.env.DB_USER} -d ${process.env.DB_DATABASE} -f "${filePath}"`;

  return new Promise((resolve, reject) => {
    exec(cmd, { env }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(stderr || error.message));
        return;
      }
      resolve({ ok: true, mensaje: 'Base de datos restaurada correctamente' });
    });
  });
}

function listarBackups() {
  if (!fs.existsSync(BACKUP_DIR)) return [];

  const files = fs.readdirSync(BACKUP_DIR)
    .filter(f => f.endsWith('.sql'))
    .map(f => {
      const stats = fs.statSync(path.join(BACKUP_DIR, f));
      return {
        nombre: f,
        tamano: (stats.size / 1024).toFixed(2) + ' KB',
        fecha: stats.mtime.toISOString(),
      };
    })
    .sort((a, b) => new Date(b.fecha).getTime() - new Date(a.fecha).getTime());

  return files;
}

function eliminarBackup(fileName) {
  const filePath = path.join(BACKUP_DIR, fileName);
  if (!fs.existsSync(filePath)) {
    throw new Error('Archivo no encontrado');
  }
  fs.unlinkSync(filePath);
  return { ok: true };
}

function descargarBackup(fileName) {
  const filePath = path.join(BACKUP_DIR, fileName);
  if (!fs.existsSync(filePath)) {
    throw new Error('Archivo no encontrado');
  }
  return filePath;
}

module.exports = {
  crearBackup,
  restaurarBackup,
  listarBackups,
  eliminarBackup,
  descargarBackup,
};
