-- Columnas para flujo "olvide mi PIN OTP" (codigo numerico de 6 digitos enviado al correo)
ALTER TABLE public.usuario
  ADD COLUMN IF NOT EXISTS pin_reset_token varchar(10),
  ADD COLUMN IF NOT EXISTS pin_reset_token_expires timestamp without time zone;

COMMENT ON COLUMN public.usuario.pin_reset_token IS
  'Codigo numerico de 6 digitos enviado por email para restablecer el PIN OTP.';
COMMENT ON COLUMN public.usuario.pin_reset_token_expires IS
  'Fecha/hora de expiracion del pin_reset_token (usualmente 10 minutos).';
