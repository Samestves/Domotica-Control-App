// Instalador del programa de las placas (ESP32) desde Chrome o Edge, con esptool-js, la herramienta oficial
// de Espressif. Pasos: 1) reinicia la placa y escucha qué programa tiene; 2) la pone en modo de carga y escribe
// el programa; 3) esptool le pide al ESP32 la huella (MD5) de lo escrito y la compara con el archivo;
// 4) la reinicia, espera su saludo «== Casa Domotica (casa-0.8) ==» y le pregunta PING, que responde PONG.
//
// #prueba en la dirección simula una placa (sin USB) para revisar la página: #prueba-otra (la placa tiene el
// programa de la otra), #prueba-boot (no entra sola en modo de carga), #prueba-error, #prueba-mudo y
// #prueba-nada (no aparece ninguna placa en la lista).
import { ESPLoader, Transport } from './lib/esptool-js-0.7.1.js';
import { ICONS } from './icons.js?v=774b99fcda';

const $ = (id) => document.getElementById(id);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const TEST = location.hash.startsWith('#prueba');
const BANNER = /==\s*([^=\n]+?)\s*\(((casa|carro)-[\w.]+)\)\s*==/g;

// Mismos parámetros que tool/cargar_esp32.ps1 (y que Arduino): el resultado es idéntico.
const FLASH = { flashMode: 'dio', flashFreq: '80m', flashSize: '4MB', eraseAll: false, compress: true };
const BAUD = 460800;

// Chips USB de las placas ESP32: la lista de Chrome muestra solo estos (no los puertos Bluetooth ni otros).
const USB_CHIPS = [
  { usbVendorId: 0x10c4 }, // Silicon Labs CP210x
  { usbVendorId: 0x1a86 }, // WCH CH340 / CH9102
  { usbVendorId: 0x0403 }, // FTDI
  { usbVendorId: 0x303a }, // Espressif (USB propio)
];

const SCREENS = ['home', 'nobrowser', 'work', 'end', 'boot', 'help'];
const PHASES = ['find', 'write', 'verify', 'boot'];
const RING = 2 * Math.PI * 76;

let manifest = null;
let board = null;
let port = null;
let writing = false;

// ---------- Iconos (los de la app) ----------
function icon(name, size = 20, color = 'currentColor') {
  const d = ICONS[name];
  if (!d) return '';
  return `<svg width="${size}" height="${size}" viewBox="0 -960 1024 1024" aria-hidden="true"><path fill="${color}" transform="scale(1,-1)" d="${d}"/></svg>`;
}
function paintIcons(root = document) {
  root.querySelectorAll('[data-icon]').forEach((el) => {
    el.innerHTML = icon(el.dataset.icon, Number(el.dataset.size || 20));
  });
}

// ---------- Registro para «Ver detalles técnicos» ----------
const lines = [];
function log(text) {
  lines.push(String(text).replace(/\s+$/, ''));
  $('log').textContent = lines.join('\n');
}

