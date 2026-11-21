// Instalador del programa de las placas (ESP32) desde Chrome o Edge, con esptool-js, la herramienta oficial
// de Espressif. Pasos: 1) reinicia la placa y escucha qué programa tiene; 2) la pone en modo de carga y escribe
// el programa; 3) esptool le pide al ESP32 la huella (MD5) de lo escrito y la compara con el archivo;
// 4) la reinicia, espera su saludo «== Casa Domotica (casa-0.7) ==» y le pregunta PING, que responde PONG.
//
// #prueba en la dirección simula una placa (sin USB) para revisar la página: #prueba-otra (la placa tiene el
// programa de la otra), #prueba-boot (no entra sola en modo de carga), #prueba-error y #prueba-mudo.
import { ESPLoader, Transport } from './lib/esptool-js-0.7.1.js';
import { ICONS } from './icons.js';

const $ = (id) => document.getElementById(id);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const TEST = location.hash.startsWith('#prueba');
const BANNER = /==\s*([^=\n]+?)\s*\(((casa|carro)-[\w.]+)\)\s*==/g;

// Mismos parámetros que tool/cargar_esp32.ps1 (y que Arduino): el resultado es idéntico.
const FLASH = { flashMode: 'dio', flashFreq: '80m', flashSize: '4MB', eraseAll: false, compress: true };
const BAUD = 460800;

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
    el.style.display = 'inline-flex';
  });
}

// ---------- Registro para «Detalles técnicos» ----------
const lines = [];
function log(text) {
  lines.push(String(text).replace(/\s+$/, ''));
  const pre = $('log');
  pre.textContent = lines.join('\n');
  pre.scrollTop = pre.scrollHeight;
}

// ---------- Pantalla ----------
function show(id, on = true) { $(id).hidden = !on; }
function only(...ids) { for (const id of ['setup', 'run', 'ask', 'manual', 'result']) show(id, ids.includes(id)); }

function step(name, state, detail) {
  const li = document.querySelector(`.step[data-step="${name}"]`);
  li.dataset.state = state;
  const mark = li.querySelector('.mark');
  mark.innerHTML = state === 'done'
    ? icon('check-circle-fill', 22, 'var(--green)')
    : state === 'fail'
      ? icon('x-circle-fill', 22, 'var(--red)')
      : '<span class="dot"></span>';
  if (state === 'done' || state === 'fail') mark.firstElementChild?.classList.add('pop');
  if (detail !== undefined) li.querySelector('.detail').textContent = detail;
}

function resetSteps() {
  for (const s of ['find', 'write', 'verify', 'boot']) step(s, 'wait', '');
  document.querySelector('.step[data-step="write"] .title').textContent = `Instalar ${board.version}`;
  show('progress', false);
  progress(0);
}

function progress(frac) {
  const p = Math.max(0, Math.min(1, frac));
  $('pct').textContent = `${Math.round(p * 100)} %`;
  $('bar').style.width = `${(p * 100).toFixed(1)}%`;
}

function renderChoices() {
  const box = $('choices');
  box.innerHTML = '';
  for (const b of manifest.boards) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'choice';
    btn.setAttribute('role', 'radio');
    btn.setAttribute('aria-checked', String(b === board));
    btn.tabIndex = b === board ? 0 : -1;
    btn.innerHTML = `${icon(b.icon, 28)}<span style="display:grid;gap:6px"><span class="callout">${b.name}</span><span class="ver">${b.version}</span></span>`;
    btn.addEventListener('click', () => pick(b));
    btn.addEventListener('keydown', (e) => {
      if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) return;
      e.preventDefault();
      const i = manifest.boards.indexOf(board);
      const next = manifest.boards[(i + (e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 1) + manifest.boards.length) % manifest.boards.length];
      pick(next);
      box.querySelectorAll('.choice')[manifest.boards.indexOf(next)].focus();
    });
    box.appendChild(btn);
  }
  $('notes').innerHTML = board.notes.map((n, i) => `<li data-n="${String(i + 1).padStart(2, '0')}">${n}</li>`).join('');
  $('start-label').textContent = `Conectar e instalar ${board.version}`;
}

