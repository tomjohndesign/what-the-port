use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::process::Command;
use std::time::{Duration, SystemTime};
use tauri::{
    menu::{Menu, MenuBuilder, MenuItemBuilder, SubmenuBuilder},
    tray::{TrayIcon, TrayIconBuilder, TrayIconId},
    AppHandle,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ListeningPort {
    port: u16,
    pid: u32,
    process: String,
    project_name: Option<String>,
    working_dir: Option<String>,
    start_time: u64, // Unix timestamp
}

// Default allowlist of common development process names
fn default_allowlist() -> HashSet<&'static str> {
    [
        "node", "npm", "npx", "deno", "bun",
        "Python", "python", "python3", "uvicorn", "gunicorn", "flask", "django",
        "ruby", "rails", "puma", "unicorn",
        "php", "php-fpm",
        "java", "gradle", "mvn",
        "go", "air",
        "cargo", "rustc",
        "dotnet",
        "beam.smp", "elixir", "mix",
        "nginx", "httpd", "apache",
        "postgres", "mysql", "redis-server", "mongod",
        "docker-proxy",
    ]
    .into_iter()
    .collect()
}

fn scan_ports() -> Vec<ListeningPort> {
    let output = Command::new("lsof")
        .args(["-iTCP", "-sTCP:LISTEN", "-P", "-n"])
        .output();

    let output = match output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).to_string(),
        Err(_) => return vec![],
    };

    let allowlist = default_allowlist();
    let mut seen: HashSet<u16> = HashSet::new();
    let mut ports: Vec<ListeningPort> = vec![];

    for line in output.lines().skip(1) {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() < 9 {
            continue;
        }

        let process_name = cols[0].to_string();
        let pid: u32 = match cols[1].parse() {
            Ok(p) => p,
            Err(_) => continue,
        };

        // NAME field is second-to-last
        let name_field = cols[cols.len() - 2];
        let port: u16 = match name_field.rsplit(':').next().and_then(|p| p.parse().ok()) {
            Some(p) => p,
            None => continue,
        };

        // Filter by port range and allowlist
        if port < 3000 || port > 9999 {
            continue;
        }
        if !allowlist.contains(process_name.as_str()) {
            continue;
        }

        if seen.insert(port) {
            let working_dir = get_working_directory(pid);
            let project_name = extract_project_name(working_dir.as_deref());
            let start_time = get_process_start_time(pid);

            ports.push(ListeningPort {
                port,
                pid,
                process: process_name,
                project_name,
                working_dir,
                start_time,
            });
        }
    }

    ports.sort_by_key(|p| p.port);
    ports
}

fn get_working_directory(pid: u32) -> Option<String> {
    let output = Command::new("lsof")
        .args(["-a", "-p", &pid.to_string(), "-d", "cwd", "-Fn"])
        .output()
        .ok()?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if let Some(path) = line.strip_prefix('n') {
            return Some(path.to_string());
        }
    }
    None
}

fn get_process_start_time(pid: u32) -> u64 {
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "lstart="])
        .output();

    if let Ok(output) = output {
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        // Parse format like "Mon Jan 13 08:30:00 2026"
        if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(&stdout, "%a %b %d %H:%M:%S %Y") {
            return dt.and_utc().timestamp() as u64;
        }
    }

    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn extract_project_name(working_dir: Option<&str>) -> Option<String> {
    let working_dir = working_dir?;

    // Try package.json
    let package_json = std::path::Path::new(working_dir).join("package.json");
    if let Ok(content) = std::fs::read_to_string(&package_json) {
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
            if let Some(name) = json.get("name").and_then(|n| n.as_str()) {
                return Some(name.to_string());
            }
        }
    }

    // Fallback to directory name
    std::path::Path::new(working_dir)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
}

fn format_uptime(start_time: u64) -> String {
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let elapsed = now.saturating_sub(start_time);

    if elapsed < 60 {
        format!("{}s", elapsed)
    } else if elapsed < 3600 {
        format!("{}m", elapsed / 60)
    } else if elapsed < 86400 {
        let hours = elapsed / 3600;
        let minutes = (elapsed % 3600) / 60;
        if minutes > 0 {
            format!("{}h {}m", hours, minutes)
        } else {
            format!("{}h", hours)
        }
    } else {
        let days = elapsed / 86400;
        let hours = (elapsed % 86400) / 3600;
        if hours > 0 {
            format!("{}d {}h", days, hours)
        } else {
            format!("{}d", days)
        }
    }
}

