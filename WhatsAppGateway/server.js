/*
 * BizFlow WhatsApp Gateway
 *
 * Links each shop's own WhatsApp number (scan a QR, like WhatsApp Web) and lets
 * the BizFlow API send bills from it and hear customer replies.
 *
 *   API  --POST /sessions/:biz/send-->  gateway  --WhatsApp-->  customer
 *   API  <--POST /api/whatsapp/inbound--  gateway  <--WhatsApp--  customer
 *
 * One Baileys socket per business. Login keys live in ./sessions/biz-<id> so a
 * restart reconnects without a new scan. Only the API may call this service:
 * every request must carry X-Gateway-Secret, and it listens on localhost only.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import QRCode from 'qrcode';
import pino from 'pino';
import makeWASocket, {
  Browsers,
  DisconnectReason,
  fetchLatestBaileysVersion,
  isJidBroadcast,
  isJidGroup,
  isJidNewsletter,
  isJidStatusBroadcast,
  isLidUser,
  isPnUser,
  jidNormalizedUser,
  useMultiFileAuthState,
} from 'baileys';

const here = path.dirname(fileURLToPath(import.meta.url));
const config = JSON.parse(fs.readFileSync(path.join(here, 'config.json'), 'utf8'));

const PORT         = Number(process.env.GATEWAY_PORT ?? config.port ?? 5055);
const HOST         = process.env.GATEWAY_HOST ?? config.host ?? '127.0.0.1';
const SECRET       = process.env.GATEWAY_SECRET ?? config.secret;
const API_URL      = (process.env.BIZFLOW_API_URL ?? config.apiUrl ?? 'http://localhost:5000').replace(/\/$/, '');
const COUNTRY_CODE = String(config.countryCode ?? '91');
const SESSIONS_DIR = path.resolve(here, config.sessionsDir ?? 'sessions');
// Spacing between two outgoing messages on the same number. Bursts are the
// quickest way to get a linked number flagged, so every send is queued.
const SEND_GAP_MS  = Number(config.sendGapMs ?? 2500);

if (!SECRET || SECRET.length < 16) {
  console.error('config.json "secret" must be set (16+ chars) and match WhatsApp:GatewaySecret in the API.');
  process.exit(1);
}
fs.mkdirSync(SESSIONS_DIR, { recursive: true });

const log = pino({ level: config.logLevel ?? 'info' });
const quiet = pino({ level: 'silent' });

/** @type {Map<number, Session>} */
const sessions = new Map();

/**
 * @typedef {object} Session
 * @property {number} businessId
 * @property {any} sock
 * @property {'connecting'|'qr'|'connected'|'disconnected'} status
 * @property {string|null} qr        data: URL of the current QR image
 * @property {string|null} phone     the linked number, digits only
 * @property {string|null} name      the WhatsApp profile name
 * @property {string|null} error
 * @property {boolean} stopping      set on logout so close does not reconnect
 * @property {Promise<unknown>} queue
 */

const authDir = (bizId) => path.join(SESSIONS_DIR, `biz-${bizId}`);
const digitsOf = (s) => String(s ?? '').replace(/\D/g, '');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function toJid(mobile) {
  let d = digitsOf(mobile);
  if (d.length === 10) d = COUNTRY_CODE + d;
  return `${d}@s.whatsapp.net`;
}

function view(s) {
  return s
    ? { businessId: s.businessId, status: s.status, qr: s.qr, phone: s.phone, name: s.name, error: s.error }
    : { status: 'disconnected', qr: null, phone: null, name: null, error: null };
}