// ---------- Pantallas ----------
function screen(id) {
  for (const s of SCREENS) $(s).hidden = s !== id;
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function phase(name, title, detail = '') {
  if ($('phase').textContent !== title) {
    const box = $('phase-box');
    box.classList.remove('swap');
    void box.offsetWidth; // reinicia la animación
    box.classList.add('swap');
  }
  $('phase').textContent = title;
  $('phase-detail').textContent = detail;
  const i = PHASES.indexOf(name);
  document.querySelectorAll('.steps li').forEach((d, j) => {
    d.className = j < i ? 'done' : j === i ? 'on' : '';
  });
}

/// El anillo: girando mientras espera (null), o lleno según el avance (0 a 1).
function ring(frac) {
  const spin = frac === null;
  $('ring').classList.toggle('spin', spin);
  $('arc').style.strokeDashoffset = String(spin ? RING * 0.72 : RING * (1 - Math.max(0, Math.min(1, frac))));
  $('pct').innerHTML = spin ? '' : `<span>${Math.round(frac * 100)}<small>%</small></span>`;
}

// Cada tarjeta es su propio botón: un toque y empieza a instalar esa placa.
function renderTiles() {
  const box = $('tiles');
  box.innerHTML = '';
  for (const b of manifest.boards) {
    const t = document.createElement('button');
    t.type = 'button';
    t.className = 'tile';
    t.setAttribute('aria-label', `Instalar en ${b.short.toLowerCase()}, versión ${b.version}`);
    t.innerHTML = `<span class="row"><span class="disc">${icon(b.icon, 40)}</span></span>`
      + `<span><b>${b.name}</b><span class="spec"><span>Versión</span><strong>${b.version.replace(/^[a-z]+-/, '')}</strong></span>`
      + `<span class="cta">Instalar ${icon('arrow-right', 18)}</span></span>`;
    t.addEventListener('click', () => {
      board = b;
      try { localStorage.setItem('placa', b.id); } catch (_) {}
      start();
    });
    box.appendChild(t);
  }
}

function home() {
  writing = false;
  screen('home');
}

function end(kind, title, text, main, second) {
  writing = false;
  const icons = { warn: 'warning-circle-fill', bad: 'x-circle-fill' };
  $('end-badge').className = `badge ${kind}`;
  $('end-badge').innerHTML = kind === 'good' ? OK_MARK : icon(icons[kind], 96);
  $('end-title').textContent = title;
  $('end-text').textContent = text;
  $('end-main').textContent = main[0];
  $('end-main').onclick = main[1];
  $('end-second').hidden = !second;
  if (second) {
    $('end-second').textContent = second[0];
    $('end-second').onclick = second[1];
  }
  $('end-details').hidden = kind === 'good';
  $('end-details').open = false;
  screen('end');
}

// Listo: el círculo se dibuja, se rellena y la palomita aparece.
const OK_MARK = `<svg class="ok" viewBox="0 0 116 116" aria-hidden="true">
  <circle class="fill" cx="58" cy="58" r="50"/><circle class="pulse" cx="58" cy="58" r="50"/>
  <circle class="ring1" cx="58" cy="58" r="50"/><path d="M37 59 L51 73 L80 43"/></svg>`;

// Copiar: la palomita confirma unos segundos y vuelve a su texto.
async function copy(btn, text, done) {
  const lbl = btn.querySelector('.lbl');
  const ic = btn.querySelector('[data-icon]');
  const was = lbl.textContent;
  try { await navigator.clipboard.writeText(text); } catch (_) { return; }
  lbl.textContent = done;
  ic.innerHTML = icon('check', Number(ic.dataset.size));
  clearTimeout(btn._t);
  btn._t = setTimeout(() => { lbl.textContent = was; ic.innerHTML = icon('copy', Number(ic.dataset.size)); }, 2200);
}

// ---------- Tema claro u oscuro ----------
function paintTheme() {
  const t = document.documentElement.dataset.theme === 'claro' ? 'claro' : 'oscuro';
  for (const b of $('theme').querySelectorAll('button')) {
    b.setAttribute('aria-checked', String(b.dataset.t === t));
    b.tabIndex = b.dataset.t === t ? 0 : -1;
  }
  document.querySelector('meta[name="theme-color"]').content = t === 'oscuro' ? '#000000' : '#F3F3F4';
}
function setTheme(t, save) {
  const root = document.documentElement;
  root.classList.add('theming');
  root.dataset.theme = t;
  if (save) try { localStorage.setItem('tema', t); } catch (_) {}
  paintTheme();
  setTimeout(() => root.classList.remove('theming'), 400);
}
function initTheme() {
  paintTheme();
  for (const b of $('theme').querySelectorAll('button')) {
    b.onclick = () => setTheme(b.dataset.t, true);
    b.onkeydown = (e) => {
      if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) return;
      e.preventDefault();
      const other = b.dataset.t === 'claro' ? 'oscuro' : 'claro';
      setTheme(other, true);
      $('theme').querySelector(`[data-t="${other}"]`).focus();
    };
  }
  // Si nunca eligió, sigue al sistema también cuando este cambia.
  matchMedia('(prefers-color-scheme: light)').addEventListener('change', (e) => {
    let saved = null;
    try { saved = localStorage.getItem('tema'); } catch (_) {}
    if (!saved) setTheme(e.matches ? 'claro' : 'oscuro', false);
  });
}

