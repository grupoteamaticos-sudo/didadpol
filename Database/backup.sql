--
-- PostgreSQL database dump
--

\restrict 3yUSmcOBlQGwpb2TZzwjS7nG4rfSlM9f3flMwMvWtu3ZJBaekaj4lfNrPr6C9J3

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: fn_get_perfil_usuario(bigint); Type: FUNCTION; Schema: public; Owner: juan
--

CREATE FUNCTION public.fn_get_perfil_usuario(p_id_usuario bigint) RETURNS TABLE(id_usuario bigint, nombre_usuario character varying, correo_login character varying, estado_usuario character varying, fecha_registro timestamp without time zone, primer_nombre character varying, segundo_nombre character varying, primer_apellido character varying, segundo_apellido character varying, identidad character varying, telefono character varying, sexo character varying, codigo_empleado character varying, fecha_ingreso date, nombre_departamento character varying, nombre_rol character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

  RETURN QUERY
  SELECT 
    u.id_usuario,
    u.nombre_usuario,
    u.correo_login,
    u.estado_usuario,
    u.fecha_registro,

    p.primer_nombre,
    p.segundo_nombre,
    p.primer_apellido,
    p.segundo_apellido,
    p.identidad,

    tp.numero AS telefono,

    p.sexo,

    e.codigo_empleado,
    e.fecha_ingreso,

    d.nombre_departamento,
    r.nombre_rol

  FROM usuario u

  LEFT JOIN empleado e ON e.id_empleado = u.id_empleado
  LEFT JOIN persona p ON p.id_persona = e.id_persona

  LEFT JOIN LATERAL (
    SELECT numero
    FROM telefono_persona
    WHERE id_persona = p.id_persona
      AND principal = true
      AND estado_telefono = 'ACTIVO'
    LIMIT 1
  ) tp ON true

  LEFT JOIN departamento d ON d.id_departamento = e.id_departamento
  LEFT JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
  LEFT JOIN rol r ON r.id_rol = ur.id_rol

  WHERE u.id_usuario = p_id_usuario
  LIMIT 1;

END;
$$;


ALTER FUNCTION public.fn_get_perfil_usuario(p_id_usuario bigint) OWNER TO juan;

--
-- Name: sp_asignacion_crear(bigint, bigint, character varying, bigint, bigint, bigint, bigint, numeric, character varying, character varying, date, character varying, text, text, boolean); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_asignacion_crear(IN p_id_tipo_registro_asignacion bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_id_empleado bigint, IN p_id_bodega_origen bigint, IN p_id_bien bigint, IN p_id_bien_item bigint, IN p_cantidad numeric, IN p_tipo_acta character varying, IN p_numero_acta character varying, IN p_fecha_emision_acta date, IN p_motivo_asignacion character varying, IN p_observaciones text, IN p_archivo_pdf text, IN p_firma_digital boolean, OUT p_id_asignacion bigint, OUT p_id_registro bigint, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_bien_final BIGINT;
    v_id_log_confirm BIGINT;
    v_id_detalle BIGINT;
BEGIN
    IF p_id_empleado IS NULL THEN
        RAISE EXCEPTION 'Debe indicar p_id_empleado';
    END IF;

    IF p_id_bodega_origen IS NULL THEN
        RAISE EXCEPTION 'Debe indicar p_id_bodega_origen';
    END IF;

    IF p_tipo_acta IS NULL OR LENGTH(TRIM(p_tipo_acta)) = 0 THEN
        RAISE EXCEPTION 'Debe indicar p_tipo_acta';
    END IF;

    IF p_id_bien_item IS NOT NULL THEN
        SELECT bi.id_bien
          INTO v_id_bien_final
          FROM bien_item bi
         WHERE bi.id_bien_item = p_id_bien_item;

        IF v_id_bien_final IS NULL THEN
            RAISE EXCEPTION 'No existe bien_item con id=%', p_id_bien_item;
        END IF;

        PERFORM 1
          FROM bien_item bi
         WHERE bi.id_bien_item = p_id_bien_item
           AND bi.id_bodega = p_id_bodega_origen
           AND bi.estado_item = 'DISPONIBLE';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'El bien_item=% no está DISPONIBLE en la bodega_origen=%',
                p_id_bien_item, p_id_bodega_origen;
        END IF;

    ELSE
        IF p_id_bien IS NULL THEN
            RAISE EXCEPTION 'Debe indicar p_id_bien o p_id_bien_item';
        END IF;

        IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
            RAISE EXCEPTION 'Cantidad inválida: %', p_cantidad;
        END IF;

        v_id_bien_final := p_id_bien;
    END IF;

    CALL sp_registro_crear(
        p_id_tipo_registro_asignacion,
        p_id_usuario,
        p_id_empleado,
        NULL,
        NULL,
        p_id_bodega_origen,
        NULL,
        p_numero_acta,
        p_observaciones,
        p_id_registro
    );

    IF p_id_bien_item IS NOT NULL THEN
        CALL sp_registro_agregar_detalle(
            p_id_registro,
            v_id_bien_final,
            p_id_bien_item,
            NULL,
            1,
            NULL,
            NULL,
            'Asignación por acta: ' || COALESCE(p_numero_acta,'(sin número)'),
            v_id_detalle
        );
    ELSE
        CALL sp_registro_agregar_detalle(
            p_id_registro,
            v_id_bien_final,
            NULL,
            NULL,
            p_cantidad,
            NULL,
            NULL,
            'Asignación por acta: ' || COALESCE(p_numero_acta,'(sin número)'),
            v_id_detalle
        );
    END IF;

    CALL sp_registro_confirmar_y_afectar_stock(
        p_id_registro,
        p_id_usuario,
        p_ip_origen,
        v_id_log_confirm
    );

    INSERT INTO asignacion_bien (
        id_bien,
        id_empleado,
        id_registro,
        tipo_acta,
        numero_acta,
        fecha_emision_acta,
        fecha_entrega_bien,
        fecha_devolucion_bien,
        motivo_asignacion,
        observaciones_asignacion,
        firma_digital,
        archivo_pdf,
        estado_asignacion,
        fecha_registro
    )
    VALUES (
        v_id_bien_final,
        p_id_empleado,
        p_id_registro,
        p_tipo_acta,
        p_numero_acta,
        p_fecha_emision_acta,
        NOW(),
        NULL,
        p_motivo_asignacion,
        p_observaciones,
        COALESCE(p_firma_digital, FALSE),
        p_archivo_pdf,
        'ACTIVA',
        NOW()
    )
    RETURNING id_asignacion INTO p_id_asignacion;

    IF p_id_bien_item IS NOT NULL THEN
        UPDATE bien_item
           SET id_empleado = p_id_empleado,
               estado_item = 'ASIGNADO'
         WHERE id_bien_item = p_id_bien_item;
    END IF;

    CALL sp_log_evento(
        p_id_usuario,
        'CREAR_ASIGNACION',
        'asignacion_bien',
        p_id_asignacion,
        p_ip_origen,
        'Asignación creada. acta=' || COALESCE(p_numero_acta,'(sin número)') ||
        ' | id_registro=' || p_id_registro::TEXT,
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_asignacion_crear(IN p_id_tipo_registro_asignacion bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_id_empleado bigint, IN p_id_bodega_origen bigint, IN p_id_bien bigint, IN p_id_bien_item bigint, IN p_cantidad numeric, IN p_tipo_acta character varying, IN p_numero_acta character varying, IN p_fecha_emision_acta date, IN p_motivo_asignacion character varying, IN p_observaciones text, IN p_archivo_pdf text, IN p_firma_digital boolean, OUT p_id_asignacion bigint, OUT p_id_registro bigint, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_asignacion_devolver(bigint, bigint, bigint, character varying, bigint, bigint, numeric, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_asignacion_devolver(IN p_id_asignacion bigint, IN p_id_tipo_registro_devolucion bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_id_bodega_destino bigint, IN p_id_bien_item bigint, IN p_cantidad numeric, IN p_observaciones text, OUT p_id_registro bigint, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_asig  VARCHAR(20);
    v_id_bien      BIGINT;
    v_id_empleado  BIGINT;
    v_id_log_confirm BIGINT;
    v_id_detalle BIGINT;
BEGIN
    SELECT ab.estado_asignacion, ab.id_bien, ab.id_empleado
      INTO v_estado_asig, v_id_bien, v_id_empleado
      FROM asignacion_bien ab
     WHERE ab.id_asignacion = p_id_asignacion;

    IF v_estado_asig IS NULL THEN
        RAISE EXCEPTION 'No existe asignacion_bien con id=%', p_id_asignacion;
    END IF;

    IF v_estado_asig <> 'ACTIVA' THEN
        RAISE EXCEPTION 'Solo se puede devolver una asignación ACTIVA. Estado actual=%', v_estado_asig;
    END IF;

    IF p_id_bodega_destino IS NULL THEN
        RAISE EXCEPTION 'Debe indicar p_id_bodega_destino';
    END IF;

    CALL sp_registro_crear(
        p_id_tipo_registro_devolucion,
        p_id_usuario,
        v_id_empleado,
        NULL,
        NULL,
        p_id_bodega_destino,
        NULL,
        'DEV-ASIG-' || p_id_asignacion::TEXT,
        p_observaciones,
        p_id_registro
    );

    IF p_id_bien_item IS NOT NULL THEN
        CALL sp_registro_agregar_detalle(
            p_id_registro,
            v_id_bien,
            p_id_bien_item,
            NULL,
            1,
            NULL,
            NULL,
            'Devolución de asignación id=' || p_id_asignacion::TEXT,
            v_id_detalle
        );
    ELSE
        IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
            RAISE EXCEPTION 'Debe indicar p_cantidad (>0) si no envía p_id_bien_item';
        END IF;

        CALL sp_registro_agregar_detalle(
            p_id_registro,
            v_id_bien,
            NULL,
            NULL,
            p_cantidad,
            NULL,
            NULL,
            'Devolución de asignación id=' || p_id_asignacion::TEXT,
            v_id_detalle
        );
    END IF;

    CALL sp_registro_confirmar_y_afectar_stock(
        p_id_registro,
        p_id_usuario,
        p_ip_origen,
        v_id_log_confirm
    );

    UPDATE asignacion_bien
       SET fecha_devolucion_bien = NOW(),
           estado_asignacion = 'DEVUELTA',
           observaciones_asignacion = CASE
              WHEN p_observaciones IS NULL OR LENGTH(TRIM(p_observaciones)) = 0
              THEN observaciones_asignacion
              ELSE COALESCE(observaciones_asignacion,'') ||
                   E'\n[DEVOLUCIÓN] ' || p_observaciones
           END
     WHERE id_asignacion = p_id_asignacion;

    IF p_id_bien_item IS NOT NULL THEN
        UPDATE bien_item
           SET id_empleado = NULL,
               id_bodega   = p_id_bodega_destino,
               estado_item = 'DISPONIBLE'
         WHERE id_bien_item = p_id_bien_item;
    END IF;

    CALL sp_log_evento(
        p_id_usuario,
        'DEVOLVER_ASIGNACION',
        'asignacion_bien',
        p_id_asignacion,
        p_ip_origen,
        'Devolución registrada. id_registro=' || p_id_registro::TEXT,
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_asignacion_devolver(IN p_id_asignacion bigint, IN p_id_tipo_registro_devolucion bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_id_bodega_destino bigint, IN p_id_bien_item bigint, IN p_cantidad numeric, IN p_observaciones text, OUT p_id_registro bigint, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_empleado_crear(bigint, bigint, bigint, bigint, bigint, character varying, date, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_empleado_crear(IN p_id_persona bigint, IN p_id_departamento bigint, IN p_id_estatus_empleado bigint, IN p_id_puesto bigint, IN p_id_sucursal bigint, IN p_codigo_empleado character varying, IN p_fecha_ingreso date, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_empleado bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_id_log BIGINT;
BEGIN

  -- =========================================
  -- VALIDACIONES
  -- =========================================
  IF p_id_persona IS NULL THEN
    RAISE EXCEPTION 'id_persona es requerido';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM persona WHERE id_persona = p_id_persona
  ) THEN
    RAISE EXCEPTION 'La persona no existe';
  END IF;

  IF EXISTS (
    SELECT 1 FROM empleado 
    WHERE id_persona = p_id_persona
    AND estado_empleado = 'ACTIVO'
  ) THEN
    RAISE EXCEPTION 'La persona ya tiene un empleado activo';
  END IF;

  IF p_codigo_empleado IS NULL OR TRIM(p_codigo_empleado) = '' THEN
    RAISE EXCEPTION 'codigo_empleado es requerido';
  END IF;

  IF EXISTS (
    SELECT 1 FROM empleado 
    WHERE codigo_empleado = p_codigo_empleado
  ) THEN
    RAISE EXCEPTION 'El codigo_empleado ya existe';
  END IF;

  -- =========================================
  -- INSERT
  -- =========================================
  INSERT INTO empleado(
    id_persona,
    id_departamento,
    id_estatus_empleado,
    id_puesto,
    id_sucursal,
    codigo_empleado,
    fecha_ingreso,
    estado_empleado
  )
  VALUES (
    p_id_persona,
    p_id_departamento,
    p_id_estatus_empleado,
    p_id_puesto,
    p_id_sucursal,
    p_codigo_empleado,
    p_fecha_ingreso,
    'ACTIVO'
  )
  RETURNING id_empleado INTO p_id_empleado;

  -- =========================================
  -- BITÁCORA
  -- =========================================
  CALL sp_log_evento(
    p_id_usuario_accion,
    'CREAR',
    'empleado',
    p_id_empleado,
    p_ip_origen,
    'Creación de empleado',
    v_id_log
  );

END;
$$;


ALTER PROCEDURE public.sp_empleado_crear(IN p_id_persona bigint, IN p_id_departamento bigint, IN p_id_estatus_empleado bigint, IN p_id_puesto bigint, IN p_id_sucursal bigint, IN p_codigo_empleado character varying, IN p_fecha_ingreso date, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_empleado bigint) OWNER TO juan;

--
-- Name: sp_inventario_consumir_reserva(bigint, bigint, bigint, numeric); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_inventario_consumir_reserva(IN p_id_bodega bigint, IN p_id_bien bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_reservado NUMERIC(14,3);
    v_actual    NUMERIC(14,3);
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad inválida: %', p_cantidad;
    END IF;

    IF p_id_bien_lote IS NOT NULL THEN
        SELECT il.stock_reservado, il.stock_actual
          INTO v_reservado, v_actual
          FROM inventario_lote il
         WHERE il.id_bodega = p_id_bodega
           AND il.id_bien_lote = p_id_bien_lote
         FOR UPDATE;

        IF v_reservado IS NULL THEN
            RAISE EXCEPTION 'No existe inventario_lote para bodega=% lote=%', p_id_bodega, p_id_bien_lote;
        END IF;

        IF v_reservado < p_cantidad THEN
            RAISE EXCEPTION 'Reserva insuficiente para consumir. bodega=% lote=% reservado=% requerido=%',
                p_id_bodega, p_id_bien_lote, v_reservado, p_cantidad;
        END IF;

        IF v_actual < p_cantidad THEN
            RAISE EXCEPTION 'Stock_actual insuficiente para consumir. bodega=% lote=% stock_actual=% requerido=%',
                p_id_bodega, p_id_bien_lote, v_actual, p_cantidad;
        END IF;

        UPDATE inventario_lote
           SET stock_reservado = stock_reservado - p_cantidad,
               stock_actual    = stock_actual - p_cantidad,
               fecha_ultima_actualizacion = NOW()
         WHERE id_bodega = p_id_bodega
           AND id_bien_lote = p_id_bien_lote;

        RETURN;
    END IF;

    IF p_id_bien IS NULL THEN
        RAISE EXCEPTION 'Debe enviar p_id_bien o p_id_bien_lote';
    END IF;

    SELECT i.stock_reservado, i.stock_actual
      INTO v_reservado, v_actual
      FROM inventario i
     WHERE i.id_bodega = p_id_bodega
       AND i.id_bien = p_id_bien
     FOR UPDATE;

    IF v_reservado IS NULL THEN
        RAISE EXCEPTION 'No existe inventario para bodega=% bien=%', p_id_bodega, p_id_bien;
    END IF;

    IF v_reservado < p_cantidad THEN
        RAISE EXCEPTION 'Reserva insuficiente para consumir. bodega=% bien=% reservado=% requerido=%',
            p_id_bodega, p_id_bien, v_reservado, p_cantidad;
    END IF;

    IF v_actual < p_cantidad THEN
        RAISE EXCEPTION 'Stock_actual insuficiente para consumir. bodega=% bien=% stock_actual=% requerido=%',
            p_id_bodega, p_id_bien, v_actual, p_cantidad;
    END IF;

    UPDATE inventario
       SET stock_reservado = stock_reservado - p_cantidad,
           stock_actual    = stock_actual - p_cantidad,
           fecha_ultima_actualizacion = NOW()
     WHERE id_bodega = p_id_bodega
       AND id_bien = p_id_bien;
END;
$$;


ALTER PROCEDURE public.sp_inventario_consumir_reserva(IN p_id_bodega bigint, IN p_id_bien bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric) OWNER TO juan;

--
-- Name: sp_inventario_liberar_reserva(bigint, bigint, bigint, numeric); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_inventario_liberar_reserva(IN p_id_bodega bigint, IN p_id_bien bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_reservado NUMERIC(14,3);
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad inválida: %', p_cantidad;
    END IF;

    IF p_id_bien_lote IS NOT NULL THEN
        SELECT il.stock_reservado
          INTO v_reservado
          FROM inventario_lote il
         WHERE il.id_bodega = p_id_bodega
           AND il.id_bien_lote = p_id_bien_lote
         FOR UPDATE;

        IF v_reservado IS NULL THEN
            RAISE EXCEPTION 'No existe inventario_lote para bodega=% lote=%', p_id_bodega, p_id_bien_lote;
        END IF;

        IF v_reservado < p_cantidad THEN
            RAISE EXCEPTION 'No se puede liberar más de lo reservado. bodega=% lote=% reservado=% a_liberar=%',
                p_id_bodega, p_id_bien_lote, v_reservado, p_cantidad;
        END IF;

        UPDATE inventario_lote
           SET stock_reservado = stock_reservado - p_cantidad,
               fecha_ultima_actualizacion = NOW()
         WHERE id_bodega = p_id_bodega
           AND id_bien_lote = p_id_bien_lote;

        RETURN;
    END IF;

    IF p_id_bien IS NULL THEN
        RAISE EXCEPTION 'Debe enviar p_id_bien o p_id_bien_lote';
    END IF;

    SELECT i.stock_reservado
      INTO v_reservado
      FROM inventario i
     WHERE i.id_bodega = p_id_bodega
       AND i.id_bien = p_id_bien
     FOR UPDATE;

    IF v_reservado IS NULL THEN
        RAISE EXCEPTION 'No existe inventario para bodega=% bien=%', p_id_bodega, p_id_bien;
    END IF;

    IF v_reservado < p_cantidad THEN
        RAISE EXCEPTION 'No se puede liberar más de lo reservado. bodega=% bien=% reservado=% a_liberar=%',
            p_id_bodega, p_id_bien, v_reservado, p_cantidad;
    END IF;

    UPDATE inventario
       SET stock_reservado = stock_reservado - p_cantidad,
           fecha_ultima_actualizacion = NOW()
     WHERE id_bodega = p_id_bodega
       AND id_bien = p_id_bien;
END;
$$;


ALTER PROCEDURE public.sp_inventario_liberar_reserva(IN p_id_bodega bigint, IN p_id_bien bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric) OWNER TO juan;

--
-- Name: sp_inventario_reservar(bigint, bigint, bigint, numeric); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_inventario_reservar(IN p_id_bodega bigint, IN p_id_bien bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_disponible NUMERIC(14,3);
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad inválida: %', p_cantidad;
    END IF;

    IF p_id_bien_lote IS NOT NULL THEN
        INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
        VALUES (p_id_bodega, p_id_bien_lote, 0, 0)
        ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

        SELECT (il.stock_actual - il.stock_reservado)
          INTO v_disponible
          FROM inventario_lote il
         WHERE il.id_bodega = p_id_bodega
           AND il.id_bien_lote = p_id_bien_lote
         FOR UPDATE;

        IF v_disponible < p_cantidad THEN
            RAISE EXCEPTION 'Stock disponible insuficiente para reservar. bodega=% lote=% disponible=% requerido=%',
                p_id_bodega, p_id_bien_lote, v_disponible, p_cantidad;
        END IF;

        UPDATE inventario_lote
           SET stock_reservado = stock_reservado + p_cantidad,
               fecha_ultima_actualizacion = NOW()
         WHERE id_bodega = p_id_bodega
           AND id_bien_lote = p_id_bien_lote;

        RETURN;
    END IF;

    IF p_id_bien IS NULL THEN
        RAISE EXCEPTION 'Debe enviar p_id_bien o p_id_bien_lote';
    END IF;

    INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
    VALUES (p_id_bodega, p_id_bien, 0, 0)
    ON CONFLICT (id_bodega, id_bien) DO NOTHING;

    SELECT (i.stock_actual - i.stock_reservado)
      INTO v_disponible
      FROM inventario i
     WHERE i.id_bodega = p_id_bodega
       AND i.id_bien = p_id_bien
     FOR UPDATE;

    IF v_disponible < p_cantidad THEN
        RAISE EXCEPTION 'Stock disponible insuficiente para reservar. bodega=% bien=% disponible=% requerido=%',
            p_id_bodega, p_id_bien, v_disponible, p_cantidad;
    END IF;

    UPDATE inventario
       SET stock_reservado = stock_reservado + p_cantidad,
           fecha_ultima_actualizacion = NOW()
     WHERE id_bodega = p_id_bodega
       AND id_bien = p_id_bien;
END;
$$;


ALTER PROCEDURE public.sp_inventario_reservar(IN p_id_bodega bigint, IN p_id_bien bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric) OWNER TO juan;

--
-- Name: sp_log_cambio(bigint, character varying, text, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_log_cambio(IN p_id_log_usuario bigint, IN p_campo_modificado character varying, IN p_valor_antes text, IN p_valor_despues text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO log_cambios (
        id_log_usuario,
        campo_modificado,
        valor_antes,
        valor_despues
    )
    VALUES (
        p_id_log_usuario,
        p_campo_modificado,
        p_valor_antes,
        p_valor_despues
    );
END;
$$;


ALTER PROCEDURE public.sp_log_cambio(IN p_id_log_usuario bigint, IN p_campo_modificado character varying, IN p_valor_antes text, IN p_valor_despues text) OWNER TO juan;

--
-- Name: sp_log_evento(bigint, character varying, character varying, bigint, character varying, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_log_evento(IN p_id_usuario bigint, IN p_tipo_accion character varying, IN p_tabla_afectada character varying, IN p_registro_afectado bigint, IN p_ip_origen character varying, IN p_descripcion_log text, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO log_usuario (
        id_usuario,
        fecha_accion,
        hora_accion,
        tipo_accion,
        tabla_afectada,
        registro_afectado,
        ip_origen,
        descripcion_log
    )
    VALUES (
        p_id_usuario,
        NOW(),
        CURRENT_TIME,
        p_tipo_accion,
        p_tabla_afectada,
        p_registro_afectado,
        p_ip_origen,
        p_descripcion_log
    )
    RETURNING id_log_usuario INTO p_id_log_usuario;
END;
$$;


ALTER PROCEDURE public.sp_log_evento(IN p_id_usuario bigint, IN p_tipo_accion character varying, IN p_tabla_afectada character varying, IN p_registro_afectado bigint, IN p_ip_origen character varying, IN p_descripcion_log text, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_mantenimiento_finalizar(bigint, date, numeric, text, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_mantenimiento_finalizar(IN p_id_mantenimiento bigint, IN p_fecha_fin date, IN p_costo numeric, IN p_observaciones text, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado VARCHAR(20);
BEGIN
    SELECT estado_mantenimiento
      INTO v_estado
      FROM mantenimiento
     WHERE id_mantenimiento = p_id_mantenimiento;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'No existe mantenimiento id=%', p_id_mantenimiento;
    END IF;

    IF v_estado <> 'EN_PROCESO' THEN
        RAISE EXCEPTION 'Solo se puede finalizar si está EN_PROCESO. Estado actual=%', v_estado;
    END IF;

    UPDATE mantenimiento
       SET fecha_fin = COALESCE(p_fecha_fin, CURRENT_DATE),
           costo_mantenimiento = p_costo,
           estado_mantenimiento = 'FINALIZADO',
           observaciones_mantenimiento = CASE
              WHEN p_observaciones IS NULL OR LENGTH(TRIM(p_observaciones))=0
              THEN observaciones_mantenimiento
              ELSE COALESCE(observaciones_mantenimiento,'') ||
                   E'\n[FINALIZADO] ' || p_observaciones
           END
     WHERE id_mantenimiento = p_id_mantenimiento;

    CALL sp_log_evento(
        p_id_usuario,
        'FINALIZAR_MANTENIMIENTO',
        'mantenimiento',
        p_id_mantenimiento,
        p_ip_origen,
        'Mantenimiento finalizado. fecha_fin=' || COALESCE(p_fecha_fin::TEXT, CURRENT_DATE::TEXT) ||
        ' costo=' || COALESCE(p_costo::TEXT,'(null)'),
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_mantenimiento_finalizar(IN p_id_mantenimiento bigint, IN p_fecha_fin date, IN p_costo numeric, IN p_observaciones text, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_mantenimiento_iniciar(bigint, date, numeric, text, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_mantenimiento_iniciar(IN p_id_mantenimiento bigint, IN p_fecha_inicio date, IN p_kilometraje numeric, IN p_observaciones text, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado VARCHAR(20);
BEGIN
    SELECT estado_mantenimiento
      INTO v_estado
      FROM mantenimiento
     WHERE id_mantenimiento = p_id_mantenimiento;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'No existe mantenimiento id=%', p_id_mantenimiento;
    END IF;

    IF v_estado <> 'PROGRAMADO' THEN
        RAISE EXCEPTION 'Solo se puede iniciar si está PROGRAMADO. Estado actual=%', v_estado;
    END IF;

    UPDATE mantenimiento
       SET fecha_inicio = COALESCE(p_fecha_inicio, CURRENT_DATE),
           kilometraje  = COALESCE(p_kilometraje, kilometraje),
           estado_mantenimiento = 'EN_PROCESO',
           observaciones_mantenimiento = CASE
              WHEN p_observaciones IS NULL OR LENGTH(TRIM(p_observaciones))=0
              THEN observaciones_mantenimiento
              ELSE COALESCE(observaciones_mantenimiento,'') ||
                   E'\n[INICIO] ' || p_observaciones
           END
     WHERE id_mantenimiento = p_id_mantenimiento;

    CALL sp_log_evento(
        p_id_usuario,
        'INICIAR_MANTENIMIENTO',
        'mantenimiento',
        p_id_mantenimiento,
        p_ip_origen,
        'Mantenimiento iniciado. fecha_inicio=' || COALESCE(p_fecha_inicio::TEXT, CURRENT_DATE::TEXT),
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_mantenimiento_iniciar(IN p_id_mantenimiento bigint, IN p_fecha_inicio date, IN p_kilometraje numeric, IN p_observaciones text, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_mantenimiento_programar(bigint, bigint, bigint, bigint, date, numeric, text, text, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_mantenimiento_programar(IN p_id_bien bigint, IN p_id_tipo_mantenimiento bigint, IN p_id_proveedor bigint, IN p_id_documento bigint, IN p_fecha_programada date, IN p_kilometraje numeric, IN p_descripcion text, IN p_observaciones text, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_mantenimiento bigint, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF p_descripcion IS NULL OR LENGTH(TRIM(p_descripcion)) = 0 THEN
        RAISE EXCEPTION 'descripcion_mantenimiento es obligatoria';
    END IF;

    INSERT INTO mantenimiento (
        id_bien,
        id_tipo_mantenimiento,
        id_proveedor,
        id_documento,
        fecha_programada,
        kilometraje,
        descripcion_mantenimiento,
        costo_mantenimiento,
        estado_mantenimiento,
        observaciones_mantenimiento,
        fecha_registro
    )
    VALUES (
        p_id_bien,
        p_id_tipo_mantenimiento,
        p_id_proveedor,
        p_id_documento,
        p_fecha_programada,
        p_kilometraje,
        p_descripcion,
        NULL,
        'PROGRAMADO',
        p_observaciones,
        NOW()
    )
    RETURNING id_mantenimiento INTO p_id_mantenimiento;

    CALL sp_log_evento(
        p_id_usuario,
        'PROGRAMAR_MANTENIMIENTO',
        'mantenimiento',
        p_id_mantenimiento,
        p_ip_origen,
        'Mantenimiento programado. fecha_programada=' || COALESCE(p_fecha_programada::TEXT,'(null)'),
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_mantenimiento_programar(IN p_id_bien bigint, IN p_id_tipo_mantenimiento bigint, IN p_id_proveedor bigint, IN p_id_documento bigint, IN p_fecha_programada date, IN p_kilometraje numeric, IN p_descripcion text, IN p_observaciones text, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_mantenimiento bigint, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_persona_crear(character varying, character varying, character varying, character varying, character varying, date, character varying, character varying, character varying, character varying, character varying, character varying, character varying, text, character varying, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_persona_crear(IN p_primer_nombre character varying, IN p_segundo_nombre character varying, IN p_primer_apellido character varying, IN p_segundo_apellido character varying, IN p_identidad character varying, IN p_fecha_nacimiento date, IN p_sexo character varying, IN p_tipo_telefono character varying, IN p_numero character varying, IN p_pais character varying, IN p_departamento character varying, IN p_municipio character varying, IN p_colonia_barrio character varying, IN p_direccion_detallada text, IN p_correo character varying, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_persona bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_id_log BIGINT; -- 👈 AQUÍ ESTÁ LA CLAVE
BEGIN

  -- =========================================
  -- VALIDACIONES
  -- =========================================
  IF p_primer_nombre IS NULL OR TRIM(p_primer_nombre) = '' THEN
    RAISE EXCEPTION 'primer_nombre es requerido';
  END IF;

  IF p_primer_apellido IS NULL OR TRIM(p_primer_apellido) = '' THEN
    RAISE EXCEPTION 'primer_apellido es requerido';
  END IF;

  -- =========================================
  -- INSERT PERSONA
  -- =========================================
  INSERT INTO persona(
    primer_nombre,
    segundo_nombre,
    primer_apellido,
    segundo_apellido,
    identidad,
    fecha_nacimiento,
    sexo,
    estado_persona
  )
  VALUES (
    p_primer_nombre,
    p_segundo_nombre,
    p_primer_apellido,
    p_segundo_apellido,
    p_identidad,
    p_fecha_nacimiento,
    p_sexo,
    'ACTIVO'
  )
  RETURNING id_persona INTO p_id_persona;

  -- =========================================
  -- TELEFONO (OPCIONAL)
  -- =========================================
  IF p_numero IS NOT NULL AND TRIM(p_numero) <> '' THEN
    INSERT INTO telefono_persona(
      id_persona,
      tipo_telefono,
      numero,
      principal,
      estado_telefono
    )
    VALUES (
      p_id_persona,
      p_tipo_telefono,
      p_numero,
      true,
      'ACTIVO'
    );
  END IF;

  -- =========================================
  -- DIRECCION (OPCIONAL)
  -- =========================================
  IF p_pais IS NOT NULL AND TRIM(p_pais) <> '' THEN
    INSERT INTO direccion_persona(
      id_persona,
      tipo_direccion,
      pais,
      departamento,
      municipio,
      colonia_barrio,
      direccion_detallada,
      principal,
      estado_direccion
    )
    VALUES (
      p_id_persona,
      'PRINCIPAL',
      p_pais,
      p_departamento,
      p_municipio,
      p_colonia_barrio,
      p_direccion_detallada,
      true,
      'ACTIVO'
    );
  END IF;

  -- =========================================
  -- CORREO (OPCIONAL)
  -- =========================================
  IF p_correo IS NOT NULL AND TRIM(p_correo) <> '' THEN
    INSERT INTO correo_persona(
      id_persona,
      correo_electronico,
      principal,
      estado_correo
    )
    VALUES (
      p_id_persona,
      p_correo,
      true,
      'ACTIVO'
    );
  END IF;

  -- =========================================
  -- BITÁCORA
  -- =========================================
  CALL sp_log_evento(
    p_id_usuario_accion,
    'CREAR',
    'persona',
    p_id_persona,
    p_ip_origen,
    'Creación de persona',
    v_id_log
  );

END;
$$;


ALTER PROCEDURE public.sp_persona_crear(IN p_primer_nombre character varying, IN p_segundo_nombre character varying, IN p_primer_apellido character varying, IN p_segundo_apellido character varying, IN p_identidad character varying, IN p_fecha_nacimiento date, IN p_sexo character varying, IN p_tipo_telefono character varying, IN p_numero character varying, IN p_pais character varying, IN p_departamento character varying, IN p_municipio character varying, IN p_colonia_barrio character varying, IN p_direccion_detallada text, IN p_correo character varying, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_persona bigint) OWNER TO juan;

--
-- Name: sp_registro_agregar_detalle(bigint, bigint, bigint, bigint, numeric, numeric, character varying, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_registro_agregar_detalle(IN p_id_registro bigint, IN p_id_bien bigint, IN p_id_bien_item bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric, IN p_costo_unitario numeric, IN p_lote character varying, IN p_observacion text, OUT p_id_detalle bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_registro VARCHAR(20);
BEGIN
    SELECT estado_registro
      INTO v_estado_registro
      FROM registro
     WHERE id_registro = p_id_registro;

    IF v_estado_registro IS NULL THEN
        RAISE EXCEPTION 'No existe registro con id_registro=%', p_id_registro;
    END IF;

    IF v_estado_registro <> 'REGISTRADO' THEN
        RAISE EXCEPTION 'No se puede agregar detalle: estado_registro=%', v_estado_registro;
    END IF;

    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad inválida: %', p_cantidad;
    END IF;

    IF p_id_bien_item IS NOT NULL AND p_cantidad <> 1 THEN
        RAISE EXCEPTION 'Para bienes por serie (id_bien_item) la cantidad debe ser 1';
    END IF;

    INSERT INTO registro_detalle (
        id_registro,
        id_bien,
        id_bien_item,
        id_bien_lote,
        cantidad,
        costo_unitario,
        lote,
        observacion_detalle
    )
    VALUES (
        p_id_registro,
        p_id_bien,
        p_id_bien_item,
        p_id_bien_lote,
        p_cantidad,
        p_costo_unitario,
        p_lote,
        p_observacion
    )
    RETURNING id_registro_detalle INTO p_id_detalle;
END;
$$;


ALTER PROCEDURE public.sp_registro_agregar_detalle(IN p_id_registro bigint, IN p_id_bien bigint, IN p_id_bien_item bigint, IN p_id_bien_lote bigint, IN p_cantidad numeric, IN p_costo_unitario numeric, IN p_lote character varying, IN p_observacion text, OUT p_id_detalle bigint) OWNER TO juan;

--
-- Name: sp_registro_anular_y_revertir_stock(bigint, bigint, character varying, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_registro_anular_y_revertir_stock(IN p_id_registro bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_motivo text, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_registro   VARCHAR(20);
    v_id_tipo_registro  BIGINT;
    v_afecta_stock      BOOLEAN;
    v_signo             INTEGER;

    v_bodega_origen     BIGINT;
    v_bodega_destino    BIGINT;
    v_es_transferencia  BOOLEAN;

    d RECORD;

    v_stock_actual      NUMERIC(14,3);
    v_stock_actual_lote NUMERIC(14,3);
BEGIN
    SELECT r.estado_registro, r.id_tipo_registro, r.id_bodega_origen, r.id_bodega_destino
      INTO v_estado_registro, v_id_tipo_registro, v_bodega_origen, v_bodega_destino
      FROM registro r
     WHERE r.id_registro = p_id_registro;

    IF v_estado_registro IS NULL THEN
        RAISE EXCEPTION 'No existe registro con id_registro=%', p_id_registro;
    END IF;

    IF v_estado_registro <> 'CONFIRMADO' THEN
        RAISE EXCEPTION 'Solo se puede anular un registro CONFIRMADO. Estado actual=%', v_estado_registro;
    END IF;

    SELECT tr.afecta_stock, tr.signo_movimiento
      INTO v_afecta_stock, v_signo
      FROM tipo_registro tr
     WHERE tr.id_tipo_registro = v_id_tipo_registro;

    IF v_afecta_stock IS NULL THEN
        RAISE EXCEPTION 'Tipo de registro inválido (id_tipo_registro=%)', v_id_tipo_registro;
    END IF;

    v_es_transferencia := (v_bodega_origen IS NOT NULL
                           AND v_bodega_destino IS NOT NULL
                           AND v_bodega_origen <> v_bodega_destino);

    IF v_afecta_stock = FALSE THEN
        UPDATE registro
           SET estado_registro = 'ANULADO',
               fecha_actualizacion = NOW(),
               observaciones_registro = COALESCE(observaciones_registro,'') ||
                                       E'\n[ANULADO] ' || COALESCE(p_motivo,'(sin motivo)')
         WHERE id_registro = p_id_registro;

        CALL sp_log_evento(
            p_id_usuario,
            'ANULAR_REGISTRO',
            'registro',
            p_id_registro,
            p_ip_origen,
            'Anulación de registro (sin afectar stock). Motivo: ' || COALESCE(p_motivo,'(sin motivo)'),
            p_id_log_usuario
        );
        RETURN;
    END IF;

    IF v_es_transferencia = FALSE AND (v_signo IS NULL OR v_signo = 0) THEN
        RAISE EXCEPTION 'signo_movimiento no definido para tipo_registro=%', v_id_tipo_registro;
    END IF;

    FOR d IN
        SELECT rd.*
          FROM registro_detalle rd
         WHERE rd.id_registro = p_id_registro
    LOOP
        IF d.cantidad IS NULL OR d.cantidad <= 0 THEN
            RAISE EXCEPTION 'Detalle inválido: cantidad=% (id_registro_detalle=%)', d.cantidad, d.id_registro_detalle;
        END IF;

        IF d.id_bien_item IS NOT NULL AND d.cantidad <> 1 THEN
            RAISE EXCEPTION 'Bien por serie: cantidad debe ser 1 (id_registro_detalle=%)', d.id_registro_detalle;
        END IF;

        IF v_es_transferencia THEN
            IF d.id_bien_item IS NOT NULL THEN
                UPDATE bien_item
                   SET id_bodega = v_bodega_origen,
                       estado_item = 'DISPONIBLE'
                 WHERE id_bien_item = d.id_bien_item;
            END IF;

            IF d.id_bien_lote IS NOT NULL THEN
                INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                VALUES (v_bodega_origen, d.id_bien_lote, 0, 0)
                ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                VALUES (v_bodega_destino, d.id_bien_lote, 0, 0)
                ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                SELECT il.stock_actual
                  INTO v_stock_actual_lote
                  FROM inventario_lote il
                 WHERE il.id_bodega = v_bodega_destino
                   AND il.id_bien_lote = d.id_bien_lote
                 FOR UPDATE;

                IF v_stock_actual_lote < d.cantidad THEN
                    RAISE EXCEPTION 'No se puede revertir: destino quedaría negativo. bodega_destino=% lote=% stock=% requerido=%',
                        v_bodega_destino, d.id_bien_lote, v_stock_actual_lote, d.cantidad;
                END IF;

                PERFORM 1
                  FROM inventario_lote il
                 WHERE il.id_bodega = v_bodega_origen
                   AND il.id_bien_lote = d.id_bien_lote
                 FOR UPDATE;

                UPDATE inventario_lote
                   SET stock_actual = stock_actual + d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_origen
                   AND id_bien_lote = d.id_bien_lote;

                UPDATE inventario_lote
                   SET stock_actual = stock_actual - d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_destino
                   AND id_bien_lote = d.id_bien_lote;

            ELSE
                IF d.id_bien IS NULL THEN
                    RAISE EXCEPTION 'Detalle sin id_bien para inventario normal (id_registro_detalle=%)', d.id_registro_detalle;
                END IF;

                INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                VALUES (v_bodega_origen, d.id_bien, 0, 0)
                ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                VALUES (v_bodega_destino, d.id_bien, 0, 0)
                ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                SELECT i.stock_actual
                  INTO v_stock_actual
                  FROM inventario i
                 WHERE i.id_bodega = v_bodega_destino
                   AND i.id_bien = d.id_bien
                 FOR UPDATE;

                IF v_stock_actual < d.cantidad THEN
                    RAISE EXCEPTION 'No se puede revertir: destino quedaría negativo. bodega_destino=% bien=% stock=% requerido=%',
                        v_bodega_destino, d.id_bien, v_stock_actual, d.cantidad;
                END IF;

                PERFORM 1
                  FROM inventario i
                 WHERE i.id_bodega = v_bodega_origen
                   AND i.id_bien = d.id_bien
                 FOR UPDATE;

                UPDATE inventario
                   SET stock_actual = stock_actual + d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_origen
                   AND id_bien = d.id_bien;

                UPDATE inventario
                   SET stock_actual = stock_actual - d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_destino
                   AND id_bien = d.id_bien;
            END IF;

        ELSE
            IF v_bodega_origen IS NULL AND v_bodega_destino IS NULL THEN
                RAISE EXCEPTION 'Registro sin bodega_origen ni bodega_destino (id_registro=%)', p_id_registro;
            END IF;

            IF v_bodega_origen IS NOT NULL THEN
                IF d.id_bien_item IS NOT NULL THEN
                    IF v_signo < 0 THEN
                        UPDATE bien_item
                           SET estado_item = 'DISPONIBLE'
                         WHERE id_bien_item = d.id_bien_item;
                    ELSE
                        UPDATE bien_item
                           SET estado_item = 'NO_DISPONIBLE'
                         WHERE id_bien_item = d.id_bien_item;
                    END IF;
                END IF;

                IF d.id_bien_lote IS NOT NULL THEN
                    INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                    VALUES (v_bodega_origen, d.id_bien_lote, 0, 0)
                    ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                    SELECT il.stock_actual
                      INTO v_stock_actual_lote
                      FROM inventario_lote il
                     WHERE il.id_bodega = v_bodega_origen
                       AND il.id_bien_lote = d.id_bien_lote
                     FOR UPDATE;

                    IF (-v_signo) < 0 AND v_stock_actual_lote < d.cantidad THEN
                        RAISE EXCEPTION 'No se puede revertir: stock quedaría negativo. bodega=% lote=% stock=% requerido=%',
                            v_bodega_origen, d.id_bien_lote, v_stock_actual_lote, d.cantidad;
                    END IF;

                    UPDATE inventario_lote
                       SET stock_actual = stock_actual + ((-v_signo) * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_origen
                       AND id_bien_lote = d.id_bien_lote;

                ELSE
                    IF d.id_bien IS NULL THEN
                        RAISE EXCEPTION 'Detalle sin id_bien para inventario normal (id_registro_detalle=%)', d.id_registro_detalle;
                    END IF;

                    INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                    VALUES (v_bodega_origen, d.id_bien, 0, 0)
                    ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                    SELECT i.stock_actual
                      INTO v_stock_actual
                      FROM inventario i
                     WHERE i.id_bodega = v_bodega_origen
                       AND i.id_bien = d.id_bien
                     FOR UPDATE;

                    IF (-v_signo) < 0 AND v_stock_actual < d.cantidad THEN
                        RAISE EXCEPTION 'No se puede revertir: stock quedaría negativo. bodega=% bien=% stock=% requerido=%',
                            v_bodega_origen, d.id_bien, v_stock_actual, d.cantidad;
                    END IF;

                    UPDATE inventario
                       SET stock_actual = stock_actual + ((-v_signo) * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_origen
                       AND id_bien = d.id_bien;
                END IF;

            ELSE
                IF d.id_bien_lote IS NOT NULL THEN
                    INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                    VALUES (v_bodega_destino, d.id_bien_lote, 0, 0)
                    ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                    SELECT il.stock_actual
                      INTO v_stock_actual_lote
                      FROM inventario_lote il
                     WHERE il.id_bodega = v_bodega_destino
                       AND il.id_bien_lote = d.id_bien_lote
                     FOR UPDATE;

                    IF (-v_signo) < 0 AND v_stock_actual_lote < d.cantidad THEN
                        RAISE EXCEPTION 'No se puede revertir: stock quedaría negativo. bodega=% lote=% stock=% requerido=%',
                            v_bodega_destino, d.id_bien_lote, v_stock_actual_lote, d.cantidad;
                    END IF;

                    UPDATE inventario_lote
                       SET stock_actual = stock_actual + ((-v_signo) * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_destino
                       AND id_bien_lote = d.id_bien_lote;

                ELSE
                    IF d.id_bien IS NULL THEN
                        RAISE EXCEPTION 'Detalle sin id_bien para inventario normal (id_registro_detalle=%)', d.id_registro_detalle;
                    END IF;

                    INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                    VALUES (v_bodega_destino, d.id_bien, 0, 0)
                    ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                    SELECT i.stock_actual
                      INTO v_stock_actual
                      FROM inventario i
                     WHERE i.id_bodega = v_bodega_destino
                       AND i.id_bien = d.id_bien
                     FOR UPDATE;

                    IF (-v_signo) < 0 AND v_stock_actual < d.cantidad THEN
                        RAISE EXCEPTION 'No se puede revertir: stock quedaría negativo. bodega=% bien=% stock=% requerido=%',
                            v_bodega_destino, d.id_bien, v_stock_actual, d.cantidad;
                    END IF;

                    UPDATE inventario
                       SET stock_actual = stock_actual + ((-v_signo) * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_destino
                       AND id_bien = d.id_bien;
                END IF;
            END IF;
        END IF;
    END LOOP;

    UPDATE registro
       SET estado_registro = 'ANULADO',
           fecha_actualizacion = NOW(),
           observaciones_registro = COALESCE(observaciones_registro,'') ||
                                   E'\n[ANULADO] ' || COALESCE(p_motivo,'(sin motivo)')
     WHERE id_registro = p_id_registro;

    CALL sp_log_evento(
        p_id_usuario,
        'ANULAR_REGISTRO',
        'registro',
        p_id_registro,
        p_ip_origen,
        'Anulación y reverso de inventario. Motivo: ' || COALESCE(p_motivo,'(sin motivo)'),
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_registro_anular_y_revertir_stock(IN p_id_registro bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_motivo text, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_registro_confirmar_y_afectar_stock(bigint, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_registro_confirmar_y_afectar_stock(IN p_id_registro bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_registro     VARCHAR(20);
    v_id_tipo_registro    BIGINT;
    v_afecta_stock        BOOLEAN;
    v_signo               INTEGER;
    v_bodega_origen       BIGINT;
    v_bodega_destino      BIGINT;

    v_es_transferencia    BOOLEAN;

    d RECORD;

    v_stock_actual        NUMERIC(14,3);
    v_stock_actual_lote   NUMERIC(14,3);

BEGIN
    SELECT r.estado_registro, r.id_tipo_registro, r.id_bodega_origen, r.id_bodega_destino
      INTO v_estado_registro, v_id_tipo_registro, v_bodega_origen, v_bodega_destino
      FROM registro r
     WHERE r.id_registro = p_id_registro;

    IF v_estado_registro IS NULL THEN
        RAISE EXCEPTION 'No existe registro con id_registro=%', p_id_registro;
    END IF;

    IF v_estado_registro <> 'REGISTRADO' THEN
        RAISE EXCEPTION 'No se puede confirmar: estado_registro=% (se requiere REGISTRADO)', v_estado_registro;
    END IF;

    SELECT tr.afecta_stock, tr.signo_movimiento
      INTO v_afecta_stock, v_signo
      FROM tipo_registro tr
     WHERE tr.id_tipo_registro = v_id_tipo_registro;

    IF v_afecta_stock IS NULL THEN
        RAISE EXCEPTION 'Tipo de registro inválido (id_tipo_registro=%)', v_id_tipo_registro;
    END IF;

    v_es_transferencia := (v_bodega_origen IS NOT NULL AND v_bodega_destino IS NOT NULL AND v_bodega_origen <> v_bodega_destino);

    IF v_afecta_stock = FALSE THEN
        UPDATE registro
           SET estado_registro = 'CONFIRMADO',
               fecha_actualizacion = NOW()
         WHERE id_registro = p_id_registro;

        CALL sp_log_evento(
            p_id_usuario,
            'CONFIRMAR_REGISTRO',
            'registro',
            p_id_registro,
            p_ip_origen,
            'Confirmación de registro (sin afectar stock)',
            p_id_log_usuario
        );

        RETURN;
    END IF;

    IF v_es_transferencia = FALSE AND (v_signo IS NULL OR v_signo = 0) THEN
        RAISE EXCEPTION 'signo_movimiento no definido para tipo_registro=%', v_id_tipo_registro;
    END IF;

    FOR d IN
        SELECT rd.*
          FROM registro_detalle rd
         WHERE rd.id_registro = p_id_registro
    LOOP
        IF d.cantidad IS NULL OR d.cantidad <= 0 THEN
            RAISE EXCEPTION 'Detalle inválido: cantidad=% (id_registro_detalle=%)', d.cantidad, d.id_registro_detalle;
        END IF;

        IF d.id_bien_item IS NOT NULL AND d.cantidad <> 1 THEN
            RAISE EXCEPTION 'Bien por serie: cantidad debe ser 1 (id_registro_detalle=%)', d.id_registro_detalle;
        END IF;

        IF v_es_transferencia THEN

            IF d.id_bien_item IS NOT NULL THEN
                PERFORM 1
                  FROM bien_item bi
                 WHERE bi.id_bien_item = d.id_bien_item
                   AND bi.id_bodega = v_bodega_origen;

                IF NOT FOUND THEN
                    RAISE EXCEPTION 'El bien_item=% no está en la bodega origen=%', d.id_bien_item, v_bodega_origen;
                END IF;

                UPDATE bien_item
                   SET id_bodega = v_bodega_destino,
                       estado_item = 'DISPONIBLE'
                 WHERE id_bien_item = d.id_bien_item;
            END IF;

            IF d.id_bien_lote IS NOT NULL THEN
                INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                VALUES (v_bodega_origen, d.id_bien_lote, 0, 0)
                ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                SELECT il.stock_actual
                  INTO v_stock_actual_lote
                  FROM inventario_lote il
                 WHERE il.id_bodega = v_bodega_origen
                   AND il.id_bien_lote = d.id_bien_lote
                 FOR UPDATE;

                IF v_stock_actual_lote < d.cantidad THEN
                    RAISE EXCEPTION 'Stock insuficiente en origen. bodega=% lote=% stock=% requerido=%',
                        v_bodega_origen, d.id_bien_lote, v_stock_actual_lote, d.cantidad;
                END IF;

                UPDATE inventario_lote
                   SET stock_actual = stock_actual - d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_origen
                   AND id_bien_lote = d.id_bien_lote;

                INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                VALUES (v_bodega_destino, d.id_bien_lote, 0, 0)
                ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                PERFORM 1
                  FROM inventario_lote il
                 WHERE il.id_bodega = v_bodega_destino
                   AND il.id_bien_lote = d.id_bien_lote
                 FOR UPDATE;

                UPDATE inventario_lote
                   SET stock_actual = stock_actual + d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_destino
                   AND id_bien_lote = d.id_bien_lote;

            ELSE
                IF d.id_bien IS NULL THEN
                    RAISE EXCEPTION 'Detalle sin id_bien para inventario normal (id_registro_detalle=%)', d.id_registro_detalle;
                END IF;

                INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                VALUES (v_bodega_origen, d.id_bien, 0, 0)
                ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                SELECT i.stock_actual
                  INTO v_stock_actual
                  FROM inventario i
                 WHERE i.id_bodega = v_bodega_origen
                   AND i.id_bien = d.id_bien
                 FOR UPDATE;

                IF v_stock_actual < d.cantidad THEN
                    RAISE EXCEPTION 'Stock insuficiente en origen. bodega=% bien=% stock=% requerido=%',
                        v_bodega_origen, d.id_bien, v_stock_actual, d.cantidad;
                END IF;

                UPDATE inventario
                   SET stock_actual = stock_actual - d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_origen
                   AND id_bien = d.id_bien;

                INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                VALUES (v_bodega_destino, d.id_bien, 0, 0)
                ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                PERFORM 1
                  FROM inventario i
                 WHERE i.id_bodega = v_bodega_destino
                   AND i.id_bien = d.id_bien
                 FOR UPDATE;

                UPDATE inventario
                   SET stock_actual = stock_actual + d.cantidad,
                       fecha_ultima_actualizacion = NOW()
                 WHERE id_bodega = v_bodega_destino
                   AND id_bien = d.id_bien;
            END IF;

        ELSE
            IF v_bodega_origen IS NULL AND v_bodega_destino IS NULL THEN
                RAISE EXCEPTION 'Registro sin bodega_origen ni bodega_destino (id_registro=%)', p_id_registro;
            END IF;

            IF v_bodega_origen IS NOT NULL THEN
                IF d.id_bien_item IS NOT NULL THEN
                    IF v_signo < 0 THEN
                        PERFORM 1
                          FROM bien_item bi
                         WHERE bi.id_bien_item = d.id_bien_item
                           AND bi.id_bodega = v_bodega_origen;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION 'El bien_item=% no está en la bodega=%', d.id_bien_item, v_bodega_origen;
                        END IF;

                        UPDATE bien_item
                           SET estado_item = 'NO_DISPONIBLE'
                         WHERE id_bien_item = d.id_bien_item;
                    ELSE
                        UPDATE bien_item
                           SET id_bodega = v_bodega_origen,
                               estado_item = 'DISPONIBLE'
                         WHERE id_bien_item = d.id_bien_item;
                    END IF;
                END IF;

                IF d.id_bien_lote IS NOT NULL THEN
                    INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                    VALUES (v_bodega_origen, d.id_bien_lote, 0, 0)
                    ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                    SELECT il.stock_actual
                      INTO v_stock_actual_lote
                      FROM inventario_lote il
                     WHERE il.id_bodega = v_bodega_origen
                       AND il.id_bien_lote = d.id_bien_lote
                     FOR UPDATE;

                    IF v_signo < 0 AND v_stock_actual_lote < d.cantidad THEN
                        RAISE EXCEPTION 'Stock insuficiente. bodega=% lote=% stock=% requerido=%',
                            v_bodega_origen, d.id_bien_lote, v_stock_actual_lote, d.cantidad;
                    END IF;

                    UPDATE inventario_lote
                       SET stock_actual = stock_actual + (v_signo * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_origen
                       AND id_bien_lote = d.id_bien_lote;

                ELSE
                    IF d.id_bien IS NULL THEN
                        RAISE EXCEPTION 'Detalle sin id_bien para inventario normal (id_registro_detalle=%)', d.id_registro_detalle;
                    END IF;

                    INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                    VALUES (v_bodega_origen, d.id_bien, 0, 0)
                    ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                    SELECT i.stock_actual
                      INTO v_stock_actual
                      FROM inventario i
                     WHERE i.id_bodega = v_bodega_origen
                       AND i.id_bien = d.id_bien
                     FOR UPDATE;

                    IF v_signo < 0 AND v_stock_actual < d.cantidad THEN
                        RAISE EXCEPTION 'Stock insuficiente. bodega=% bien=% stock=% requerido=%',
                            v_bodega_origen, d.id_bien, v_stock_actual, d.cantidad;
                    END IF;

                    UPDATE inventario
                       SET stock_actual = stock_actual + (v_signo * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_origen
                       AND id_bien = d.id_bien;
                END IF;

            ELSE
                IF d.id_bien_item IS NOT NULL THEN
                    UPDATE bien_item
                       SET id_bodega = v_bodega_destino,
                           estado_item = 'DISPONIBLE'
                     WHERE id_bien_item = d.id_bien_item;
                END IF;

                IF d.id_bien_lote IS NOT NULL THEN
                    INSERT INTO inventario_lote (id_bodega, id_bien_lote, stock_actual, stock_reservado)
                    VALUES (v_bodega_destino, d.id_bien_lote, 0, 0)
                    ON CONFLICT (id_bodega, id_bien_lote) DO NOTHING;

                    PERFORM 1
                      FROM inventario_lote il
                     WHERE il.id_bodega = v_bodega_destino
                       AND il.id_bien_lote = d.id_bien_lote
                     FOR UPDATE;

                    UPDATE inventario_lote
                       SET stock_actual = stock_actual + (v_signo * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_destino
                       AND id_bien_lote = d.id_bien_lote;

                ELSE
                    IF d.id_bien IS NULL THEN
                        RAISE EXCEPTION 'Detalle sin id_bien para inventario normal (id_registro_detalle=%)', d.id_registro_detalle;
                    END IF;

                    INSERT INTO inventario (id_bodega, id_bien, stock_actual, stock_reservado)
                    VALUES (v_bodega_destino, d.id_bien, 0, 0)
                    ON CONFLICT (id_bodega, id_bien) DO NOTHING;

                    PERFORM 1
                      FROM inventario i
                     WHERE i.id_bodega = v_bodega_destino
                       AND i.id_bien = d.id_bien
                     FOR UPDATE;

                    UPDATE inventario
                       SET stock_actual = stock_actual + (v_signo * d.cantidad),
                           fecha_ultima_actualizacion = NOW()
                     WHERE id_bodega = v_bodega_destino
                       AND id_bien = d.id_bien;
                END IF;
            END IF;
        END IF;
    END LOOP;

    UPDATE registro
       SET estado_registro = 'CONFIRMADO',
           fecha_actualizacion = NOW()
     WHERE id_registro = p_id_registro;

    CALL sp_log_evento(
        p_id_usuario,
        'CONFIRMAR_REGISTRO',
        'registro',
        p_id_registro,
        p_ip_origen,
        'Confirmación de registro y afectación de inventario',
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_registro_confirmar_y_afectar_stock(IN p_id_registro bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_registro_crear(bigint, bigint, bigint, bigint, bigint, bigint, bigint, character varying, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_registro_crear(IN p_id_tipo_registro bigint, IN p_id_usuario bigint, IN p_id_empleado bigint, IN p_id_solicitud bigint, IN p_id_documento bigint, IN p_id_bodega_origen bigint, IN p_id_bodega_destino bigint, IN p_referencia_externa character varying, IN p_observaciones text, OUT p_id_registro bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO registro (
        id_tipo_registro,
        id_usuario,
        id_empleado,
        id_solicitud,
        id_documento,
        id_bodega_origen,
        id_bodega_destino,
        referencia_externa,
        observaciones_registro,
        estado_registro,
        fecha_registro
    )
    VALUES (
        p_id_tipo_registro,
        p_id_usuario,
        p_id_empleado,
        p_id_solicitud,
        p_id_documento,
        p_id_bodega_origen,
        p_id_bodega_destino,
        p_referencia_externa,
        p_observaciones,
        'REGISTRADO',
        NOW()
    )
    RETURNING id_registro INTO p_id_registro;
END;
$$;


ALTER PROCEDURE public.sp_registro_crear(IN p_id_tipo_registro bigint, IN p_id_usuario bigint, IN p_id_empleado bigint, IN p_id_solicitud bigint, IN p_id_documento bigint, IN p_id_bodega_origen bigint, IN p_id_bodega_destino bigint, IN p_referencia_externa character varying, IN p_observaciones text, OUT p_id_registro bigint) OWNER TO juan;

--
-- Name: sp_rol_asignar_permiso(bigint, bigint, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_rol_asignar_permiso(IN p_id_rol bigint, IN p_id_permiso bigint, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_rol_permiso bigint, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO rol_permiso (id_rol, id_permiso)
    VALUES (p_id_rol, p_id_permiso)
    ON CONFLICT (id_rol, id_permiso) DO NOTHING
    RETURNING id_rol_permiso INTO p_id_rol_permiso;

    CALL sp_log_evento(
        p_id_usuario_accion,
        'ASIGNAR_PERMISO_ROL',
        'rol_permiso',
        p_id_rol_permiso,
        p_ip_origen,
        'Asignar permiso id_permiso=' || p_id_permiso::TEXT || ' a rol id_rol=' || p_id_rol::TEXT,
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_rol_asignar_permiso(IN p_id_rol bigint, IN p_id_permiso bigint, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_rol_permiso bigint, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_solicitud_cambiar_estado_y_reservar(bigint, bigint, bigint, bigint, character varying, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_solicitud_cambiar_estado_y_reservar(IN p_id_solicitud bigint, IN p_id_estado_nuevo bigint, IN p_id_bodega_reserva bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_observacion text, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_actual_id   BIGINT;
    v_estado_actual_nom  VARCHAR(60);
    v_estado_nuevo_nom   VARCHAR(60);

    v_nuevo_upper        VARCHAR(60);
    v_actual_upper       VARCHAR(60);

    d RECORD;
BEGIN
    SELECT sl.id_estado_solicitud
      INTO v_estado_actual_id
      FROM solicitud_logistica sl
     WHERE sl.id_solicitud = p_id_solicitud;

    IF v_estado_actual_id IS NULL THEN
        RAISE EXCEPTION 'No existe solicitud_logistica con id_solicitud=%', p_id_solicitud;
    END IF;

    SELECT es.nombre_estado
      INTO v_estado_actual_nom
      FROM estado_solicitud es
     WHERE es.id_estado_solicitud = v_estado_actual_id;

    SELECT es.nombre_estado
      INTO v_estado_nuevo_nom
      FROM estado_solicitud es
     WHERE es.id_estado_solicitud = p_id_estado_nuevo;

    IF v_estado_nuevo_nom IS NULL THEN
        RAISE EXCEPTION 'Estado nuevo invalido (id_estado_solicitud=%)', p_id_estado_nuevo;
    END IF;

    IF v_estado_actual_id = p_id_estado_nuevo THEN
        RAISE EXCEPTION 'La solicitud ya esta en ese estado (%).', v_estado_nuevo_nom;
    END IF;

    v_nuevo_upper  := UPPER(TRIM(v_estado_nuevo_nom));
    v_actual_upper := UPPER(TRIM(COALESCE(v_estado_actual_nom,'')));

    UPDATE solicitud_logistica
       SET id_estado_solicitud = p_id_estado_nuevo,
           fecha_respuesta = CASE
               WHEN v_nuevo_upper IN ('APROBADA','RECHAZADA','CANCELADA','CANCELADO')
               THEN NOW()
               ELSE fecha_respuesta
           END,
           observaciones_solicitud = CASE
               WHEN p_observacion IS NULL OR LENGTH(TRIM(p_observacion)) = 0
               THEN observaciones_solicitud
               ELSE COALESCE(observaciones_solicitud,'') ||
                    E'\n[' || TO_CHAR(NOW(),'YYYY-MM-DD HH24:MI') || '] ' || p_observacion
           END
     WHERE id_solicitud = p_id_solicitud;

    IF v_nuevo_upper = 'APROBADA' THEN
        IF p_id_bodega_reserva IS NULL THEN
            RAISE EXCEPTION 'Para APROBADA debe enviar p_id_bodega_reserva';
        END IF;

        FOR d IN
            SELECT sd.*
              FROM solicitud_detalle sd
             WHERE sd.id_solicitud = p_id_solicitud
        LOOP
            IF d.id_bien IS NOT NULL THEN
                CALL sp_inventario_reservar(
                    p_id_bodega_reserva,
                    d.id_bien,
                    NULL,
                    d.cantidad
                );
            END IF;
        END LOOP;

    ELSIF v_nuevo_upper IN ('RECHAZADA','CANCELADA','CANCELADO') AND v_actual_upper = 'APROBADA' THEN
        IF p_id_bodega_reserva IS NOT NULL THEN
            FOR d IN
                SELECT sd.*
                  FROM solicitud_detalle sd
                 WHERE sd.id_solicitud = p_id_solicitud
            LOOP
                IF d.id_bien IS NOT NULL THEN
                    DECLARE
                        v_reservado_actual NUMERIC(14,3);
                    BEGIN
                        SELECT COALESCE(i.stock_reservado, 0)
                          INTO v_reservado_actual
                          FROM inventario i
                         WHERE i.id_bodega = p_id_bodega_reserva
                           AND i.id_bien = d.id_bien;

                        IF v_reservado_actual IS NOT NULL AND v_reservado_actual >= d.cantidad THEN
                            CALL sp_inventario_liberar_reserva(
                                p_id_bodega_reserva,
                                d.id_bien,
                                NULL,
                                d.cantidad
                            );
                        END IF;
                    END;
                END IF;
            END LOOP;
        END IF;
    END IF;

    CALL sp_log_evento(
        p_id_usuario,
        'CAMBIAR_ESTADO_SOLICITUD',
        'solicitud_logistica',
        p_id_solicitud,
        p_ip_origen,
        'Cambio de estado: ' || COALESCE(v_estado_actual_nom,'(null)') ||
        ' -> ' || v_estado_nuevo_nom ||
        CASE WHEN p_id_bodega_reserva IS NULL THEN '' ELSE ' | bodega_reserva=' || p_id_bodega_reserva::TEXT END,
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_solicitud_cambiar_estado_y_reservar(IN p_id_solicitud bigint, IN p_id_estado_nuevo bigint, IN p_id_bodega_reserva bigint, IN p_id_usuario bigint, IN p_ip_origen character varying, IN p_observacion text, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_solicitud_generar_registro_salida(bigint, bigint, bigint, bigint, character varying, text, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_solicitud_generar_registro_salida(IN p_id_solicitud bigint, IN p_id_tipo_registro bigint, IN p_id_usuario bigint, IN p_id_bodega_origen bigint, IN p_referencia_externa character varying, IN p_observaciones text, IN p_ip_origen character varying, OUT p_id_registro bigint, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_empleado        BIGINT;
    v_id_estado          BIGINT;
    v_estado_nombre      VARCHAR(60);
    d RECORD;
BEGIN
    SELECT sl.id_empleado, sl.id_estado_solicitud
      INTO v_id_empleado, v_id_estado
      FROM solicitud_logistica sl
     WHERE sl.id_solicitud = p_id_solicitud;

    IF v_id_estado IS NULL THEN
        RAISE EXCEPTION 'No existe solicitud_logistica con id_solicitud=%', p_id_solicitud;
    END IF;

    SELECT es.nombre_estado
      INTO v_estado_nombre
      FROM estado_solicitud es
     WHERE es.id_estado_solicitud = v_id_estado;

    IF UPPER(TRIM(COALESCE(v_estado_nombre,''))) <> 'APROBADA' THEN
        RAISE EXCEPTION 'La solicitud debe estar APROBADA para generar el registro. Estado actual=%', v_estado_nombre;
    END IF;

    IF p_id_bodega_origen IS NULL THEN
        RAISE EXCEPTION 'Debe indicar p_id_bodega_origen para generar una salida';
    END IF;

    INSERT INTO registro (
        id_tipo_registro,
        id_usuario,
        id_empleado,
        id_solicitud,
        id_documento,
        id_bodega_origen,
        id_bodega_destino,
        referencia_externa,
        observaciones_registro,
        estado_registro,
        fecha_registro,
        fecha_actualizacion
    )
    VALUES (
        p_id_tipo_registro,
        p_id_usuario,
        v_id_empleado,
        p_id_solicitud,
        NULL,
        p_id_bodega_origen,
        NULL,
        COALESCE(p_referencia_externa, ('SOL-' || p_id_solicitud::TEXT)),
        p_observaciones,
        'REGISTRADO',
        NOW(),
        NOW()
    )
    RETURNING id_registro INTO p_id_registro;

    FOR d IN
        SELECT sd.*
          FROM solicitud_detalle sd
         WHERE sd.id_solicitud = p_id_solicitud
    LOOP
        IF d.id_bien IS NULL THEN
            CONTINUE;
        END IF;

        INSERT INTO registro_detalle (
            id_registro,
            id_bien,
            id_bien_item,
            id_bien_lote,
            cantidad,
            costo_unitario,
            lote,
            observacion_detalle
        )
        VALUES (
            p_id_registro,
            d.id_bien,
            NULL,
            NULL,
            d.cantidad,
            NULL,
            NULL,
            COALESCE(d.justificacion, d.descripcion_item)
        );
    END LOOP;

    CALL sp_log_evento(
        p_id_usuario,
        'GENERAR_REGISTRO_DESDE_SOLICITUD',
        'registro',
        p_id_registro,
        p_ip_origen,
        'Se generó un registro REGISTRADO desde solicitud=' || p_id_solicitud::TEXT ||
        ' | bodega_origen=' || p_id_bodega_origen::TEXT,
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_solicitud_generar_registro_salida(IN p_id_solicitud bigint, IN p_id_tipo_registro bigint, IN p_id_usuario bigint, IN p_id_bodega_origen bigint, IN p_referencia_externa character varying, IN p_observaciones text, IN p_ip_origen character varying, OUT p_id_registro bigint, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_usuario_asignar_rol(bigint, bigint, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_usuario_asignar_rol(IN p_id_usuario_objetivo bigint, IN p_id_rol bigint, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_usuario_rol bigint, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO usuario_rol (id_usuario, id_rol)
    VALUES (p_id_usuario_objetivo, p_id_rol)
    ON CONFLICT (id_usuario, id_rol) DO NOTHING
    RETURNING id_usuario_rol INTO p_id_usuario_rol;

    CALL sp_log_evento(
        p_id_usuario_accion,
        'ASIGNAR_ROL_USUARIO',
        'usuario_rol',
        p_id_usuario_rol,
        p_ip_origen,
        'Asignar rol id_rol=' || p_id_rol::TEXT || ' a usuario id_usuario=' || p_id_usuario_objetivo::TEXT,
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_usuario_asignar_rol(IN p_id_usuario_objetivo bigint, IN p_id_rol bigint, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_usuario_rol bigint, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_usuario_bloquear_desbloquear(bigint, boolean, boolean, bigint, character varying, text); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_usuario_bloquear_desbloquear(IN p_id_usuario_objetivo bigint, IN p_bloqueado boolean, IN p_reset_intentos boolean, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, IN p_motivo text, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_existe BIGINT;
BEGIN
    SELECT id_usuario INTO v_existe
      FROM usuario
     WHERE id_usuario = p_id_usuario_objetivo;

    IF v_existe IS NULL THEN
        RAISE EXCEPTION 'No existe usuario id=%', p_id_usuario_objetivo;
    END IF;

    UPDATE usuario
       SET bloqueado = COALESCE(p_bloqueado, bloqueado),
           intentos_fallidos = CASE
              WHEN COALESCE(p_reset_intentos,FALSE) THEN 0
              ELSE intentos_fallidos
           END
     WHERE id_usuario = p_id_usuario_objetivo;

    CALL sp_log_evento(
        p_id_usuario_accion,
        CASE WHEN COALESCE(p_bloqueado,FALSE) THEN 'BLOQUEAR_USUARIO' ELSE 'DESBLOQUEAR_USUARIO' END,
        'usuario',
        p_id_usuario_objetivo,
        p_ip_origen,
        COALESCE(p_motivo,'(sin motivo)'),
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_usuario_bloquear_desbloquear(IN p_id_usuario_objetivo bigint, IN p_bloqueado boolean, IN p_reset_intentos boolean, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, IN p_motivo text, OUT p_id_log_usuario bigint) OWNER TO juan;

--
-- Name: sp_usuario_crear(bigint, character varying, text, character varying, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: juan
--

CREATE PROCEDURE public.sp_usuario_crear(IN p_id_empleado bigint, IN p_nombre_usuario character varying, IN p_contrasena_hash text, IN p_correo_login character varying, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_usuario_nuevo bigint, OUT p_id_log_usuario bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF p_nombre_usuario IS NULL OR LENGTH(TRIM(p_nombre_usuario))=0 THEN
        RAISE EXCEPTION 'nombre_usuario es obligatorio';
    END IF;

    IF p_contrasena_hash IS NULL OR LENGTH(TRIM(p_contrasena_hash))=0 THEN
        RAISE EXCEPTION 'contrasena_usuario (hash) es obligatoria';
    END IF;

    INSERT INTO usuario (
        id_empleado,
        nombre_usuario,
        contrasena_usuario,
        correo_login
    )
    VALUES (
        p_id_empleado,
        TRIM(p_nombre_usuario),
        p_contrasena_hash,
        p_correo_login
    )
    RETURNING id_usuario INTO p_id_usuario_nuevo;

    CALL sp_log_evento(
        p_id_usuario_accion,
        'CREAR_USUARIO',
        'usuario',
        p_id_usuario_nuevo,
        p_ip_origen,
        'Usuario creado: ' || TRIM(p_nombre_usuario),
        p_id_log_usuario
    );
END;
$$;


ALTER PROCEDURE public.sp_usuario_crear(IN p_id_empleado bigint, IN p_nombre_usuario character varying, IN p_contrasena_hash text, IN p_correo_login character varying, IN p_id_usuario_accion bigint, IN p_ip_origen character varying, OUT p_id_usuario_nuevo bigint, OUT p_id_log_usuario bigint) OWNER TO juan;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: asignacion_bien; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.asignacion_bien (
    id_asignacion bigint NOT NULL,
    id_bien bigint,
    id_empleado bigint,
    id_registro bigint,
    tipo_acta character varying(40) NOT NULL,
    numero_acta character varying(60),
    fecha_emision_acta date,
    fecha_entrega_bien timestamp without time zone DEFAULT now() NOT NULL,
    fecha_devolucion_bien timestamp without time zone,
    motivo_asignacion character varying(120),
    observaciones_asignacion text,
    firma_digital boolean DEFAULT false NOT NULL,
    archivo_pdf text,
    estado_asignacion character varying(20) DEFAULT 'ACTIVA'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.asignacion_bien OWNER TO juan;

--
-- Name: asignacion_bien_id_asignacion_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.asignacion_bien_id_asignacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.asignacion_bien_id_asignacion_seq OWNER TO juan;

--
-- Name: asignacion_bien_id_asignacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.asignacion_bien_id_asignacion_seq OWNED BY public.asignacion_bien.id_asignacion;


--
-- Name: bien; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.bien (
    id_bien bigint NOT NULL,
    id_tipo_bien bigint,
    id_proveedor bigint,
    id_valor_bien bigint,
    codigo_inventario character varying(60) NOT NULL,
    nombre_bien character varying(120) NOT NULL,
    descripcion_bien text,
    marca character varying(60),
    modelo character varying(60),
    unidad_medida character varying(20),
    es_consumible boolean DEFAULT false NOT NULL,
    requiere_lote boolean DEFAULT false NOT NULL,
    requiere_serie boolean DEFAULT false NOT NULL,
    estado_bien character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    fecha_actualizacion timestamp without time zone,
    valor_unitario numeric(14,3) DEFAULT 0,
    requiere_mantenimiento boolean DEFAULT false NOT NULL,
    stock_minimo numeric(14,3)
);


ALTER TABLE public.bien OWNER TO juan;

--
-- Name: bien_id_bien_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.bien_id_bien_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bien_id_bien_seq OWNER TO juan;

--
-- Name: bien_id_bien_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.bien_id_bien_seq OWNED BY public.bien.id_bien;


--
-- Name: bien_item; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.bien_item (
    id_bien_item bigint NOT NULL,
    id_bien bigint,
    id_bodega bigint,
    id_empleado bigint,
    numero_serie character varying(120) NOT NULL,
    codigo_item character varying(120),
    estado_item character varying(20) DEFAULT 'DISPONIBLE'::character varying NOT NULL,
    fecha_alta timestamp without time zone DEFAULT now() NOT NULL,
    observaciones text
);


ALTER TABLE public.bien_item OWNER TO juan;

--
-- Name: bien_item_id_bien_item_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.bien_item_id_bien_item_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bien_item_id_bien_item_seq OWNER TO juan;

--
-- Name: bien_item_id_bien_item_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.bien_item_id_bien_item_seq OWNED BY public.bien_item.id_bien_item;


--
-- Name: bien_lote; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.bien_lote (
    id_bien_lote bigint NOT NULL,
    id_bien bigint,
    id_proveedor bigint,
    codigo_lote character varying(60) NOT NULL,
    fecha_fabricacion date,
    fecha_vencimiento date,
    estado_lote character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    observaciones_lote text,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.bien_lote OWNER TO juan;

--
-- Name: bien_lote_id_bien_lote_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.bien_lote_id_bien_lote_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bien_lote_id_bien_lote_seq OWNER TO juan;

--
-- Name: bien_lote_id_bien_lote_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.bien_lote_id_bien_lote_seq OWNED BY public.bien_lote.id_bien_lote;


--
-- Name: bodega; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.bodega (
    id_bodega bigint NOT NULL,
    id_sucursal bigint,
    nombre_bodega character varying(120) NOT NULL,
    codigo_bodega character varying(50),
    direccion_bodega character varying(200),
    responsable_bodega character varying(120),
    telefono_bodega character varying(20),
    estado_bodega character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    fecha_actualizacion timestamp without time zone
);


ALTER TABLE public.bodega OWNER TO juan;

--
-- Name: bodega_id_bodega_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.bodega_id_bodega_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bodega_id_bodega_seq OWNER TO juan;

--
-- Name: bodega_id_bodega_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.bodega_id_bodega_seq OWNED BY public.bodega.id_bodega;


--
-- Name: caracteristica_bien; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.caracteristica_bien (
    id_caracteristica_bien bigint NOT NULL,
    id_tipo_bien bigint,
    id_tipo_campo bigint,
    nombre_caracteristica character varying(120) NOT NULL,
    es_requerida boolean DEFAULT false NOT NULL,
    orden integer,
    estado_caracteristica character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.caracteristica_bien OWNER TO juan;

--
-- Name: caracteristica_bien_id_caracteristica_bien_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.caracteristica_bien_id_caracteristica_bien_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.caracteristica_bien_id_caracteristica_bien_seq OWNER TO juan;

--
-- Name: caracteristica_bien_id_caracteristica_bien_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.caracteristica_bien_id_caracteristica_bien_seq OWNED BY public.caracteristica_bien.id_caracteristica_bien;


--
-- Name: caracteristica_opcion; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.caracteristica_opcion (
    id_caracteristica_opcion bigint NOT NULL,
    id_caracteristica_bien bigint,
    valor_opcion character varying(120) NOT NULL,
    estado_opcion character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.caracteristica_opcion OWNER TO juan;

--
-- Name: caracteristica_opcion_id_caracteristica_opcion_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.caracteristica_opcion_id_caracteristica_opcion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.caracteristica_opcion_id_caracteristica_opcion_seq OWNER TO juan;

--
-- Name: caracteristica_opcion_id_caracteristica_opcion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.caracteristica_opcion_id_caracteristica_opcion_seq OWNED BY public.caracteristica_opcion.id_caracteristica_opcion;


--
-- Name: correo_persona; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.correo_persona (
    id_correo bigint NOT NULL,
    id_persona bigint,
    correo_electronico character varying(160) NOT NULL,
    principal boolean DEFAULT false NOT NULL,
    estado_correo character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.correo_persona OWNER TO juan;

--
-- Name: correo_persona_id_correo_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.correo_persona_id_correo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.correo_persona_id_correo_seq OWNER TO juan;

--
-- Name: correo_persona_id_correo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.correo_persona_id_correo_seq OWNED BY public.correo_persona.id_correo;


--
-- Name: departamento; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.departamento (
    id_departamento bigint NOT NULL,
    nombre_departamento character varying(120) NOT NULL,
    descripcion_departamento text,
    ubicacion_departamento character varying(120),
    estado_departamento character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.departamento OWNER TO juan;

--
-- Name: departamento_id_departamento_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.departamento_id_departamento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.departamento_id_departamento_seq OWNER TO juan;

--
-- Name: departamento_id_departamento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.departamento_id_departamento_seq OWNED BY public.departamento.id_departamento;


--
-- Name: direccion_persona; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.direccion_persona (
    id_direccion bigint NOT NULL,
    id_persona bigint,
    tipo_direccion character varying(40),
    pais character varying(80),
    departamento character varying(80),
    municipio character varying(80),
    colonia_barrio character varying(120),
    direccion_detallada text,
    principal boolean DEFAULT false NOT NULL,
    estado_direccion character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.direccion_persona OWNER TO juan;

--
-- Name: direccion_persona_id_direccion_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.direccion_persona_id_direccion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.direccion_persona_id_direccion_seq OWNER TO juan;

--
-- Name: direccion_persona_id_direccion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.direccion_persona_id_direccion_seq OWNED BY public.direccion_persona.id_direccion;


--
-- Name: documento; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.documento (
    id_documento bigint NOT NULL,
    nombre_documento character varying(150) NOT NULL,
    tipo_documento character varying(60) NOT NULL,
    entidad_emisora character varying(120),
    fecha_emision date,
    numero_referencia character varying(80),
    ruta_archivo text,
    notas_adicionales text,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.documento OWNER TO juan;

--
-- Name: documento_id_documento_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.documento_id_documento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.documento_id_documento_seq OWNER TO juan;

--
-- Name: documento_id_documento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.documento_id_documento_seq OWNED BY public.documento.id_documento;


--
-- Name: empleado; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.empleado (
    id_empleado bigint NOT NULL,
    id_persona bigint,
    id_departamento bigint,
    id_estatus_empleado bigint,
    id_puesto bigint,
    id_sucursal bigint,
    codigo_empleado character varying(40),
    fecha_ingreso date,
    estado_empleado character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.empleado OWNER TO juan;

--
-- Name: empleado_id_empleado_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.empleado_id_empleado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.empleado_id_empleado_seq OWNER TO juan;

--
-- Name: empleado_id_empleado_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.empleado_id_empleado_seq OWNED BY public.empleado.id_empleado;


--
-- Name: empresa; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.empresa (
    id_empresa bigint NOT NULL,
    nombre_empresa character varying(120) NOT NULL,
    rtn_empresa character varying(30),
    direccion_fiscal character varying(200),
    correo_empresa character varying(160),
    telefono_empresa character varying(20),
    estado_empresa character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    fecha_actualizacion timestamp without time zone
);


ALTER TABLE public.empresa OWNER TO juan;

--
-- Name: empresa_id_empresa_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.empresa_id_empresa_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.empresa_id_empresa_seq OWNER TO juan;

--
-- Name: empresa_id_empresa_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.empresa_id_empresa_seq OWNED BY public.empresa.id_empresa;


--
-- Name: estado_solicitud; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.estado_solicitud (
    id_estado_solicitud bigint NOT NULL,
    nombre_estado character varying(60) NOT NULL,
    descripcion_estado text,
    estado_registro character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.estado_solicitud OWNER TO juan;

--
-- Name: estado_solicitud_id_estado_solicitud_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.estado_solicitud_id_estado_solicitud_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.estado_solicitud_id_estado_solicitud_seq OWNER TO juan;

--
-- Name: estado_solicitud_id_estado_solicitud_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.estado_solicitud_id_estado_solicitud_seq OWNED BY public.estado_solicitud.id_estado_solicitud;


--
-- Name: estatus_empleado; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.estatus_empleado (
    id_estatus_empleado bigint NOT NULL,
    nombre_estatus character varying(40) NOT NULL,
    descripcion_estatus text,
    estado_estatus character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.estatus_empleado OWNER TO juan;

--
-- Name: estatus_empleado_id_estatus_empleado_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.estatus_empleado_id_estatus_empleado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.estatus_empleado_id_estatus_empleado_seq OWNER TO juan;

--
-- Name: estatus_empleado_id_estatus_empleado_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.estatus_empleado_id_estatus_empleado_seq OWNED BY public.estatus_empleado.id_estatus_empleado;


--
-- Name: historial_reservas; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.historial_reservas (
    id_historial integer NOT NULL,
    id_bodega integer NOT NULL,
    id_bien integer NOT NULL,
    cantidad integer NOT NULL,
    accion character varying(20) NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usuario character varying(100),
    solicitante character varying(120),
    motivo text
);


ALTER TABLE public.historial_reservas OWNER TO juan;

--
-- Name: historial_reservas_id_historial_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.historial_reservas_id_historial_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.historial_reservas_id_historial_seq OWNER TO juan;

--
-- Name: historial_reservas_id_historial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.historial_reservas_id_historial_seq OWNED BY public.historial_reservas.id_historial;


--
-- Name: inventario; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.inventario (
    id_inventario bigint NOT NULL,
    id_bodega bigint,
    id_bien bigint NOT NULL,
    stock_actual numeric(14,3) DEFAULT 0 NOT NULL,
    stock_reservado numeric(14,3) DEFAULT 0 NOT NULL,
    stock_minimo numeric(14,3),
    estado_inventario character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_ultima_actualizacion timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_inventario_stock CHECK (((stock_actual >= (0)::numeric) AND (stock_reservado >= (0)::numeric)))
);


ALTER TABLE public.inventario OWNER TO juan;

--
-- Name: inventario_id_inventario_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.inventario_id_inventario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventario_id_inventario_seq OWNER TO juan;

--
-- Name: inventario_id_inventario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.inventario_id_inventario_seq OWNED BY public.inventario.id_inventario;


--
-- Name: inventario_lote; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.inventario_lote (
    id_inventario_lote bigint NOT NULL,
    id_bodega bigint NOT NULL,
    id_bien_lote bigint NOT NULL,
    stock_actual numeric(14,3) DEFAULT 0 NOT NULL,
    stock_reservado numeric(14,3) DEFAULT 0 NOT NULL,
    estado_inventario_lote character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_ultima_actualizacion timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_inventario_lote_stock CHECK (((stock_actual >= (0)::numeric) AND (stock_reservado >= (0)::numeric)))
);


ALTER TABLE public.inventario_lote OWNER TO juan;

--
-- Name: inventario_lote_id_inventario_lote_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.inventario_lote_id_inventario_lote_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventario_lote_id_inventario_lote_seq OWNER TO juan;

--
-- Name: inventario_lote_id_inventario_lote_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.inventario_lote_id_inventario_lote_seq OWNED BY public.inventario_lote.id_inventario_lote;


--
-- Name: kardex; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.kardex (
    id_kardex integer NOT NULL,
    fecha timestamp without time zone DEFAULT now(),
    tipo character varying(10) NOT NULL,
    id_bien bigint NOT NULL,
    entrada numeric DEFAULT 0,
    salida numeric DEFAULT 0,
    saldo numeric DEFAULT 0,
    usuario character varying(50),
    id_bodega bigint
);


ALTER TABLE public.kardex OWNER TO juan;

--
-- Name: kardex_id_kardex_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.kardex_id_kardex_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.kardex_id_kardex_seq OWNER TO juan;

--
-- Name: kardex_id_kardex_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.kardex_id_kardex_seq OWNED BY public.kardex.id_kardex;


--
-- Name: log_cambios; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.log_cambios (
    id_log_cambios bigint NOT NULL,
    id_log_usuario bigint,
    campo_modificado character varying(80) NOT NULL,
    valor_antes text,
    valor_despues text
);


ALTER TABLE public.log_cambios OWNER TO juan;

--
-- Name: log_cambios_id_log_cambios_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.log_cambios_id_log_cambios_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.log_cambios_id_log_cambios_seq OWNER TO juan;

--
-- Name: log_cambios_id_log_cambios_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.log_cambios_id_log_cambios_seq OWNED BY public.log_cambios.id_log_cambios;


--
-- Name: log_usuario; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.log_usuario (
    id_log_usuario bigint NOT NULL,
    id_usuario bigint,
    fecha_accion timestamp without time zone DEFAULT now() NOT NULL,
    hora_accion time without time zone,
    tipo_accion character varying(40) NOT NULL,
    tabla_afectada character varying(60),
    registro_afectado bigint,
    ip_origen character varying(45),
    descripcion_log text
);


ALTER TABLE public.log_usuario OWNER TO juan;

--
-- Name: log_usuario_id_log_usuario_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.log_usuario_id_log_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.log_usuario_id_log_usuario_seq OWNER TO juan;

--
-- Name: log_usuario_id_log_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.log_usuario_id_log_usuario_seq OWNED BY public.log_usuario.id_log_usuario;


--
-- Name: mantenimiento; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.mantenimiento (
    id_mantenimiento bigint NOT NULL,
    id_bien bigint,
    id_tipo_mantenimiento bigint,
    id_proveedor bigint,
    id_documento bigint,
    fecha_inicio date,
    fecha_fin date,
    fecha_programada date,
    kilometraje numeric(12,1),
    descripcion_mantenimiento text NOT NULL,
    costo_mantenimiento numeric(14,2),
    estado_mantenimiento character varying(20) DEFAULT 'PROGRAMADO'::character varying NOT NULL,
    observaciones_mantenimiento text,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.mantenimiento OWNER TO juan;

--
-- Name: mantenimiento_id_mantenimiento_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.mantenimiento_id_mantenimiento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mantenimiento_id_mantenimiento_seq OWNER TO juan;

--
-- Name: mantenimiento_id_mantenimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.mantenimiento_id_mantenimiento_seq OWNED BY public.mantenimiento.id_mantenimiento;


--
-- Name: permiso; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.permiso (
    id_permiso bigint NOT NULL,
    nombre_permiso character varying(80) NOT NULL,
    codigo_permiso character varying(60) NOT NULL,
    descripcion_permiso text,
    estado_permiso character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.permiso OWNER TO juan;

--
-- Name: permiso_id_permiso_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.permiso_id_permiso_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.permiso_id_permiso_seq OWNER TO juan;

--
-- Name: permiso_id_permiso_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.permiso_id_permiso_seq OWNED BY public.permiso.id_permiso;


--
-- Name: persona; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.persona (
    id_persona bigint NOT NULL,
    primer_nombre character varying(60) NOT NULL,
    segundo_nombre character varying(60),
    primer_apellido character varying(60) NOT NULL,
    segundo_apellido character varying(60),
    identidad character varying(30) NOT NULL,
    fecha_nacimiento date,
    sexo character varying(10),
    estado_persona character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.persona OWNER TO juan;

--
-- Name: persona_id_persona_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.persona_id_persona_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.persona_id_persona_seq OWNER TO juan;

--
-- Name: persona_id_persona_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.persona_id_persona_seq OWNED BY public.persona.id_persona;


--
-- Name: proveedor; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.proveedor (
    id_proveedor bigint NOT NULL,
    nombre_proveedor character varying(150) NOT NULL,
    rtn_proveedor character varying(30),
    categoria_servicio character varying(80),
    especialidad character varying(120),
    contacto_representante character varying(120),
    telefono_contacto character varying(20),
    correo_contacto character varying(160),
    estado_proveedor character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.proveedor OWNER TO juan;

--
-- Name: proveedor_id_proveedor_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.proveedor_id_proveedor_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.proveedor_id_proveedor_seq OWNER TO juan;

--
-- Name: proveedor_id_proveedor_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.proveedor_id_proveedor_seq OWNED BY public.proveedor.id_proveedor;


--
-- Name: puesto; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.puesto (
    id_puesto bigint NOT NULL,
    nombre_puesto character varying(80) NOT NULL,
    descripcion_puesto text,
    nivel_puesto character varying(40),
    estado_puesto character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.puesto OWNER TO juan;

--
-- Name: puesto_id_puesto_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.puesto_id_puesto_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.puesto_id_puesto_seq OWNER TO juan;

--
-- Name: puesto_id_puesto_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.puesto_id_puesto_seq OWNED BY public.puesto.id_puesto;


--
-- Name: rate_limiter; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.rate_limiter (
    key character varying(255) NOT NULL,
    points integer DEFAULT 0 NOT NULL,
    expire bigint
);


ALTER TABLE public.rate_limiter OWNER TO juan;

--
-- Name: registro; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.registro (
    id_registro bigint NOT NULL,
    id_tipo_registro bigint,
    id_usuario bigint,
    id_empleado bigint,
    id_solicitud bigint,
    id_documento bigint,
    id_bodega_origen bigint,
    id_bodega_destino bigint,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    referencia_externa character varying(80),
    observaciones_registro text,
    estado_registro character varying(20) DEFAULT 'REGISTRADO'::character varying NOT NULL,
    fecha_actualizacion timestamp without time zone
);


ALTER TABLE public.registro OWNER TO juan;

--
-- Name: registro_caracteristica; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.registro_caracteristica (
    id_registro_caracteristica bigint NOT NULL,
    id_registro_detalle bigint NOT NULL,
    id_caracteristica_bien bigint NOT NULL,
    id_opcion bigint,
    valor_texto text,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.registro_caracteristica OWNER TO juan;

--
-- Name: registro_caracteristica_id_registro_caracteristica_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.registro_caracteristica_id_registro_caracteristica_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.registro_caracteristica_id_registro_caracteristica_seq OWNER TO juan;

--
-- Name: registro_caracteristica_id_registro_caracteristica_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.registro_caracteristica_id_registro_caracteristica_seq OWNED BY public.registro_caracteristica.id_registro_caracteristica;


--
-- Name: registro_detalle; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.registro_detalle (
    id_registro_detalle bigint NOT NULL,
    id_registro bigint NOT NULL,
    id_bien bigint,
    id_bien_item bigint,
    id_bien_lote bigint,
    cantidad numeric(14,3) NOT NULL,
    costo_unitario numeric(14,2),
    lote character varying(60),
    observacion_detalle text,
    CONSTRAINT ck_registro_detalle_cantidad CHECK ((cantidad > (0)::numeric))
);


ALTER TABLE public.registro_detalle OWNER TO juan;

--
-- Name: registro_detalle_id_registro_detalle_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.registro_detalle_id_registro_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.registro_detalle_id_registro_detalle_seq OWNER TO juan;

--
-- Name: registro_detalle_id_registro_detalle_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.registro_detalle_id_registro_detalle_seq OWNED BY public.registro_detalle.id_registro_detalle;


--
-- Name: registro_id_registro_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.registro_id_registro_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.registro_id_registro_seq OWNER TO juan;

--
-- Name: registro_id_registro_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.registro_id_registro_seq OWNED BY public.registro.id_registro;


--
-- Name: rol; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.rol (
    id_rol bigint NOT NULL,
    nombre_rol character varying(60) NOT NULL,
    descripcion_rol text,
    estado_rol character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.rol OWNER TO juan;

--
-- Name: rol_id_rol_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.rol_id_rol_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rol_id_rol_seq OWNER TO juan;

--
-- Name: rol_id_rol_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.rol_id_rol_seq OWNED BY public.rol.id_rol;


--
-- Name: rol_permiso; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.rol_permiso (
    id_rol_permiso bigint NOT NULL,
    id_rol bigint,
    id_permiso bigint,
    fecha_asignacion timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.rol_permiso OWNER TO juan;

--
-- Name: rol_permiso_id_rol_permiso_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.rol_permiso_id_rol_permiso_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rol_permiso_id_rol_permiso_seq OWNER TO juan;

--
-- Name: rol_permiso_id_rol_permiso_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.rol_permiso_id_rol_permiso_seq OWNED BY public.rol_permiso.id_rol_permiso;


--
-- Name: solicitud_detalle; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.solicitud_detalle (
    id_solicitud_detalle bigint NOT NULL,
    id_solicitud bigint NOT NULL,
    id_bien bigint,
    descripcion_item character varying(200),
    cantidad numeric(14,3) NOT NULL,
    justificacion text,
    CONSTRAINT ck_solicitud_detalle_cantidad CHECK ((cantidad > (0)::numeric))
);


ALTER TABLE public.solicitud_detalle OWNER TO juan;

--
-- Name: solicitud_detalle_id_solicitud_detalle_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.solicitud_detalle_id_solicitud_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.solicitud_detalle_id_solicitud_detalle_seq OWNER TO juan;

--
-- Name: solicitud_detalle_id_solicitud_detalle_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.solicitud_detalle_id_solicitud_detalle_seq OWNED BY public.solicitud_detalle.id_solicitud_detalle;


--
-- Name: solicitud_logistica; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.solicitud_logistica (
    id_solicitud bigint NOT NULL,
    id_empleado bigint,
    id_tipo_solicitud bigint,
    id_estado_solicitud bigint,
    prioridad character varying(20),
    descripcion_solicitud text NOT NULL,
    fecha_solicitud timestamp without time zone DEFAULT now() NOT NULL,
    fecha_respuesta timestamp without time zone,
    observaciones_solicitud text
);


ALTER TABLE public.solicitud_logistica OWNER TO juan;

--
-- Name: solicitud_logistica_id_solicitud_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.solicitud_logistica_id_solicitud_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.solicitud_logistica_id_solicitud_seq OWNER TO juan;

--
-- Name: solicitud_logistica_id_solicitud_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.solicitud_logistica_id_solicitud_seq OWNED BY public.solicitud_logistica.id_solicitud;


--
-- Name: sucursal; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.sucursal (
    id_sucursal bigint NOT NULL,
    id_empresa bigint,
    nombre_sucursal character varying(120) NOT NULL,
    codigo_sucursal character varying(50),
    direccion_sucursal character varying(200),
    telefono_sucursal character varying(20),
    correo_sucursal character varying(160),
    estado_sucursal character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    fecha_actualizacion timestamp without time zone
);


ALTER TABLE public.sucursal OWNER TO juan;

--
-- Name: sucursal_id_sucursal_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.sucursal_id_sucursal_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sucursal_id_sucursal_seq OWNER TO juan;

--
-- Name: sucursal_id_sucursal_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.sucursal_id_sucursal_seq OWNED BY public.sucursal.id_sucursal;


--
-- Name: telefono_persona; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.telefono_persona (
    id_telefono bigint NOT NULL,
    id_persona bigint,
    tipo_telefono character varying(40),
    numero character varying(20) NOT NULL,
    extension character varying(10),
    principal boolean DEFAULT false NOT NULL,
    estado_telefono character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.telefono_persona OWNER TO juan;

--
-- Name: telefono_persona_id_telefono_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.telefono_persona_id_telefono_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.telefono_persona_id_telefono_seq OWNER TO juan;

--
-- Name: telefono_persona_id_telefono_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.telefono_persona_id_telefono_seq OWNED BY public.telefono_persona.id_telefono;


--
-- Name: tipo_bien; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.tipo_bien (
    id_tipo_bien bigint NOT NULL,
    nombre_tipo_bien character varying(80) NOT NULL,
    descripcion_tipo_bien text,
    estado_tipo_bien character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tipo_bien OWNER TO juan;

--
-- Name: tipo_bien_id_tipo_bien_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.tipo_bien_id_tipo_bien_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_bien_id_tipo_bien_seq OWNER TO juan;

--
-- Name: tipo_bien_id_tipo_bien_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.tipo_bien_id_tipo_bien_seq OWNED BY public.tipo_bien.id_tipo_bien;


--
-- Name: tipo_campo; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.tipo_campo (
    id_tipo_campo bigint NOT NULL,
    nombre_tipo_campo character varying(80) NOT NULL,
    tipo_dato character varying(40) NOT NULL,
    estado_tipo_campo character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tipo_campo OWNER TO juan;

--
-- Name: tipo_campo_id_tipo_campo_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.tipo_campo_id_tipo_campo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_campo_id_tipo_campo_seq OWNER TO juan;

--
-- Name: tipo_campo_id_tipo_campo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.tipo_campo_id_tipo_campo_seq OWNED BY public.tipo_campo.id_tipo_campo;


--
-- Name: tipo_mantenimiento; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.tipo_mantenimiento (
    id_tipo_mantenimiento bigint NOT NULL,
    nombre_tipo_mantenimiento character varying(80) NOT NULL,
    categoria_general character varying(60),
    frecuencia_recomendada integer,
    costo_estimado numeric(14,2),
    estado_tipo_mantenimiento character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tipo_mantenimiento OWNER TO juan;

--
-- Name: tipo_mantenimiento_id_tipo_mantenimiento_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.tipo_mantenimiento_id_tipo_mantenimiento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_mantenimiento_id_tipo_mantenimiento_seq OWNER TO juan;

--
-- Name: tipo_mantenimiento_id_tipo_mantenimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.tipo_mantenimiento_id_tipo_mantenimiento_seq OWNED BY public.tipo_mantenimiento.id_tipo_mantenimiento;


--
-- Name: tipo_registro; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.tipo_registro (
    id_tipo_registro bigint NOT NULL,
    nombre_tipo_registro character varying(80) NOT NULL,
    afecta_stock boolean DEFAULT true NOT NULL,
    signo_movimiento integer,
    estado_tipo_registro character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tipo_registro OWNER TO juan;

--
-- Name: tipo_registro_id_tipo_registro_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.tipo_registro_id_tipo_registro_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_registro_id_tipo_registro_seq OWNER TO juan;

--
-- Name: tipo_registro_id_tipo_registro_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.tipo_registro_id_tipo_registro_seq OWNED BY public.tipo_registro.id_tipo_registro;


--
-- Name: tipo_solicitud; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.tipo_solicitud (
    id_tipo_solicitud bigint NOT NULL,
    nombre_tipo_solicitud character varying(80) NOT NULL,
    descripcion_tipo_solicitud text,
    estado_tipo_solicitud character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tipo_solicitud OWNER TO juan;

--
-- Name: tipo_solicitud_id_tipo_solicitud_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.tipo_solicitud_id_tipo_solicitud_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_solicitud_id_tipo_solicitud_seq OWNER TO juan;

--
-- Name: tipo_solicitud_id_tipo_solicitud_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.tipo_solicitud_id_tipo_solicitud_seq OWNED BY public.tipo_solicitud.id_tipo_solicitud;


--
-- Name: usuario; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.usuario (
    id_usuario bigint NOT NULL,
    id_empleado bigint,
    nombre_usuario character varying(60) NOT NULL,
    contrasena_usuario text NOT NULL,
    correo_login character varying(160),
    ultimo_acceso timestamp without time zone,
    intentos_fallidos integer DEFAULT 0 NOT NULL,
    bloqueado boolean DEFAULT false NOT NULL,
    estado_usuario character varying(20) DEFAULT 'ACTIVO'::character varying NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    reset_token character varying(16),
    reset_token_expires timestamp without time zone,
    pin_hash character varying(100),
    pin_reset_token character varying(10),
    pin_reset_token_expires timestamp without time zone
);


ALTER TABLE public.usuario OWNER TO juan;

--
-- Name: COLUMN usuario.reset_token; Type: COMMENT; Schema: public; Owner: juan
--

COMMENT ON COLUMN public.usuario.reset_token IS 'Token alfanumerico de 8 caracteres enviado por email para recuperar contrasena';


--
-- Name: COLUMN usuario.reset_token_expires; Type: COMMENT; Schema: public; Owner: juan
--

COMMENT ON COLUMN public.usuario.reset_token_expires IS 'Fecha/hora de expiracion del reset_token (usualmente 15 minutos despues de generado)';


--
-- Name: COLUMN usuario.pin_hash; Type: COMMENT; Schema: public; Owner: juan
--

COMMENT ON COLUMN public.usuario.pin_hash IS 'Hash bcrypt del PIN de 8 caracteres alfanumerico que el usuario debe ingresar en el paso 2FA despues del login.';


--
-- Name: COLUMN usuario.pin_reset_token; Type: COMMENT; Schema: public; Owner: juan
--

COMMENT ON COLUMN public.usuario.pin_reset_token IS 'Codigo numerico de 6 digitos enviado por email para restablecer el PIN OTP.';


--
-- Name: COLUMN usuario.pin_reset_token_expires; Type: COMMENT; Schema: public; Owner: juan
--

COMMENT ON COLUMN public.usuario.pin_reset_token_expires IS 'Fecha/hora de expiracion del pin_reset_token (usualmente 10 minutos).';


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.usuario_id_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuario_id_usuario_seq OWNER TO juan;

--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.usuario_id_usuario_seq OWNED BY public.usuario.id_usuario;


--
-- Name: usuario_permiso; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.usuario_permiso (
    id_usuario bigint NOT NULL,
    id_permiso bigint NOT NULL
);


ALTER TABLE public.usuario_permiso OWNER TO juan;

--
-- Name: usuario_rol; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.usuario_rol (
    id_usuario_rol bigint NOT NULL,
    id_usuario bigint,
    id_rol bigint,
    fecha_asignacion timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.usuario_rol OWNER TO juan;

--
-- Name: usuario_rol_id_usuario_rol_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.usuario_rol_id_usuario_rol_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuario_rol_id_usuario_rol_seq OWNER TO juan;

--
-- Name: usuario_rol_id_usuario_rol_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.usuario_rol_id_usuario_rol_seq OWNED BY public.usuario_rol.id_usuario_rol;


--
-- Name: valor_bien; Type: TABLE; Schema: public; Owner: juan
--

CREATE TABLE public.valor_bien (
    id_valor_bien bigint NOT NULL,
    valor_compra numeric(14,2),
    valor_actual numeric(14,2),
    valor_depreciacion numeric(14,2),
    porcentaje_depreciacion numeric(6,2),
    vida_util_estimada integer,
    fecha_avaluo date,
    entidad_avaluadora character varying(120),
    moneda character varying(10),
    observaciones_valor text,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.valor_bien OWNER TO juan;

--
-- Name: valor_bien_id_valor_bien_seq; Type: SEQUENCE; Schema: public; Owner: juan
--

CREATE SEQUENCE public.valor_bien_id_valor_bien_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.valor_bien_id_valor_bien_seq OWNER TO juan;

--
-- Name: valor_bien_id_valor_bien_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: juan
--

ALTER SEQUENCE public.valor_bien_id_valor_bien_seq OWNED BY public.valor_bien.id_valor_bien;


--
-- Name: vw_kardex; Type: VIEW; Schema: public; Owner: juan
--

CREATE VIEW public.vw_kardex AS
 SELECT r.id_registro,
    r.fecha_registro,
    tr.nombre_tipo_registro,
    tr.signo_movimiento,
    r.id_bodega_origen,
    r.id_bodega_destino,
    rd.id_bien,
    b.nombre_bien,
    rd.cantidad,
        CASE
            WHEN (tr.signo_movimiento > 0) THEN rd.cantidad
            ELSE (0)::numeric
        END AS entrada,
        CASE
            WHEN (tr.signo_movimiento < 0) THEN rd.cantidad
            ELSE (0)::numeric
        END AS salida,
    r.referencia_externa,
    r.estado_registro
   FROM (((public.registro r
     JOIN public.registro_detalle rd ON ((rd.id_registro = r.id_registro)))
     JOIN public.tipo_registro tr ON ((tr.id_tipo_registro = r.id_tipo_registro)))
     JOIN public.bien b ON ((b.id_bien = rd.id_bien)))
  WHERE ((r.estado_registro)::text = 'CONFIRMADO'::text);


ALTER VIEW public.vw_kardex OWNER TO juan;

--
-- Name: asignacion_bien id_asignacion; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.asignacion_bien ALTER COLUMN id_asignacion SET DEFAULT nextval('public.asignacion_bien_id_asignacion_seq'::regclass);


--
-- Name: bien id_bien; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien ALTER COLUMN id_bien SET DEFAULT nextval('public.bien_id_bien_seq'::regclass);


--
-- Name: bien_item id_bien_item; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_item ALTER COLUMN id_bien_item SET DEFAULT nextval('public.bien_item_id_bien_item_seq'::regclass);


--
-- Name: bien_lote id_bien_lote; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_lote ALTER COLUMN id_bien_lote SET DEFAULT nextval('public.bien_lote_id_bien_lote_seq'::regclass);


--
-- Name: bodega id_bodega; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bodega ALTER COLUMN id_bodega SET DEFAULT nextval('public.bodega_id_bodega_seq'::regclass);


--
-- Name: caracteristica_bien id_caracteristica_bien; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.caracteristica_bien ALTER COLUMN id_caracteristica_bien SET DEFAULT nextval('public.caracteristica_bien_id_caracteristica_bien_seq'::regclass);


--
-- Name: caracteristica_opcion id_caracteristica_opcion; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.caracteristica_opcion ALTER COLUMN id_caracteristica_opcion SET DEFAULT nextval('public.caracteristica_opcion_id_caracteristica_opcion_seq'::regclass);


--
-- Name: correo_persona id_correo; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.correo_persona ALTER COLUMN id_correo SET DEFAULT nextval('public.correo_persona_id_correo_seq'::regclass);


--
-- Name: departamento id_departamento; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.departamento ALTER COLUMN id_departamento SET DEFAULT nextval('public.departamento_id_departamento_seq'::regclass);


--
-- Name: direccion_persona id_direccion; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.direccion_persona ALTER COLUMN id_direccion SET DEFAULT nextval('public.direccion_persona_id_direccion_seq'::regclass);


--
-- Name: documento id_documento; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.documento ALTER COLUMN id_documento SET DEFAULT nextval('public.documento_id_documento_seq'::regclass);


--
-- Name: empleado id_empleado; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado ALTER COLUMN id_empleado SET DEFAULT nextval('public.empleado_id_empleado_seq'::regclass);


--
-- Name: empresa id_empresa; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empresa ALTER COLUMN id_empresa SET DEFAULT nextval('public.empresa_id_empresa_seq'::regclass);


--
-- Name: estado_solicitud id_estado_solicitud; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.estado_solicitud ALTER COLUMN id_estado_solicitud SET DEFAULT nextval('public.estado_solicitud_id_estado_solicitud_seq'::regclass);


--
-- Name: estatus_empleado id_estatus_empleado; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.estatus_empleado ALTER COLUMN id_estatus_empleado SET DEFAULT nextval('public.estatus_empleado_id_estatus_empleado_seq'::regclass);


--
-- Name: historial_reservas id_historial; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.historial_reservas ALTER COLUMN id_historial SET DEFAULT nextval('public.historial_reservas_id_historial_seq'::regclass);


--
-- Name: inventario id_inventario; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario ALTER COLUMN id_inventario SET DEFAULT nextval('public.inventario_id_inventario_seq'::regclass);


--
-- Name: inventario_lote id_inventario_lote; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario_lote ALTER COLUMN id_inventario_lote SET DEFAULT nextval('public.inventario_lote_id_inventario_lote_seq'::regclass);


--
-- Name: kardex id_kardex; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.kardex ALTER COLUMN id_kardex SET DEFAULT nextval('public.kardex_id_kardex_seq'::regclass);


--
-- Name: log_cambios id_log_cambios; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.log_cambios ALTER COLUMN id_log_cambios SET DEFAULT nextval('public.log_cambios_id_log_cambios_seq'::regclass);


--
-- Name: log_usuario id_log_usuario; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.log_usuario ALTER COLUMN id_log_usuario SET DEFAULT nextval('public.log_usuario_id_log_usuario_seq'::regclass);


--
-- Name: mantenimiento id_mantenimiento; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.mantenimiento ALTER COLUMN id_mantenimiento SET DEFAULT nextval('public.mantenimiento_id_mantenimiento_seq'::regclass);


--
-- Name: permiso id_permiso; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.permiso ALTER COLUMN id_permiso SET DEFAULT nextval('public.permiso_id_permiso_seq'::regclass);


--
-- Name: persona id_persona; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.persona ALTER COLUMN id_persona SET DEFAULT nextval('public.persona_id_persona_seq'::regclass);


--
-- Name: proveedor id_proveedor; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.proveedor ALTER COLUMN id_proveedor SET DEFAULT nextval('public.proveedor_id_proveedor_seq'::regclass);


--
-- Name: puesto id_puesto; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.puesto ALTER COLUMN id_puesto SET DEFAULT nextval('public.puesto_id_puesto_seq'::regclass);


--
-- Name: registro id_registro; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro ALTER COLUMN id_registro SET DEFAULT nextval('public.registro_id_registro_seq'::regclass);


--
-- Name: registro_caracteristica id_registro_caracteristica; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_caracteristica ALTER COLUMN id_registro_caracteristica SET DEFAULT nextval('public.registro_caracteristica_id_registro_caracteristica_seq'::regclass);


--
-- Name: registro_detalle id_registro_detalle; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_detalle ALTER COLUMN id_registro_detalle SET DEFAULT nextval('public.registro_detalle_id_registro_detalle_seq'::regclass);


--
-- Name: rol id_rol; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol ALTER COLUMN id_rol SET DEFAULT nextval('public.rol_id_rol_seq'::regclass);


--
-- Name: rol_permiso id_rol_permiso; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol_permiso ALTER COLUMN id_rol_permiso SET DEFAULT nextval('public.rol_permiso_id_rol_permiso_seq'::regclass);


--
-- Name: solicitud_detalle id_solicitud_detalle; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_detalle ALTER COLUMN id_solicitud_detalle SET DEFAULT nextval('public.solicitud_detalle_id_solicitud_detalle_seq'::regclass);


--
-- Name: solicitud_logistica id_solicitud; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_logistica ALTER COLUMN id_solicitud SET DEFAULT nextval('public.solicitud_logistica_id_solicitud_seq'::regclass);


--
-- Name: sucursal id_sucursal; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.sucursal ALTER COLUMN id_sucursal SET DEFAULT nextval('public.sucursal_id_sucursal_seq'::regclass);


--
-- Name: telefono_persona id_telefono; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.telefono_persona ALTER COLUMN id_telefono SET DEFAULT nextval('public.telefono_persona_id_telefono_seq'::regclass);


--
-- Name: tipo_bien id_tipo_bien; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_bien ALTER COLUMN id_tipo_bien SET DEFAULT nextval('public.tipo_bien_id_tipo_bien_seq'::regclass);


--
-- Name: tipo_campo id_tipo_campo; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_campo ALTER COLUMN id_tipo_campo SET DEFAULT nextval('public.tipo_campo_id_tipo_campo_seq'::regclass);


--
-- Name: tipo_mantenimiento id_tipo_mantenimiento; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_mantenimiento ALTER COLUMN id_tipo_mantenimiento SET DEFAULT nextval('public.tipo_mantenimiento_id_tipo_mantenimiento_seq'::regclass);


--
-- Name: tipo_registro id_tipo_registro; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_registro ALTER COLUMN id_tipo_registro SET DEFAULT nextval('public.tipo_registro_id_tipo_registro_seq'::regclass);


--
-- Name: tipo_solicitud id_tipo_solicitud; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_solicitud ALTER COLUMN id_tipo_solicitud SET DEFAULT nextval('public.tipo_solicitud_id_tipo_solicitud_seq'::regclass);


--
-- Name: usuario id_usuario; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuario_id_usuario_seq'::regclass);


--
-- Name: usuario_rol id_usuario_rol; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_rol ALTER COLUMN id_usuario_rol SET DEFAULT nextval('public.usuario_rol_id_usuario_rol_seq'::regclass);


--
-- Name: valor_bien id_valor_bien; Type: DEFAULT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.valor_bien ALTER COLUMN id_valor_bien SET DEFAULT nextval('public.valor_bien_id_valor_bien_seq'::regclass);


--
-- Data for Name: asignacion_bien; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.asignacion_bien (id_asignacion, id_bien, id_empleado, id_registro, tipo_acta, numero_acta, fecha_emision_acta, fecha_entrega_bien, fecha_devolucion_bien, motivo_asignacion, observaciones_asignacion, firma_digital, archivo_pdf, estado_asignacion, fecha_registro) FROM stdin;
1	1	1	11	ENTREGA	ACTA-001	2026-03-02	2026-03-02 22:30:13.014699	\N	Asignación de equipo	Entrega inicial	f	\N	ACTIVA	2026-03-02 22:30:13.014699
2	1	1	12	ENTREGA	TEST-INTEGRAL-01	2026-03-03	2026-03-03 13:02:16.624815	2026-03-03 13:59:45.451702	Prueba integral	Prueba control	f	\N	DEVUELTA	2026-03-03 13:02:16.624815
4	10	9	26	ASIGNACION	\N	\N	2026-04-18 16:37:43.65564	2026-04-18 16:37:53.793224	Asignacion de bien	\n[DEVOLUCIÓN] Devolucion de bien	f	\N	DEVUELTA	2026-04-18 16:37:43.65564
3	7	1	23	ASIGNACION	\N	\N	2026-04-18 05:00:06.224076	2026-04-18 21:31:29.888836	Asignacion de bien	\n[DEVOLUCIÓN] Devolucion de bien	f	\N	DEVUELTA	2026-04-18 05:00:06.224076
5	6	7	29	ASIGNACION	\N	\N	2026-04-18 21:31:48.805864	2026-04-18 22:19:54.02229	Asignacion de bien	\n[DEVOLUCIÓN] Devolucion de bien	f	\N	DEVUELTA	2026-04-18 21:31:48.805864
7	10	11	32	ASIGNACION	\N	\N	2026-04-19 10:27:05.614249	\N	Para de la empresa	Para de la empresa	f	\N	ACTIVA	2026-04-19 10:27:05.614249
6	10	5	30	ASIGNACION	\N	\N	2026-04-18 22:19:40.217709	2026-04-19 10:28:06.329121	Asignacion de bien	\n[DEVOLUCIÓN] Ya le dio el uso 	f	\N	DEVUELTA	2026-04-18 22:19:40.217709
\.


--
-- Data for Name: bien; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.bien (id_bien, id_tipo_bien, id_proveedor, id_valor_bien, codigo_inventario, nombre_bien, descripcion_bien, marca, modelo, unidad_medida, es_consumible, requiere_lote, requiere_serie, estado_bien, fecha_registro, fecha_actualizacion, valor_unitario, requiere_mantenimiento, stock_minimo) FROM stdin;
2	\N	\N	\N	PAPEL-A4-001	Resma de papel A4	Resma de papel bond tamaño carta 500 hojas	\N	\N	RESMA	t	f	f	ACTIVO	2026-03-01 21:22:33.78018	\N	0.000	f	\N
4	\N	\N	\N	BIEN-003	Mouse	\N	\N	\N	\N	f	f	f	ACTIVO	2026-03-24 18:42:21.984902	\N	0.000	f	\N
5	\N	\N	\N	BIEN-004	Teclado	\N	\N	\N	\N	f	f	f	ACTIVO	2026-03-24 18:42:36.485745	\N	0.000	f	\N
6	\N	\N	\N	BIEN-005	Monitor	\N	\N	\N	\N	f	f	f	ACTIVO	2026-03-24 18:42:55.726828	\N	0.000	f	\N
7	\N	\N	\N	BIEN-006	Celular	\N	Samsung	A71	\N	f	f	f	ACTIVO	2026-04-07 18:22:26.020632	\N	5000.000	f	\N
9	\N	\N	\N	ofgnio	 bikjjg	\N	mkvfk	\N	\N	f	f	f	INACTIVO	2026-04-18 03:23:12.219017	\N	5000.000	f	\N
8	\N	\N	\N	bien 	manual	\N	sii	niknijd	\N	f	f	f	INACTIVO	2026-04-18 03:14:22.37024	\N	500.000	f	\N
1	\N	\N	\N	BIEN-001	Laptop Prueba	\N	\N	\N	\N	f	f	f	INACTIVO	2026-03-01 19:48:42.304481	\N	15000.000	f	\N
10	\N	\N	\N	BIEN-007	iphone	\N	apple	pro max	\N	f	f	f	ACTIVO	2026-04-18 05:40:13.262374	\N	10000.000	f	\N
11	\N	\N	\N	PAPEL-001	Papel carta	\N	no se 	\N	\N	f	f	f	ACTIVO	2026-04-18 05:41:32.464107	\N	0.000	f	\N
12	\N	\N	\N	BN-001	Laptop	\N	HP	\N	\N	f	f	f	ACTIVO	2026-04-18 16:46:51.718665	\N	5000.000	t	\N
13	\N	\N	\N	tester	test	\N	874903	bnei8389'	\N	f	f	f	INACTIVO	2026-04-18 20:29:36.442758	\N	0.000	f	\N
14	\N	\N	\N	BN-000	TEST	\N	\N	\N	\N	f	f	f	ACTIVO	2026-04-18 20:49:09.880484	\N	100.000	t	\N
15	\N	\N	\N	test1	test1	\N	test	1234	\N	f	f	f	ACTIVO	2026-04-18 22:01:45.685665	\N	100.000	t	12.000
16	\N	\N	\N	BIEN-009	lata	\N	\N	\N	\N	f	f	f	INACTIVO	2026-04-18 22:14:05.16601	\N	0.000	f	10.000
17	\N	\N	\N	BIEN-011	LAPICES	\N	PEN	\N	\N	f	f	f	ACTIVO	2026-04-18 21:55:56.580636	\N	1222.000	f	10.000
18	\N	\N	\N	BIEN-012	CARRO	\N	HONDA	HONDA CIVIC	\N	f	f	f	ACTIVO	2026-04-19 10:18:31.87662	\N	120000.000	t	1.000
\.


--
-- Data for Name: bien_item; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.bien_item (id_bien_item, id_bien, id_bodega, id_empleado, numero_serie, codigo_item, estado_item, fecha_alta, observaciones) FROM stdin;
\.


--
-- Data for Name: bien_lote; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.bien_lote (id_bien_lote, id_bien, id_proveedor, codigo_lote, fecha_fabricacion, fecha_vencimiento, estado_lote, observaciones_lote, fecha_registro) FROM stdin;
\.


--
-- Data for Name: bodega; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.bodega (id_bodega, id_sucursal, nombre_bodega, codigo_bodega, direccion_bodega, responsable_bodega, telefono_bodega, estado_bodega, fecha_registro, fecha_actualizacion) FROM stdin;
1	\N	Bodega Principal	\N	\N	\N	\N	ACTIVO	2026-03-01 19:26:54.362109	\N
2	\N	Bodega Secundaria	\N	\N	\N	\N	ACTIVO	2026-03-01 19:26:54.362109	\N
\.


--
-- Data for Name: caracteristica_bien; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.caracteristica_bien (id_caracteristica_bien, id_tipo_bien, id_tipo_campo, nombre_caracteristica, es_requerida, orden, estado_caracteristica, fecha_registro) FROM stdin;
\.


--
-- Data for Name: caracteristica_opcion; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.caracteristica_opcion (id_caracteristica_opcion, id_caracteristica_bien, valor_opcion, estado_opcion, fecha_registro) FROM stdin;
\.


--
-- Data for Name: correo_persona; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.correo_persona (id_correo, id_persona, correo_electronico, principal, estado_correo, fecha_registro) FROM stdin;
4	6	correo@test.com	t	ACTIVO	2026-04-10 15:11:47.682531
6	9	juan@prueba.com	t	ACTIVO	2026-04-10 23:47:16.55071
8	11	prueba@gmail.com	t	ACTIVO	2026-04-12 22:58:24.080872
5	8	correo@test.com	t	ACTIVO	2026-04-10 22:07:37.746005
9	12	siiii@gmail.com	t	ACTIVO	2026-04-18 01:50:47.901322
7	10	alex@prueba.com	t	ACTIVO	2026-04-12 11:16:08.027584
10	2	it@gmail.com	t	ACTIVO	2026-04-18 22:24:55.494034
11	13	clairemora45@gmail.com	t	ACTIVO	2026-04-18 23:26:25.046199
\.


--
-- Data for Name: departamento; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.departamento (id_departamento, nombre_departamento, descripcion_departamento, ubicacion_departamento, estado_departamento, fecha_registro) FROM stdin;
1	Logística	Departamento de logística	Edificio central	ACTIVO	2026-02-28 17:07:40.545194
\.


--
-- Data for Name: direccion_persona; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.direccion_persona (id_direccion, id_persona, tipo_direccion, pais, departamento, municipio, colonia_barrio, direccion_detallada, principal, estado_direccion, fecha_registro) FROM stdin;
4	6	PRINCIPAL	Honduras	Francisco Morazán	Tegucigalpa	Centro	Casa 123	t	ACTIVO	2026-04-10 15:11:47.682531
5	8	PRINCIPAL	Honduras	FM	TGU	Centro	Casa 1234	t	ACTIVO	2026-04-10 22:07:37.746005
6	9	PRINCIPAL	Honduras					t	ACTIVO	2026-04-10 23:47:16.55071
7	10	PRINCIPAL	Honduras					t	ACTIVO	2026-04-12 11:16:08.027584
8	11	PRINCIPAL	Honduras					t	ACTIVO	2026-04-12 22:58:24.080872
9	12	PRINCIPAL	Honduras					t	ACTIVO	2026-04-18 01:50:47.901322
10	13	PRINCIPAL	Honduras					t	ACTIVO	2026-04-18 23:26:25.046199
\.


--
-- Data for Name: documento; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.documento (id_documento, nombre_documento, tipo_documento, entidad_emisora, fecha_emision, numero_referencia, ruta_archivo, notas_adicionales, fecha_registro) FROM stdin;
\.


--
-- Data for Name: empleado; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.empleado (id_empleado, id_persona, id_departamento, id_estatus_empleado, id_puesto, id_sucursal, codigo_empleado, fecha_ingreso, estado_empleado, fecha_registro) FROM stdin;
1	1	1	1	1	1	EMP001	\N	ACTIVO	2026-02-28 17:09:09.066011
5	2	1	1	1	1	EMP002	\N	ACTIVO	2026-03-01 07:46:15.571028
6	9	1	1	1	1	EMP003	2026-04-11	ACTIVO	2026-04-11 21:27:54.302588
7	8	1	1	1	1	EMO004	2026-04-12	ACTIVO	2026-04-12 00:01:46.444606
8	10	1	1	1	1	EMP005	2026-04-12	ACTIVO	2026-04-12 11:16:46.005247
9	11	1	1	1	1	EMP006	2026-04-12	ACTIVO	2026-04-12 22:59:51.260043
10	12	1	1	1	1	EMP007	2026-04-17	ACTIVO	2026-04-18 02:10:34.06971
11	13	1	1	1	1	EMP008	2026-01-12	ACTIVO	2026-04-18 23:28:21.557922
\.


--
-- Data for Name: empresa; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.empresa (id_empresa, nombre_empresa, rtn_empresa, direccion_fiscal, correo_empresa, telefono_empresa, estado_empresa, fecha_registro, fecha_actualizacion) FROM stdin;
1	DIDADPOL	00000000000000	Tegucigalpa	admin@didadpol.gob	00000000	ACTIVO	2026-02-28 17:02:52.702252	\N
\.


--
-- Data for Name: estado_solicitud; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.estado_solicitud (id_estado_solicitud, nombre_estado, descripcion_estado, estado_registro, fecha_registro) FROM stdin;
1	CREADA	\N	ACTIVO	2026-03-02 11:23:29.018052
2	APROBADA	\N	ACTIVO	2026-03-02 11:23:29.018052
3	RECHAZADA	\N	ACTIVO	2026-03-02 11:23:29.018052
4	CANCELADA	\N	ACTIVO	2026-03-02 11:23:29.018052
\.


--
-- Data for Name: estatus_empleado; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.estatus_empleado (id_estatus_empleado, nombre_estatus, descripcion_estatus, estado_estatus, fecha_registro) FROM stdin;
1	ACTIVO	Empleado activo	ACTIVO	2026-02-28 17:08:12.541696
\.


--
-- Data for Name: historial_reservas; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.historial_reservas (id_historial, id_bodega, id_bien, cantidad, accion, fecha, usuario, solicitante, motivo) FROM stdin;
1	2	1	1	RESERVAR	2026-03-31 18:11:50.088137	sistema	\N	\N
2	2	1	1	RESERVAR	2026-03-31 18:16:17.279751	sistema	\N	\N
3	1	1	2	RESERVAR	2026-03-31 21:37:41.9549	sistema	\N	\N
4	2	1	3	LIBERAR	2026-03-31 21:49:27.766044	sistema	\N	\N
5	1	4	1	RESERVAR	2026-04-07 00:15:48.591323	sistema	\N	\N
6	1	4	1	RESERVAR	2026-04-07 01:45:51.14766	sistema	\N	\N
7	1	2	9	LIBERAR	2026-04-18 03:15:59.187929	admin	\N	\N
8	1	1	15	CONSUMIR	2026-04-18 03:25:23.224098	sistema	\N	\N
9	1	6	2	LIBERAR	2026-04-18 03:33:24.835035	admin	\N	\N
10	1	7	9	LIBERAR	2026-04-18 04:18:41.367542	admin	\N	\N
11	1	7	1	RESERVAR	2026-04-18 04:19:23.39477	sistema	\N	\N
12	1	4	2	LIBERAR	2026-04-18 04:19:39.598271	sistema	\N	\N
13	1	11	10	LIBERAR	2026-04-18 05:42:15.106579	admin	\N	\N
14	1	11	10000	LIBERAR	2026-04-18 05:43:01.428293	admin	\N	\N
15	1	11	10000	LIBERAR	2026-04-18 05:44:22.724651	admin	\N	\N
16	1	11	10001	LIBERAR	2026-04-18 05:46:15.778146	admin	\N	\N
17	1	11	19999	LIBERAR	2026-04-18 05:46:55.468587	admin	\N	\N
18	1	11	20000	LIBERAR	2026-04-18 05:50:52.247834	admin	\N	\N
19	1	11	10000	LIBERAR	2026-04-18 05:51:11.647084	admin	\N	\N
20	1	11	20	LIBERAR	2026-04-18 05:55:06.953413	admin	\N	\N
21	1	11	1000	CONSUMIR	2026-04-18 05:56:01.706418	admin	\N	\N
22	1	11	50000	CONSUMIR	2026-04-18 05:56:34.774447	admin	\N	\N
23	1	11	20	AJUSTE	2026-04-18 05:59:26.091479	admin	\N	\N
24	2	10	15	AJUSTE	2026-04-18 06:06:58.115996	admin	\N	\N
25	1	10	10	AJUSTE	2026-04-18 16:14:32.43731	admin	\N	\N
26	1	11	15	AJUSTE	2026-04-18 16:23:48.586104	admin	\N	\N
27	2	12	5	LIBERAR	2026-04-18 16:47:29.303864	admin	\N	\N
28	1	10	3	CONSUMIR	2026-04-18 16:52:24.790017	admin	\N	\N
29	1	10	25	AJUSTE	2026-04-18 17:04:25.015055	admin	\N	\N
30	1	11	1	CONSUMIR	2026-04-18 20:20:22.685813	admin	\N	\N
31	1	4	0	AJUSTE	2026-04-18 20:35:13.297632	admin	\N	\N
32	2	10	1	RESERVAR	2026-04-18 20:50:00.534245	sistema	\N	\N
33	1	6	1	RESERVAR	2026-04-18 20:51:34.096664	sistema	\N	\N
34	1	7	1	RESERVAR	2026-04-18 20:57:16.142297	sistema	juan	presta
35	1	6	1	LIBERAR	2026-04-18 20:59:03.73976	sistema	\N	\N
36	1	6	2	RESERVAR	2026-04-18 20:59:23.336838	sistema	ana	para oficina
37	1	6	2	LIBERAR	2026-04-18 20:59:41.246561	sistema	\N	\N
38	2	10	1	CONSUMIR	2026-04-18 20:59:58.646254	sistema	\N	\N
39	2	11	10	AJUSTE	2026-04-18 21:34:04.408411	admin	\N	\N
40	1	10	10	AJUSTE	2026-04-18 21:47:54.633783	admin	\N	\N
41	2	15	10	LIBERAR	2026-04-18 22:02:10.182797	admin	\N	\N
42	1	16	10	LIBERAR	2026-04-18 22:15:17.075624	admin	\N	\N
43	1	16	9	AJUSTE	2026-04-18 22:15:29.357894	admin	\N	\N
44	1	6	2	RESERVAR	2026-04-18 22:16:47.864817	sistema	juan	salida
45	1	7	2	LIBERAR	2026-04-18 22:16:57.968775	sistema	\N	\N
46	2	12	1	RESERVAR	2026-04-19 00:54:44.162037	sistema	ciena	presta
47	2	17	1	LIBERAR	2026-04-18 22:00:11.726275	admin	\N	\N
48	1	17	122	AJUSTE	2026-04-18 22:01:36.652601	admin	\N	\N
49	1	17	3	RESERVAR	2026-04-18 22:03:51.352209	sistema	Departamento de bienes	Necesita lapices
50	1	18	1	AJUSTE	2026-04-19 10:19:00.633773	admin	\N	\N
51	2	18	1	LIBERAR	2026-04-19 10:22:53.383392	admin	\N	\N
52	2	18	1	RESERVAR	2026-04-19 10:24:26.934627	sistema	licenciado caleb 	Visita al sucursal de San Pedro Sula
\.


--
-- Data for Name: inventario; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.inventario (id_inventario, id_bodega, id_bien, stock_actual, stock_reservado, stock_minimo, estado_inventario, fecha_ultima_actualizacion) FROM stdin;
3	2	1	5.000	0.000	60.000	ACTIVO	2026-03-31 21:49:27.766044
36	2	4	5.000	0.000	\N	ACTIVO	2026-04-07 09:45:48.771119
38	1	2	9.000	0.000	\N	ACTIVO	2026-04-18 03:15:59.187929
1	1	1	12.000	0.000	60.000	ACTIVO	2026-04-18 03:25:23.224098
44	1	11	14.000	0.000	\N	ACTIVO	2026-04-18 05:42:15.106579
27	1	4	0.000	0.000	\N	ACTIVO	2026-04-18 04:19:39.598271
54	2	7	1.000	0.000	\N	ACTIVO	2026-04-18 21:31:29.888836
56	2	11	10.000	0.000	\N	ACTIVO	2026-04-18 21:34:04.408411
57	2	15	10.000	0.000	12.000	ACTIVO	2026-04-18 22:02:10.182797
58	1	16	9.000	0.000	10.000	ACTIVO	2026-04-18 22:15:17.075624
37	1	7	11.000	0.000	\N	ACTIVO	2026-04-18 22:16:57.968775
45	2	10	15.000	0.000	\N	ACTIVO	2026-04-18 22:19:40.217709
41	1	6	4.000	2.000	\N	ACTIVO	2026-04-18 22:19:54.02229
49	2	12	5.000	1.000	\N	ACTIVO	2026-04-19 00:54:44.162037
63	2	17	1.000	0.000	10.000	ACTIVO	2026-04-18 22:00:11.726275
64	1	17	122.000	3.000	10.000	ACTIVO	2026-04-18 22:03:51.352209
66	1	18	1.000	0.000	1.000	ACTIVO	2026-04-19 10:19:00.633773
67	2	18	1.000	1.000	1.000	ACTIVO	2026-04-19 10:24:26.934627
46	1	10	12.000	0.000	\N	ACTIVO	2026-04-19 10:28:06.329121
\.


--
-- Data for Name: inventario_lote; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.inventario_lote (id_inventario_lote, id_bodega, id_bien_lote, stock_actual, stock_reservado, estado_inventario_lote, fecha_ultima_actualizacion) FROM stdin;
\.


--
-- Data for Name: kardex; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.kardex (id_kardex, fecha, tipo, id_bien, entrada, salida, saldo, usuario, id_bodega) FROM stdin;
1	2026-04-06 23:09:03.792305	ALTA	4	5	0	0	admin	\N
2	2026-04-07 00:11:17.658756	ALTA	4	5	0	0	admin	\N
3	2026-04-07 00:57:34.595734	ALTA	4	3	0	8	admin	\N
4	2026-04-07 01:14:18.627944	BAJA	4	0	1	7	admin	\N
5	2026-04-07 01:15:17.508369	BAJA	4	0	1	6	admin	\N
6	2026-04-07 01:22:27.834595	ALTA	4	5	0	11	admin	\N
7	2026-04-07 09:45:48.771119	ALTA	4	5	0	5	admin	2
8	2026-04-18 03:03:11.340335	ALTA	7	1	0	1	admin	1
\.


--
-- Data for Name: log_cambios; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.log_cambios (id_log_cambios, id_log_usuario, campo_modificado, valor_antes, valor_despues) FROM stdin;
\.


--
-- Data for Name: log_usuario; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.log_usuario (id_log_usuario, id_usuario, fecha_accion, hora_accion, tipo_accion, tabla_afectada, registro_afectado, ip_origen, descripcion_log) FROM stdin;
1	3	2026-02-28 17:56:35.918552	17:56:35.918552	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
2	3	2026-02-28 17:56:55.984968	17:56:55.984968	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
3	3	2026-02-28 17:58:13.241776	17:58:13.241776	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
4	3	2026-02-28 21:21:03.340859	21:21:03.340859	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
5	\N	2026-02-28 22:07:00.947947	22:07:00.947947	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/usuarios
6	\N	2026-02-28 22:12:32.853897	22:12:32.853897	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/usuarios
7	3	2026-02-28 22:15:37.583319	22:15:37.583319	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
8	3	2026-02-28 22:20:03.144765	22:20:03.144765	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
9	3	2026-02-28 22:24:58.064632	22:24:58.064632	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
10	3	2026-02-28 22:25:04.175238	22:25:04.175238	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
11	3	2026-02-28 22:25:56.516376	22:25:56.516376	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
12	3	2026-02-28 22:26:13.202693	22:26:13.202693	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
13	3	2026-02-28 22:26:17.573442	22:26:17.573442	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
14	3	2026-02-28 22:27:03.012957	22:27:03.012957	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
15	3	2026-02-28 22:32:06.750491	22:32:06.750491	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
16	3	2026-02-28 22:34:42.898345	22:34:42.898345	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
17	3	2026-02-28 22:38:48.880994	22:38:48.880994	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
18	3	2026-02-28 22:42:01.354433	22:42:01.354433	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
19	3	2026-02-28 22:47:24.948804	22:47:24.948804	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
20	3	2026-02-28 22:53:10.988321	22:53:10.988321	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
21	3	2026-02-28 22:54:22.766392	22:54:22.766392	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
22	3	2026-02-28 22:57:51.41676	22:57:51.41676	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
23	3	2026-02-28 23:15:42.385424	23:15:42.385424	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
24	\N	2026-03-01 07:47:36.977864	07:47:36.977864	CREAR_USUARIO	usuario	6	::1	Usuario creado: Carlos prueba1
25	\N	2026-03-01 07:47:36.977864	07:47:36.977864	ASIGNAR_ROL_USUARIO	usuario_rol	3	::1	Asignar rol id_rol=4 a usuario id_usuario=6
26	6	2026-03-01 08:22:26.813852	08:22:26.813852	LOGIN_SUCCESS	usuario	6	::1	Inicio de sesión exitoso
27	6	2026-03-01 08:23:32.487647	08:23:32.487647	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios sin roles requeridos (ADMIN, SUPERADMIN)
28	6	2026-03-01 08:24:45.122972	08:24:45.122972	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios/6/bloquear sin roles requeridos (ADMIN, SUPERADMIN)
29	6	2026-03-01 08:26:54.092566	08:26:54.092566	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios/6/bloquear sin roles requeridos (ADMIN, SUPERADMIN)
30	6	2026-03-01 08:28:02.044788	08:28:02.044788	ACCESS_DENIED_ROLE	\N	\N	::1	Intento de acceso a /api/usuarios/6/bloquear sin roles requeridos (ADMIN, SUPERADMIN)
31	3	2026-03-01 08:28:40.781734	08:28:40.781734	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
32	3	2026-03-01 08:29:01.913248	08:29:01.913248	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
33	6	2026-03-01 15:25:58.676095	15:25:58.676095	LOGIN_SUCCESS	usuario	6	::1	Inicio de sesión exitoso
34	6	2026-03-01 15:26:25.969405	15:26:25.969405	LOGIN_FAILED	usuario	6	::1	Contraseña incorrecta
35	6	2026-03-01 15:26:41.329258	15:26:41.329258	LOGIN_FAILED	usuario	6	::1	Contraseña incorrecta
36	6	2026-03-01 15:26:46.50635	15:26:46.50635	AUTO_LOCK_USER	usuario	6	::1	Usuario bloqueado automáticamente por intentos fallidos
37	6	2026-03-01 15:46:30.956191	15:46:30.956191	LOGIN_SUCCESS	usuario	6	::1	Inicio de sesión exitoso
38	6	2026-03-01 15:46:42.135384	15:46:42.135384	LOGIN_FAILED	usuario	6	::1	Contraseña incorrecta
39	6	2026-03-01 15:46:44.117233	15:46:44.117233	LOGIN_FAILED	usuario	6	::1	Contraseña incorrecta
40	6	2026-03-01 15:46:45.572069	15:46:45.572069	AUTO_LOCK_USER	usuario	6	::1	Usuario bloqueado automáticamente por intentos fallidos
41	6	2026-03-01 15:48:17.994562	15:48:17.994562	LOGIN_SUCCESS	usuario	6	::1	Inicio de sesión exitoso
42	\N	2026-03-01 17:43:50.929858	17:43:50.929858	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/registros
43	3	2026-03-01 17:57:49.83861	17:57:49.83861	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
44	3	2026-03-01 17:59:29.990852	17:59:29.990852	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
45	3	2026-03-01 18:04:29.383487	18:04:29.383487	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s) requerido(s): REGISTRO_CREAR
46	3	2026-03-01 18:07:54.7368	18:07:54.7368	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s) requerido(s): REGISTRO_CREAR
47	3	2026-03-01 18:08:03.287523	18:08:03.287523	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
48	3	2026-03-01 18:35:01.627259	18:35:01.627259	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
49	\N	2026-03-01 18:40:32.662864	18:40:32.662864	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/registros
50	3	2026-03-01 18:41:22.839819	18:41:22.839819	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
51	3	2026-03-01 20:12:24.955983	20:12:24.955983	CONFIRMAR_REGISTRO	registro	3	::1	Confirmación de registro y afectación de inventario
52	3	2026-03-01 20:28:37.752426	20:28:37.752426	ANULAR_REGISTRO	registro	3	::1	Anulación y reverso de inventario. Motivo: Prueba anulación
53	3	2026-03-01 20:58:45.814969	20:58:45.814969	CONFIRMAR_REGISTRO	registro	4	::1	Confirmación de registro y afectación de inventario
54	3	2026-03-01 21:31:40.507362	21:31:40.507362	CONFIRMAR_REGISTRO	registro	5	::1	Confirmación de registro y afectación de inventario
55	3	2026-03-01 21:55:46.941367	21:55:46.941367	CONFIRMAR_REGISTRO	registro	6	::1	Confirmación de registro y afectación de inventario
56	3	2026-03-01 23:45:43.636056	23:45:43.636056	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s) requerido(s): KARDEX_VER
57	3	2026-03-01 23:54:07.979213	23:54:07.979213	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
58	3	2026-03-02 09:11:24.975864	09:11:24.975864	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
59	3	2026-03-02 10:12:41.557702	10:12:41.557702	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
60	3	2026-03-02 10:38:44.974542	10:38:44.974542	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
61	3	2026-03-02 11:50:41.607835	11:50:41.607835	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
62	3	2026-03-02 11:55:55.433843	11:55:55.433843	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	1	::1	Cambio de estado: CREADA -> APROBADA | bodega_reserva=1
63	3	2026-03-02 11:56:53.193485	11:56:53.193485	GENERAR_REGISTRO_DESDE_SOLICITUD	registro	7	::1	Se generó un registro REGISTRADO desde solicitud=1 | bodega_origen=1
64	3	2026-03-02 12:06:24.139427	12:06:24.139427	GENERAR_REGISTRO_DESDE_SOLICITUD	registro	8	::1	Se generó un registro REGISTRADO desde solicitud=1 | bodega_origen=1
65	3	2026-03-02 12:19:25.367902	12:19:25.367902	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	3	::1	Cambio de estado: CREADA -> APROBADA | bodega_reserva=1
66	3	2026-03-02 12:20:20.73851	12:20:20.73851	GENERAR_REGISTRO_DESDE_SOLICITUD	registro	9	::1	Se generó un registro REGISTRADO desde solicitud=3 | bodega_origen=1
67	3	2026-03-02 12:30:53.717268	12:30:53.717268	CONFIRMAR_REGISTRO	registro	7	::1	Confirmación de registro y afectación de inventario
68	3	2026-03-02 14:27:01.903284	14:27:01.903284	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
69	3	2026-03-02 21:37:45.018092	21:37:45.018092	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s) requerido(s): ASIGNAR_BIEN
70	3	2026-03-02 21:44:46.219331	21:44:46.219331	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
71	3	2026-03-02 22:30:13.014699	22:30:13.014699	CONFIRMAR_REGISTRO	registro	11	::1	Confirmación de registro y afectación de inventario
72	3	2026-03-02 22:30:13.014699	22:30:13.014699	CREAR_ASIGNACION	asignacion_bien	1	::1	Asignación creada. acta=ACTA-001 | id_registro=11
73	\N	2026-03-03 13:00:15.688338	13:00:15.688338	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/asignaciones
74	3	2026-03-03 13:01:17.082962	13:01:17.082962	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
75	3	2026-03-03 13:02:16.624815	13:02:16.624815	CONFIRMAR_REGISTRO	registro	12	::1	Confirmación de registro y afectación de inventario
76	3	2026-03-03 13:02:16.624815	13:02:16.624815	CREAR_ASIGNACION	asignacion_bien	2	::1	Asignación creada. acta=TEST-INTEGRAL-01 | id_registro=12
77	3	2026-03-03 13:26:13.891525	13:26:13.891525	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s) requerido(s): DEVOLVER_BIEN
78	3	2026-03-03 13:44:36.419209	13:44:36.419209	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
79	3	2026-03-03 13:59:45.451702	13:59:45.451702	CONFIRMAR_REGISTRO	registro	17	::1	Confirmación de registro y afectación de inventario
80	3	2026-03-03 13:59:45.451702	13:59:45.451702	DEVOLVER_ASIGNACION	asignacion_bien	2	::1	Devolución registrada. id_registro=17
81	3	2026-03-23 14:13:12.458701	14:13:12.458701	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
82	3	2026-03-23 15:20:33.195861	15:20:33.195861	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
83	3	2026-03-23 15:24:22.450757	15:24:22.450757	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
84	3	2026-03-23 15:24:36.556323	15:24:36.556323	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
85	\N	2026-03-23 15:25:07.563871	15:25:07.563871	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/reportes/ejecutivo
86	3	2026-03-23 15:25:37.141332	15:25:37.141332	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
87	\N	2026-03-23 15:26:29.699991	15:26:29.699991	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/reportes/ejecutivo
88	3	2026-03-23 15:33:22.63216	15:33:22.63216	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
89	3	2026-03-23 17:07:50.439093	17:07:50.439093	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s) requerido(s): SOLICITUD_VER
90	3	2026-03-23 17:22:15.466601	17:22:15.466601	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
91	3	2026-03-23 18:17:07.280019	18:17:07.280019	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
92	3	2026-03-24 08:36:33.872604	08:36:33.872604	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
93	3	2026-03-24 13:27:41.458717	13:27:41.458717	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
94	3	2026-03-24 14:54:49.641374	14:54:49.641374	LOGIN_SUCCESS	usuario	3	::1	Inicio de sesión exitoso
95	3	2026-03-24 16:01:13.818323	16:01:13.818323	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
96	3	2026-03-24 16:07:43.84771	16:07:43.84771	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
97	3	2026-03-24 16:09:44.153557	16:09:44.153557	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
98	3	2026-03-24 16:13:17.410273	16:13:17.410273	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
99	3	2026-03-24 16:21:41.280327	16:21:41.280327	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
100	3	2026-03-24 16:21:59.633857	16:21:59.633857	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
101	3	2026-03-24 16:22:50.668818	16:22:50.668818	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
102	3	2026-03-24 16:23:10.311897	16:23:10.311897	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
103	\N	2026-03-24 16:23:34.430749	16:23:34.430749	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario
104	3	2026-03-24 16:25:47.373603	16:25:47.373603	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
105	3	2026-03-24 16:26:05.123324	16:26:05.123324	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
106	3	2026-03-24 16:52:13.819955	16:52:13.819955	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
107	3	2026-03-24 16:52:33.114058	16:52:33.114058	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
108	\N	2026-03-24 16:52:44.724318	16:52:44.724318	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario
109	3	2026-03-24 17:05:33.04481	17:05:33.04481	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
110	3	2026-03-24 17:05:45.403893	17:05:45.403893	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
111	3	2026-03-24 17:05:56.07841	17:05:56.07841	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
112	3	2026-03-24 17:18:10.942378	17:18:10.942378	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
113	3	2026-03-24 17:18:25.19652	17:18:25.19652	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
114	3	2026-03-24 17:34:47.661764	17:34:47.661764	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
115	3	2026-03-24 17:35:00.415784	17:35:00.415784	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
116	3	2026-03-24 17:36:53.48652	17:36:53.48652	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
117	3	2026-03-24 17:37:03.904317	17:37:03.904317	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
118	3	2026-03-24 17:54:01.153839	17:54:01.153839	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
119	3	2026-03-24 17:54:11.855058	17:54:11.855058	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
120	3	2026-03-24 17:54:21.563302	17:54:21.563302	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
121	3	2026-03-24 18:16:10.420064	18:16:10.420064	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
122	3	2026-03-24 18:16:35.804807	18:16:35.804807	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
123	3	2026-03-24 19:53:30.556685	19:53:30.556685	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
124	3	2026-03-24 19:53:55.030501	19:53:55.030501	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
125	\N	2026-03-24 20:20:40.649021	20:20:40.649021	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
126	3	2026-03-24 20:21:37.833473	20:21:37.833473	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
127	3	2026-03-24 20:21:49.551925	20:21:49.551925	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
128	3	2026-03-24 20:22:04.003569	20:22:04.003569	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
129	\N	2026-03-24 20:22:34.130702	20:22:34.130702	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
130	\N	2026-03-24 20:37:37.034443	20:37:37.034443	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
131	3	2026-03-24 20:38:03.774221	20:38:03.774221	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
132	3	2026-03-24 20:38:35.039175	20:38:35.039175	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
133	\N	2026-03-24 20:39:18.5352	20:39:18.5352	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
134	3	2026-03-24 20:51:51.631949	20:51:51.631949	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
135	3	2026-03-24 20:52:02.077271	20:52:02.077271	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
136	\N	2026-03-24 20:52:19.541937	20:52:19.541937	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
137	3	2026-03-24 21:00:55.53746	21:00:55.53746	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
138	3	2026-03-24 21:01:10.146972	21:01:10.146972	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
139	\N	2026-03-24 21:01:33.057895	21:01:33.057895	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
140	3	2026-03-24 21:04:12.984957	21:04:12.984957	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
141	3	2026-03-24 21:04:17.062909	21:04:17.062909	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
142	3	2026-03-24 21:04:38.439651	21:04:38.439651	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
143	\N	2026-03-24 21:04:55.389913	21:04:55.389913	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
144	3	2026-03-24 21:14:32.847391	21:14:32.847391	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
145	3	2026-03-24 21:14:35.342762	21:14:35.342762	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
146	3	2026-03-24 21:15:06.602729	21:15:06.602729	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
147	\N	2026-03-24 21:17:38.900752	21:17:38.900752	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
148	3	2026-03-24 21:32:09.503245	21:32:09.503245	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
149	3	2026-03-24 21:32:29.39711	21:32:29.39711	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
150	\N	2026-03-24 21:32:45.615897	21:32:45.615897	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
151	3	2026-03-24 21:33:39.534268	21:33:39.534268	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
152	3	2026-03-24 21:33:45.412218	21:33:45.412218	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
153	3	2026-03-24 21:33:55.04532	21:33:55.04532	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
154	\N	2026-03-24 21:34:09.00908	21:34:09.00908	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
155	3	2026-03-24 21:42:42.384491	21:42:42.384491	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
156	3	2026-03-24 21:43:27.353821	21:43:27.353821	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
157	\N	2026-03-24 21:44:00.736622	21:44:00.736622	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
158	3	2026-03-24 21:45:50.581	21:45:50.581	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
159	3	2026-03-24 21:46:10.181196	21:46:10.181196	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
160	\N	2026-03-24 21:46:30.377874	21:46:30.377874	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario/reservar
161	\N	2026-03-24 21:58:01.954179	21:58:01.954179	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario/reservar
162	3	2026-03-24 21:58:48.941856	21:58:48.941856	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
163	3	2026-03-24 21:59:07.809293	21:59:07.809293	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
164	\N	2026-03-24 21:59:24.291775	21:59:24.291775	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario/reservar
165	3	2026-03-24 22:07:51.612857	22:07:51.612857	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
166	3	2026-03-24 22:08:03.347421	22:08:03.347421	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
167	\N	2026-03-24 22:08:20.918953	22:08:20.918953	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario/reservar
168	3	2026-03-25 06:05:42.447831	06:05:42.447831	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
169	3	2026-03-25 06:06:01.403243	06:06:01.403243	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
170	\N	2026-03-25 06:06:24.741663	06:06:24.741663	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario/reservar
171	3	2026-03-25 06:31:14.945669	06:31:14.945669	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
172	3	2026-03-25 06:31:38.283624	06:31:38.283624	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
173	\N	2026-03-25 06:32:29.399839	06:32:29.399839	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario/reservar
174	3	2026-03-25 06:40:06.789564	06:40:06.789564	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
175	3	2026-03-25 06:40:26.3452	06:40:26.3452	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
176	\N	2026-03-25 06:40:46.506068	06:40:46.506068	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario/reservar
177	3	2026-03-25 11:44:23.468803	11:44:23.468803	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
178	3	2026-03-25 11:44:26.773818	11:44:26.773818	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
179	3	2026-03-25 11:44:50.979227	11:44:50.979227	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
180	3	2026-03-26 09:38:28.304854	09:38:28.304854	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
181	3	2026-03-26 09:38:45.009696	09:38:45.009696	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
182	3	2026-03-26 09:38:47.483822	09:38:47.483822	AUTO_LOCK_USER	usuario	3	::1	Usuario bloqueado automáticamente por intentos fallidos
183	\N	2026-03-26 09:40:41.519563	09:40:41.519563	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
184	\N	2026-03-26 09:40:43.557357	09:40:43.557357	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
185	\N	2026-03-26 09:40:44.269076	09:40:44.269076	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
186	\N	2026-03-26 09:40:44.97692	09:40:44.97692	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
187	\N	2026-03-26 09:40:45.151506	09:40:45.151506	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
188	\N	2026-03-26 09:40:45.311862	09:40:45.311862	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
189	\N	2026-03-26 09:40:45.475895	09:40:45.475895	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
190	\N	2026-03-26 09:40:45.620559	09:40:45.620559	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
191	\N	2026-03-26 09:40:45.757693	09:40:45.757693	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
192	\N	2026-03-26 09:40:50.65556	09:40:50.65556	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
193	\N	2026-03-26 09:40:51.18933	09:40:51.18933	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
194	\N	2026-03-26 09:40:51.346761	09:40:51.346761	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
195	\N	2026-03-26 09:40:51.504252	09:40:51.504252	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
196	\N	2026-03-26 09:41:14.85258	09:41:14.85258	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
197	\N	2026-03-26 09:41:17.431577	09:41:17.431577	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
198	\N	2026-03-26 09:41:17.62877	09:41:17.62877	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
199	\N	2026-03-26 09:41:17.804928	09:41:17.804928	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
200	3	2026-03-26 13:37:37.971968	13:37:37.971968	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
201	3	2026-03-26 13:37:53.541395	13:37:53.541395	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
202	3	2026-03-26 16:03:36.601743	16:03:36.601743	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
203	3	2026-03-26 16:03:47.531348	16:03:47.531348	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
204	3	2026-03-26 16:08:05.148245	16:08:05.148245	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
205	3	2026-03-26 16:08:30.110846	16:08:30.110846	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
206	3	2026-03-26 16:11:00.534519	16:11:00.534519	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
207	3	2026-03-26 16:11:02.795984	16:11:02.795984	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
208	3	2026-03-26 16:11:05.026076	16:11:05.026076	AUTO_LOCK_USER	usuario	3	::1	Usuario bloqueado automáticamente por intentos fallidos
209	3	2026-03-26 16:11:38.247513	16:11:38.247513	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
210	3	2026-03-26 16:11:41.635167	16:11:41.635167	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
211	3	2026-03-26 16:11:55.386165	16:11:55.386165	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
212	3	2026-03-31 15:11:40.616164	15:11:40.616164	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
213	3	2026-03-31 15:11:56.469392	15:11:56.469392	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
214	3	2026-03-31 15:35:18.074921	15:35:18.074921	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
215	3	2026-03-31 15:35:31.955907	15:35:31.955907	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
216	3	2026-03-31 15:53:13.663365	15:53:13.663365	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
217	3	2026-03-31 15:53:25.002106	15:53:25.002106	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
218	3	2026-03-31 15:53:27.516173	15:53:27.516173	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): RESERVA_VER
219	3	2026-03-31 16:00:34.226446	16:00:34.226446	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
220	3	2026-03-31 16:00:47.94586	16:00:47.94586	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
221	3	2026-03-31 16:28:06.143392	16:28:06.143392	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
222	3	2026-03-31 16:28:20.179504	16:28:20.179504	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
223	\N	2026-03-31 16:35:45.812636	16:35:45.812636	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/inventario
224	3	2026-03-31 16:47:11.316113	16:47:11.316113	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
225	3	2026-03-31 16:47:29.110272	16:47:29.110272	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
226	3	2026-03-31 17:01:45.243659	17:01:45.243659	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
227	3	2026-03-31 17:01:57.068605	17:01:57.068605	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
228	3	2026-03-31 17:18:03.855202	17:18:03.855202	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
229	3	2026-03-31 17:18:19.656665	17:18:19.656665	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
230	3	2026-03-31 17:18:45.826439	17:18:45.826439	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
231	3	2026-03-31 17:59:34.967767	17:59:34.967767	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
232	3	2026-03-31 17:59:48.124431	17:59:48.124431	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
233	3	2026-03-31 18:15:45.254696	18:15:45.254696	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
234	3	2026-03-31 18:15:58.572173	18:15:58.572173	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
235	3	2026-03-31 18:31:41.835606	18:31:41.835606	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
236	\N	2026-03-31 18:32:38.573268	18:32:38.573268	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/reservas/historial
237	3	2026-03-31 18:33:50.838481	18:33:50.838481	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
238	3	2026-03-31 18:39:36.729268	18:39:36.729268	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
239	3	2026-03-31 18:42:38.718018	18:42:38.718018	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
240	3	2026-03-31 18:53:55.096815	18:53:55.096815	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
241	3	2026-03-31 18:55:47.100919	18:55:47.100919	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
242	3	2026-03-31 19:23:38.417237	19:23:38.417237	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
243	3	2026-03-31 19:23:54.149705	19:23:54.149705	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
244	3	2026-03-31 19:35:08.103127	19:35:08.103127	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
245	3	2026-03-31 19:35:20.325363	19:35:20.325363	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
246	3	2026-03-31 20:01:16.598349	20:01:16.598349	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
247	3	2026-03-31 20:01:29.68907	20:01:29.68907	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
248	3	2026-03-31 20:16:22.088019	20:16:22.088019	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
249	3	2026-03-31 20:16:42.584325	20:16:42.584325	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
250	3	2026-03-31 20:42:10.587428	20:42:10.587428	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
251	3	2026-03-31 20:42:29.041589	20:42:29.041589	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
252	3	2026-03-31 21:01:26.461695	21:01:26.461695	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
253	3	2026-03-31 21:01:40.354967	21:01:40.354967	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
254	3	2026-03-31 21:28:13.831117	21:28:13.831117	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
255	3	2026-03-31 21:28:32.459395	21:28:32.459395	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
256	3	2026-04-06 12:38:30.226674	12:38:30.226674	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
257	3	2026-04-06 12:38:48.044923	12:38:48.044923	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
258	3	2026-04-06 12:39:06.912706	12:39:06.912706	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
259	3	2026-04-06 12:53:46.233354	12:53:46.233354	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
260	3	2026-04-06 12:53:56.576585	12:53:56.576585	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
261	3	2026-04-06 12:54:09.903193	12:54:09.903193	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
262	3	2026-04-06 13:18:28.018075	13:18:28.018075	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
263	3	2026-04-06 13:18:49.693725	13:18:49.693725	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
264	3	2026-04-06 13:22:32.839641	13:22:32.839641	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
265	3	2026-04-06 13:22:48.533557	13:22:48.533557	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
266	3	2026-04-06 13:47:49.919379	13:47:49.919379	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
267	3	2026-04-06 13:48:04.512821	13:48:04.512821	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
268	3	2026-04-06 18:00:49.677434	18:00:49.677434	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
269	3	2026-04-06 18:00:57.489799	18:00:57.489799	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
270	3	2026-04-06 19:35:58.914585	19:35:58.914585	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
271	3	2026-04-06 19:36:09.804659	19:36:09.804659	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
272	3	2026-04-06 20:46:36.047809	20:46:36.047809	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
273	3	2026-04-06 20:46:46.130268	20:46:46.130268	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
274	3	2026-04-06 21:15:20.123534	21:15:20.123534	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
275	3	2026-04-06 21:15:31.992888	21:15:31.992888	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
276	3	2026-04-06 21:54:21.278191	21:54:21.278191	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
277	3	2026-04-06 21:54:34.943461	21:54:34.943461	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
278	3	2026-04-06 22:29:28.896815	22:29:28.896815	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
279	3	2026-04-06 22:29:36.804658	22:29:36.804658	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
280	3	2026-04-06 23:43:04.513101	23:43:04.513101	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
281	3	2026-04-06 23:43:14.054711	23:43:14.054711	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
282	3	2026-04-07 00:05:52.585366	00:05:52.585366	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
283	3	2026-04-07 00:06:01.658687	00:06:01.658687	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
284	3	2026-04-07 00:50:24.620066	00:50:24.620066	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
285	3	2026-04-07 00:50:30.854061	00:50:30.854061	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
286	3	2026-04-07 01:05:14.885806	01:05:14.885806	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
287	3	2026-04-07 01:05:26.743891	01:05:26.743891	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
288	3	2026-04-07 01:13:39.403887	01:13:39.403887	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
289	3	2026-04-07 01:13:48.063951	01:13:48.063951	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
290	3	2026-04-07 02:13:53.767384	02:13:53.767384	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
291	3	2026-04-07 02:14:01.82864	02:14:01.82864	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
292	\N	2026-04-07 02:21:36.402267	02:21:36.402267	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: supradmin
293	3	2026-04-07 02:21:46.329223	02:21:46.329223	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
294	3	2026-04-07 02:21:52.099484	02:21:52.099484	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
295	3	2026-04-07 02:22:09.244452	02:22:09.244452	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
296	3	2026-04-07 09:05:26.31123	09:05:26.31123	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
297	3	2026-04-07 09:05:34.600875	09:05:34.600875	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
298	3	2026-04-07 09:44:30.219259	09:44:30.219259	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
299	3	2026-04-07 09:44:45.848439	09:44:45.848439	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
300	3	2026-04-07 10:25:54.655687	10:25:54.655687	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
301	3	2026-04-07 10:26:09.52094	10:26:09.52094	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
302	3	2026-04-07 12:37:48.057838	12:37:48.057838	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
303	3	2026-04-07 12:38:03.165217	12:38:03.165217	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
304	3	2026-04-07 13:07:39.616465	13:07:39.616465	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
305	3	2026-04-07 13:07:54.025874	13:07:54.025874	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
306	3	2026-04-07 13:46:20.018719	13:46:20.018719	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
307	3	2026-04-07 13:46:32.74095	13:46:32.74095	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
308	3	2026-04-07 13:46:59.834011	13:46:59.834011	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
309	3	2026-04-07 13:47:14.46452	13:47:14.46452	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
310	3	2026-04-07 17:26:55.518784	17:26:55.518784	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
311	3	2026-04-07 17:27:07.908318	17:27:07.908318	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
312	3	2026-04-07 17:53:58.597942	17:53:58.597942	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
313	3	2026-04-07 17:54:09.303343	17:54:09.303343	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
314	3	2026-04-07 20:02:00.962918	20:02:00.962918	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
315	3	2026-04-07 20:02:16.003688	20:02:16.003688	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
316	3	2026-04-07 20:41:29.201013	20:41:29.201013	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
317	3	2026-04-07 20:41:42.290339	20:41:42.290339	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
318	3	2026-04-08 09:49:14.544842	09:49:14.544842	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
319	3	2026-04-08 09:49:22.877459	09:49:22.877459	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
320	3	2026-04-08 11:12:14.06534	11:12:14.06534	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
321	3	2026-04-08 11:12:24.09187	11:12:24.09187	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
322	3	2026-04-08 13:20:11.822938	13:20:11.822938	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
323	3	2026-04-08 13:23:40.971368	13:23:40.971368	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
324	\N	2026-04-08 13:24:28.717841	13:24:28.717841	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/roles
325	3	2026-04-08 18:33:04.824371	18:33:04.824371	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
326	3	2026-04-08 18:33:15.326319	18:33:15.326319	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
327	3	2026-04-08 18:33:28.198188	18:33:28.198188	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
328	3	2026-04-08 19:52:50.303278	19:52:50.303278	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
329	3	2026-04-08 19:53:00.288227	19:53:00.288227	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
330	3	2026-04-08 22:10:25.47702	22:10:25.47702	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
331	3	2026-04-08 22:16:51.163583	22:16:51.163583	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
332	3	2026-04-08 22:16:57.873888	22:16:57.873888	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
333	\N	2026-04-08 23:42:33.064508	23:42:33.064508	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/usuarios
334	3	2026-04-09 11:32:01.458	11:32:01.458	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
335	3	2026-04-09 11:32:09.680434	11:32:09.680434	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
336	\N	2026-04-09 11:51:56.914193	11:51:56.914193	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/usuarios
337	3	2026-04-09 11:53:19.78453	11:53:19.78453	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
338	3	2026-04-09 11:58:15.541231	11:58:15.541231	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
339	3	2026-04-09 11:58:37.289566	11:58:37.289566	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
340	3	2026-04-09 11:58:44.076685	11:58:44.076685	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
341	3	2026-04-09 14:30:26.653782	14:30:26.653782	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
342	3	2026-04-09 14:30:35.068858	14:30:35.068858	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
343	3	2026-04-09 14:55:16.770603	14:55:16.770603	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
344	3	2026-04-09 14:55:24.873127	14:55:24.873127	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
345	3	2026-04-09 17:17:22.258898	17:17:22.258898	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
346	3	2026-04-09 17:17:37.647059	17:17:37.647059	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
347	\N	2026-04-09 17:24:38.795236	17:24:38.795236	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/usuarios
348	3	2026-04-10 11:02:08.315563	11:02:08.315563	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
349	3	2026-04-10 11:02:20.37124	11:02:20.37124	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
350	3	2026-04-10 14:22:26.880365	14:22:26.880365	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
351	3	2026-04-10 14:22:35.139585	14:22:35.139585	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
353	3	2026-04-10 15:11:47.682531	15:11:47.682531	CREAR	persona	6	127.0.0.1	Creación de persona
354	\N	2026-04-10 21:51:25.857666	21:51:25.857666	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/usuarios
355	\N	2026-04-10 21:51:37.665448	21:51:37.665448	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/personas
356	3	2026-04-10 21:52:39.280251	21:52:39.280251	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
357	3	2026-04-10 21:52:47.712624	21:52:47.712624	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
358	\N	2026-04-10 21:59:00.868974	21:59:00.868974	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/personas
359	\N	2026-04-10 21:59:10.744366	21:59:10.744366	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
360	\N	2026-04-10 22:07:37.746005	22:07:37.746005	CREAR	persona	8	::1	Creación de persona
361	3	2026-04-10 23:25:04.655874	23:25:04.655874	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
362	3	2026-04-10 23:25:15.351944	23:25:15.351944	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
363	\N	2026-04-10 23:47:16.55071	23:47:16.55071	CREAR	persona	9	::1	Creación de persona
364	3	2026-04-11 19:21:15.727947	19:21:15.727947	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
365	3	2026-04-11 19:21:19.902438	19:21:19.902438	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
366	3	2026-04-11 19:21:28.664219	19:21:28.664219	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
367	\N	2026-04-11 19:54:57.887077	19:54:57.887077	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: superadin
368	3	2026-04-11 19:55:09.667468	19:55:09.667468	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
369	3	2026-04-11 19:55:21.913094	19:55:21.913094	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
370	3	2026-04-11 20:12:17.83312	20:12:17.83312	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): EMPLEADO_CREAR
371	3	2026-04-11 20:22:56.505347	20:22:56.505347	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): EMPLEADO_CREAR
372	3	2026-04-11 20:23:35.315198	20:23:35.315198	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
373	3	2026-04-11 20:23:49.369984	20:23:49.369984	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
374	3	2026-04-11 20:24:11.596973	20:24:11.596973	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): EMPLEADO_CREAR
375	3	2026-04-11 20:31:47.011914	20:31:47.011914	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): EMPLEADO_CREAR
376	3	2026-04-11 20:34:22.005669	20:34:22.005669	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
377	3	2026-04-11 20:34:31.181476	20:34:31.181476	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
378	3	2026-04-11 20:34:53.790391	20:34:53.790391	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): EMPLEADO_CREAR
379	3	2026-04-11 21:27:11.820251	21:27:11.820251	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
380	3	2026-04-11 21:27:20.19281	21:27:20.19281	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
381	\N	2026-04-11 21:27:54.302588	21:27:54.302588	CREAR	empleado	6	::1	Creación de empleado
382	3	2026-04-11 22:26:26.350232	22:26:26.350232	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
383	3	2026-04-11 22:26:33.545993	22:26:33.545993	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
384	3	2026-04-11 22:26:43.967773	22:26:43.967773	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): EMPLEADO_VER
385	3	2026-04-11 22:26:49.706079	22:26:49.706079	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): EMPLEADO_VER
386	3	2026-04-11 22:30:34.357858	22:30:34.357858	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
387	3	2026-04-11 22:30:44.812237	22:30:44.812237	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
388	3	2026-04-11 23:59:49.85759	23:59:49.85759	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
389	3	2026-04-11 23:59:55.811408	23:59:55.811408	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
390	\N	2026-04-12 00:01:46.444606	00:01:46.444606	CREAR	empleado	7	::1	Creación de empleado
391	\N	2026-04-12 00:09:35.980944	00:09:35.980944	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
392	3	2026-04-12 00:19:13.626151	00:19:13.626151	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
393	3	2026-04-12 00:19:18.973557	00:19:18.973557	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
394	\N	2026-04-12 00:20:05.620367	00:20:05.620367	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
395	3	2026-04-12 00:20:17.346165	00:20:17.346165	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
396	3	2026-04-12 00:20:33.407105	00:20:33.407105	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
397	3	2026-04-12 10:20:38.258805	10:20:38.258805	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
398	3	2026-04-12 10:20:47.291424	10:20:47.291424	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
399	\N	2026-04-12 10:30:32.186059	10:30:32.186059	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
400	3	2026-04-12 10:59:06.958832	10:59:06.958832	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
401	3	2026-04-12 10:59:15.326042	10:59:15.326042	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
402	\N	2026-04-12 11:10:32.963532	11:10:32.963532	CREAR_USUARIO	usuario	11	::1	Usuario creado: jgomez
403	\N	2026-04-12 11:10:32.963532	11:10:32.963532	ASIGNAR_ROL_USUARIO	usuario_rol	6	::1	Asignar rol id_rol=1 a usuario id_usuario=11
404	3	2026-04-12 11:12:39.696494	11:12:39.696494	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
405	3	2026-04-12 11:12:41.995869	11:12:41.995869	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
406	3	2026-04-12 11:13:00.367405	11:13:00.367405	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
407	\N	2026-04-12 11:13:39.412007	11:13:39.412007	CREAR_USUARIO	usuario	12	::1	Usuario creado: mdiaz
408	\N	2026-04-12 11:13:39.412007	11:13:39.412007	ASIGNAR_ROL_USUARIO	usuario_rol	7	::1	Asignar rol id_rol=3 a usuario id_usuario=12
409	\N	2026-04-12 11:16:08.027584	11:16:08.027584	CREAR	persona	10	::1	Creación de persona
410	\N	2026-04-12 11:16:46.005247	11:16:46.005247	CREAR	empleado	8	::1	Creación de empleado
411	\N	2026-04-12 11:17:30.691447	11:17:30.691447	CREAR_USUARIO	usuario	13	::1	Usuario creado: aberrones
412	\N	2026-04-12 11:17:30.691447	11:17:30.691447	ASIGNAR_ROL_USUARIO	usuario_rol	8	::1	Asignar rol id_rol=1 a usuario id_usuario=13
413	\N	2026-04-12 13:03:54.827758	13:03:54.827758	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
414	3	2026-04-12 13:47:25.439422	13:47:25.439422	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
415	3	2026-04-12 13:47:41.180032	13:47:41.180032	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
416	3	2026-04-12 16:15:44.688382	16:15:44.688382	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
417	3	2026-04-12 16:15:58.112572	16:15:58.112572	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
418	3	2026-04-12 16:47:50.696979	16:47:50.696979	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
419	3	2026-04-12 16:47:59.73466	16:47:59.73466	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
420	3	2026-04-12 18:12:31.453724	18:12:31.453724	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
421	3	2026-04-12 18:12:39.697832	18:12:39.697832	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
422	3	2026-04-12 18:43:10.691931	18:43:10.691931	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
423	3	2026-04-12 18:43:16.250056	18:43:16.250056	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
424	3	2026-04-12 18:43:29.954467	18:43:29.954467	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
425	3	2026-04-12 20:17:45.793502	20:17:45.793502	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
426	3	2026-04-12 20:17:54.469417	20:17:54.469417	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
427	3	2026-04-12 20:37:36.700953	20:37:36.700953	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
428	3	2026-04-12 20:37:44.533411	20:37:44.533411	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
429	3	2026-04-12 20:55:52.193021	20:55:52.193021	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
430	3	2026-04-12 20:55:58.708323	20:55:58.708323	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
431	3	2026-04-12 20:59:09.345733	20:59:09.345733	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
432	3	2026-04-12 20:59:17.282451	20:59:17.282451	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
433	3	2026-04-12 21:43:58.120874	21:43:58.120874	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
434	3	2026-04-12 21:44:10.455591	21:44:10.455591	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
435	3	2026-04-12 22:05:08.119257	22:05:08.119257	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
436	3	2026-04-12 22:05:13.489772	22:05:13.489772	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
437	\N	2026-04-12 22:55:25.849588	22:55:25.849588	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
438	\N	2026-04-12 22:58:24.080872	22:58:24.080872	CREAR	persona	11	::1	Creación de persona
439	\N	2026-04-12 22:59:51.260043	22:59:51.260043	CREAR	empleado	9	::1	Creación de empleado
440	\N	2026-04-12 23:01:02.426693	23:01:02.426693	CREAR_USUARIO	usuario	14	::1	Usuario creado: dpastrana
441	\N	2026-04-12 23:01:02.426693	23:01:02.426693	ASIGNAR_ROL_USUARIO	usuario_rol	9	::1	Asignar rol id_rol=1 a usuario id_usuario=14
442	3	2026-04-12 23:36:50.999103	23:36:50.999103	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
443	3	2026-04-12 23:38:21.512214	23:38:21.512214	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
444	3	2026-04-13 08:21:24.469599	08:21:24.469599	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
445	3	2026-04-13 08:22:08.365991	08:22:08.365991	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
446	3	2026-04-13 08:22:20.762579	08:22:20.762579	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
447	3	2026-04-13 09:07:59.237439	09:07:59.237439	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
448	3	2026-04-13 09:08:02.205706	09:08:02.205706	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
449	3	2026-04-13 09:08:11.096345	09:08:11.096345	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
450	3	2026-04-13 09:22:20.500826	09:22:20.500826	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
451	3	2026-04-13 09:22:37.279965	09:22:37.279965	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
452	3	2026-04-13 10:03:47.774094	10:03:47.774094	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
453	3	2026-04-13 10:04:00.22486	10:04:00.22486	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
454	3	2026-04-13 10:52:59.495838	10:52:59.495838	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
455	3	2026-04-13 10:53:07.197547	10:53:07.197547	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
456	3	2026-04-13 11:47:23.315587	11:47:23.315587	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
457	3	2026-04-13 11:47:30.65788	11:47:30.65788	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
458	3	2026-04-13 12:02:35.62407	12:02:35.62407	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
459	3	2026-04-13 12:02:37.114497	12:02:37.114497	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
460	3	2026-04-13 12:02:54.097542	12:02:54.097542	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
461	\N	2026-04-13 18:23:08.288636	18:23:08.288636	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
462	\N	2026-04-13 18:29:45.445554	18:29:45.445554	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/kardex
463	3	2026-04-13 18:55:49.148732	18:55:49.148732	LOGIN_FAILED	usuario	3	::1	Contraseña incorrecta
464	3	2026-04-13 18:56:04.627975	18:56:04.627975	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
465	3	2026-04-13 18:56:14.343302	18:56:14.343302	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
466	3	2026-04-13 20:11:49.214143	20:11:49.214143	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
467	3	2026-04-13 20:12:07.28116	20:12:07.28116	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
468	3	2026-04-13 20:22:32.703103	20:22:32.703103	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
469	3	2026-04-13 20:22:40.483492	20:22:40.483492	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
470	3	2026-04-13 21:05:38.556808	21:05:38.556808	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
471	3	2026-04-13 21:05:47.082318	21:05:47.082318	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
472	3	2026-04-13 21:17:43.430643	21:17:43.430643	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
473	3	2026-04-13 21:17:51.262841	21:17:51.262841	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
474	3	2026-04-13 21:19:09.928771	21:19:09.928771	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
475	3	2026-04-13 21:19:17.247942	21:19:17.247942	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
476	3	2026-04-13 21:24:00.191658	21:24:00.191658	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
477	3	2026-04-13 21:24:07.685869	21:24:07.685869	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
478	\N	2026-04-13 21:29:31.585879	21:29:31.585879	LOGIN_FAILED	usuario	\N	::1	Intento con usuario inexistente: superasmin
479	3	2026-04-13 21:29:41.123419	21:29:41.123419	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
480	3	2026-04-13 21:29:51.437137	21:29:51.437137	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
481	3	2026-04-13 21:37:56.433971	21:37:56.433971	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
482	3	2026-04-13 21:38:04.179682	21:38:04.179682	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
483	3	2026-04-13 21:40:05.287315	21:40:05.287315	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
484	3	2026-04-13 21:40:18.088578	21:40:18.088578	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
485	3	2026-04-13 21:43:37.147239	21:43:37.147239	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
486	3	2026-04-13 21:43:44.851079	21:43:44.851079	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
487	3	2026-04-13 21:44:33.346636	21:44:33.346636	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
488	3	2026-04-13 21:44:46.954128	21:44:46.954128	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
489	3	2026-04-13 21:52:18.922512	21:52:18.922512	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
490	3	2026-04-13 21:52:25.631322	21:52:25.631322	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
491	3	2026-04-13 22:28:48.683568	22:28:48.683568	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
492	3	2026-04-13 22:28:56.044459	22:28:56.044459	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
493	3	2026-04-13 22:32:35.803672	22:32:35.803672	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
494	3	2026-04-13 22:32:44.688456	22:32:44.688456	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
495	3	2026-04-13 22:47:53.202517	22:47:53.202517	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
496	3	2026-04-13 22:47:59.371195	22:47:59.371195	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
497	3	2026-04-13 22:56:41.900777	22:56:41.900777	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
498	3	2026-04-13 22:57:00.760253	22:57:00.760253	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
499	3	2026-04-13 23:06:20.827581	23:06:20.827581	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
500	3	2026-04-13 23:06:29.563101	23:06:29.563101	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
501	3	2026-04-13 23:09:53.72685	23:09:53.72685	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
502	3	2026-04-13 23:10:04.282466	23:10:04.282466	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
503	3	2026-04-13 23:15:29.632707	23:15:29.632707	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
504	3	2026-04-13 23:15:39.151126	23:15:39.151126	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
505	3	2026-04-13 23:17:10.575729	23:17:10.575729	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
506	3	2026-04-13 23:17:24.42842	23:17:24.42842	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
507	3	2026-04-13 23:21:33.047139	23:21:33.047139	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
508	3	2026-04-13 23:21:42.998539	23:21:42.998539	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
509	3	2026-04-13 23:35:13.321625	23:35:13.321625	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
510	3	2026-04-13 23:35:22.44496	23:35:22.44496	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
511	3	2026-04-13 23:43:35.436262	23:43:35.436262	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
512	3	2026-04-13 23:43:45.227903	23:43:45.227903	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
513	3	2026-04-17 23:18:38.320079	23:18:38.320079	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
514	3	2026-04-17 23:18:39.74124	23:18:39.74124	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
515	3	2026-04-17 23:21:43.314863	23:21:43.314863	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
516	3	2026-04-17 23:21:45.062775	23:21:45.062775	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
517	3	2026-04-17 23:22:53.795427	23:22:53.795427	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
518	3	2026-04-17 23:50:49.877045	23:50:49.877045	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
519	3	2026-04-17 23:50:52.004891	23:50:52.004891	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
520	3	2026-04-17 23:51:26.578924	23:51:26.578924	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
521	3	2026-04-17 23:52:08.976193	23:52:08.976193	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
522	3	2026-04-17 23:52:31.302795	23:52:31.302795	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
523	3	2026-04-17 23:52:58.170244	23:52:58.170244	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
524	3	2026-04-17 23:58:28.061331	23:58:28.061331	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
525	3	2026-04-17 23:58:30.459185	23:58:30.459185	LOGIN_2FA_REQUIRED	usuario	3	::1	Login correcto, requiere OTP
526	3	2026-04-17 23:59:01.127774	23:59:01.127774	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con 2FA
527	3	2026-04-18 00:05:40.796941	00:05:40.796941	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
528	3	2026-04-18 00:12:51.680291	00:12:51.680291	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
529	3	2026-04-18 00:12:58.447926	00:12:58.447926	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
530	3	2026-04-18 00:14:35.59157	00:14:35.59157	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
531	3	2026-04-18 00:19:18.437189	00:19:18.437189	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
532	3	2026-04-18 00:21:15.392383	00:21:15.392383	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
533	3	2026-04-18 00:24:24.564547	00:24:24.564547	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
534	3	2026-04-18 00:29:51.986401	00:29:51.986401	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
535	3	2026-04-18 00:31:34.997738	00:31:34.997738	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
536	3	2026-04-18 01:22:12.002529	01:22:12.002529	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
537	\N	2026-04-18 01:48:09.526705	01:48:09.526705	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/empleados
538	\N	2026-04-18 01:48:20.152964	01:48:20.152964	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/empleados
539	3	2026-04-18 01:48:32.353223	01:48:32.353223	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
540	\N	2026-04-18 01:49:36.669097	01:49:36.669097	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/empleados
541	\N	2026-04-18 01:50:47.901322	01:50:47.901322	CREAR	persona	12	::1	Creación de persona
542	\N	2026-04-18 02:10:34.06971	02:10:34.06971	CREAR	empleado	10	::1	Creación de empleado
543	\N	2026-04-18 02:28:26.822346	02:28:26.822346	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/permisos
544	\N	2026-04-18 02:31:53.660114	02:31:53.660114	CREAR_USUARIO	usuario	15	::1	Usuario creado: tyab
545	\N	2026-04-18 02:31:53.660114	02:31:53.660114	ASIGNAR_ROL_USUARIO	usuario_rol	10	::1	Asignar rol id_rol=1 a usuario id_usuario=15
546	3	2026-04-18 02:44:39.298004	02:44:39.298004	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
547	3	2026-04-18 02:51:34.122764	02:51:34.122764	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): ROL_ELIMINAR
548	3	2026-04-18 02:51:35.158878	02:51:35.158878	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): ROL_ELIMINAR
549	3	2026-04-18 02:51:35.376452	02:51:35.376452	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): ROL_ELIMINAR
550	3	2026-04-18 02:51:36.678633	02:51:36.678633	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): ROL_ELIMINAR
551	3	2026-04-18 02:52:01.832314	02:52:01.832314	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): PERMISO_ELIMINAR
552	3	2026-04-18 02:53:53.932376	02:53:53.932376	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): ROL_ELIMINAR
553	3	2026-04-18 02:58:59.468183	02:58:59.468183	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): ROL_ELIMINAR
554	3	2026-04-18 02:59:30.625754	02:59:30.625754	ACCESS_DENIED_PERMISSION	\N	\N	::1	Intento sin permiso(s): ROL_ELIMINAR
555	\N	2026-04-18 03:18:09.599099	03:18:09.599099	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario
556	\N	2026-04-18 03:22:15.896178	03:22:15.896178	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario
557	\N	2026-04-18 03:44:33.395835	03:44:33.395835	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario
558	3	2026-04-18 04:18:00.790787	04:18:00.790787	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
559	3	2026-04-18 04:29:23.653698	04:29:23.653698	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	2	::1	Cambio de estado: CREADA -> APROBADA | bodega_reserva=1
560	3	2026-04-18 04:45:53.515439	04:45:53.515439	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
561	3	2026-04-18 05:00:06.224076	05:00:06.224076	CONFIRMAR_REGISTRO	registro	23	::1	Confirmación de registro y afectación de inventario
562	3	2026-04-18 05:00:06.224076	05:00:06.224076	CREAR_ASIGNACION	asignacion_bien	3	::1	Asignacion creada. acta=(sin numero) | id_registro=23
563	\N	2026-04-18 16:06:00.299062	16:06:00.299062	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario
564	\N	2026-04-18 16:06:27.469887	16:06:27.469887	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario
565	\N	2026-04-18 16:10:43.03953	16:10:43.03953	ACCESS_DENIED_INVALID_TOKEN	\N	\N	::1	Token inválido al acceder a /api/inventario
566	3	2026-04-18 16:11:24.650005	16:11:24.650005	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
567	\N	2026-04-18 16:27:35.198985	16:27:35.198985	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/backup/download/backup_bienes_logistica_2026-04-18T16-27-32.sql
568	3	2026-04-18 16:37:43.65564	16:37:43.65564	CONFIRMAR_REGISTRO	registro	26	::1	Confirmación de registro y afectación de inventario
569	3	2026-04-18 16:37:43.65564	16:37:43.65564	CREAR_ASIGNACION	asignacion_bien	4	::1	Asignación creada. acta=(sin número) | id_registro=26
570	3	2026-04-18 16:37:53.793224	16:37:53.793224	CONFIRMAR_REGISTRO	registro	27	::1	Confirmación de registro y afectación de inventario
571	3	2026-04-18 16:37:53.793224	16:37:53.793224	DEVOLVER_ASIGNACION	asignacion_bien	4	::1	Devolución registrada. id_registro=27
572	3	2026-04-18 17:03:03.748927	17:03:03.748927	PROGRAMAR_MANTENIMIENTO	mantenimiento	1	::1	Mantenimiento programado. fecha_programada=(null)
573	3	2026-04-18 17:03:11.905853	17:03:11.905853	INICIAR_MANTENIMIENTO	mantenimiento	1	::1	Mantenimiento iniciado. fecha_inicio=2026-04-18
574	3	2026-04-18 17:03:27.216031	17:03:27.216031	FINALIZAR_MANTENIMIENTO	mantenimiento	1	::1	Mantenimiento finalizado. fecha_fin=2026-04-18 costo=(null)
575	\N	2026-04-18 17:05:01.860494	17:05:01.860494	ACCESS_DENIED_NO_TOKEN	\N	\N	::1	Acceso sin token a /api/backup/download/backup_bienes_logistica_2026-04-18T16-27-32.sql
576	3	2026-04-18 20:03:13.311569	20:03:13.311569	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
577	3	2026-04-18 21:07:50.025099	21:07:50.025099	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	5	::1	Cambio de estado: CREADA -> APROBADA | bodega_reserva=2
578	3	2026-04-18 21:11:35.125706	21:11:35.125706	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	9	::1	Cambio de estado: CREADA -> APROBADA | bodega_reserva=2
579	3	2026-04-18 21:11:39.566414	21:11:39.566414	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	9	::1	Cambio de estado: APROBADA -> CANCELADA | bodega_reserva=2
580	3	2026-04-18 21:11:47.811778	21:11:47.811778	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	8	::1	Cambio de estado: CREADA -> CANCELADA
581	3	2026-04-18 21:14:26.453229	21:14:26.453229	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	5	::1	Cambio de estado: APROBADA -> CANCELADA | bodega_reserva=1
582	3	2026-04-18 21:15:20.543243	21:15:20.543243	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	1	::1	Cambio de estado: APROBADA -> CANCELADA | bodega_reserva=2
583	3	2026-04-18 21:31:29.888836	21:31:29.888836	CONFIRMAR_REGISTRO	registro	28	::1	Confirmación de registro y afectación de inventario
584	3	2026-04-18 21:31:29.888836	21:31:29.888836	DEVOLVER_ASIGNACION	asignacion_bien	3	::1	Devolución registrada. id_registro=28
585	3	2026-04-18 21:31:48.805864	21:31:48.805864	CONFIRMAR_REGISTRO	registro	29	::1	Confirmación de registro y afectación de inventario
586	3	2026-04-18 21:31:48.805864	21:31:48.805864	CREAR_ASIGNACION	asignacion_bien	5	::1	Asignación creada. acta=(sin número) | id_registro=29
587	3	2026-04-18 21:32:14.825704	21:32:14.825704	PROGRAMAR_MANTENIMIENTO	mantenimiento	2	::1	Mantenimiento programado. fecha_programada=2026-04-18
588	3	2026-04-18 21:32:21.45683	21:32:21.45683	INICIAR_MANTENIMIENTO	mantenimiento	2	::1	Mantenimiento iniciado. fecha_inicio=2026-04-18
589	3	2026-04-18 22:18:47.361472	22:18:47.361472	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	6	::1	Cambio de estado: CREADA -> APROBADA | bodega_reserva=1
590	3	2026-04-18 22:18:56.723188	22:18:56.723188	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	4	::1	Cambio de estado: CREADA -> CANCELADA
591	3	2026-04-18 22:19:40.217709	22:19:40.217709	CONFIRMAR_REGISTRO	registro	30	::1	Confirmación de registro y afectación de inventario
592	3	2026-04-18 22:19:40.217709	22:19:40.217709	CREAR_ASIGNACION	asignacion_bien	6	::1	Asignación creada. acta=(sin número) | id_registro=30
593	3	2026-04-18 22:19:54.02229	22:19:54.02229	CONFIRMAR_REGISTRO	registro	31	::1	Confirmación de registro y afectación de inventario
594	3	2026-04-18 22:19:54.02229	22:19:54.02229	DEVOLVER_ASIGNACION	asignacion_bien	5	::1	Devolución registrada. id_registro=31
595	3	2026-04-18 22:20:54.921051	22:20:54.921051	PROGRAMAR_MANTENIMIENTO	mantenimiento	3	::1	Mantenimiento programado. fecha_programada=2026-04-18
654	3	2026-04-19 10:15:42.862199	10:15:42.862199	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
596	3	2026-04-18 22:21:08.311821	22:21:08.311821	INICIAR_MANTENIMIENTO	mantenimiento	3	::1	Mantenimiento iniciado. fecha_inicio=2026-04-18
597	3	2026-04-18 22:21:10.552683	22:21:10.552683	FINALIZAR_MANTENIMIENTO	mantenimiento	3	::1	Mantenimiento finalizado. fecha_fin=2026-04-18 costo=(null)
598	3	2026-04-18 22:29:38.101284	22:29:38.101284	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
599	3	2026-04-18 22:31:16.571525	22:31:16.571525	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
600	3	2026-04-18 22:59:22.347251	22:59:22.347251	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
601	3	2026-04-18 23:07:23.301549	23:07:23.301549	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
602	3	2026-04-18 23:11:09.088125	23:11:09.088125	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
603	\N	2026-04-18 23:26:00.621873	23:26:00.621873	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=superadmin correo=xagc@tu.com
604	\N	2026-04-18 23:26:02.277192	23:26:02.277192	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=superadmin correo=xagc@tu.com
605	\N	2026-04-18 23:26:03.118108	23:26:03.118108	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=superadmin correo=xagc@tu.com
606	3	2026-04-18 23:26:30.689877	23:26:30.689877	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
607	3	2026-04-18 23:26:31.596641	23:26:31.596641	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
608	3	2026-04-18 23:26:34.853675	23:26:34.853675	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
609	3	2026-04-18 23:30:21.760648	23:30:21.760648	PASSWORD_RESET	usuario	3	::1	Contrasena actualizada via recuperacion
610	3	2026-04-18 23:39:04.522988	23:39:04.522988	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
611	3	2026-04-18 23:39:49.885076	23:39:49.885076	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
612	3	2026-04-18 23:47:06.007062	23:47:06.007062	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
613	3	2026-04-18 23:48:27.210866	23:48:27.210866	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
614	\N	2026-04-18 23:50:16.207505	23:50:16.207505	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=pepe correo=pepe@mail.com
615	3	2026-04-18 23:50:27.539373	23:50:27.539373	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
616	3	2026-04-18 23:50:52.624516	23:50:52.624516	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
617	3	2026-04-18 23:52:47.778639	23:52:47.778639	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
618	\N	2026-04-18 23:53:27.714178	23:53:27.714178	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=jjk correo=grupoteamaticos@gmail.com
619	\N	2026-04-18 23:54:32.763688	23:54:32.763688	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=jjkj correo=grupoteamaticos@gmail.com
620	\N	2026-04-18 23:54:47.819352	23:54:47.819352	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=admin correo=grupoteamaticos@gmail.com
621	3	2026-04-18 23:55:06.185239	23:55:06.185239	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
622	\N	2026-04-18 23:55:07.51069	23:55:07.51069	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=xxx correo=noexiste@x.com
623	3	2026-04-18 23:57:25.952773	23:57:25.952773	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
624	\N	2026-04-18 23:58:40.485103	23:58:40.485103	FORGOT_PASSWORD_FAILED	usuario	\N	::1	Intento de recuperacion fallido. usuario=kola correo=grupoteamaticos@gmail.com
625	3	2026-04-18 23:58:50.940393	23:58:50.940393	FORGOT_PASSWORD_REQUEST	usuario	3	::1	Codigo de recuperacion enviado a gr*************@gmail.com
626	3	2026-04-18 23:59:48.25533	23:59:48.25533	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (OTP desactivado DEV)
627	3	2026-04-19 00:08:22.518808	00:08:22.518808	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
628	3	2026-04-19 00:20:38.263872	00:20:38.263872	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
629	3	2026-04-19 00:20:40.662752	00:20:40.662752	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
630	3	2026-04-19 00:20:49.337089	00:20:49.337089	LOGIN_PIN_FAILED	usuario	3	::1	PIN incorrecto
631	3	2026-04-19 00:20:51.527375	00:20:51.527375	LOGIN_PIN_FAILED	usuario	3	::1	PIN incorrecto
632	3	2026-04-19 00:21:48.26412	00:21:48.26412	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con PIN 2FA
633	3	2026-04-19 00:22:02.338026	00:22:02.338026	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
634	3	2026-04-19 00:22:04.583971	00:22:04.583971	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
635	3	2026-04-19 00:25:34.492999	00:25:34.492999	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
636	3	2026-04-19 00:25:52.183163	00:25:52.183163	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con PIN 2FA
637	3	2026-04-19 00:40:29.904246	00:40:29.904246	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
638	3	2026-04-19 00:40:41.345604	00:40:41.345604	FORGOT_PIN_REQUEST	usuario	3	::1	Codigo de restablecimiento de PIN enviado a gr*************@gmail.com
639	3	2026-04-19 00:41:46.336334	00:41:46.336334	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
640	3	2026-04-19 00:42:25.791592	00:42:25.791592	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
641	3	2026-04-19 00:54:04.145771	00:54:04.145771	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
642	3	2026-04-19 00:54:11.269615	00:54:11.269615	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con PIN 2FA
643	3	2026-04-19 01:00:22.215106	01:00:22.215106	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
644	3	2026-04-18 21:53:06.55641	21:53:06.55641	LOGIN_PENDING_PIN	usuario	3	::1	Credenciales validas, esperando PIN 2FA
655	3	2026-04-19 10:26:25.795854	10:26:25.795854	CAMBIAR_ESTADO_SOLICITUD	solicitud_logistica	10	::1	Cambio de estado: CREADA -> APROBADA | bodega_reserva=2
666	3	2026-04-20 04:18:23.736654	04:18:23.736654	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
645	3	2026-04-18 21:53:50.825221	21:53:50.825221	LOGIN_SUCCESS	usuario	3	::1	Login exitoso con PIN 2FA
656	3	2026-04-19 10:27:05.614249	10:27:05.614249	CONFIRMAR_REGISTRO	registro	32	::1	Confirmación de registro y afectación de inventario
657	3	2026-04-19 10:27:05.614249	10:27:05.614249	CREAR_ASIGNACION	asignacion_bien	7	::1	Asignación creada. acta=(sin número) | id_registro=32
646	3	2026-04-18 22:22:05.166907	22:22:05.166907	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
658	3	2026-04-19 10:28:06.329121	10:28:06.329121	CONFIRMAR_REGISTRO	registro	33	::1	Confirmación de registro y afectación de inventario
659	3	2026-04-19 10:28:06.329121	10:28:06.329121	DEVOLVER_ASIGNACION	asignacion_bien	6	::1	Devolución registrada. id_registro=33
647	3	2026-04-18 22:32:40.620579	22:32:40.620579	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
660	3	2026-04-19 10:29:59.81684	10:29:59.81684	PROGRAMAR_MANTENIMIENTO	mantenimiento	4	::1	Mantenimiento programado. fecha_programada=2026-04-21
648	\N	2026-04-18 23:26:25.046199	23:26:25.046199	CREAR	persona	13	::1	Creación de persona
661	3	2026-04-19 10:30:29.216876	10:30:29.216876	INICIAR_MANTENIMIENTO	mantenimiento	4	::1	Mantenimiento iniciado. fecha_inicio=2026-04-19
649	\N	2026-04-18 23:28:21.557922	23:28:21.557922	CREAR	empleado	11	::1	Creación de empleado
662	3	2026-04-19 10:30:36.423884	10:30:36.423884	FINALIZAR_MANTENIMIENTO	mantenimiento	4	::1	Mantenimiento finalizado. fecha_fin=2026-04-19 costo=(null)
650	\N	2026-04-18 23:31:37.732183	23:31:37.732183	CREAR_USUARIO	usuario	16	::1	Usuario creado: cmora
651	\N	2026-04-18 23:31:37.732183	23:31:37.732183	ASIGNAR_ROL_USUARIO	usuario_rol	11	::1	Asignar rol id_rol=4 a usuario id_usuario=16
663	16	2026-04-19 10:39:05.222229	10:39:05.222229	LOGIN_FAILED	usuario	16	::1	Contraseña incorrecta
652	3	2026-04-19 01:57:53.750193	01:57:53.750193	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
664	16	2026-04-19 10:39:43.576257	10:39:43.576257	LOGIN_FAILED	usuario	16	::1	Contraseña incorrecta
653	3	2026-04-19 10:02:13.260248	10:02:13.260248	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
665	3	2026-04-19 10:40:22.950201	10:40:22.950201	LOGIN_SUCCESS	usuario	3	::1	Login exitoso (sin PIN configurado)
\.


--
-- Data for Name: mantenimiento; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.mantenimiento (id_mantenimiento, id_bien, id_tipo_mantenimiento, id_proveedor, id_documento, fecha_inicio, fecha_fin, fecha_programada, kilometraje, descripcion_mantenimiento, costo_mantenimiento, estado_mantenimiento, observaciones_mantenimiento, fecha_registro) FROM stdin;
1	12	2	1	\N	2026-04-18	2026-04-18	\N	90.0	Mantenimiento - BN-001 - Laptop	\N	FINALIZADO	\N	2026-04-18 17:03:03.748927
2	14	2	7	\N	2026-04-18	\N	2026-04-18	90.0	Mantenimiento - BN-000 - TEST	\N	EN_PROCESO	\N	2026-04-18 21:32:14.825704
3	15	2	9	\N	2026-04-18	2026-04-18	2026-04-18	10.0	Mantenimiento - test1 - test1	\N	FINALIZADO	\N	2026-04-18 22:20:54.921051
4	18	1	10	\N	2026-04-19	2026-04-19	2026-04-21	6000.0	Mantenimiento - BIEN-012 - CARRO	\N	FINALIZADO	Cambio de aceite	2026-04-19 10:29:59.81684
\.


--
-- Data for Name: permiso; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.permiso (id_permiso, nombre_permiso, codigo_permiso, descripcion_permiso, estado_permiso, fecha_registro) FROM stdin;
1	Ver Usuarios	USUARIO_VER	Permite consultar la lista de usuarios	ACTIVO	2026-02-26 12:10:52.829903
2	Crear Usuario	USUARIO_CREAR	Permite registrar nuevos usuarios	ACTIVO	2026-02-26 12:10:52.829903
3	Editar Usuario	USUARIO_EDITAR	Permite modificar información de usuarios	ACTIVO	2026-02-26 12:10:52.829903
4	Bloquear Usuario	USUARIO_BLOQUEAR	Permite bloquear y desbloquear usuarios	ACTIVO	2026-02-26 12:10:52.829903
5	Ver Roles	ROL_VER	Permite consultar los roles del sistema	ACTIVO	2026-02-26 12:10:52.829903
6	Crear Rol	ROL_CREAR	Permite crear nuevos roles	ACTIVO	2026-02-26 12:10:52.829903
7	Ver Permisos	PERMISO_VER	Permite consultar permisos existentes	ACTIVO	2026-02-26 12:10:52.829903
8	Asignar Permiso a Rol	PERMISO_ASIGNAR	Permite asignar permisos a los roles	ACTIVO	2026-02-26 12:10:52.829903
10	Crear Registro	REGISTRO_CREAR	\N	ACTIVO	2026-03-01 18:16:46.870052
11	Confirmar Registro	REGISTRO_CONFIRMAR	\N	ACTIVO	2026-03-01 18:16:46.870052
12	Anular Registro	REGISTRO_ANULAR	\N	ACTIVO	2026-03-01 18:16:46.870052
13	Ver Kardex	KARDEX_VER	\N	ACTIVO	2026-03-01 23:51:11.543566
14	Ver Inventario	INVENTARIO_VER	\N	ACTIVO	2026-03-02 10:03:20.672655
15	Crear Reserva	RESERVA_CREAR	\N	ACTIVO	2026-03-02 10:36:17.529178
16	Modificar Reserva	RESERVA_EDITAR	\N	ACTIVO	2026-03-02 10:36:17.529178
17	Crear Solicitud	SOLICITUD_CREAR	\N	ACTIVO	2026-03-02 11:48:41.498958
18	Editar Solicitud	SOLICITUD_EDITAR	\N	ACTIVO	2026-03-02 11:48:41.498958
19	Ver Reportes	REPORTE_VER	\N	ACTIVO	2026-03-02 14:25:02.223131
20	Asignar Bien	ASIGNAR_BIEN	Permite asignar bienes a empleados	ACTIVO	2026-03-02 21:42:17.73067
21	Devolver Bien Asignado	DEVOLVER_BIEN	Permite devolver bienes previamente asignados	ACTIVO	2026-03-03 13:41:14.154655
22	Ver Solicitudes	SOLICITUD_VER	Permite ver listado de solicitudes	ACTIVO	2026-03-23 17:20:21.097017
23	Ver Asignaciones	ASIGNACION_VER	Permite ver listado de asignaciones	ACTIVO	2026-03-23 18:16:00.068032
24	Ver Reservas	RESERVA_VER	Permite ver el listado de las reservas	ACTIVO	2026-03-31 15:57:34.691969
25	Crear empleado	EMPLEADO_CREAR	Permite crear nuevos empleados.	ACTIVO	2026-04-11 20:22:47.512154
26	Ver empleado	EMPLEADO_VER	Permite ver los empleados existentes.	ACTIVO	2026-04-11 22:29:12.918099
\.


--
-- Data for Name: persona; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.persona (id_persona, primer_nombre, segundo_nombre, primer_apellido, segundo_apellido, identidad, fecha_nacimiento, sexo, estado_persona, fecha_registro) FROM stdin;
1	Admin	\N	Sistema	\N	0000000000000	\N	M	ACTIVO	2026-02-28 17:08:48.465249
6	Juan	Carlos	Perez	Lopez	0801190012345	2000-01-01	M	ACTIVO	2026-04-10 15:11:47.682531
9	Juan	Alberto	Gomez	Cerrato	0801200006347	2000-03-06	M	ACTIVO	2026-04-10 23:47:16.55071
11	Daniel	Enrrique	Pastrana	Pastrana	0608200200150	2002-11-21	M	ACTIVO	2026-04-12 22:58:24.080872
8	Maria	Jose	Diaz	Lopez	0801190012348	2000-01-01	F	ACTIVO	2026-04-10 22:07:37.746005
12	test		Yab		12346789000	2026-04-03	F	ACTIVO	2026-04-18 01:50:47.901322
10	Alex	Andre	Berrones	Gomez	0801202212345	2000-04-01	M	ACTIVO	2026-04-12 11:16:08.027584
2	Carlos	Andres	Lopez	Martinez	0801199912345	1999-01-01	M	ACTIVO	2026-03-01 07:45:47.753564
13	Chris		Mora	Bayley	0901200100765	2001-03-03	F	ACTIVO	2026-04-18 23:26:25.046199
\.


--
-- Data for Name: proveedor; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.proveedor (id_proveedor, nombre_proveedor, rtn_proveedor, categoria_servicio, especialidad, contacto_representante, telefono_contacto, correo_contacto, estado_proveedor, fecha_registro) FROM stdin;
1	Proveedor A	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-18 16:56:11.922372
2	Proveedor B	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-18 16:56:11.922372
3	Proveedor C	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-18 16:56:11.922372
4	june	\N	\N	\N	\N	\N	\N	INACTIVO	2026-04-18 20:19:36.7567
5	TEST	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-18 20:33:39.54736
6	nombre	\N	\N	\N	\N	\N	\N	INACTIVO	2026-04-18 20:33:47.529956
7	sol	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-18 21:32:14.762884
8	kol	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-18 22:14:35.747797
9	SPS	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-18 22:20:54.856359
10	Taller Lopez	\N	\N	\N	\N	\N	\N	ACTIVO	2026-04-19 10:29:59.767226
\.


--
-- Data for Name: puesto; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.puesto (id_puesto, nombre_puesto, descripcion_puesto, nivel_puesto, estado_puesto, fecha_registro) FROM stdin;
1	Administrador	Administrador del sistema	1	ACTIVO	2026-02-28 17:07:53.769282
\.


--
-- Data for Name: rate_limiter; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.rate_limiter (key, points, expire) FROM stdin;
\.


--
-- Data for Name: registro; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.registro (id_registro, id_tipo_registro, id_usuario, id_empleado, id_solicitud, id_documento, id_bodega_origen, id_bodega_destino, fecha_registro, referencia_externa, observaciones_registro, estado_registro, fecha_actualizacion) FROM stdin;
3	1	3	1	\N	\N	1	2	2026-03-01 19:30:19.678884	REQ-123	Prueba creación registro\n[ANULADO] Prueba anulación	ANULADO	2026-03-01 20:28:37.752426
4	1	3	1	\N	\N	1	2	2026-03-01 20:55:16.528128	REQ-123	Prueba creación registro2	CONFIRMADO	2026-03-01 20:58:45.814969
5	2	3	1	\N	\N	1	\N	2026-03-01 21:28:20.151862	FACT-001	Ingreso compra resmas de papel	CONFIRMADO	2026-03-01 21:31:40.507362
6	3	3	1	\N	\N	1	\N	2026-03-01 21:53:39.352673	REQ-002	Salida 10 resmas para oficina administrativa	CONFIRMADO	2026-03-01 21:55:46.941367
9	3	3	1	3	\N	1	\N	2026-03-02 12:20:20.73851	SOL-3	\N	REGISTRADO	2026-03-02 12:20:20.73851
11	3	3	1	\N	\N	1	\N	2026-03-02 22:30:13.014699	ACTA-001	Entrega inicial	CONFIRMADO	2026-03-02 22:30:13.014699
12	3	3	1	\N	\N	1	\N	2026-03-03 13:02:16.624815	TEST-INTEGRAL-01	Prueba control	CONFIRMADO	2026-03-03 13:02:16.624815
17	3	3	1	\N	\N	1	\N	2026-03-03 13:59:45.451702	DEV-ASIG-2	Devolución prueba	CONFIRMADO	2026-03-03 13:59:45.451702
23	1	3	1	\N	\N	1	\N	2026-04-18 05:00:06.224076	\N		CONFIRMADO	2026-04-18 05:00:06.224076
26	1	3	9	\N	\N	1	\N	2026-04-18 16:37:43.65564	\N		CONFIRMADO	2026-04-18 16:37:43.65564
27	1	3	9	\N	\N	1	\N	2026-04-18 16:37:53.793224	DEV-ASIG-4	Devolucion de bien	CONFIRMADO	2026-04-18 16:37:53.793224
8	3	3	1	\N	\N	1	\N	2026-03-02 12:06:24.139427	SOL-1	\N	REGISTRADO	2026-03-02 12:06:24.139427
7	3	3	1	\N	\N	1	\N	2026-03-02 11:56:53.193485	SOL-1	\N	CONFIRMADO	2026-03-02 12:30:53.717268
28	1	3	1	\N	\N	2	\N	2026-04-18 21:31:29.888836	DEV-ASIG-3	Devolucion de bien	CONFIRMADO	2026-04-18 21:31:29.888836
29	1	3	7	\N	\N	1	\N	2026-04-18 21:31:48.805864	\N		CONFIRMADO	2026-04-18 21:31:48.805864
30	1	3	5	\N	\N	2	\N	2026-04-18 22:19:40.217709	\N		CONFIRMADO	2026-04-18 22:19:40.217709
31	1	3	7	\N	\N	1	\N	2026-04-18 22:19:54.02229	DEV-ASIG-5	Devolucion de bien	CONFIRMADO	2026-04-18 22:19:54.02229
32	1	3	11	\N	\N	1	\N	2026-04-19 10:27:05.614249	\N	Para de la empresa	CONFIRMADO	2026-04-19 10:27:05.614249
33	1	3	5	\N	\N	1	\N	2026-04-19 10:28:06.329121	DEV-ASIG-6	Ya le dio el uso 	CONFIRMADO	2026-04-19 10:28:06.329121
\.


--
-- Data for Name: registro_caracteristica; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.registro_caracteristica (id_registro_caracteristica, id_registro_detalle, id_caracteristica_bien, id_opcion, valor_texto, fecha_registro) FROM stdin;
\.


--
-- Data for Name: registro_detalle; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.registro_detalle (id_registro_detalle, id_registro, id_bien, id_bien_item, id_bien_lote, cantidad, costo_unitario, lote, observacion_detalle) FROM stdin;
1	3	1	\N	\N	5.000	100.00	\N	Salida prueba
2	4	1	\N	\N	5.000	100.00	\N	Salida prueba2
3	5	1	\N	\N	50.000	85.00	\N	Compra inicial resmas
4	6	1	\N	\N	10.000	85.00	\N	Entrega a administración
5	7	1	\N	\N	5.000	\N	\N	Uso administrativo
6	8	1	\N	\N	5.000	\N	\N	Uso administrativo
7	8	1	\N	\N	5.000	\N	\N	Uso administrativo
8	9	1	\N	\N	5.000	\N	\N	Uso administrativo
9	11	1	\N	\N	1.000	\N	\N	Asignación por acta: ACTA-001
10	12	1	\N	\N	1.000	\N	\N	Asignación por acta: TEST-INTEGRAL-01
12	17	1	\N	\N	1.000	\N	\N	Devolución de asignación id=2
13	23	7	\N	\N	1.000	\N	\N	Asignacion por acta: (sin numero)
14	26	10	\N	\N	1.000	\N	\N	Asignación por acta: (sin número)
15	27	10	\N	\N	1.000	\N	\N	Devolución de asignación id=4
16	28	7	\N	\N	1.000	\N	\N	Devolución de asignación id=3
17	29	6	\N	\N	1.000	\N	\N	Asignación por acta: (sin número)
18	30	10	\N	\N	1.000	\N	\N	Asignación por acta: (sin número)
19	31	6	\N	\N	1.000	\N	\N	Devolución de asignación id=5
20	32	10	\N	\N	1.000	\N	\N	Asignación por acta: (sin número)
21	33	10	\N	\N	1.000	\N	\N	Devolución de asignación id=6
\.


--
-- Data for Name: rol; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.rol (id_rol, nombre_rol, descripcion_rol, estado_rol, fecha_registro) FROM stdin;
1	SUPERADMIN	Acceso total al sistema	ACTIVO	2026-02-26 12:11:00.117013
2	ADMIN	Administrador general del sistema	ACTIVO	2026-02-26 12:11:00.117013
3	LOGISTICA	Operador de logística	ACTIVO	2026-02-26 12:11:00.117013
4	CONSULTA	Usuarios de solo lectura	ACTIVO	2026-02-26 12:11:00.117013
5	BIENES	Rol exclusivo para los usuarios del departamento de bienes.	ACTIVO	2026-04-12 13:48:59.593787
\.


--
-- Data for Name: rol_permiso; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.rol_permiso (id_rol_permiso, id_rol, id_permiso, fecha_asignacion) FROM stdin;
1	1	1	2026-02-26 12:11:27.534534
2	1	2	2026-02-26 12:11:27.534534
3	1	3	2026-02-26 12:11:27.534534
4	1	4	2026-02-26 12:11:27.534534
5	1	5	2026-02-26 12:11:27.534534
6	1	6	2026-02-26 12:11:27.534534
7	1	7	2026-02-26 12:11:27.534534
8	1	8	2026-02-26 12:11:27.534534
9	2	1	2026-02-26 12:11:27.534534
10	2	2	2026-02-26 12:11:27.534534
11	2	3	2026-02-26 12:11:27.534534
12	2	4	2026-02-26 12:11:27.534534
13	2	5	2026-02-26 12:11:27.534534
14	2	6	2026-02-26 12:11:27.534534
15	2	7	2026-02-26 12:11:27.534534
16	2	8	2026-02-26 12:11:27.534534
17	3	1	2026-02-26 12:11:27.534534
18	3	5	2026-02-26 12:11:27.534534
19	3	7	2026-02-26 12:11:27.534534
20	4	1	2026-02-26 12:11:27.534534
21	4	5	2026-02-26 12:11:27.534534
22	4	7	2026-02-26 12:11:27.534534
23	1	10	2026-03-01 18:17:56.392687
24	1	11	2026-03-01 18:17:56.392687
25	1	12	2026-03-01 18:17:56.392687
26	1	13	2026-03-01 23:53:23.783096
27	1	14	2026-03-02 10:07:43.269268
28	1	15	2026-03-02 10:37:18.62369
29	1	16	2026-03-02 10:37:27.12065
30	1	17	2026-03-02 11:49:51.959069
31	1	18	2026-03-02 11:50:08.19833
32	1	19	2026-03-02 14:26:09.229232
33	1	20	2026-03-02 21:42:56.480724
34	1	21	2026-03-03 13:41:38.265534
35	1	22	2026-03-23 17:21:05.884421
36	1	23	2026-03-23 18:16:10.604043
37	1	24	2026-03-31 16:00:07.517434
38	1	25	2026-04-11 20:31:40.569073
39	1	26	2026-04-11 22:29:29.195206
\.


--
-- Data for Name: solicitud_detalle; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.solicitud_detalle (id_solicitud_detalle, id_solicitud, id_bien, descripcion_item, cantidad, justificacion) FROM stdin;
4	3	1	Laptop para oficina	5.000	Uso administrativo
\.


--
-- Data for Name: solicitud_logistica; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.solicitud_logistica (id_solicitud, id_empleado, id_tipo_solicitud, id_estado_solicitud, prioridad, descripcion_solicitud, fecha_solicitud, fecha_respuesta, observaciones_solicitud) FROM stdin;
3	1	1	2	ALTA	Solicitud de papel	2026-03-02 12:14:04.380924	2026-03-02 12:19:25.367902	\n[2026-03-02 12:19] Aprobada por logística
2	1	1	2	ALTA	Solicitud de papel	2026-03-02 12:03:02.041812	2026-04-18 04:29:23.653698	\n[2026-04-18 04:29] Aprobada
9	\N	1	4	BAJA		2026-04-18 21:10:58.475576	2026-04-18 21:11:39.566414	\n[2026-04-18 21:11] Aprobada\n[2026-04-18 21:11] Cancelada
5	\N	1	4	URGENTE		2026-04-18 04:23:47.102486	2026-04-18 21:14:26.453229	\n[2026-04-18 21:07] Aprobada\n[2026-04-18 21:14] Cancelada
6	\N	2	2	NORMAL		2026-04-18 04:26:18.223762	2026-04-18 22:18:47.361472	\n[2026-04-18 22:18] Aprobada
4	\N	2	4	BAJA	papel	2026-04-18 04:10:01.983755	2026-04-18 22:18:56.723188	\n[2026-04-18 22:18] Cancelada
10	\N	1	2	NORMAL	Viaje 	2026-04-19 10:25:51.703126	2026-04-19 10:26:25.795854	\n[2026-04-19 10:26] Aprobada
\.


--
-- Data for Name: sucursal; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.sucursal (id_sucursal, id_empresa, nombre_sucursal, codigo_sucursal, direccion_sucursal, telefono_sucursal, correo_sucursal, estado_sucursal, fecha_registro, fecha_actualizacion) FROM stdin;
1	1	Central	SUC001	Tegucigalpa	00000000	central@didadpol.gob	ACTIVO	2026-02-28 17:03:47.598193	\N
\.


--
-- Data for Name: telefono_persona; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.telefono_persona (id_telefono, id_persona, tipo_telefono, numero, extension, principal, estado_telefono, fecha_registro) FROM stdin;
4	6	CELULAR	99999999	\N	t	ACTIVO	2026-04-10 15:11:47.682531
6	9	CELULAR	88888888	\N	t	ACTIVO	2026-04-10 23:47:16.55071
8	11	CELULAR	99999999	\N	t	ACTIVO	2026-04-12 22:58:24.080872
5	8	CELULAR	98765439	\N	t	ACTIVO	2026-04-10 22:07:37.746005
9	12	CELULAR	23456789	\N	t	ACTIVO	2026-04-18 01:50:47.901322
7	10	CELULAR	89080890	\N	t	ACTIVO	2026-04-12 11:16:08.027584
10	2	CELULAR	24647389	\N	f	ACTIVO	2026-04-18 22:24:55.490164
11	13	CELULAR	99445366	\N	t	ACTIVO	2026-04-18 23:26:25.046199
\.


--
-- Data for Name: tipo_bien; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.tipo_bien (id_tipo_bien, nombre_tipo_bien, descripcion_tipo_bien, estado_tipo_bien, fecha_registro) FROM stdin;
\.


--
-- Data for Name: tipo_campo; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.tipo_campo (id_tipo_campo, nombre_tipo_campo, tipo_dato, estado_tipo_campo, fecha_registro) FROM stdin;
\.


--
-- Data for Name: tipo_mantenimiento; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.tipo_mantenimiento (id_tipo_mantenimiento, nombre_tipo_mantenimiento, categoria_general, frecuencia_recomendada, costo_estimado, estado_tipo_mantenimiento, fecha_registro) FROM stdin;
1	Preventivo	General	\N	\N	ACTIVO	2026-04-18 16:56:11.901755
2	Correctivo	General	\N	\N	ACTIVO	2026-04-18 16:56:11.901755
\.


--
-- Data for Name: tipo_registro; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.tipo_registro (id_tipo_registro, nombre_tipo_registro, afecta_stock, signo_movimiento, estado_tipo_registro, fecha_registro) FROM stdin;
1	TRANSFERENCIA	t	1	ACTIVO	2026-03-01 19:27:52.420737
2	ENTRADA POR COMPRA	t	1	ACTIVO	2026-03-01 21:25:41.992557
3	SALIDA POR CONSUMO	t	-1	ACTIVO	2026-03-01 21:48:38.486251
\.


--
-- Data for Name: tipo_solicitud; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.tipo_solicitud (id_tipo_solicitud, nombre_tipo_solicitud, descripcion_tipo_solicitud, estado_tipo_solicitud, fecha_registro) FROM stdin;
1	SALIDA POR SOLICITUD	\N	ACTIVO	2026-03-02 11:24:22.09315
2	TRANSFERENCIA INTERNA	\N	ACTIVO	2026-03-02 11:24:22.09315
\.


--
-- Data for Name: usuario; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.usuario (id_usuario, id_empleado, nombre_usuario, contrasena_usuario, correo_login, ultimo_acceso, intentos_fallidos, bloqueado, estado_usuario, fecha_registro, reset_token, reset_token_expires, pin_hash, pin_reset_token, pin_reset_token_expires) FROM stdin;
12	7	mdiaz	$2b$10$h6X6ccCr3NZLg3iAuVHC2ul.qbbBW03TA0mseXVPJ6n0g/cHoa4f.	mdiaz@didadpol.gob	\N	0	f	ACTIVO	2026-04-12 11:13:39.412007	\N	\N	$2b$10$UPzQ5rS/lRs9Wxh9uStkG.7a7NYmEXPTPCihU4bFJizvkTapYuQku	\N	\N
14	9	dpastrana	$2b$10$uLkIZRyM1WwmLfxfR1aq1eHic9h.USgPlCMtue7xh9jPa0cnEMIDC	dpastrana@didadpol.gob	\N	0	f	ACTIVO	2026-04-12 23:01:02.426693	\N	\N	$2b$10$UPzQ5rS/lRs9Wxh9uStkG.7a7NYmEXPTPCihU4bFJizvkTapYuQku	\N	\N
11	6	jgomez	$2b$10$YCw5rIcr8coDjOmzg3jlE.txeMU8.j74Oc3aBUp8F/G4o.XdkgFHe	jgomez@didadpol.gob	\N	0	f	ACTIVO	2026-04-12 11:10:32.963532	\N	\N	$2b$10$UPzQ5rS/lRs9Wxh9uStkG.7a7NYmEXPTPCihU4bFJizvkTapYuQku	\N	\N
13	8	aberrones	$2b$10$pa/tAmoQHrscvUfv.fyZkOHlhTkaJ0.YOL6pzx1jFo3FrfH52xXeO	aberrones@didadpol.gob	\N	0	f	ACTIVO	2026-04-12 11:17:30.691447	\N	\N	$2b$10$UPzQ5rS/lRs9Wxh9uStkG.7a7NYmEXPTPCihU4bFJizvkTapYuQku	\N	\N
15	10	tyab	$2b$10$Z5j7RFz0zp9xZy4yfSqEsuswqejXfCDNtRmdBZ9ZJaDSIwPcjelUG	tyab@didadpol.gob	\N	0	f	ACTIVO	2026-04-18 02:31:53.660114	\N	\N	$2b$10$UPzQ5rS/lRs9Wxh9uStkG.7a7NYmEXPTPCihU4bFJizvkTapYuQku	\N	\N
6	5	Carlos prueba1	$2b$10$3rpO3aL2mo/lvZE7d2cud.xR.XsjFsVkWf5vYwO46LAcunc/9IStq	prueba1@mail.com	2026-03-01 15:48:17.971675	0	f	ACTIVO	2026-03-01 07:47:36.977864	\N	\N	$2b$10$UPzQ5rS/lRs9Wxh9uStkG.7a7NYmEXPTPCihU4bFJizvkTapYuQku	\N	\N
16	11	cmora	$2b$10$gLM9fHfEvbnE3jBRdJDqhuK.dyJZbkisOIuKNOzGY5xTlndgqSQWi	cmora@didadpol.gob	\N	2	f	ACTIVO	2026-04-18 23:31:37.732183	\N	\N	$2b$10$hIiakplLjWoLZAsTBqfOB.svaDS/LQtdP2go8I61e8G5ET04c1PxK	\N	\N
3	1	superadmin	$2b$10$kLPAhh31/D.WAmam9y9Kee1LUE/I6qTi0x/7mMLW2AuYPTKZqu.fW	grupoteamaticos@gmail.com	2026-04-20 04:18:23.632084	0	f	ACTIVO	2026-02-28 17:09:38.967604	J6Y95SGX	2026-04-18 18:13:48.027	$2b$10$UPzQ5rS/lRs9Wxh9uStkG.7a7NYmEXPTPCihU4bFJizvkTapYuQku	269697	2026-04-18 18:50:37.159
\.


--
-- Data for Name: usuario_permiso; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.usuario_permiso (id_usuario, id_permiso) FROM stdin;
11	26
16	15
16	24
16	17
\.


--
-- Data for Name: usuario_rol; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.usuario_rol (id_usuario_rol, id_usuario, id_rol, fecha_asignacion) FROM stdin;
2	3	1	2026-02-28 17:12:51.651694
3	6	4	2026-03-01 07:47:36.977864
6	11	1	2026-04-12 11:10:32.963532
7	12	3	2026-04-12 11:13:39.412007
8	13	1	2026-04-12 11:17:30.691447
9	14	1	2026-04-12 23:01:02.426693
10	15	1	2026-04-18 02:31:53.660114
11	16	4	2026-04-18 23:31:37.732183
\.


--
-- Data for Name: valor_bien; Type: TABLE DATA; Schema: public; Owner: juan
--

COPY public.valor_bien (id_valor_bien, valor_compra, valor_actual, valor_depreciacion, porcentaje_depreciacion, vida_util_estimada, fecha_avaluo, entidad_avaluadora, moneda, observaciones_valor, fecha_registro) FROM stdin;
\.


--
-- Name: asignacion_bien_id_asignacion_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.asignacion_bien_id_asignacion_seq', 7, true);


--
-- Name: bien_id_bien_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.bien_id_bien_seq', 18, true);


--
-- Name: bien_item_id_bien_item_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.bien_item_id_bien_item_seq', 1, false);


--
-- Name: bien_lote_id_bien_lote_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.bien_lote_id_bien_lote_seq', 1, false);


--
-- Name: bodega_id_bodega_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.bodega_id_bodega_seq', 2, true);


--
-- Name: caracteristica_bien_id_caracteristica_bien_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.caracteristica_bien_id_caracteristica_bien_seq', 1, false);


--
-- Name: caracteristica_opcion_id_caracteristica_opcion_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.caracteristica_opcion_id_caracteristica_opcion_seq', 1, false);


--
-- Name: correo_persona_id_correo_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.correo_persona_id_correo_seq', 11, true);


--
-- Name: departamento_id_departamento_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.departamento_id_departamento_seq', 1, true);


--
-- Name: direccion_persona_id_direccion_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.direccion_persona_id_direccion_seq', 10, true);


--
-- Name: documento_id_documento_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.documento_id_documento_seq', 1, false);


--
-- Name: empleado_id_empleado_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.empleado_id_empleado_seq', 11, true);


--
-- Name: empresa_id_empresa_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.empresa_id_empresa_seq', 1, true);


--
-- Name: estado_solicitud_id_estado_solicitud_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.estado_solicitud_id_estado_solicitud_seq', 4, true);


--
-- Name: estatus_empleado_id_estatus_empleado_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.estatus_empleado_id_estatus_empleado_seq', 1, true);


--
-- Name: historial_reservas_id_historial_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.historial_reservas_id_historial_seq', 52, true);


--
-- Name: inventario_id_inventario_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.inventario_id_inventario_seq', 70, true);


--
-- Name: inventario_lote_id_inventario_lote_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.inventario_lote_id_inventario_lote_seq', 1, false);


--
-- Name: kardex_id_kardex_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.kardex_id_kardex_seq', 8, true);


--
-- Name: log_cambios_id_log_cambios_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.log_cambios_id_log_cambios_seq', 1, false);


--
-- Name: log_usuario_id_log_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.log_usuario_id_log_usuario_seq', 666, true);


--
-- Name: mantenimiento_id_mantenimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.mantenimiento_id_mantenimiento_seq', 4, true);


--
-- Name: permiso_id_permiso_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.permiso_id_permiso_seq', 26, true);


--
-- Name: persona_id_persona_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.persona_id_persona_seq', 13, true);


--
-- Name: proveedor_id_proveedor_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.proveedor_id_proveedor_seq', 10, true);


--
-- Name: puesto_id_puesto_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.puesto_id_puesto_seq', 1, true);


--
-- Name: registro_caracteristica_id_registro_caracteristica_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.registro_caracteristica_id_registro_caracteristica_seq', 1, false);


--
-- Name: registro_detalle_id_registro_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.registro_detalle_id_registro_detalle_seq', 21, true);


--
-- Name: registro_id_registro_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.registro_id_registro_seq', 33, true);


--
-- Name: rol_id_rol_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.rol_id_rol_seq', 8, true);


--
-- Name: rol_permiso_id_rol_permiso_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.rol_permiso_id_rol_permiso_seq', 39, true);


--
-- Name: solicitud_detalle_id_solicitud_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.solicitud_detalle_id_solicitud_detalle_seq', 4, true);


--
-- Name: solicitud_logistica_id_solicitud_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.solicitud_logistica_id_solicitud_seq', 10, true);


--
-- Name: sucursal_id_sucursal_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.sucursal_id_sucursal_seq', 1, true);


--
-- Name: telefono_persona_id_telefono_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.telefono_persona_id_telefono_seq', 11, true);


--
-- Name: tipo_bien_id_tipo_bien_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.tipo_bien_id_tipo_bien_seq', 1, false);


--
-- Name: tipo_campo_id_tipo_campo_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.tipo_campo_id_tipo_campo_seq', 1, false);


--
-- Name: tipo_mantenimiento_id_tipo_mantenimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.tipo_mantenimiento_id_tipo_mantenimiento_seq', 2, true);


--
-- Name: tipo_registro_id_tipo_registro_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.tipo_registro_id_tipo_registro_seq', 3, true);


--
-- Name: tipo_solicitud_id_tipo_solicitud_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.tipo_solicitud_id_tipo_solicitud_seq', 2, true);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.usuario_id_usuario_seq', 16, true);


--
-- Name: usuario_rol_id_usuario_rol_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.usuario_rol_id_usuario_rol_seq', 11, true);


--
-- Name: valor_bien_id_valor_bien_seq; Type: SEQUENCE SET; Schema: public; Owner: juan
--

SELECT pg_catalog.setval('public.valor_bien_id_valor_bien_seq', 1, false);


--
-- Name: asignacion_bien asignacion_bien_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.asignacion_bien
    ADD CONSTRAINT asignacion_bien_pkey PRIMARY KEY (id_asignacion);


--
-- Name: bien bien_codigo_inventario_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien
    ADD CONSTRAINT bien_codigo_inventario_key UNIQUE (codigo_inventario);


--
-- Name: bien_item bien_item_numero_serie_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_item
    ADD CONSTRAINT bien_item_numero_serie_key UNIQUE (numero_serie);


--
-- Name: bien_item bien_item_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_item
    ADD CONSTRAINT bien_item_pkey PRIMARY KEY (id_bien_item);


--
-- Name: bien_lote bien_lote_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_lote
    ADD CONSTRAINT bien_lote_pkey PRIMARY KEY (id_bien_lote);


--
-- Name: bien bien_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien
    ADD CONSTRAINT bien_pkey PRIMARY KEY (id_bien);


--
-- Name: bodega bodega_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bodega
    ADD CONSTRAINT bodega_pkey PRIMARY KEY (id_bodega);


--
-- Name: caracteristica_bien caracteristica_bien_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.caracteristica_bien
    ADD CONSTRAINT caracteristica_bien_pkey PRIMARY KEY (id_caracteristica_bien);


--
-- Name: caracteristica_opcion caracteristica_opcion_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.caracteristica_opcion
    ADD CONSTRAINT caracteristica_opcion_pkey PRIMARY KEY (id_caracteristica_opcion);


--
-- Name: correo_persona correo_persona_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.correo_persona
    ADD CONSTRAINT correo_persona_pkey PRIMARY KEY (id_correo);


--
-- Name: departamento departamento_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.departamento
    ADD CONSTRAINT departamento_pkey PRIMARY KEY (id_departamento);


--
-- Name: direccion_persona direccion_persona_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.direccion_persona
    ADD CONSTRAINT direccion_persona_pkey PRIMARY KEY (id_direccion);


--
-- Name: documento documento_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_pkey PRIMARY KEY (id_documento);


--
-- Name: empleado empleado_codigo_empleado_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_codigo_empleado_key UNIQUE (codigo_empleado);


--
-- Name: empleado empleado_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_pkey PRIMARY KEY (id_empleado);


--
-- Name: empresa empresa_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empresa
    ADD CONSTRAINT empresa_pkey PRIMARY KEY (id_empresa);


--
-- Name: estado_solicitud estado_solicitud_nombre_estado_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.estado_solicitud
    ADD CONSTRAINT estado_solicitud_nombre_estado_key UNIQUE (nombre_estado);


--
-- Name: estado_solicitud estado_solicitud_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.estado_solicitud
    ADD CONSTRAINT estado_solicitud_pkey PRIMARY KEY (id_estado_solicitud);


--
-- Name: estatus_empleado estatus_empleado_nombre_estatus_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.estatus_empleado
    ADD CONSTRAINT estatus_empleado_nombre_estatus_key UNIQUE (nombre_estatus);


--
-- Name: estatus_empleado estatus_empleado_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.estatus_empleado
    ADD CONSTRAINT estatus_empleado_pkey PRIMARY KEY (id_estatus_empleado);


--
-- Name: historial_reservas historial_reservas_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.historial_reservas
    ADD CONSTRAINT historial_reservas_pkey PRIMARY KEY (id_historial);


--
-- Name: inventario_lote inventario_lote_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario_lote
    ADD CONSTRAINT inventario_lote_pkey PRIMARY KEY (id_inventario_lote);


--
-- Name: inventario inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT inventario_pkey PRIMARY KEY (id_inventario);


--
-- Name: kardex kardex_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.kardex
    ADD CONSTRAINT kardex_pkey PRIMARY KEY (id_kardex);


--
-- Name: log_cambios log_cambios_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.log_cambios
    ADD CONSTRAINT log_cambios_pkey PRIMARY KEY (id_log_cambios);


--
-- Name: log_usuario log_usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.log_usuario
    ADD CONSTRAINT log_usuario_pkey PRIMARY KEY (id_log_usuario);


--
-- Name: mantenimiento mantenimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_pkey PRIMARY KEY (id_mantenimiento);


--
-- Name: permiso permiso_codigo_permiso_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.permiso
    ADD CONSTRAINT permiso_codigo_permiso_key UNIQUE (codigo_permiso);


--
-- Name: permiso permiso_nombre_permiso_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.permiso
    ADD CONSTRAINT permiso_nombre_permiso_key UNIQUE (nombre_permiso);


--
-- Name: permiso permiso_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.permiso
    ADD CONSTRAINT permiso_pkey PRIMARY KEY (id_permiso);


--
-- Name: persona persona_identidad_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.persona
    ADD CONSTRAINT persona_identidad_key UNIQUE (identidad);


--
-- Name: persona persona_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.persona
    ADD CONSTRAINT persona_pkey PRIMARY KEY (id_persona);


--
-- Name: proveedor proveedor_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.proveedor
    ADD CONSTRAINT proveedor_pkey PRIMARY KEY (id_proveedor);


--
-- Name: puesto puesto_nombre_puesto_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.puesto
    ADD CONSTRAINT puesto_nombre_puesto_key UNIQUE (nombre_puesto);


--
-- Name: puesto puesto_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.puesto
    ADD CONSTRAINT puesto_pkey PRIMARY KEY (id_puesto);


--
-- Name: rate_limiter rate_limiter_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rate_limiter
    ADD CONSTRAINT rate_limiter_pkey PRIMARY KEY (key);


--
-- Name: registro_caracteristica registro_caracteristica_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_caracteristica
    ADD CONSTRAINT registro_caracteristica_pkey PRIMARY KEY (id_registro_caracteristica);


--
-- Name: registro_detalle registro_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_detalle
    ADD CONSTRAINT registro_detalle_pkey PRIMARY KEY (id_registro_detalle);


--
-- Name: registro registro_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_pkey PRIMARY KEY (id_registro);


--
-- Name: rol rol_nombre_rol_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol
    ADD CONSTRAINT rol_nombre_rol_key UNIQUE (nombre_rol);


--
-- Name: rol_permiso rol_permiso_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol_permiso
    ADD CONSTRAINT rol_permiso_pkey PRIMARY KEY (id_rol_permiso);


--
-- Name: rol rol_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol
    ADD CONSTRAINT rol_pkey PRIMARY KEY (id_rol);


--
-- Name: solicitud_detalle solicitud_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_detalle
    ADD CONSTRAINT solicitud_detalle_pkey PRIMARY KEY (id_solicitud_detalle);


--
-- Name: solicitud_logistica solicitud_logistica_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_logistica
    ADD CONSTRAINT solicitud_logistica_pkey PRIMARY KEY (id_solicitud);


--
-- Name: sucursal sucursal_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.sucursal
    ADD CONSTRAINT sucursal_pkey PRIMARY KEY (id_sucursal);


--
-- Name: telefono_persona telefono_persona_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.telefono_persona
    ADD CONSTRAINT telefono_persona_pkey PRIMARY KEY (id_telefono);


--
-- Name: tipo_bien tipo_bien_nombre_tipo_bien_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_bien
    ADD CONSTRAINT tipo_bien_nombre_tipo_bien_key UNIQUE (nombre_tipo_bien);


--
-- Name: tipo_bien tipo_bien_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_bien
    ADD CONSTRAINT tipo_bien_pkey PRIMARY KEY (id_tipo_bien);


--
-- Name: tipo_campo tipo_campo_nombre_tipo_campo_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_campo
    ADD CONSTRAINT tipo_campo_nombre_tipo_campo_key UNIQUE (nombre_tipo_campo);


--
-- Name: tipo_campo tipo_campo_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_campo
    ADD CONSTRAINT tipo_campo_pkey PRIMARY KEY (id_tipo_campo);


--
-- Name: tipo_mantenimiento tipo_mantenimiento_nombre_tipo_mantenimiento_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_mantenimiento
    ADD CONSTRAINT tipo_mantenimiento_nombre_tipo_mantenimiento_key UNIQUE (nombre_tipo_mantenimiento);


--
-- Name: tipo_mantenimiento tipo_mantenimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_mantenimiento
    ADD CONSTRAINT tipo_mantenimiento_pkey PRIMARY KEY (id_tipo_mantenimiento);


--
-- Name: tipo_registro tipo_registro_nombre_tipo_registro_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_registro
    ADD CONSTRAINT tipo_registro_nombre_tipo_registro_key UNIQUE (nombre_tipo_registro);


--
-- Name: tipo_registro tipo_registro_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_registro
    ADD CONSTRAINT tipo_registro_pkey PRIMARY KEY (id_tipo_registro);


--
-- Name: tipo_solicitud tipo_solicitud_nombre_tipo_solicitud_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_solicitud
    ADD CONSTRAINT tipo_solicitud_nombre_tipo_solicitud_key UNIQUE (nombre_tipo_solicitud);


--
-- Name: tipo_solicitud tipo_solicitud_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.tipo_solicitud
    ADD CONSTRAINT tipo_solicitud_pkey PRIMARY KEY (id_tipo_solicitud);


--
-- Name: bien_lote uq_bien_lote; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_lote
    ADD CONSTRAINT uq_bien_lote UNIQUE (id_bien, codigo_lote);


--
-- Name: empleado uq_empleado_persona; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT uq_empleado_persona UNIQUE (id_persona);


--
-- Name: inventario uq_inventario; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT uq_inventario UNIQUE (id_bodega, id_bien);


--
-- Name: inventario_lote uq_inventario_lote; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario_lote
    ADD CONSTRAINT uq_inventario_lote UNIQUE (id_bodega, id_bien_lote);


--
-- Name: rol_permiso uq_rol_permiso; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol_permiso
    ADD CONSTRAINT uq_rol_permiso UNIQUE (id_rol, id_permiso);


--
-- Name: usuario uq_usuario_empleado; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT uq_usuario_empleado UNIQUE (id_empleado);


--
-- Name: usuario_rol uq_usuario_rol; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT uq_usuario_rol UNIQUE (id_usuario, id_rol);


--
-- Name: usuario usuario_nombre_usuario_key; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_nombre_usuario_key UNIQUE (nombre_usuario);


--
-- Name: usuario_permiso usuario_permiso_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_permiso
    ADD CONSTRAINT usuario_permiso_pkey PRIMARY KEY (id_usuario, id_permiso);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario);


--
-- Name: usuario_rol usuario_rol_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_pkey PRIMARY KEY (id_usuario_rol);


--
-- Name: valor_bien valor_bien_pkey; Type: CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.valor_bien
    ADD CONSTRAINT valor_bien_pkey PRIMARY KEY (id_valor_bien);


--
-- Name: idx_bien_proveedor; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_bien_proveedor ON public.bien USING btree (id_proveedor);


--
-- Name: idx_bien_tipo; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_bien_tipo ON public.bien USING btree (id_tipo_bien);


--
-- Name: idx_bodega_sucursal; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_bodega_sucursal ON public.bodega USING btree (id_sucursal);


--
-- Name: idx_empleado_persona; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_empleado_persona ON public.empleado USING btree (id_persona);


--
-- Name: idx_empleado_sucursal; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_empleado_sucursal ON public.empleado USING btree (id_sucursal);


--
-- Name: idx_inventario_bodega_bien; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_inventario_bodega_bien ON public.inventario USING btree (id_bodega, id_bien);


--
-- Name: idx_inventario_lote_bodega; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_inventario_lote_bodega ON public.inventario_lote USING btree (id_bodega, id_bien_lote);


--
-- Name: idx_log_usuario_usuario; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_log_usuario_usuario ON public.log_usuario USING btree (id_usuario);


--
-- Name: idx_mantenimiento_bien; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_mantenimiento_bien ON public.mantenimiento USING btree (id_bien);


--
-- Name: idx_registro_bodegas; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_registro_bodegas ON public.registro USING btree (id_bodega_origen, id_bodega_destino);


--
-- Name: idx_registro_detalle_bien; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_registro_detalle_bien ON public.registro_detalle USING btree (id_bien);


--
-- Name: idx_registro_detalle_item; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_registro_detalle_item ON public.registro_detalle USING btree (id_bien_item);


--
-- Name: idx_registro_detalle_lote; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_registro_detalle_lote ON public.registro_detalle USING btree (id_bien_lote);


--
-- Name: idx_registro_detalle_registro; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_registro_detalle_registro ON public.registro_detalle USING btree (id_registro);


--
-- Name: idx_registro_fecha; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_registro_fecha ON public.registro USING btree (fecha_registro);


--
-- Name: idx_registro_tipo; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_registro_tipo ON public.registro USING btree (id_tipo_registro);


--
-- Name: idx_solicitud_empleado; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_solicitud_empleado ON public.solicitud_logistica USING btree (id_empleado);


--
-- Name: idx_solicitud_estado; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_solicitud_estado ON public.solicitud_logistica USING btree (id_estado_solicitud);


--
-- Name: idx_sucursal_empresa; Type: INDEX; Schema: public; Owner: juan
--

CREATE INDEX idx_sucursal_empresa ON public.sucursal USING btree (id_empresa);


--
-- Name: asignacion_bien asignacion_bien_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.asignacion_bien
    ADD CONSTRAINT asignacion_bien_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien) ON DELETE SET NULL;


--
-- Name: asignacion_bien asignacion_bien_id_empleado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.asignacion_bien
    ADD CONSTRAINT asignacion_bien_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES public.empleado(id_empleado) ON DELETE SET NULL;


--
-- Name: asignacion_bien asignacion_bien_id_registro_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.asignacion_bien
    ADD CONSTRAINT asignacion_bien_id_registro_fkey FOREIGN KEY (id_registro) REFERENCES public.registro(id_registro) ON DELETE SET NULL;


--
-- Name: bien bien_id_proveedor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien
    ADD CONSTRAINT bien_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor) ON DELETE SET NULL;


--
-- Name: bien bien_id_tipo_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien
    ADD CONSTRAINT bien_id_tipo_bien_fkey FOREIGN KEY (id_tipo_bien) REFERENCES public.tipo_bien(id_tipo_bien) ON DELETE SET NULL;


--
-- Name: bien bien_id_valor_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien
    ADD CONSTRAINT bien_id_valor_bien_fkey FOREIGN KEY (id_valor_bien) REFERENCES public.valor_bien(id_valor_bien) ON DELETE SET NULL;


--
-- Name: bien_item bien_item_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_item
    ADD CONSTRAINT bien_item_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien) ON DELETE CASCADE;


--
-- Name: bien_item bien_item_id_bodega_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_item
    ADD CONSTRAINT bien_item_id_bodega_fkey FOREIGN KEY (id_bodega) REFERENCES public.bodega(id_bodega) ON DELETE SET NULL;


--
-- Name: bien_item bien_item_id_empleado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_item
    ADD CONSTRAINT bien_item_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES public.empleado(id_empleado) ON DELETE SET NULL;


--
-- Name: bien_lote bien_lote_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_lote
    ADD CONSTRAINT bien_lote_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien) ON DELETE CASCADE;


--
-- Name: bien_lote bien_lote_id_proveedor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bien_lote
    ADD CONSTRAINT bien_lote_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor) ON DELETE SET NULL;


--
-- Name: bodega bodega_id_sucursal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.bodega
    ADD CONSTRAINT bodega_id_sucursal_fkey FOREIGN KEY (id_sucursal) REFERENCES public.sucursal(id_sucursal) ON DELETE SET NULL;


--
-- Name: caracteristica_bien caracteristica_bien_id_tipo_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.caracteristica_bien
    ADD CONSTRAINT caracteristica_bien_id_tipo_bien_fkey FOREIGN KEY (id_tipo_bien) REFERENCES public.tipo_bien(id_tipo_bien) ON DELETE CASCADE;


--
-- Name: caracteristica_bien caracteristica_bien_id_tipo_campo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.caracteristica_bien
    ADD CONSTRAINT caracteristica_bien_id_tipo_campo_fkey FOREIGN KEY (id_tipo_campo) REFERENCES public.tipo_campo(id_tipo_campo) ON DELETE SET NULL;


--
-- Name: caracteristica_opcion caracteristica_opcion_id_caracteristica_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.caracteristica_opcion
    ADD CONSTRAINT caracteristica_opcion_id_caracteristica_bien_fkey FOREIGN KEY (id_caracteristica_bien) REFERENCES public.caracteristica_bien(id_caracteristica_bien) ON DELETE CASCADE;


--
-- Name: correo_persona correo_persona_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.correo_persona
    ADD CONSTRAINT correo_persona_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona) ON DELETE SET NULL;


--
-- Name: direccion_persona direccion_persona_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.direccion_persona
    ADD CONSTRAINT direccion_persona_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona) ON DELETE SET NULL;


--
-- Name: empleado empleado_id_departamento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_id_departamento_fkey FOREIGN KEY (id_departamento) REFERENCES public.departamento(id_departamento) ON DELETE SET NULL;


--
-- Name: empleado empleado_id_estatus_empleado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_id_estatus_empleado_fkey FOREIGN KEY (id_estatus_empleado) REFERENCES public.estatus_empleado(id_estatus_empleado) ON DELETE SET NULL;


--
-- Name: empleado empleado_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona) ON DELETE SET NULL;


--
-- Name: empleado empleado_id_puesto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_id_puesto_fkey FOREIGN KEY (id_puesto) REFERENCES public.puesto(id_puesto) ON DELETE SET NULL;


--
-- Name: empleado empleado_id_sucursal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_id_sucursal_fkey FOREIGN KEY (id_sucursal) REFERENCES public.sucursal(id_sucursal) ON DELETE SET NULL;


--
-- Name: kardex fk_kardex_bodega; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.kardex
    ADD CONSTRAINT fk_kardex_bodega FOREIGN KEY (id_bodega) REFERENCES public.bodega(id_bodega);


--
-- Name: inventario inventario_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT inventario_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien) ON DELETE RESTRICT;


--
-- Name: inventario inventario_id_bodega_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT inventario_id_bodega_fkey FOREIGN KEY (id_bodega) REFERENCES public.bodega(id_bodega) ON DELETE CASCADE;


--
-- Name: inventario_lote inventario_lote_id_bien_lote_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario_lote
    ADD CONSTRAINT inventario_lote_id_bien_lote_fkey FOREIGN KEY (id_bien_lote) REFERENCES public.bien_lote(id_bien_lote) ON DELETE CASCADE;


--
-- Name: inventario_lote inventario_lote_id_bodega_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.inventario_lote
    ADD CONSTRAINT inventario_lote_id_bodega_fkey FOREIGN KEY (id_bodega) REFERENCES public.bodega(id_bodega) ON DELETE CASCADE;


--
-- Name: kardex kardex_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.kardex
    ADD CONSTRAINT kardex_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien);


--
-- Name: log_cambios log_cambios_id_log_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.log_cambios
    ADD CONSTRAINT log_cambios_id_log_usuario_fkey FOREIGN KEY (id_log_usuario) REFERENCES public.log_usuario(id_log_usuario) ON DELETE CASCADE;


--
-- Name: log_usuario log_usuario_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.log_usuario
    ADD CONSTRAINT log_usuario_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario) ON DELETE SET NULL;


--
-- Name: mantenimiento mantenimiento_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien) ON DELETE SET NULL;


--
-- Name: mantenimiento mantenimiento_id_documento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_documento_fkey FOREIGN KEY (id_documento) REFERENCES public.documento(id_documento) ON DELETE SET NULL;


--
-- Name: mantenimiento mantenimiento_id_proveedor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedor(id_proveedor) ON DELETE SET NULL;


--
-- Name: mantenimiento mantenimiento_id_tipo_mantenimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_tipo_mantenimiento_fkey FOREIGN KEY (id_tipo_mantenimiento) REFERENCES public.tipo_mantenimiento(id_tipo_mantenimiento) ON DELETE SET NULL;


--
-- Name: registro_caracteristica registro_caracteristica_id_caracteristica_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_caracteristica
    ADD CONSTRAINT registro_caracteristica_id_caracteristica_bien_fkey FOREIGN KEY (id_caracteristica_bien) REFERENCES public.caracteristica_bien(id_caracteristica_bien) ON DELETE RESTRICT;


--
-- Name: registro_caracteristica registro_caracteristica_id_opcion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_caracteristica
    ADD CONSTRAINT registro_caracteristica_id_opcion_fkey FOREIGN KEY (id_opcion) REFERENCES public.caracteristica_opcion(id_caracteristica_opcion) ON DELETE SET NULL;


--
-- Name: registro_caracteristica registro_caracteristica_id_registro_detalle_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_caracteristica
    ADD CONSTRAINT registro_caracteristica_id_registro_detalle_fkey FOREIGN KEY (id_registro_detalle) REFERENCES public.registro_detalle(id_registro_detalle) ON DELETE CASCADE;


--
-- Name: registro_detalle registro_detalle_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_detalle
    ADD CONSTRAINT registro_detalle_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien) ON DELETE SET NULL;


--
-- Name: registro_detalle registro_detalle_id_bien_item_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_detalle
    ADD CONSTRAINT registro_detalle_id_bien_item_fkey FOREIGN KEY (id_bien_item) REFERENCES public.bien_item(id_bien_item) ON DELETE SET NULL;


--
-- Name: registro_detalle registro_detalle_id_bien_lote_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_detalle
    ADD CONSTRAINT registro_detalle_id_bien_lote_fkey FOREIGN KEY (id_bien_lote) REFERENCES public.bien_lote(id_bien_lote) ON DELETE SET NULL;


--
-- Name: registro_detalle registro_detalle_id_registro_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro_detalle
    ADD CONSTRAINT registro_detalle_id_registro_fkey FOREIGN KEY (id_registro) REFERENCES public.registro(id_registro) ON DELETE CASCADE;


--
-- Name: registro registro_id_bodega_destino_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_id_bodega_destino_fkey FOREIGN KEY (id_bodega_destino) REFERENCES public.bodega(id_bodega) ON DELETE SET NULL;


--
-- Name: registro registro_id_bodega_origen_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_id_bodega_origen_fkey FOREIGN KEY (id_bodega_origen) REFERENCES public.bodega(id_bodega) ON DELETE SET NULL;


--
-- Name: registro registro_id_documento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_id_documento_fkey FOREIGN KEY (id_documento) REFERENCES public.documento(id_documento) ON DELETE SET NULL;


--
-- Name: registro registro_id_empleado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES public.empleado(id_empleado) ON DELETE SET NULL;


--
-- Name: registro registro_id_solicitud_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_id_solicitud_fkey FOREIGN KEY (id_solicitud) REFERENCES public.solicitud_logistica(id_solicitud) ON DELETE SET NULL;


--
-- Name: registro registro_id_tipo_registro_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_id_tipo_registro_fkey FOREIGN KEY (id_tipo_registro) REFERENCES public.tipo_registro(id_tipo_registro) ON DELETE SET NULL;


--
-- Name: registro registro_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.registro
    ADD CONSTRAINT registro_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario) ON DELETE SET NULL;


--
-- Name: rol_permiso rol_permiso_id_permiso_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol_permiso
    ADD CONSTRAINT rol_permiso_id_permiso_fkey FOREIGN KEY (id_permiso) REFERENCES public.permiso(id_permiso) ON DELETE CASCADE;


--
-- Name: rol_permiso rol_permiso_id_rol_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.rol_permiso
    ADD CONSTRAINT rol_permiso_id_rol_fkey FOREIGN KEY (id_rol) REFERENCES public.rol(id_rol) ON DELETE CASCADE;


--
-- Name: solicitud_detalle solicitud_detalle_id_bien_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_detalle
    ADD CONSTRAINT solicitud_detalle_id_bien_fkey FOREIGN KEY (id_bien) REFERENCES public.bien(id_bien) ON DELETE SET NULL;


--
-- Name: solicitud_detalle solicitud_detalle_id_solicitud_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_detalle
    ADD CONSTRAINT solicitud_detalle_id_solicitud_fkey FOREIGN KEY (id_solicitud) REFERENCES public.solicitud_logistica(id_solicitud) ON DELETE CASCADE;


--
-- Name: solicitud_logistica solicitud_logistica_id_empleado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_logistica
    ADD CONSTRAINT solicitud_logistica_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES public.empleado(id_empleado) ON DELETE SET NULL;


--
-- Name: solicitud_logistica solicitud_logistica_id_estado_solicitud_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_logistica
    ADD CONSTRAINT solicitud_logistica_id_estado_solicitud_fkey FOREIGN KEY (id_estado_solicitud) REFERENCES public.estado_solicitud(id_estado_solicitud) ON DELETE SET NULL;


--
-- Name: solicitud_logistica solicitud_logistica_id_tipo_solicitud_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.solicitud_logistica
    ADD CONSTRAINT solicitud_logistica_id_tipo_solicitud_fkey FOREIGN KEY (id_tipo_solicitud) REFERENCES public.tipo_solicitud(id_tipo_solicitud) ON DELETE SET NULL;


--
-- Name: sucursal sucursal_id_empresa_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.sucursal
    ADD CONSTRAINT sucursal_id_empresa_fkey FOREIGN KEY (id_empresa) REFERENCES public.empresa(id_empresa) ON DELETE SET NULL;


--
-- Name: telefono_persona telefono_persona_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.telefono_persona
    ADD CONSTRAINT telefono_persona_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona) ON DELETE SET NULL;


--
-- Name: usuario usuario_id_empleado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES public.empleado(id_empleado) ON DELETE SET NULL;


--
-- Name: usuario_permiso usuario_permiso_id_permiso_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_permiso
    ADD CONSTRAINT usuario_permiso_id_permiso_fkey FOREIGN KEY (id_permiso) REFERENCES public.permiso(id_permiso) ON DELETE CASCADE;


--
-- Name: usuario_permiso usuario_permiso_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_permiso
    ADD CONSTRAINT usuario_permiso_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario) ON DELETE CASCADE;


--
-- Name: usuario_rol usuario_rol_id_rol_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_id_rol_fkey FOREIGN KEY (id_rol) REFERENCES public.rol(id_rol) ON DELETE CASCADE;


--
-- Name: usuario_rol usuario_rol_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: juan
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 3yUSmcOBlQGwpb2TZzwjS7nG4rfSlM9f3flMwMvWtu3ZJBaekaj4lfNrPr6C9J3

