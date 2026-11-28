// Runs the web development command in headless Chrome and edits its app while it runs.
import {spawn} from "node:child_process";
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import {createServer} from "node:net";
import {tmpdir} from "node:os";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

const [root, ash] = process.argv.slice(2);
const project = join(dirname(fileURLToPath(import.meta.url)), "bin", "web");
const profile = mkdtempSync(join(tmpdir(), "hxnme-web-dev-"));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const freePort = () => new Promise(resolve => {
  const server = createServer();
  server.listen(0, "127.0.0.1", () => {
    const port = server.address().port;
    server.close(() => resolve(port));
  });
});
const port = await freePort();
const debugPort = await freePort();
const url = `http://127.0.0.1:${port}/`;
let command, browser, socket;
let output = "";
const lines = [];
const write = (name, text) => writeFileSync(join(project, name), text);
const source = label => `
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;
import hxn.me.Assets;
class Main {
  static function main() hxn.me.App.run(Probe);
}
class Probe {
  static var value = "";
  @:system(Start)
  static function load(assets:ResMut<Assets>) assets.load(Files.Value).then(asset -> value = asset.value);
  @:system(Update)
  static function show(time:Res<Time>) {
    if (time.frame % 30 == 0 && value != "") Sys.println("web ${label} " + value);
  }
}
`;

async function until(test, description) {
  const end = Date.now() + 120_000;
  while (Date.now() < end) {
    if (command && (command.exitCode !== null || command.signalCode !== null))
      throw new Error(`the development command stopped\n${output}`);
    if (await test()) {
      console.log(`${description}: yes`);
      return;
    }
    await sleep(100);
  }
  throw new Error(`${description}: no\n${output}\n${lines.join("\n")}`);
}

async function revision() {
  try {
    const response = await fetch(`${url}hxnme-dev.json`);
    return response.ok ? (await response.json()).revision : -1;
  } catch { return -1; }
}

function start(file = "app.hxml") {
  output = "";
  command = spawn("haxe", ["-lib", "hxn", "-cp", join(root, "tools"), "-cp", join(root, "src"), "--run", "hxn.me.cli.Tool"], {
    cwd: project,
    detached: true,
  });
  command.stdout.on("data", bytes => { output += bytes; });
  command.stderr.on("data", bytes => { output += bytes; });
  command.stdin.end(JSON.stringify({version: 1, kind: "command", library: "hxnme", root, cwd: project,
    arguments: ["dev", "web", file, "--port", String(port), "--ash", ash]}));
}

async function stop() {
  if (!command) return;
  const ended = new Promise(resolve => command.once("exit", resolve));
  try { process.kill(-command.pid, "SIGTERM"); } catch {}
  await Promise.race([ended, sleep(3000)]);
  command = null;
}

try {
  rmSync(project, {recursive: true, force: true});
  mkdirSync(join(project, "assets"), {recursive: true});
  write("app.hxml", "-lib hxnme\n-main Main\n");
  write("hxnme.toml", "[app]\nrate = 30\n");
  write("Main.hx", source("one"));
  write("Files.hx", `import hxn.me.AssetRef;
@:build(hxn.me.Assets.build()) class Files {
  @:asset("value.txt") public static var Value:AssetRef<String>;
}
`);
  write("assets/value.txt", "first");
  start();
  await until(async () => await revision() === 1, "the command serves the first successful build");
  const headers = await fetch(url);
  if (headers.headers.get("cross-origin-opener-policy") !== "same-origin" || headers.headers.get("cross-origin-embedder-policy") !== "require-corp")
    throw new Error("the page lacks cross-origin isolation headers");
  console.log("the server isolates the threaded page: yes");

  const chrome = process.env.HXN_BROWSER || (process.platform === "darwin"
    ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" : "google-chrome");
  browser = spawn(chrome, ["--headless=new", "--no-first-run", "--no-default-browser-check",
    `--remote-debugging-port=${debugPort}`, `--user-data-dir=${profile}`,
    ...(process.env.HXN_BROWSER_ARGS || "").split(/\s+/).filter(Boolean), "about:blank"], {stdio: "ignore"});
  let target;
  await until(async () => {
    try {
      const response = await fetch(`http://127.0.0.1:${debugPort}/json/new?about:blank`, {method: "PUT"});
      if (response.ok) target = await response.json();
      return !!target;
    } catch { return false; }
  }, "the browser starts");
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let nextId = 1;
  const waiting = new Map();
  const send = (method, params = {}, sessionId) => new Promise(resolve => {
    const id = nextId++;
    waiting.set(id, resolve);
    socket.send(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}));
  });
  socket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (waiting.has(message.id)) {
      waiting.get(message.id)(message);
      waiting.delete(message.id);
    } else if (message.method === "Target.attachedToTarget") {
      const id = message.params.sessionId;
      send("Runtime.enable", {}, id);
      send("Target.setAutoAttach", {autoAttach: true, waitForDebuggerOnStart: true, flatten: true}, id);
      send("Runtime.runIfWaitingForDebugger", {}, id);
    } else if (message.method === "Runtime.consoleAPICalled") {
      lines.push(message.params.args.map(arg => arg.value ?? arg.description ?? "").join(" "));
    } else if (message.method === "Runtime.exceptionThrown") {
      lines.push(JSON.stringify(message.params.exceptionDetails));
    }
  };
  await send("Runtime.enable");
  await send("Target.setAutoAttach", {autoAttach: true, waitForDebuggerOnStart: true, flatten: true});
  await send("Page.navigate", {url});
  await until(() => lines.some(line => line.includes("web one first")), "the app runs in the page");

  write("Main.hx", source("two"));
  await until(() => lines.some(line => line.includes("web two first")), "a changed system runs after the page reloads");
  const good = await revision();
  write("Main.hx", source("two").replace('Sys.println("web two " + value)', "Sys.println(missingValue)"));
  await until(() => output.includes("Unknown identifier : missingValue"), "the command reports a compile error");
  lines.length = 0;
  await until(() => lines.some(line => line.includes("web two first")), "the app keeps running after a compile error");
  if (await revision() !== good) throw new Error("a failed build changed the served revision");
  console.log("a failed build keeps the previous page: yes");

  write("Main.hx", source("three"));
  await until(() => lines.some(line => line.includes("web three first")), "the page reloads after the compile error is fixed");
  write("assets/value.txt", "second");
  await until(() => lines.some(line => line.includes("web three second")), "the page reads a changed asset");
  const beforeConfig = await revision();
  write("hxnme.toml", "[app]\nrate = 60\n");
  await until(async () => await revision() > beforeConfig, "a project configuration change rebuilds the page");

  await stop();
  write("tools.hxml", readFileSync(join(project, "app.hxml"), "utf8"));
  write("Main.hx", source("four").replace('Sys.println("web four " + value)', "Sys.println(missingValue)"));
  start("tools.hxml");
  await until(async () => await revision() === 0 && (await (await fetch(url)).text()).includes("Waiting for a successful build"),
    "an initial compile error serves a waiting page");
  write("Main.hx", source("four"));
  await until(() => lines.some(line => line.includes("web four second")), "a custom program file recovers after its first compile error");
  console.log("Web development checks passed");
} finally {
  socket?.close();
  if (browser && browser.exitCode === null && browser.signalCode === null) {
    const ended = new Promise(resolve => browser.once("exit", resolve));
    browser.kill();
    await Promise.race([ended, sleep(3000)]);
  }
  await stop();
  rmSync(profile, {recursive: true, force: true, maxRetries: 10, retryDelay: 100});
}