// ---------- Hablar con la placa por el cable (115200, como el Monitor Serie) ----------
function parseBanner(text) {
  let last = null;
  for (const m of text.matchAll(BANNER)) last = { name: m[1], version: m[2], kind: m[3] };
  return last;
}

// Reinicia la placa normalmente y escucha lo que dice al arrancar. Con [expect], espera ese saludo;
// con [ping], después le escribe PING y espera PONG.
async function listen({ ms, expect = null, ping = false }) {
  if (TEST) return fakeListen({ expect });
  await port.open({ baudRate: 115200 });
  let text = '';
  let pong = false;
  const reader = port.readable.getReader();
  const dec = new TextDecoder();
  const pump = (async () => {
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        text += dec.decode(value, { stream: true });
      }
    } catch (_) { /* se canceló la lectura */ }
  })();
  try {
    // Reinicio normal: RTS baja EN; DTR apagado deja BOOT (GPIO0) arriba. Nunca DTR encendido con RTS apagado
    // mientras corre el programa: eso deja BOOT apretado y, a los 5 segundos, el programa borra su clave.
    await port.setSignals({ dataTerminalReady: false, requestToSend: true });
    await sleep(120);
    await port.setSignals({ dataTerminalReady: false, requestToSend: false });
    const seen = () => (expect ? text.includes(`(${expect})`) : parseBanner(text) !== null);
    const end = Date.now() + ms;
    while (Date.now() < end && !seen()) await sleep(80);
    if (ping && seen()) {
      await sleep(1500); // que termine de arrancar el Bluetooth y el Wi-Fi
      for (let i = 0; i < 3 && !pong; i++) {
        const from = text.length;
        const w = port.writable.getWriter();
        await w.write(new TextEncoder().encode('PING\n'));
        w.releaseLock();
        const end2 = Date.now() + 1500;
        while (Date.now() < end2 && !(pong = text.slice(from).includes('PONG'))) await sleep(80);
      }
    }
  } finally {
    try { await reader.cancel(); } catch (_) {}
    await pump;
    reader.releaseLock();
    await port.close();
  }
  const said = text.trim();
  log(said ? said.split(/\r?\n/).slice(-14).map((l) => `│ ${l}`).join('\n') : '│ (la placa no dijo nada)');
  return { text, pong };
}

async function download() {
  const out = [];
  for (const f of board.files) {
    const res = await fetch(f.url, { cache: 'no-store' });
    if (!res.ok) throw new Error(`${f.url}: respuesta ${res.status}`);
    const data = new Uint8Array(await res.arrayBuffer());
    if (data.length !== f.size || SparkMD5.ArrayBuffer.hash(data.buffer) !== f.md5) throw new Error(`${f.url}: llegó incompleto`);
    out.push({ ...f, data });
  }
  log(`Descargado ${board.version}: ${out.map((f) => `${f.name} (${f.data.length} bytes)`).join(', ')}`);
  return out;
}

class WrongChip extends Error {
  constructor(name) { super(`Esta placa es un ${name}, no un ESP32 como los de la casa y el carrito.`); }
}

async function flash(files, mode, verified) {
  if (TEST) return fakeFlash(files, mode, verified);
  const transport = new Transport(port, false);
  const terminal = {
    clean() {},
    writeLine(t) {
      log(t);
      if (/Hash of data verified/.test(t)) verified.n++;
    },
    write(t) { log(t); },
  };
  const loader = new ESPLoader({ transport, baudrate: BAUD, romBaudrate: 115200, terminal, debugLogging: false });
  try {
    log(`Chip: ${await loader.main(mode)}`);
    if (loader.chip.CHIP_NAME !== 'ESP32') throw new WrongChip(loader.chip.CHIP_NAME);
    phase('write', 'Instalando');
    phaseDetailSize(files);
    ring(0);
    const sizes = files.map((f) => f.data.length);
    const total = sizes.reduce((a, b) => a + b, 0);
    await loader.writeFlash({
      ...FLASH,
      fileArray: files.map((f) => ({ data: f.data, address: f.address })),
      reportProgress: (i, written, size) => {
        const before = sizes.slice(0, i).reduce((a, b) => a + b, 0);
        ring((before + sizes[i] * (size ? written / size : 0)) / total);
      },
      calculateMD5Hash: (image) => SparkMD5.ArrayBuffer.hash(image.buffer.slice(image.byteOffset, image.byteOffset + image.byteLength)),
    });
    ring(1);
    await loader.after('no_reset_stub'); // el reinicio lo hace listen(), mientras escucha
  } finally {
    try { await transport.disconnect(); } catch (_) {}
  }
}

