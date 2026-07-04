const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const outDir = path.join(projectRoot, "data");
const logFile = path.join(outDir, "codex-hook-log.jsonl");
const statusFile = path.join(outDir, "codex-status.json");

function formatLocalTime(date) {
  const pad = (value) => String(value).padStart(2, "0");

  return [
    date.getFullYear(),
    "-",
    pad(date.getMonth() + 1),
    "-",
    pad(date.getDate()),
    " ",
    pad(date.getHours()),
    ":",
    pad(date.getMinutes()),
    ":",
    pad(date.getSeconds()),
  ].join("");
}

function pickEventName(event) {
  return (
    event.hook_event_name ||
    event.event_name ||
    event.event ||
    event.type ||
    "unknown"
  );
}

function mapStatus(event) {
  const name = pickEventName(event);

  if (name === "ParseError") {
    return {
      state: "attention",
      color: "red",
      reason: "parse_error",
    };
  }

  if (name === "EmptyInput") {
    return {
      state: "idle",
      color: "gray",
      reason: "empty_input",
    };
  }

  if (name === "PermissionRequest") {
    return {
      state: "attention",
      color: "red",
      reason: "permission_required",
    };
  }

  if (name === "Stop") {
    return {
      state: "idle",
      color: "green",
      reason: "stopped",
    };
  }

  if (
    name === "UserPromptSubmit" ||
    name === "PreToolUse" ||
    name === "PostToolUse" ||
    name === "SubagentStop"
  ) {
    return {
      state: "working",
      color: "yellow",
      reason: name,
    };
  }

  return {
    state: "working",
    color: "yellow",
    reason: name,
  };
}

function readStdin() {
  try {
    return fs.readFileSync(0, "utf8");
  } catch (error) {
    return "";
  }
}

function parseInput(input) {
  if (!input.trim()) {
    return {
      hook_event_name: "EmptyInput",
    };
  }

  try {
    return JSON.parse(input);
  } catch (error) {
    return {
      hook_event_name: "ParseError",
      parse_error: String(error),
      raw_input: input,
    };
  }
}

function readStatus() {
  try {
    return JSON.parse(fs.readFileSync(statusFile, "utf8"));
  } catch (error) {
    return {};
  }
}

function sessionKey(event) {
  return event.session_id || "__unknown";
}

function main() {
  fs.mkdirSync(outDir, { recursive: true });

  const input = readStdin();
  const event = parseInput(input);
  const status = mapStatus(event);
  const eventName = pickEventName(event);
  const now = new Date();
  const updatedAt = formatLocalTime(now);
  const updatedAtIso = now.toISOString();
  const sessionStatus = {
    provider: "codex",
    state: status.state,
    color: status.color,
    reason: status.reason,
    event: eventName,
    session_id: event.session_id,
    tool_name: event.tool_name,
    cwd: event.cwd,
    updatedAt,
    updatedAtIso,
  };

  const record = {
    time: updatedAt,
    time_iso: updatedAtIso,
    provider: "codex",
    event: eventName,
    session_id: event.session_id,
    tool_name: event.tool_name,
    cwd: event.cwd,
    status,
  };

  if (event.parse_error) {
    record.error = event.parse_error;
  }

  if (process.env.CODEX_HOOK_LOG_RAW === "1") {
    record.raw = event;
  }

  fs.appendFileSync(logFile, `${JSON.stringify(record)}\n`, "utf8");

  const current = readStatus();
  const sessions = current.sessions || {};
  sessions[sessionKey(event)] = sessionStatus;

  fs.writeFileSync(
    statusFile,
    JSON.stringify({ ...sessionStatus, sessions }, null, 2),
    "utf8"
  );
}

main();
