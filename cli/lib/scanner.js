import { execSync, exec } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';

// Default allowlist of common development process names
const DEFAULT_ALLOWLIST = new Set([
  'node', 'npm', 'npx', 'deno', 'bun',           // JavaScript/TypeScript
  'Python', 'python', 'python3', 'uvicorn', 'gunicorn', 'flask', 'django',  // Python
  'ruby', 'rails', 'puma', 'unicorn',            // Ruby
  'php', 'php-fpm',                              // PHP
  'java', 'gradle', 'mvn',                       // Java
  'go', 'air',                                   // Go
  'cargo', 'rustc',                              // Rust
  'dotnet',                                      // .NET
  'beam.smp', 'elixir', 'mix',                   // Elixir/Erlang
  'nginx', 'httpd', 'apache',                    // Web servers
  'postgres', 'mysql', 'redis-server', 'mongod', // Databases
  'docker-proxy',                                // Docker
]);

export function scanPorts(options = {}) {
  const {
    minPort = 3000,
    maxPort = 9999,
    allowlist = DEFAULT_ALLOWLIST
  } = options;

  const output = runLsof();
  const ports = parseLsofOutput(output);

  return ports.filter(port =>
    port.port >= minPort &&
    port.port <= maxPort &&
    allowlist.has(port.process)
  );
}

function runLsof() {
  try {
    return execSync('lsof -iTCP -sTCP:LISTEN -P -n', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (error) {
    // lsof returns non-zero if no matching files found
    return error.stdout || '';
  }
}

function parseLsofOutput(output) {
  const seen = new Set();
  const ports = [];

  const lines = output.split('\n').slice(1); // Skip header

  for (const line of lines) {
    if (!line.trim()) continue;

    const cols = line.split(/\s+/);
    if (cols.length < 9) continue;

    const processName = cols[0];
    const pid = parseInt(cols[1], 10);
    if (isNaN(pid)) continue;

    // The NAME field contains address:port
    const nameField = cols[cols.length - 2];
    const colonIdx = nameField.lastIndexOf(':');
    if (colonIdx === -1) continue;

    const port = parseInt(nameField.slice(colonIdx + 1), 10);
    if (isNaN(port)) continue;

    if (!seen.has(port)) {
      seen.add(port);

      const workingDir = getWorkingDirectory(pid);
      const projectName = extractProjectName(workingDir);
      const startTime = getProcessStartTime(pid);

      ports.push({
        port,
        pid,
        process: processName,
        projectName,
        workingDir,
        startTime
      });
    }
  }

  return ports.sort((a, b) => a.port - b.port);
}

function getWorkingDirectory(pid) {
  try {
    const output = execSync(`lsof -a -p ${pid} -d cwd -Fn`, {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe']
    });

    for (const line of output.split('\n')) {
      if (line.startsWith('n')) {
        return line.slice(1);
      }
    }
  } catch {
    // Ignore errors
  }
  return null;
}

function getProcessStartTime(pid) {
  try {
    const output = execSync(`ps -p ${pid} -o lstart=`, {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe']
    }).trim();

    // Parse format like "Mon Jan 13 08:30:00 2026"
    const date = new Date(output);
    if (!isNaN(date.getTime())) {
      return date;
    }
  } catch {
    // Ignore errors
  }
  return new Date();
}

function extractProjectName(workingDir) {
  if (!workingDir) return null;

  // Try package.json for Node.js projects
  const packageJsonPath = join(workingDir, 'package.json');
  if (existsSync(packageJsonPath)) {
    try {
      const pkg = JSON.parse(readFileSync(packageJsonPath, 'utf-8'));
      if (pkg.name) return pkg.name;
    } catch {
      // Ignore parse errors
    }
  }

  // Try pyproject.toml for Python projects
  const pyprojectPath = join(workingDir, 'pyproject.toml');
  if (existsSync(pyprojectPath)) {
    try {
      const content = readFileSync(pyprojectPath, 'utf-8');
      const match = content.match(/name\s*=\s*"([^"]+)"/);
      if (match) return match[1];
    } catch {
      // Ignore read errors
    }
  }

  // Fallback to directory name
  return dirname(workingDir).split('/').pop() || workingDir.split('/').pop();
}

export function stopProcess(pid) {
  try {
    process.kill(pid, 'SIGTERM');
    return true;
  } catch {
    return false;
  }
}

export function formatUptime(startTime) {
  const elapsed = Math.floor((Date.now() - startTime.getTime()) / 1000);

  if (elapsed < 60) {
    return `${elapsed}s`;
  } else if (elapsed < 3600) {
    const minutes = Math.floor(elapsed / 60);
    return `${minutes}m`;
  } else if (elapsed < 86400) {
    const hours = Math.floor(elapsed / 3600);
    const minutes = Math.floor((elapsed % 3600) / 60);
    return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
  } else {
    const days = Math.floor(elapsed / 86400);
    const hours = Math.floor((elapsed % 86400) / 3600);
    return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
  }
}