function pick(b) {
  board = b;
  try { localStorage.setItem('placa', b.id); } catch (_) {}
  renderChoices();
}

function backToSetup() {
  writing = false;
  only('setup');
  $('lead').hidden = false;
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
  if (TEST) return fakeListen({ expect, ping });
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
    const chip = await loader.main(mode);
    log(`Chip: ${chip}`);
    if (loader.chip.CHIP_NAME !== 'ESP32') throw new WrongChip(loader.chip.CHIP_NAME);
    step('write', 'doing', 'Escribiendo en la memoria…');
    startProgress(files);
    const sizes = files.map((f) => f.data.length);
    const total = sizes.reduce((a, b) => a + b, 0);
    await loader.writeFlash({
      ...FLASH,
      fileArray: files.map((f) => ({ data: f.data, address: f.address })),
      reportProgress: (i, written, size) => {
        const before = sizes.slice(0, i).reduce((a, b) => a + b, 0);
        progress((before + sizes[i] * (size ? written / size : 0)) / total);
      },
      calculateMD5Hash: (image) => SparkMD5.ArrayBuffer.hash(image.buffer.slice(image.byteOffset, image.byteOffset + image.byteLength)),
    });
    progress(1);
    await loader.after('no_reset_stub'); // el reinicio lo hace listen(), mientras escucha
  } finally {
    try { await transport.disconnect(); } catch (_) {}
  }
}

class WrongChip extends Error {
  constructor(name) { super(`Esta placa es un ${name}, no un ESP32 como los de la casa y el carrito.`); }
}

function startProgress(files) {
  const mb = files.reduce((a, f) => a + f.data.length, 0) / 1048576;
  $('pct-detail').textContent = `de ${mb.toFixed(1).replace('.', ',')} MB`;
  show('progress');
}

// ---------- El recorrido completo ----------
async function start() {
  if (writing) return;
  if (!TEST) {
    try {
      port = await navigator.serial.requestPort();
    } catch (_) {
      return; // cerró la ventana sin elegir
    }
  }
  lines.length = 0;
  log(`Instalador · ${board.name} ${board.version} · ${new Date().toLocaleString('es')}`);
  await install('default_reset');
}

async function install(mode) {
  writing = true;
  only('run');
  $('lead').hidden = true;
  $('run-eyebrow').textContent = `Instalando ${board.version} · ${board.name}`;
  show('keep');
  resetSteps();

  // 1 · Qué programa tiene ahora. En modo manual ya espera el programa nuevo: no se reinicia.
  if (mode === 'default_reset') {
    step('find', 'doing', 'Reiniciando la placa para ver qué programa tiene…');
    let current = null;
    try {
      current = parseBanner((await listen({ ms: 3000 })).text);
    } catch (e) {
      return fail('find', portProblem(e), e);
    }
    if (current && current.kind !== board.id) {
      step('find', 'doing', `Tiene ${current.version}.`);
      if (!(await ask(current))) return backToSetup();
    }
    step('find', 'done', current
      ? (current.version === board.version ? `Ya tiene ${current.version}: se reinstala igual.` : `Tiene ${current.version}. Se cambia por ${board.version}.`)
      : 'Encontrada. No dijo qué programa tiene, así que seguimos.');
  } else {
    step('find', 'done', 'En modo de carga, lista para recibir el programa.');
  }

  // 2 y 3 · Escribir y comprobar la huella
  let files;
  try {
    files = await download();
  } catch (e) {
    return fail('write', 'No se pudo descargar el programa. Revisa el internet y vuelve a cargar la página.', e);
  }
  step('write', 'doing', 'Conectando con el cargador del ESP32…');
  const verified = { n: 0 };
  try {
    await flash(files, mode, verified);
  } catch (e) {
    if (e instanceof WrongChip) return fail('write', e.message, e);
    if (/md5|does not match/i.test(String(e))) {
      step('write', 'done', 'Escrito.');
      return fail('verify', 'Lo escrito no coincide con el archivo. Prueba otro cable u otro puerto USB e intenta de nuevo.', e);
    }
    if (/connect|timeout|timed out|sync|no serial data/i.test(String(e))) return needManual(e);
    return fail('write', portProblem(e), e);
  }
  step('write', 'done', `${board.version} quedó escrito en la memoria.`);
  if (verified.n < files.length) return fail('verify', 'No se pudo comprobar la huella de todo lo escrito. Intenta de nuevo.');
  step('verify', 'done', `La huella de las ${files.length} partes coincide con los archivos.`);

  // 4 · Arrancar y saludar
  step('boot', 'doing', 'Reiniciando y escuchando a la placa…');
  let heard = { text: '', pong: false };
  try {
    heard = await listen({ ms: 9000, expect: board.version, ping: true });
  } catch (e) {
    log(`No se pudo escuchar: ${e}`);
  }
  const now = parseBanner(heard.text);
  writing = false;
  show('keep', false);
  if (now && now.version === board.version) {
    step('boot', 'done', heard.pong ? `Arrancó con ${now.version} y respondió.` : `Arrancó con ${now.version}.`);
    return result('good', {
      eyebrow: 'Instalada y comprobada',
      title: `Listo: tiene ${board.version}`,
      text: `${board.short} arrancó con ${board.version}${heard.pong ? ' y respondió' : ''}. Ya puedes desconectar el USB y volver a enchufar la fuente de la maqueta.`,
      primary: ['Instalar en otra placa', backToSetup],
    });
  }
  step('boot', 'fail', 'Quedó escrita, pero no la escuché arrancar.');
  return result('warn', {
    eyebrow: 'Escrita, sin confirmar',
    title: 'Quedó escrita, pero no la escuché',
    text: 'La huella coincide con el archivo, así que el programa quedó bien escrito. Desconecta el USB, vuelve a conectarlo y revisa en la app que la placa aparezca. Si no, manda una foto de «Detalles técnicos».',
    primary: ['Volver al inicio', backToSetup],
  });
}