function phaseDetailSize(files) {
  const mb = files.reduce((a, f) => a + f.data.length, 0) / 1048576;
  $('phase-detail').textContent = `${board.version} · ${mb.toFixed(1).replace('.', ',')} MB`;
}

// ---------- El recorrido completo ----------
async function choosePort(all = false) {
  if (TEST) {
    if (location.hash === '#prueba-nada') throw new DOMException('No port selected by the user.', 'NotFoundError');
    return {};
  }
  return navigator.serial.requestPort(all ? {} : { filters: USB_CHIPS });
}

async function start(all = false) {
  if (writing) return;
  try {
    port = await choosePort(all);
  } catch (_) {
    screen('help'); // cerró la lista: casi siempre porque la placa no aparecía
    return;
  }
  lines.length = 0;
  log(`Instalador · ${board.name} ${board.version} · ${new Date().toLocaleString('es')}`);
  await install('default_reset');
}

async function install(mode) {
  writing = true;
  screen('work');
  $('ask').hidden = true;

  // 1 · Qué programa tiene ahora. En modo manual ya espera el programa nuevo: no se reinicia.
  if (mode === 'default_reset') {
    phase('find', 'Buscando la placa');
    ring(null);
    let current = null;
    try {
      current = parseBanner((await listen({ ms: 3000 })).text);
    } catch (e) {
      return fail(portProblem(e), e);
    }
    if (current) {
      $('phase-detail').textContent = `Tiene ${current.version}`;
      if (current.kind !== board.id && !(await ask(current))) return home();
    }
  }

  // 2 y 3 · Escribir y comprobar la huella
  let files;
  try {
    files = await download();
  } catch (e) {
    return fail('No se pudo descargar el programa. Revisa el internet.', e);
  }
  phase('write', 'Conectando');
  ring(null);
  const verified = { n: 0 };
  try {
    await flash(files, mode, verified);
  } catch (e) {
    if (e instanceof WrongChip) return fail(e.message, e);
    if (/md5|does not match/i.test(String(e))) return fail('Lo escrito no coincidió. Prueba otro cable o puerto USB.', e);
    if (/connect|timeout|timed out|sync|no serial data/i.test(String(e))) {
      log(`No entró sola en modo de carga: ${e && e.message ? e.message : e}`);
      writing = false;
      screen('boot');
      return;
    }
    return fail(portProblem(e), e);
  }
  phase('verify', 'Comprobando', 'Que quedó idéntico');
  if (verified.n < files.length) return fail('No se pudo comprobar lo escrito.');
  await sleep(500);

  // 4 · Arrancar y saludar
  phase('boot', 'Arrancando', 'Esperando que responda');
  ring(null);
  let heard = { text: '', pong: false };
  try {
    heard = await listen({ ms: 9000, expect: board.version, ping: true });
  } catch (e) {
    log(`No se pudo escuchar: ${e}`);
  }
  const now = parseBanner(heard.text);
  if (now && now.version === board.version) {
    return end('good', '¡Listo!', `${board.short} ya tiene ${board.version}. Puedes desconectar el USB.`, ['Terminar', home]);
  }
  return end('warn', 'Quedó instalada', 'Pero no la escuché responder. Desconecta y vuelve a conectar el USB.', ['Terminar', home]);
}