// ------------------------------------------------------------------ sockets
async function startSession(bizId) {
  const existing = sessions.get(bizId);
  if (existing && existing.status !== 'disconnected') return existing;

  /** @type {Session} */
  const s = existing ?? {
    businessId: bizId, sock: null, status: 'connecting', qr: null,
    phone: null, name: null, error: null, stopping: false, queue: Promise.resolve(),
  };
  s.status = 'connecting';
  s.error = null;
  s.stopping = false;
  sessions.set(bizId, s);

  const { state, saveCreds } = await useMultiFileAuthState(authDir(bizId));
  const { version } = await fetchLatestBaileysVersion().catch(() => ({ version: undefined }));

  const sock = makeWASocket({
    version,
    auth: state,
    logger: quiet,
    browser: Browsers.ubuntu('BizFlow'),
    syncFullHistory: false,
    markOnlineOnConnect: false,
    generateHighQualityLinkPreview: false,
  });
  s.sock = sock;

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', async (u) => {
    if (s.sock !== sock) return; // a newer socket replaced this one

    if (u.qr) {
      s.status = 'qr';
      s.qr = await QRCode.toDataURL(u.qr, { margin: 1, width: 320 });
      log.info({ bizId }, 'QR ready - waiting for scan');
    }

    if (u.connection === 'open') {
      s.status = 'connected';
      s.qr = null;
      s.phone = digitsOf(jidNormalizedUser(sock.user?.id).split('@')[0]);
      s.name = sock.user?.name ?? sock.user?.verifiedName ?? null;
      log.info({ bizId, phone: s.phone }, 'WhatsApp linked');
    }

    if (u.connection === 'close') {
      const code = u.lastDisconnect?.error?.output?.statusCode;
      s.qr = null;

      if (code === DisconnectReason.loggedOut || s.stopping) {
        // Unlinked from the phone (or by us) - the saved keys are useless now.
        s.status = 'disconnected';
        s.phone = null;
        s.name = null;
        s.error = s.stopping ? null : 'WhatsApp was logged out from the phone.';
        fs.rmSync(authDir(bizId), { recursive: true, force: true });
        log.warn({ bizId }, 'WhatsApp logged out');
        return;
      }

      // Anything else (restart required, network drop) - reconnect with the same keys.
      s.status = 'connecting';
      log.info({ bizId, code }, 'connection closed - reconnecting');
      await sleep(code === DisconnectReason.restartRequired ? 0 : 3000);
      s.status = 'disconnected'; // lets startSession proceed
      startSession(bizId).catch((e) => log.error(e, 'reconnect failed'));
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return; // skip history sync
    for (const m of messages) {
      try {
        await forwardInbound(s, m);
      } catch (e) {
        log.error({ err: e.message, bizId }, 'could not forward inbound message');
      }
    }
  });

  return s;
}

async function stopSession(bizId) {
  const s = sessions.get(bizId);
  if (s?.sock) {
    s.stopping = true;
    try { await s.sock.logout(); } catch { /* already gone */ }
    try { s.sock.end(undefined); } catch { /* ignore */ }
  }
  fs.rmSync(authDir(bizId), { recursive: true, force: true });
  sessions.delete(bizId);
}

// ------------------------------------------------------------------ inbound
function textOf(msg) {
  const c = msg.message ?? {};
  const inner = c.ephemeralMessage?.message ?? c.viewOnceMessage?.message ?? c;
  return (
    inner.conversation ??
    inner.extendedTextMessage?.text ??
    inner.imageMessage?.caption ??
    inner.videoMessage?.caption ??
    inner.documentMessage?.caption ??
    inner.buttonsResponseMessage?.selectedDisplayText ??
    inner.listResponseMessage?.title ??
    null
  );
}

function kindOf(msg) {
  const c = msg.message ?? {};
  if (c.imageMessage) return 'image';
  if (c.documentMessage) return 'document';
  if (c.audioMessage) return 'audio';
  if (c.videoMessage) return 'video';
  if (c.stickerMessage) return 'sticker';
  if (c.locationMessage) return 'location';
  return 'text';
}

/** WhatsApp now often addresses chats by LID; the API needs the real mobile. */
async function phoneOf(sock, key) {
  const candidates = [key.remoteJid, key.remoteJidAlt, key.participant, key.participantAlt];
  for (const j of candidates) if (j && isPnUser(j)) return digitsOf(j.split('@')[0]);
  for (const j of candidates) {
    if (j && isLidUser(j)) {
      const pn = await sock.signalRepository?.lidMapping?.getPNForLID(j).catch(() => null);
      if (pn) return digitsOf(pn.split('@')[0].split(':')[0]);
    }
  }
  return null;
}

