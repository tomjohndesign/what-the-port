#!/usr/bin/env node

import chalk from 'chalk';
import Table from 'cli-table3';
import inquirer from 'inquirer';
import open from 'open';
import clipboardy from 'clipboardy';
import { scanPorts, stopProcess, formatUptime } from '../lib/scanner.js';

const LOGO = `
${chalk.cyan('╦ ╦┬ ┬┌─┐┌┬┐  ┌┬┐┬ ┬┌─┐  ╔═╗┌─┐┬─┐┌┬┐')}
${chalk.cyan('║║║├─┤├─┤ │    │ ├─┤├┤   ╠═╝│ │├┬┘ │ ')}
${chalk.cyan('╚╩╝┴ ┴┴ ┴ ┴    ┴ ┴ ┴└─┘  ╩  └─┘┴└─ ┴ ')}
`;

async function main() {
  const args = process.argv.slice(2);

  // Handle --help
  if (args.includes('--help') || args.includes('-h')) {
    showHelp();
    return;
  }

  // Handle --list (non-interactive mode)
  if (args.includes('--list') || args.includes('-l')) {
    listPorts();
    return;
  }

  // Interactive mode
  await interactiveMode();
}

function showHelp() {
  console.log(LOGO);
  console.log(chalk.white('See what\'s running on your ports\n'));
  console.log(chalk.yellow('Usage:'));
  console.log('  what-the-port          Interactive mode');
  console.log('  what-the-port -l       List ports and exit');
  console.log('  wtp                    Short alias\n');
  console.log(chalk.yellow('Options:'));
  console.log('  -l, --list             List ports without interaction');
  console.log('  -h, --help             Show this help message\n');
}

function listPorts() {
  const ports = scanPorts();

  if (ports.length === 0) {
    console.log(chalk.yellow('No dev servers running on ports 3000-9999'));
    return;
  }

  const table = new Table({
    head: [
      chalk.cyan('Port'),
      chalk.cyan('Project'),
      chalk.cyan('Process'),
      chalk.cyan('PID'),
      chalk.cyan('Uptime')
    ],
    style: { head: [], border: [] }
  });

  for (const port of ports) {
    table.push([
      chalk.green(`:${port.port}`),
      port.projectName || chalk.dim('-'),
      port.process,
      chalk.dim(port.pid),
      formatUptime(port.startTime)
    ]);
  }

  console.log(table.toString());
}

async function interactiveMode() {
  console.clear();
  console.log(LOGO);

  while (true) {
    const ports = scanPorts();

    if (ports.length === 0) {
      console.log(chalk.yellow('\n  No dev servers running on ports 3000-9999\n'));

      const { action } = await inquirer.prompt([{
        type: 'list',
        name: 'action',
        message: 'What would you like to do?',
        choices: [
          { name: 'Refresh', value: 'refresh' },
          { name: 'Quit', value: 'quit' }
        ]
      }]);

      if (action === 'quit') break;
      console.clear();
      console.log(LOGO);
      continue;
    }

    // Build choices from ports
    const portChoices = ports.map(port => ({
      name: `${chalk.green(`:${port.port}`)} ${port.projectName || port.process} ${chalk.dim(`• ${formatUptime(port.startTime)}`)}`,
      value: port
    }));

    portChoices.push(new inquirer.Separator());
    portChoices.push({ name: chalk.blue('↻ Refresh'), value: 'refresh' });
    portChoices.push({ name: chalk.red('✕ Quit'), value: 'quit' });

    const { selected } = await inquirer.prompt([{
      type: 'list',
      name: 'selected',
      message: 'Select a port:',
      choices: portChoices,
      pageSize: 15
    }]);

    if (selected === 'quit') break;
    if (selected === 'refresh') {
      console.clear();
      console.log(LOGO);
      continue;
    }

    // Port selected, show actions
    await showPortActions(selected);
    console.clear();
    console.log(LOGO);
  }

  console.log(chalk.dim('\nGoodbye!\n'));
}

async function showPortActions(port) {
  const url = `http://localhost:${port.port}`;

  console.log(chalk.dim(`\n  ${port.workingDir || ''}\n`));

  const { action } = await inquirer.prompt([{
    type: 'list',
    name: 'action',
    message: `${chalk.green(`:${port.port}`)} ${port.projectName || port.process}`,
    choices: [
      { name: `🌐 Open in browser  ${chalk.dim(url)}`, value: 'open' },
      { name: `📋 Copy URL`, value: 'copy' },
      { name: `🛑 Stop server  ${chalk.dim(`kill ${port.pid}`)}`, value: 'stop' },
      new inquirer.Separator(),
      { name: chalk.dim('← Back'), value: 'back' }
    ]
  }]);

  switch (action) {
    case 'open':
      await open(url);
      console.log(chalk.green(`  ✓ Opened ${url}`));
      await sleep(500);
      break;
    case 'copy':
      await clipboardy.write(url);
      console.log(chalk.green(`  ✓ Copied ${url} to clipboard`));
      await sleep(500);
      break;
    case 'stop':
      const { confirm } = await inquirer.prompt([{
        type: 'confirm',
        name: 'confirm',
        message: `Stop ${port.projectName || port.process} on port ${port.port}?`,
        default: false
      }]);

      if (confirm) {
        const success = stopProcess(port.pid);
        if (success) {
          console.log(chalk.green(`  ✓ Stopped process ${port.pid}`));
        } else {
          console.log(chalk.red(`  ✗ Failed to stop process ${port.pid}`));
        }
        await sleep(500);
      }
      break;
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

main().catch(console.error);
