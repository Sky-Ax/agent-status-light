const assert = require("assert");
const { mkdtempSync, readFileSync, copyFileSync, rmSync } = require("fs");
const { tmpdir } = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

function runHook(event) {
  const dir = mkdtempSync(path.join(tmpdir(), "codex-hook-"));
  const binDir = path.join(dir, "bin");
  require("fs").mkdirSync(binDir);
  copyFileSync(path.join(__dirname, "..", "bin", "codex-hook.js"), path.join(binDir, "codex-hook.js"));

  const result = spawnSync(process.execPath, [path.join(binDir, "codex-hook.js")], {
    input: event === undefined ? "" : JSON.stringify(event),
    encoding: "utf8",
  });

  assert.strictEqual(result.status, 0, result.stderr);

  const status = JSON.parse(readFileSync(path.join(dir, "data", "codex-status.json"), "utf8"));
  const log = readFileSync(path.join(dir, "data", "codex-hook-log.jsonl"), "utf8")
    .trim()
    .split(/\r?\n/)
    .map((line) => JSON.parse(line));

  rmSync(dir, { recursive: true, force: true });
  return { status, log };
}

{
  const { status, log } = runHook({
    hook_event_name: "UserPromptSubmit",
    session_id: "s1",
    prompt: "secret prompt",
  });

  assert.strictEqual(status.sessions.s1.state, "working");
  assert.strictEqual(log[0].raw, undefined);
  assert.strictEqual(log[0].prompt, undefined);
}

{
  const { status } = runHook({ hook_event_name: "ParseError", session_id: "s2" });
  assert.strictEqual(status.sessions.s2.state, "attention");
  assert.strictEqual(status.sessions.s2.color, "red");
}

{
  const { status } = runHook();
  assert.strictEqual(status.state, "idle");
  assert.strictEqual(status.color, "gray");
}