async function forwardInbound(s, m) {
  const jid = m.key?.remoteJid;
  if (!jid || m.key.fromMe) return;
  // Only one-to-one chats. Groups, status updates and channels never reach the API.
  if (isJidGroup(jid) || isJidBroadcast(jid) || isJidStatusBroadcast(jid) || isJidNewsletter(jid)) return;
  if (!m.message || m.message.protocolMessage || m.message.reactionMessage) return;

  const mobile = await phoneOf(s.sock, m.key);
  if (!mobile) {
    log.warn({ bizId: s.businessId, jid }, 'could not resolve sender number - skipped');
    return;
  }

  const kind = kindOf(m);
  const body = {
    businessId: s.businessId,
    fromMobile: mobile.length > 10 ? mobile.slice(-10) : mobile,
    text: textOf(m) ?? `[${kind}]`,
    kind,
    messageId: m.key.id,
    pushName: m.pushName ?? null,
    timestamp: Number(m.messageTimestamp ?? Math.floor(Date.now() / 1000)),
  };

  const res = await fetch(`${API_URL}/api/whatsapp/inbound`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Gateway-Secret': SECRET },
    body: JSON.stringify(body),
  });
  if (!res.ok) log.warn({ status: res.status, bizId: s.businessId }, 'API rejected inbound message');
}

// ------------------------------------------------------------------ outbound
function enqueue(s, job) {
  const run = s.queue.then(job, job);
  s.queue = run.then(() => sleep(SEND_GAP_MS), () => sleep(SEND_GAP_MS));
  return run;
}

async function send(s, { to, text, document }) {
  const jid = toJid(to);
  const [hit] = await s.sock.onWhatsApp(jid.split('@')[0]);
  if (!hit?.exists) {
    const err = new Error(`+${digitsOf(jid)} is not on WhatsApp.`);
    err.status = 422;
    throw err;
  }
  const target = hit.jid ?? jid;

  const sent = document?.base64
    ? await s.sock.sendMessage(target, {
        document: Buffer.from(document.base64, 'base64'),
        mimetype: document.mimeType ?? 'application/pdf',
        fileName: document.fileName ?? 'bill.pdf',
        caption: text ?? undefined,
      })
    : await s.sock.sendMessage(target, { text });

  return { id: sent?.key?.id ?? null };
}

// ------------------------------------------------------------------ http
const app = express();
app.use(express.json({ limit: '15mb' }));

app.use((req, res, next) => {
  if (req.path === '/health') return next();
  if (req.get('X-Gateway-Secret') !== SECRET) return res.status(401).json({ error: 'unauthorised' });
  next();
});

const bizParam = (req) => {
  const id = Number(req.params.biz);
  return Number.isInteger(id) && id > 0 ? id : null;
};

app.get('/health', (_req, res) => res.json({ status: 'ok', sessions: sessions.size }));

app.get('/sessions/:biz', (req, res) => {
  const id = bizParam(req);
  if (!id) return res.status(400).json({ error: 'bad business id' });
  res.json(view(sessions.get(id)));
});

/** Starts (or resumes) a session and waits briefly for a QR or a live link. */
app.post('/sessions/:biz/start', async (req, res) => {
  const id = bizParam(req);
  if (!id) return res.status(400).json({ error: 'bad business id' });
  try {
    const s = await startSession(id);
    for (let i = 0; i < 40 && s.status === 'connecting'; i++) await sleep(250);
    res.json(view(s));
  } catch (e) {
    log.error(e, 'start failed');
    res.status(500).json({ error: e.message });
  }
});

app.post('/sessions/:biz/logout', async (req, res) => {
  const id = bizParam(req);
  if (!id) return res.status(400).json({ error: 'bad business id' });
  await stopSession(id);
  res.json(view(null));
});

app.post('/sessions/:biz/send', async (req, res) => {
  const id = bizParam(req);
  if (!id) return res.status(400).json({ error: 'bad business id' });
  const s = sessions.get(id);
  if (!s || s.status !== 'connected') {
    return res.status(409).json({ error: 'This shop has not linked WhatsApp yet.' });
  }
  const { to, text, document } = req.body ?? {};
  if (!to || (!text && !document?.base64)) return res.status(400).json({ error: 'to and text are required' });

  try {
    res.json(await enqueue(s, () => send(s, { to, text, document })));
  } catch (e) {
    log.error({ err: e.message, bizId: id }, 'send failed');
    res.status(e.status ?? 502).json({ error: e.message });
  }
});

// Bring back every shop that was linked before the last restart.
for (const dir of fs.readdirSync(SESSIONS_DIR)) {
  const m = /^biz-(\d+)$/.exec(dir);
  if (m && fs.existsSync(path.join(SESSIONS_DIR, dir, 'creds.json'))) {
    startSession(Number(m[1])).catch((e) => log.error(e, `resume biz ${m[1]} failed`));
  }
}

app.listen(PORT, HOST, () => log.info(`WhatsApp gateway on http://${HOST}:${PORT} -> API ${API_URL}`));