function portProblem(e) {
  const s = String(e && e.message ? e.message : e);
  if (/failed to open|access denied|in use|busy|already open/i.test(s)) {
    return 'La placa está ocupada por otro programa (Arduino, el Monitor Serie u otra pestaña). Ciérralo e intenta de nuevo.';
  }
  if (/lost|disconnect|not found|NetworkError/i.test(s)) return 'Se desconectó el USB. Vuelve a conectarlo e intenta de nuevo.';
  return 'Algo falló al hablar con la placa. Desconecta y vuelve a conectar el USB, e intenta de nuevo.';
}

function fail(stepName, message, e) {
  writing = false;
  show('keep', false);
  if (e) log(`Error: ${e && e.message ? e.message : e}`);
  step(stepName, 'fail', message);
  return result('bad', {
    eyebrow: 'No se pudo instalar',
    title: 'Algo salió mal',
    text: `${message} La placa no se dañó: se puede intentar las veces que haga falta.`,
    primary: ['Intentar de nuevo', () => install('default_reset')],
    secondary: ['Volver al inicio', backToSetup],
  });
}

function result(kind, { eyebrow, title, text, primary, secondary }) {
  const icons = { good: ['check-circle-fill', 'var(--green)'], warn: ['warning-circle-fill', 'var(--amber)'], bad: ['x-circle-fill', 'var(--red)'] };
  const [name, color] = icons[kind];
  $('result-icon').innerHTML = icon(name, 56, color);
  $('result-icon').classList.remove('pop');
  void $('result-icon').offsetWidth;
  $('result-icon').classList.add('pop');
  $('result-eyebrow').textContent = eyebrow;
  $('result-eyebrow').style.color = color;
  $('result-title').textContent = title;
  $('result-text').textContent = text;
  const again = $('again');
  again.textContent = primary[0];
  again.onclick = primary[1];
  let second = $('again2');
  if (secondary) {
    if (!second) {
      second = document.createElement('button');
      second.id = 'again2';
      second.type = 'button';
      second.className = 'pill wide';
      again.parentElement.appendChild(second);
    }
    second.textContent = secondary[0];
    second.onclick = secondary[1];
    second.hidden = false;
  } else if (second) {
    second.hidden = true;
  }
  show('run');
  show('result');
  $('result').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function ask(current) {
  const what = (k) => (k === 'carro' ? 'del carrito' : 'de la casa');
  $('ask-text').textContent = `Esta placa tiene el programa ${what(current.kind)} (${current.version}), pero elegiste ${board.name}. Si sigues, deja de funcionar como ${current.kind === 'carro' ? 'carrito' : 'casa'}.`;
  $('ask-yes').textContent = `Sí, instalar ${board.version}`;
  show('ask');
  return new Promise((resolve) => {
    $('ask-yes').onclick = () => { show('ask', false); resolve(true); };
    $('ask-no').onclick = () => { show('ask', false); resolve(false); };
  });
}

function needManual(e) {
  log(`No entró sola en modo de carga: ${e && e.message ? e.message : e}`);
  step('write', 'fail', 'La placa no entró sola en modo de carga.');
  show('manual');
  $('manual').scrollIntoView({ behavior: 'smooth', block: 'center' });
  $('manual-retry').onclick = () => { show('manual', false); install('no_reset'); };
  $('manual-cancel').onclick = backToSetup;
  writing = false;
  show('keep', false);
}

// ---------- Simulación (#prueba) ----------
async function fakeListen({ expect }) {
  await sleep(900);
  const other = board.id === 'casa' ? ['Carrito 4x4', 'carro-0.4'] : ['Casa Domotica', 'casa-0.7'];
  const same = board.id === 'casa' ? ['Casa Domotica', 'casa-0.6'] : ['Carrito 4x4', 'carro-0.3'];
  if (!expect) {
    const [name, ver] = location.hash === '#prueba-otra' ? other : same;
    const text = `rst:0x1 (POWERON_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)\n== ${name} (${ver}) ==\nBluetooth listo\n`;
    log(text.trim().split('\n').map((l) => `│ ${l}`).join('\n'));
    return { text, pong: false };
  }
  if (location.hash === '#prueba-mudo') return { text: '', pong: false };
  await sleep(1200);
  const text = `== ${board.id === 'casa' ? 'Casa Domotica' : 'Carrito 4x4'} (${board.version}) ==\nBluetooth listo\nPONG\n`;
  log(text.trim().split('\n').map((l) => `│ ${l}`).join('\n'));
  return { text, pong: true };
}

async function fakeFlash(files, mode, verified) {
  await sleep(900);
  if (location.hash === '#prueba-boot' && mode === 'default_reset') throw new Error('Failed to connect with the device');
  step('write', 'doing', 'Escribiendo en la memoria…');
  startProgress(files);
  for (let i = 0; i <= 50; i++) {
    progress(i / 50);
    await sleep(70);
  }
  if (location.hash === '#prueba-error') throw new Error('MD5 of file does not match data in flash!');
  for (const f of files) log(`Wrote ${f.data.length} bytes at 0x${f.address.toString(16)}\nHash of data verified.`);
  verified.n = files.length;
}

// ---------- Arranque ----------
async function init() {
  paintIcons();
  show('test-banner', TEST);
  $('copy-log').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(lines.join('\n')); $('copy-log').lastChild.textContent = 'Copiado'; } catch (_) {}
  });
  $('copy-link').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(location.href.split('#')[0]); $('copy-link').lastChild.textContent = 'Enlace copiado'; } catch (_) {}
  });
  window.addEventListener('beforeunload', (e) => { if (writing) e.preventDefault(); });

  try {
    manifest = await (await fetch('placas.json', { cache: 'no-store' })).json();
  } catch (e) {
    $('lead').textContent = 'No se pudo cargar la lista de versiones. Revisa el internet y vuelve a cargar la página.';
    show('setup', false);
    return;
  }
  let saved = null;
  try { saved = localStorage.getItem('placa'); } catch (_) {}
  board = manifest.boards.find((b) => b.id === saved) || manifest.boards[0];
  renderChoices();
  $('versions').textContent = `Versiones publicadas: ${manifest.boards.map((b) => b.version).join(' · ')} · actualizado el ${manifest.updated}.`;

  if (!('serial' in navigator) && !TEST) {
    show('unsupported');
    $('start').disabled = true;
  }
  $('start').addEventListener('click', start);
}

init();
