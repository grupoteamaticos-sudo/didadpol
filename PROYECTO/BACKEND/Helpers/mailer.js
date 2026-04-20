const nodemailer = require('nodemailer');

let transporter = null;

function getTransporter() {
  if (transporter) return transporter;

  transporter = nodemailer.createTransport({
    host: process.env.MAIL_HOST || 'smtp.gmail.com',
    port: Number(process.env.MAIL_PORT || 465),
    secure: String(process.env.MAIL_SECURE || 'true') === 'true',
    auth: {
      user: process.env.MAIL_USER,
      pass: process.env.MAIL_PASS
    },
    // Timeouts para que SMTP falle rapido si hay bloqueo de red / credenciales
    connectionTimeout: 10000,   // 10s TCP connect
    greetingTimeout:   10000,   // 10s handshake SMTP
    socketTimeout:     15000,   // 15s inactividad
    pool: false
  });

  return transporter;
}

async function sendMail({ to, subject, html, text }) {
  const t = getTransporter();
  const from = process.env.MAIL_FROM || process.env.MAIL_USER;

  return t.sendMail({ from, to, subject, html, text });
}

function buildResetTokenEmail({ nombre, token, ttlMin }) {
  const safeNombre = nombre || 'Usuario';
  const safeToken = token || '';
  const safeTtl = ttlMin || 15;

  const text = `Hola ${safeNombre},

Recibimos una solicitud para recuperar tu contrasena en DIDADPOL - Sistema de Bienes y Logistica.

Tu codigo de recuperacion es: ${safeToken}

El codigo es valido por ${safeTtl} minutos. Si vos no solicitaste esto, ignora este correo.

--
DIDADPOL
`;

  const html = `
<div style="font-family: Arial, Helvetica, sans-serif; max-width:520px; margin:0 auto; background:#f8fafc; padding:24px; border-radius:12px; color:#1e293b;">
  <div style="text-align:center; padding-bottom:16px; border-bottom:3px solid #f59e0b;">
    <h2 style="margin:0; color:#111827;">DIDADPOL</h2>
    <p style="margin:4px 0 0; color:#6b7280; font-size:13px;">Sistema de Bienes y Logistica</p>
  </div>

  <div style="padding:20px 4px;">
    <p style="margin:0 0 12px;">Hola <strong>${safeNombre}</strong>,</p>
    <p style="margin:0 0 12px;">
      Recibimos una solicitud para recuperar tu contrasena. Usa el siguiente codigo en la
      pantalla de recuperacion para continuar:
    </p>

    <div style="margin:20px 0; text-align:center;">
      <div style="display:inline-block; background:#fff; border:2px dashed #f59e0b; border-radius:10px; padding:16px 28px; letter-spacing:6px; font-size:28px; font-weight:800; color:#b45309;">
        ${safeToken}
      </div>
    </div>

    <p style="margin:0 0 12px; color:#475569; font-size:14px;">
      Este codigo expira en <strong>${safeTtl} minutos</strong>.
    </p>
    <p style="margin:0; color:#6b7280; font-size:12px;">
      Si vos no solicitaste este cambio, ignora este correo y tu contrasena seguira siendo la misma.
    </p>
  </div>

  <div style="border-top:1px solid #e5e7eb; padding-top:12px; text-align:center; color:#94a3b8; font-size:11px;">
    Este es un mensaje automatico. No respondas a este correo.
  </div>
</div>
`;

  return { subject: 'Codigo de recuperacion - DIDADPOL', text, html };
}

function buildPinResetEmail({ nombre, token, ttlMin }) {
  const safeNombre = nombre || 'Usuario';
  const safeToken = token || '';
  const safeTtl = ttlMin || 10;

  const text = `Hola ${safeNombre},

Solicitaste restablecer tu PIN OTP en DIDADPOL - Sistema de Bienes y Logistica.

Tu codigo de verificacion es: ${safeToken}

El codigo es valido por ${safeTtl} minutos. Si vos no solicitaste esto, ignora este correo.

--
DIDADPOL
`;

  const html = `
<div style="font-family: Arial, Helvetica, sans-serif; max-width:520px; margin:0 auto; background:#f8fafc; padding:24px; border-radius:12px; color:#1e293b;">
  <div style="text-align:center; padding-bottom:16px; border-bottom:3px solid #2563eb;">
    <h2 style="margin:0; color:#111827;">DIDADPOL</h2>
    <p style="margin:4px 0 0; color:#6b7280; font-size:13px;">Restablecer PIN OTP</p>
  </div>

  <div style="padding:20px 4px;">
    <p style="margin:0 0 12px;">Hola <strong>${safeNombre}</strong>,</p>
    <p style="margin:0 0 12px;">
      Solicitaste restablecer tu PIN. Usa el siguiente codigo de verificacion:
    </p>

    <div style="margin:20px 0; text-align:center;">
      <div style="display:inline-block; background:#fff; border:2px dashed #2563eb; border-radius:10px; padding:16px 28px; letter-spacing:8px; font-size:32px; font-weight:800; color:#1d4ed8;">
        ${safeToken}
      </div>
    </div>

    <p style="margin:0 0 12px; color:#475569; font-size:14px;">
      Este codigo expira en <strong>${safeTtl} minutos</strong>.
    </p>
    <p style="margin:0; color:#6b7280; font-size:12px;">
      Si vos no solicitaste este cambio, ignora este correo.
    </p>
  </div>

  <div style="border-top:1px solid #e5e7eb; padding-top:12px; text-align:center; color:#94a3b8; font-size:11px;">
    Este es un mensaje automatico. No respondas a este correo.
  </div>
</div>
`;

  return { subject: 'Codigo de verificacion para restablecer PIN - DIDADPOL', text, html };
}

module.exports = {
  sendMail,
  buildResetTokenEmail,
  buildPinResetEmail
};
