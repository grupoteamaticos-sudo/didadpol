-- PIN de 8 caracteres usado como 2FA estatico por usuario (se guarda hasheado)
ALTER TABLE public.usuario
  ADD COLUMN IF NOT EXISTS pin_hash varchar(100);

COMMENT ON COLUMN public.usuario.pin_hash IS
  'Hash bcrypt del PIN de 8 caracteres alfanumerico que el usuario debe ingresar en el paso 2FA despues del login.';
