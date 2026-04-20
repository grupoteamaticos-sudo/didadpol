const express = require('express');
const cors = require('cors');
const path = require('path');
const helmet = require('helmet');
const { createServer } = require('http');
const createRateLimiter = require('../Helpers/rate-limiter');
const { socketController } = require('../sockets/controller');
const pool = require('../DB/db');
const { setSocketInstance } = require('../sockets/socket.js');

class Server {
  constructor() {
    this.app = express();

    // 🔥 CORRECCIÓN CLAVE
    this.port = process.env.PORT || 5001;
    this.ip = '0.0.0.0';

    // HTTP + Socket.io
    this.serverHttp = createServer(this.app);
    this.io = require('socket.io')(this.serverHttp, {
      cors: {
        origin: true,
        credentials: true,
        methods: ['GET', 'POST']
      }
    });

    setSocketInstance(this.io);

    // ==============================
    // Rutas
    // ==============================
    this.authPath = '/api/auth';
    this.usersPath = '/api/usuarios';
    this.rolesPath = '/api/roles';
    this.permisosPath = '/api/permisos';
    this.personasPath = '/api/personas';
    this.empleadosPath = '/api/empleados';
    this.catalogosPath = '/api/catalogos';

    this.bienesPath = '/api/bienes';
    this.bienesItemsPath = '/api/bienes-items';
    this.proveedoresPath = '/api/proveedores';
    this.documentosPath = '/api/documentos';

    this.inventarioPath = '/api/inventario';
    this.reservasPath = '/api/reservas';
    this.solicitudesPath = '/api/solicitudes';
    this.kardexPath = '/api/kardex';
    this.registrosPath = '/api/registros';

    this.asignacionesPath = '/api/asignaciones';
    this.mantenimientosPath = '/api/mantenimientos';
    this.uploadsPath = '/api/uploads';

    this.middlewares();
    this.routes();
    this.sockets();
  }

  async middlewares() {
    this.app.use(helmet({ contentSecurityPolicy: false }));
    this.app.use(cors({ origin: true, credentials: true }));
    this.app.use(express.json({ limit: '100mb' }));

    // 🔥 CORRECCIÓN ERROR TEMPLATE STRING
    this.app.use(express.urlencoded({
      limit: `${process.env.FILE_LIMIT || 10}mb`,
      extended: false
    }));

    this.app.use(express.static('public'));

    try {
      const rateLimiter = await createRateLimiter({
        storeClient: pool,
        points: 100,
        duration: 60
      });

      this.app.use(async (req, res, next) => {
        try {
          await rateLimiter.consume(req.ip);
          next();
        } catch (error) {
          res.status(429).json({
            ok: false,
            msg: 'Demasiadas solicitudes, intenta más tarde.'
          });
        }
      });

    } catch (error) {
      console.error('Error iniciando rate limiter:', error);
    }
  }

  routes() {
    this.app.get('/api/health', (req, res) => {
      res.json({ ok: true, message: 'API Bienes & Logistica OK' });
    });

    // Seguridad
    this.app.use(this.authPath, require('../Routes/auth.js'));

    this.app.use(this.usersPath, require('../Routes/usuarios.js'));
    this.app.use(this.rolesPath, require('../Routes/roles.js'));
    this.app.use(this.personasPath, require('../Routes/personas.js'));
    this.app.use(this.empleadosPath, require('../Routes/empleados.js'));
    this.app.use(this.catalogosPath, require('../Routes/catalogos.js'));
    this.app.use(this.permisosPath, require('../Routes/permisos.js'));

    // Catálogos
    this.app.use(this.bienesPath, require('../Routes/bienes.js'));
    this.app.use(this.proveedoresPath, require('../Routes/proveedores.js'));

    // Operaciones
    this.app.use(this.inventarioPath, require('../Routes/inventario.js'));
    this.app.use(this.reservasPath, require('../Routes/reservas.js'));
    this.app.use(this.solicitudesPath, require('../Routes/solicitudes.js'));
    this.app.use(this.kardexPath, require('../Routes/kardex.js'));
    this.app.use(this.registrosPath, require('../Routes/registros.js'));

    // Extras
    this.app.use('/api/reportes', require('../Routes/reportes.js'));
    this.app.use(this.asignacionesPath, require('../Routes/asignaciones.js'));
    this.app.use('/api/backup', require('../Routes/backup.js'));
    this.app.use('/api/bitacora', require('../Routes/bitacora.js'));
    this.app.use(this.mantenimientosPath, require('../Routes/mantenimientos.js'));

    // 404
    this.app.use((req, res) => {
      res.status(404).json({
        ok: false,
        msg: 'Endpoint no encontrado'
      });
    });

    // Manejo de errores
    const { mapError } = require('../Helpers/error-mapper');

    this.app.use((err, req, res, _next) => {
      const mapped = mapError(err);
      console.error(`[${mapped.code}] ${mapped.original}`);

      res.status(err.status || 500).json({
        ok: false,
        code: mapped.code,
        message: mapped.message
      });
    });
  }

  sockets() {
    this.io.on('connection', (socket) => socketController(socket, this.io));
  }

  listen() {
    this.serverHttp.listen(this.port, this.ip, () => {
      console.log(`🚀 Servidor corriendo en http://${this.ip}:${this.port}`);
    });
  }
}

module.exports = { Server };