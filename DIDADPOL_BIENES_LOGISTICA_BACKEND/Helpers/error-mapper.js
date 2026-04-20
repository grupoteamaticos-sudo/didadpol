/**
 * Mapeo de errores técnicos a mensajes amigables para el usuario.
 * Cada entrada: { pattern: RegExp, code: string, message: string }
 */
const ERROR_MAP = [
  {
    pattern: /ECONNREFUSED/i,
    code: 'ERR-001',
    message: 'No se puede conectar con la base de datos. Contacte al administrador.'
  },
  {
    pattern: /foreign key constraint|violates foreign key/i,
    code: 'ERR-002',
    message: 'No se puede eliminar este registro porque tiene datos relacionados.'
  },
  {
    pattern: /duplicate key|unique constraint|llave duplicada|valor de llave duplicado/i,
    code: 'ERR-003',
    message: 'Ya existe un registro con estos datos. Verifique e intente de nuevo.'
  },
  {
    pattern: /null value in column|violates not-null/i,
    code: 'ERR-004',
    message: 'Faltan campos obligatorios. Verifique el formulario.'
  },
  {
    pattern: /value too long|character varying/i,
    code: 'ERR-005',
    message: 'Uno o mas campos exceden el tamano permitido.'
  },
  {
    pattern: /invalid input syntax|tipo de dato/i,
    code: 'ERR-006',
    message: 'Tipo de dato invalido. Verifique los campos ingresados.'
  },
  {
    pattern: /permission denied|permiso denegado/i,
    code: 'ERR-007',
    message: 'No tiene permisos para realizar esta accion.'
  },
  {
    pattern: /timeout|tiempo de espera/i,
    code: 'ERR-008',
    message: 'La operacion tardo demasiado. Intente de nuevo.'
  },
  {
    pattern: /stock insuficiente|stock_actual.*menor|Cantidad inválida/i,
    code: 'ERR-009',
    message: 'Stock insuficiente para realizar esta operacion.'
  },
  {
    pattern: /no existe|does not exist|not found/i,
    code: 'ERR-010',
    message: 'El registro solicitado no fue encontrado.'
  },
  {
    pattern: /usuario bloqueado|bloqueado/i,
    code: 'ERR-011',
    message: 'El usuario se encuentra bloqueado. Contacte al administrador.'
  },
  {
    pattern: /contraseña incorrecta|password.*incorrect|credenciales/i,
    code: 'ERR-012',
    message: 'Credenciales incorrectas. Verifique usuario y contrasena.'
  },
  {
    pattern: /token.*expired|jwt expired|token.*invalido/i,
    code: 'ERR-013',
    message: 'Su sesion ha expirado. Inicie sesion nuevamente.'
  },
];

/**
 * Traduce un error técnico a un mensaje amigable.
 * @param {Error|string} error - El error original
 * @returns {{ code: string, message: string, original: string }}
 */
function mapError(error) {
  const msg = typeof error === 'string' ? error : (error?.message || '');

  for (const entry of ERROR_MAP) {
    if (entry.pattern.test(msg)) {
      return {
        code: entry.code,
        message: entry.message,
        original: msg,
      };
    }
  }

  return {
    code: 'ERR-999',
    message: 'Error desconocido. Favor contactar al administrador.',
    original: msg,
  };
}

module.exports = { mapError, ERROR_MAP };
