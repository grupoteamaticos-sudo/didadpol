-- Agrega stock_minimo como atributo del bien (valor por defecto por bodega)
ALTER TABLE public.bien
  ADD COLUMN IF NOT EXISTS stock_minimo numeric(14,3);

COMMENT ON COLUMN public.bien.stock_minimo IS
  'Stock minimo por defecto que se usa en los reportes (stock critico). Puede ser sobrescrito por inventario.stock_minimo por bodega.';
