/*
 * PoE2 Market : lib/ggg-auth.js
 *
 * Вход через pathofexile.com по OAuth 2.1 — так, как это предусмотрено для desktop-приложений:
 * публичный клиент, Authorization Code + PKCE, локальный redirect, без client_secret.
 * （Официальная документация: pathofexile.com/developer/docs/authorization.）
 *
 * Что это даёт: имя аккаунта подставляется само, и по желанию можно читать свои вкладки и персонажей.
 * Токены хранятся только на этой машине в .state/oauth.json; access — 10 часов, refresh — 7 дней.
 *
 * Секретов здесь нет: публичному клиенту client_secret не положен, а PKCE-проверка живёт в памяти
 * процесса до самого обмена кода на токен.
 */

'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const STATE_DIR = process.env.POE2_MARKET_STATE || path.join(__dirname, '..', '.state');
const TOKEN_FILE = path.join(STATE_DIR, 'oauth.json');
const PENDING_FILE = path.join(STATE_DIR, 'oauth-pending.json');

const AUTHORIZE_URL = 'https://www.pathofexile.com/oauth/authorize';
const TOKEN_URL = 'https://www.pathofexile.com/oauth/token';
const API_BASE = 'https://api.pathofexile.com';
/** Скоупы публичного клиента: service:* ему недоступны. */
const DEFAULT_SCOPES = ['account:profile', 'account:characters', 'account:stashes'];
const USER_AGENT = 'OAuth dsh-poe2-market/0.1.0 (contact: local tool)';

function base64url(buffer) {
  return buffer.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Шаг 1 PKCE: verifier и его S256-хэш. Проверяется тестом — от этого зависит, примет ли GGG вход.
 * @returns {{verifier: string, challenge: string}}
 */
function pkcePair() {
  const verifier = base64url(crypto.randomBytes(32));
  const challenge = base64url(crypto.createHash('sha256').update(verifier).digest());
  return { verifier, challenge };
}

/** Ссылка, на которую отправляем пользователя для подтверждения доступа. */
function buildAuthUrl(opts) {
  const params = new URLSearchParams({
    client_id: opts.clientId,
    response_type: 'code',
    scope: (opts.scopes || DEFAULT_SCOPES).join(' '),
    state: opts.state,
    redirect_uri: opts.redirectUri,
    code_challenge: opts.challenge,
    code_challenge_method: 'S256',
  });
  return `${AUTHORIZE_URL}?${params.toString()}`;
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}

function readTokens() {
  return readJson(TOKEN_FILE);
}

function saveTokens(tokens) {
  writeJson(TOKEN_FILE, tokens);
  return tokens;
}

function clearTokens() {
  try {
    fs.unlinkSync(TOKEN_FILE);
  } catch {
    // уже нет — и хорошо
  }
}

function savePending(pending) {
  writeJson(PENDING_FILE, pending);
}

function takePending() {
  const pending = readJson(PENDING_FILE);
  try {
    fs.unlinkSync(PENDING_FILE);
  } catch {
    // нечего удалять
  }
  return pending;
}

async function postForm(url, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': USER_AGENT,
      Accept: 'application/json',
    },
    body: new URLSearchParams(body).toString(),
  });
  const text = await response.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { raw: text.slice(0, 300) };
  }
  if (!response.ok) {
    const detail = parsed && (parsed.error_description || parsed.error || parsed.raw);
    throw new Error(`OAuth ${response.status}: ${detail || text.slice(0, 200)}`);
  }
  return parsed;
}

/** Обмен кода на токены. Код живёт 30 секунд — обмениваем сразу после редиректа. */
async function exchangeCode(opts) {
  const tokens = await postForm(TOKEN_URL, {
    client_id: opts.clientId,
    grant_type: 'authorization_code',
    code: opts.code,
    redirect_uri: opts.redirectUri,
    scope: (opts.scopes || DEFAULT_SCOPES).join(' '),
    code_verifier: opts.verifier,
    ...(opts.clientSecret ? { client_secret: opts.clientSecret } : {}),
  });
  return storeTokens(tokens);
}

/** Обновление access-токена: refresh живёт 7 дней и наследует срок жизни. */
async function refreshTokens(opts) {
  const current = opts.tokens || readTokens();
  if (!current || !current.refreshToken) throw new Error('нет refresh-токена: нужен повторный вход');
  const tokens = await postForm(TOKEN_URL, {
    client_id: opts.clientId,
    grant_type: 'refresh_token',
    refresh_token: current.refreshToken,
    ...(opts.clientSecret ? { client_secret: opts.clientSecret } : {}),
  });
  return storeTokens(tokens, current);
}

function storeTokens(tokens, previous) {
  const stored = {
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token || (previous && previous.refreshToken) || null,
    tokenType: tokens.token_type || 'bearer',
    scope: tokens.scope || null,
    username: tokens.username || (previous && previous.username) || null,
    sub: tokens.sub || (previous && previous.sub) || null,
    expiresAt: tokens.expires_in ? new Date(Date.now() + tokens.expires_in * 1000).toISOString() : null,
    savedAt: new Date().toISOString(),
  };
  return saveTokens(stored);
}

function isExpired(tokens, skewMs = 60 * 1000) {
  if (!tokens || !tokens.accessToken) return true;
  if (!tokens.expiresAt) return false;
  return Date.now() > new Date(tokens.expiresAt).getTime() - skewMs;
}

/** Запрос к API от имени пользователя: токен подставляется сам и обновляется при истечении. */
async function authorizedGet(pathname, opts = {}) {
  const clientId = opts.clientId;
  let tokens = readTokens();
  if (!tokens) throw new Error('нет входа: сначала авторизуйтесь через pathofexile.com');
  if (isExpired(tokens)) {
    if (!clientId) throw new Error('токен истёк, а client_id не задан — нужен повторный вход');
    tokens = await refreshTokens({ clientId, clientSecret: opts.clientSecret });
  }
  const response = await fetch(`${API_BASE}${pathname}`, {
    headers: {
      Authorization: `Bearer ${tokens.accessToken}`,
      'User-Agent': USER_AGENT,
      Accept: 'application/json',
    },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`API ${response.status}: ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

/** Состояние входа для страницы. */
function authStatus() {
  const tokens = readTokens();
  if (!tokens || !tokens.accessToken) {
    return { authorized: false, note: 'вход не выполнен' };
  }
  return {
    authorized: true,
    username: tokens.username,
    scope: tokens.scope,
    expiresAt: tokens.expiresAt,
    expiresInSeconds: tokens.expiresAt
      ? Math.max(0, Math.round((new Date(tokens.expiresAt).getTime() - Date.now()) / 1000))
      : null,
    refreshUntil: null,
    hasRefresh: Boolean(tokens.refreshToken),
    note: isExpired(tokens) ? 'токен истёк, будет обновлён при следующем запросе' : 'вход выполнен',
  };
}

module.exports = {
  AUTHORIZE_URL,
  TOKEN_URL,
  API_BASE,
  TOKEN_FILE,
  PENDING_FILE,
  DEFAULT_SCOPES,
  USER_AGENT,
  pkcePair,
  buildAuthUrl,
  exchangeCode,
  refreshTokens,
  readTokens,
  saveTokens,
  clearTokens,
  savePending,
  takePending,
  isExpired,
  authorizedGet,
  authStatus,
};
