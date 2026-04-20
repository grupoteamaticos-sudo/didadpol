-- Columnas para flujo "olvidé mi contraseña"
ALTER TABLE public.usuario
  ADD COLUMN IF NOT EXISTS reset_token varchar(16),
  ADD COLUMN IF NOT EXISTS reset_token_expires timestamp without time zone;

COMMENT ON COLUMN public.usuario.reset_token IS
  'Token alfanumerico de 8 caracteres enviado por email para recuperar contrasena';
COMMENT ON COLUMN public.usuario.reset_token_expires IS
  'Fecha/hora de expiracion del reset_token (usualmente 15 minutos despues de generado)';