fn stop_process(pid: u32) -> bool {
    Command::new("kill")
        .args(["-TERM", &pid.to_string()])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn build_tray_menu(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let ports = scan_ports();

    let mut builder = MenuBuilder::new(app);

    if ports.is_empty() {
        let no_ports = MenuItemBuilder::new("No dev servers running")
            .enabled(false)
            .build(app)?;
        builder = builder.item(&no_ports);
    } else {
        for port in &ports {
            let name = port.project_name.as_deref().unwrap_or(&port.process);
            let uptime = format_uptime(port.start_time);
            let label = format!(":{} {} • {}", port.port, name, uptime);

            let open_id = format!("open_{}", port.port);
            let copy_id = format!("copy_{}", port.port);
            let stop_id = format!("stop_{}_{}", port.port, port.pid);

            let open_item = MenuItemBuilder::new("Open in Browser")
                .id(&open_id)
                .build(app)?;
            let copy_item = MenuItemBuilder::new("Copy URL")
                .id(&copy_id)
                .build(app)?;
            let stop_item = MenuItemBuilder::new("Stop Server")
                .id(&stop_id)
                .build(app)?;

            let submenu = SubmenuBuilder::new(app, &label)
                .item(&open_item)
                .item(&copy_item)
                .separator()
                .item(&stop_item)
                .build()?;

            builder = builder.item(&submenu);
        }
    }

    builder = builder.separator();

    let refresh = MenuItemBuilder::new("Refresh")
        .id("refresh")
        .accelerator("CmdOrCtrl+R")
        .build(app)?;
    builder = builder.item(&refresh);

    builder = builder.separator();

    let quit = MenuItemBuilder::new("Quit")
        .id("quit")
        .accelerator("CmdOrCtrl+Q")
        .build(app)?;
    builder = builder.item(&quit);

    builder.build()
}

fn update_tray_menu(app: &AppHandle, tray: &TrayIcon) {
    if let Ok(menu) = build_tray_menu(app) {
        let _ = tray.set_menu(Some(menu));
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let handle = app.handle().clone();

            // Build initial menu
            let menu = build_tray_menu(&handle)?;

            // Create tray icon
            let tray_id = TrayIconId::new("main");
            let tray = TrayIconBuilder::with_id(tray_id)
                .menu(&menu)
                .tooltip("What The Port")
                .on_menu_event(move |app, event| {
                    let id = event.id().as_ref();

                    if id == "quit" {
                        app.exit(0);
                    } else if id == "refresh" {
                        if let Some(tray) = app.tray_by_id("main") {
                            update_tray_menu(app, &tray);
                        }
                    } else if let Some(port_str) = id.strip_prefix("open_") {
                        if let Ok(port) = port_str.parse::<u16>() {
                            let url = format!("http://localhost:{}", port);
                            let _ = open::that(&url);
                        }
                    } else if let Some(port_str) = id.strip_prefix("copy_") {
                        if let Ok(port) = port_str.parse::<u16>() {
                            let url = format!("http://localhost:{}", port);
                            #[cfg(target_os = "macos")]
                            {
                                let _ = Command::new("pbcopy")
                                    .stdin(std::process::Stdio::piped())
                                    .spawn()
                                    .and_then(|mut child| {
                                        use std::io::Write;
                                        if let Some(stdin) = child.stdin.as_mut() {
                                            stdin.write_all(url.as_bytes())?;
                                        }
                                        child.wait()
                                    });
                            }
                        }
                    } else if let Some(rest) = id.strip_prefix("stop_") {
                        // Format: stop_PORT_PID
                        let parts: Vec<&str> = rest.split('_').collect();
                        if parts.len() == 2 {
                            if let Ok(pid) = parts[1].parse::<u32>() {
                                stop_process(pid);
                                // Refresh menu after stopping
                                if let Some(tray) = app.tray_by_id("main") {
                                    // Small delay to let process stop
                                    std::thread::sleep(Duration::from_millis(500));
                                    update_tray_menu(app, &tray);
                                }
                            }
                        }
                    }
                })
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(true)
                .build(app)?;

            // Auto-refresh every 5 seconds
            let handle_clone = handle.clone();
            std::thread::spawn(move || {
                loop {
                    std::thread::sleep(Duration::from_secs(5));
                    if let Some(tray) = handle_clone.tray_by_id("main") {
                        update_tray_menu(&handle_clone, &tray);
                    }
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