function portProblem(e) {
  const s = String(e && e.message ? e.message : e);
  if (/failed to open|access denied|in use|busy|already open/i.test(s)) return 'La placa está ocupada. Cierra Arduino o el Monitor Serie.';
  if (/lost|disconnect|not found|NetworkError/i.test(s)) return 'Se desconectó el USB. Vuelve a conectarlo.';
  return 'No pudo hablar con la placa. Desconecta y vuelve a conectar el USB.';
}

function fail(message, e) {
  if (e) log(`Error: ${e && e.message ? e.message : e}`);
  end('bad', 'No se pudo', `${message} La placa no se dañó.`, ['Intentar de nuevo', () => install('default_reset')], ['Volver', home]);
}

function ask(current) {
  const was = current.kind === 'carro' ? 'el carrito' : 'la casa';
  $('ask-text').textContent = `Esta placa es ${was} (${current.version}). ¿Cambiarla por ${board.id === 'carro' ? 'el carrito' : 'la casa'}?`;
  $('ask-yes').textContent = `Sí, instalar ${board.version}`;
  $('ask').hidden = false;
  return new Promise((resolve) => {
    $('ask-yes').onclick = () => { $('ask').hidden = true; resolve(true); };
    $('ask-no').onclick = () => { $('ask').hidden = true; resolve(false); };
  });
}

// ---------- Simulación (#prueba) ----------
async function fakeListen({ expect }) {
  await sleep(1000);
  const other = board.id === 'casa' ? ['Carrito 4x4', 'carro-0.4'] : ['Casa Domotica', 'casa-0.7'];
  const same = board.id === 'casa' ? ['Casa Domotica', 'casa-0.6'] : ['Carrito 4x4', 'carro-0.3'];
  let text;
  if (!expect) {
    const [name, ver] = location.hash === '#prueba-otra' ? other : same;
    text = `rst:0x1 (POWERON_RESET)\n== ${name} (${ver}) ==\nBluetooth listo\n`;
  } else if (location.hash === '#prueba-mudo') {
    text = '';
  } else {
    await sleep(1000);
    text = `== ${board.id === 'casa' ? 'Casa Domotica' : 'Carrito 4x4'} (${board.version}) ==\nBluetooth listo\nPONG\n`;
  }
  log(text ? text.trim().split('\n').map((l) => `│ ${l}`).join('\n') : '│ (la placa no dijo nada)');
  return { text, pong: text.includes('PONG') };
}

async function fakeFlash(files, mode, verified) {
  await sleep(900);
  if (location.hash === '#prueba-boot' && mode === 'default_reset') throw new Error('Failed to connect with the device');
  phase('write', 'Instalando');
  phaseDetailSize(files);
  for (let i = 0; i <= 60; i++) {
    ring(i / 60);
    await sleep(60);
  }
  if (location.hash === '#prueba-error') throw new Error('MD5 of file does not match data in flash!');
  for (const f of files) log(`Wrote ${f.data.length} bytes at 0x${f.address.toString(16)}\nHash of data verified.`);
  verified.n = files.length;
}

// ---------- Arranque ----------
async function init() {
  paintIcons();
  initTheme();
  $('test-banner').hidden = !TEST;
  window.addEventListener('beforeunload', (e) => { if (writing) e.preventDefault(); });
  $('copy-log').onclick = () => copy($('copy-log'), lines.join('\n'), 'Copiado');
  $('copy-link').onclick = () => copy($('copy-link'), location.href.split('#')[0], 'Enlace copiado');
  $('help-open').onclick = () => screen('help');
  $('help-retry').onclick = () => start();
  $('help-all').onclick = () => start(true);
  $('help-back').onclick = home;
  $('boot-retry').onclick = () => install('no_reset');
  $('boot-cancel').onclick = home;

  try {
    manifest = await (await fetch('placas.json', { cache: 'no-store' })).json();
  } catch (_) {
    $('home').innerHTML = '<div class="titles"><h1>Sin conexión</h1><p class="big">Revisa el internet y vuelve a cargar la página.</p></div>';
    return;
  }
  let saved = null;
  try { saved = localStorage.getItem('placa'); } catch (_) {}
  board = manifest.boards.find((b) => b.id === saved) || manifest.boards[0];
  renderTiles();
  if (!('serial' in navigator) && !TEST) screen('nobrowser');
}

init();
