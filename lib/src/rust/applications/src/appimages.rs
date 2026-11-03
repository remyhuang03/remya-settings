//! AppImage library: one folder, desktop integration and updates from release sources.
//! Long work runs on worker threads because the service state lock must stay available.
//! Images are read with `backhand` as SquashFS, so none is executed; deltas use `zsync-rs`.
use backhand::{FilesystemReader, InnerNode, Node, SquashfsFileReader};
use gio::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    io::{BufReader, Read, Seek, SeekFrom, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub const INSTALL: &str = "appimages.install";
pub const CHECK: &str = "appimages.check";
pub const UPDATE: &str = "appimages.update";
pub const CANCEL: &str = "appimages.cancel";
pub const SOURCE: &str = "appimages.source";
pub const INTEGRATE: &str = "appimages.integrate";
pub const OPEN: &str = "appimages.open";
pub const UNINSTALL: &str = "appimages.uninstall";
pub const AUTO_CHECK: &str = "appimages.auto-check";
pub const AUTO_UPDATE: &str = "appimages.auto-update";
const DAY: u64 = 86_400;
const RETRY: u64 = 3_600;

pub fn is_setting(id: &str) -> bool {
    id.starts_with("appimages.")
}
fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AppPrefs {
    source: Option<String>,
    updates_disabled: bool,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Prefs {
    auto_check: bool,
    auto_update: bool,
    last_check: u64,
    apps: BTreeMap<String, AppPrefs>,
}
impl Default for Prefs {
    fn default() -> Self {
        Self {
            auto_check: true,
            auto_update: false,
            last_check: 0,
            apps: BTreeMap::new(),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
enum Source {
    Github {
        owner: String,
        repo: String,
        tag: String,
        glob: Option<String>,
    },
    Zsync(String),
}
fn slug(text: &str) -> bool {
    !text.is_empty()
        && !text.starts_with('.')
        && text
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
}
fn parse_source(text: &str) -> Result<Source, String> {
    let text = text.trim();
    let parts = text.split('|').collect::<Vec<_>>();
    if let ["gh-releases-zsync", owner, repo, tag, glob] = parts[..]
        && slug(owner)
        && slug(repo)
        && !tag.contains(['/', '?', '#'])
        && !glob.contains('/')
    {
        return Ok(Source::Github {
            owner: owner.into(),
            repo: repo.into(),
            tag: tag.into(),
            glob: Some(glob.into()),
        });
    }
    if let ["zsync", url] = parts[..] {
        return https(url).map(|url| Source::Zsync(url.into()));
    }
    if let Some(path) = text.strip_prefix("https://github.com/") {
        let path = path.trim_end_matches('/').trim_end_matches(".git");
        if let [owner, repo] = path.split('/').collect::<Vec<_>>()[..]
            && slug(owner)
            && slug(repo)
        {
            return Ok(Source::Github {
                owner: owner.into(),
                repo: repo.into(),
                tag: "latest".into(),
                glob: None,
            });
        }
    }
    if text.ends_with(".zsync") {
        return https(text).map(|url| Source::Zsync(url.into()));
    }
    Err(invalid(
        "Use https://github.com/owner/repo, an https .zsync URL or AppImage update information",
    ))
}
fn https(url: &str) -> Result<&str, String> {
    if url.starts_with("https://") && !url.contains(|c: char| c.is_whitespace() || c.is_control()) {
        Ok(url)
    } else {
        Err(invalid("Update sources must use https"))
    }
}

#[derive(Clone, Debug, PartialEq)]
struct Remote {
    version: Option<String>,
    /// The whole file; absent when only a zsync control file is published.
    url: Option<String>,
    zsync: Option<String>,
    size: u64,
    /// ("sha256sum" or "sha1sum", lowercase hex).
    digest: Option<(&'static str, String)>,
}
#[derive(Deserialize)]
struct Asset {
    name: String,
    size: u64,
    browser_download_url: String,
    digest: Option<String>,
}
#[derive(Deserialize)]
struct Release {
    tag_name: String,
    assets: Vec<Asset>,
}
fn glob_match(glob: &str, name: &str) -> bool {
    let parts = glob.split('*').collect::<Vec<_>>();
    if parts.len() == 1 {
        return glob == name;
    }
    let (first, last) = (parts[0], parts[parts.len() - 1]);
    if !name.starts_with(first) || !name[first.len()..].ends_with(last) {
        return false;
    }
    let mut rest = &name[first.len()..name.len() - last.len()];
    for part in &parts[1..parts.len() - 1] {
        match rest.find(part) {
            Some(at) => rest = &rest[at + part.len()..],
            None => return false,
        }
    }
    true
}
fn arch_matches(name: &str) -> bool {
    const ALL: [(&str, &[&str]); 5] = [
        ("x86_64", &["x86_64", "x86-64", "amd64"]),
        ("aarch64", &["aarch64", "arm64"]),
        ("arm", &["armhf", "armv7"]),
        ("x86", &["i386", "i686"]),
        ("riscv64", &["riscv64"]),
    ];
    let name = name.to_lowercase();
    ALL.iter().all(|(arch, tags)| {
        *arch == std::env::consts::ARCH || !tags.iter().any(|t| name.contains(t))
    })
}
fn pick_asset<'a>(assets: &'a [Asset], glob: Option<&str>) -> Option<&'a Asset> {
    let image = |a: &&Asset| a.name.to_lowercase().ends_with(".appimage") && arch_matches(&a.name);
    match glob {
        Some(glob) => assets
            .iter()
            .filter(|a| glob_match(glob, &a.name))
            .filter_map(|z| z.name.strip_suffix(".zsync"))
            .find_map(|name| assets.iter().find(|a| a.name == name))
            .filter(|a| image(a)),
        None => assets.iter().find(image),
    }
}
/// Plain http is refused here, including on redirects and in zsync control files.
fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .https_only(true)
        .timeout_connect(Some(Duration::from_secs(30)))
        .timeout_recv_response(Some(Duration::from_secs(60)))
        .build()
        .new_agent()
}
fn fetch(url: &str) -> Result<Vec<u8>, String> {
    agent()
        .get(url)
        .call()
        .and_then(|mut response| {
            response
                .body_mut()
                .with_config()
                .limit(32 << 20)
                .read_to_vec()
        })
        .map_err(|e| format!("{url}: {e}"))
}
fn resolve(source: &Source) -> Result<Remote, String> {
    match source {
        Source::Zsync(url) => {
            let control = zsync_rs::http::HttpClient::with_agent(agent())
                .fetch_control_file(url)
                .map_err(|e| format!("{url}: {e}"))?;
            Ok(Remote {
                version: None,
                url: None,
                zsync: Some(url.clone()),
                size: control.length,
                digest: control.sha1.map(|d| ("sha1sum", d.to_lowercase())),
            })
        }
        Source::Github {
            owner,
            repo,
            tag,
            glob,
        } => {
            let base = format!("https://api.github.com/repos/{owner}/{repo}/releases");
            let release: Release = match tag.as_str() {
                "latest" => serde_json::from_slice(&fetch(&format!("{base}/latest"))?),
                "latest-pre" | "latest-all" => {
                    let list: Vec<Release> = serde_json::from_slice(&fetch(&base)?)
                        .map_err(|e| format!("Invalid release list: {e}"))?;
                    Ok(list.into_iter().next().ok_or("No releases found")?)
                }
                tag => serde_json::from_slice(&fetch(&format!("{base}/tags/{tag}"))?),
            }
            .map_err(|e| format!("Invalid release data: {e}"))?;
            let asset = pick_asset(&release.assets, glob.as_deref()).ok_or(format!(
                "Release {} has no AppImage for this architecture",
                release.tag_name
            ))?;
            https(&asset.browser_download_url)?;
            let control = format!("{}.zsync", asset.name);
            Ok(Remote {
                version: Some(release.tag_name.trim_start_matches('v').to_string()),
                url: Some(asset.browser_download_url.clone()),
                zsync: release
                    .assets
                    .iter()
                    .find(|a| a.name == control)
                    .map(|a| a.browser_download_url.clone()),
                size: asset.size,
                digest: asset
                    .digest
                    .as_deref()
                    .and_then(|d| d.strip_prefix("sha256:"))
                    .map(|d| ("sha256sum", d.to_lowercase())),
            })
        }
    }
}
fn hash(tool: &str, path: &Path) -> Result<String, String> {
    let out = Command::new(format!("/usr/bin/{tool}"))
        .arg("--")
        .arg(path)
        .stdin(Stdio::null())
        .output()
        .map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .next()
        .map(str::to_lowercase)
        .ok_or("Checksum tool returned nothing".into())
}
/// A published checksum decides; without one, a size change means a new build.
fn is_current(remote: &Remote, path: &Path) -> Result<bool, String> {
    match &remote.digest {
        Some((tool, digest)) => Ok(hash(tool, path)? == *digest),
        None => Ok(fs::metadata(path).map_err(|e| e.to_string())?.len() == remote.size),
    }
}

/// ELF magic plus the type 2 AppImage marker at offset 8.
fn is_appimage(path: &Path) -> bool {
    let mut head = [0u8; 11];
    fs::File::open(path)
        .and_then(|mut f| f.read_exact(&mut head))
        .is_ok()
        && head[..4] == *b"\x7fELF"
        && head[8..11] == *b"AI\x02"
}
/// Recognize launchers for images in the same library the AppImages feature manages.
pub(crate) fn managed_launcher(exec: &str, directory: &Path) -> Option<PathBuf> {
    let args = gio::glib::shell_parse_argv(exec).ok()?;
    let mut args = args.iter();
    let first = args.next()?;
    let executable = if Path::new(first).file_name()? == "env" {
        args.find(|arg| !arg.to_string_lossy().contains('='))?
    } else {
        first
    };
    let path = PathBuf::from(executable);
    (path.is_absolute()
        && path.parent() == Some(directory)
        && path.file_name()?.to_str().is_some_and(valid_id)
        && path.is_file()
        && is_appimage(&path))
    .then_some(path)
}

/// Section headers of a 64-bit little-endian ELF runtime, and where the runtime ends.
type Sections = Vec<(Vec<u8>, u64, u64)>;
fn elf_sections(file: &mut fs::File) -> Option<(Sections, u64)> {
    let length = file.metadata().ok()?.len();
    let mut head = [0u8; 64];
    file.seek(SeekFrom::Start(0)).ok()?;
    file.read_exact(&mut head).ok()?;
    if head[..4] != *b"\x7fELF" || head[4] != 2 || head[5] != 1 {
        return None;
    }
    let u64_at = |b: &[u8], at: usize| u64::from_le_bytes(b[at..at + 8].try_into().unwrap());
    let u16_at = |at: usize| u16::from_le_bytes(head[at..at + 2].try_into().unwrap()) as usize;
    let (offset, count, names) = (u64_at(&head, 40), u16_at(60), u16_at(62));
    if count == 0 || names >= count || u16_at(58) != 64 {
        return None;
    }
    let mut read = |at: u64, size: u64| -> Option<Vec<u8>> {
        if size > 1 << 20 || at.checked_add(size)? > length {
            return None;
        }
        let mut data = vec![0; size as usize];
        file.seek(SeekFrom::Start(at)).ok()?;
        file.read_exact(&mut data).ok()?;
        Some(data)
    };
    let table = read(offset, count as u64 * 64)?;
    let strings = read(
        u64_at(&table, names * 64 + 24),
        u64_at(&table, names * 64 + 32),
    )?;
    let mut end = offset + count as u64 * 64;
    let mut sections = vec![];
    for section in table.as_chunks::<64>().0 {
        let name = u32::from_le_bytes(section[..4].try_into().unwrap()) as usize;
        let name = strings.get(name..)?.split(|b| *b == 0).next()?.to_vec();
        let (at, size) = (u64_at(section, 24), u64_at(section, 32));
        // SHT_NOBITS occupies no file space.
        if u32::from_le_bytes(section[4..8].try_into().unwrap()) != 8 {
            end = end.max(at.checked_add(size)?);
        }
        sections.push((name, at, size));
    }
    Some((sections, end))
}
fn embedded_update_info(path: &Path) -> Option<String> {
    let mut file = fs::File::open(path).ok()?;
    let (sections, _) = elf_sections(&mut file)?;
    let (_, at, size) = sections.into_iter().find(|(n, ..)| n == b".upd_info")?;
    if size > 4096 {
        return None;
    }
    let mut data = vec![0; size as usize];
    file.seek(SeekFrom::Start(at)).ok()?;
    file.read_exact(&mut data).ok()?;
    let text = std::str::from_utf8(data.split(|b| *b == 0).next()?)
        .ok()?
        .trim();
    (!text.is_empty()).then(|| text.to_string())
}

fn desktop_fields(text: &str) -> Vec<(String, String)> {
    let mut inside = false;
    let mut fields = vec![];
    for line in text.lines() {
        if line.starts_with('[') {
            inside = line.trim() == "[Desktop Entry]";
        } else if inside
            && !line.starts_with('#')
            && let Some((key, value)) = line.split_once('=')
        {
            fields.push((key.trim().to_string(), value.trim().to_string()));
        }
    }
    fields
}
fn field<'a>(fields: &'a [(String, String)], key: &str) -> Option<&'a str> {
    fields
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.as_str())
}
/// Desktop Exec quoting, then the string-value escaping the specification layers on top.
fn exec_quote(path: &Path) -> String {
    let mut value = path.to_string_lossy().replace('%', "%%");
    for c in ['\\', '"', '`', '$'] {
        value = value.replace(c, &format!("\\{c}"));
    }
    format!("\"{}\"", value.replace('\\', "\\\\"))
}
/// The visible entry; hidden ones are the application's own URL or folder handlers.
fn launcher<'a>(
    entries: &'a [(PathBuf, Vec<(String, String)>)],
    path: &Path,
) -> Option<&'a (PathBuf, Vec<(String, String)>)> {
    entries
        .iter()
        .find(|(_, f)| desktop_refers(f, path) && field(f, "NoDisplay") != Some("true"))
}
fn desktop_refers(fields: &[(String, String)], path: &Path) -> bool {
    field(fields, "Exec").is_some_and(|exec| {
        exec.contains(&*path.to_string_lossy()) || exec.contains(&exec_quote(path))
    })
}
/// Keeps the application's descriptive keys. Exec and actions never come from the image.
fn render_entry(
    embedded: &[(String, String)],
    previous: &[(String, String)],
    path: &Path,
    icon: Option<&str>,
) -> String {
    // Descriptive keys only; anything executable or non-standard stays out of the launcher.
    const KEPT: [&str; 13] = [
        "Name",
        "GenericName",
        "Comment",
        "Categories",
        "Keywords",
        "MimeType",
        "StartupWMClass",
        "StartupNotify",
        "Terminal",
        "OnlyShowIn",
        "NotShowIn",
        "PrefersNonDefaultGPU",
        "SingleMainWindow",
    ];
    let name = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let code = field(embedded, "Exec")
        .and_then(|exec| {
            ["%F", "%f", "%U", "%u"]
                .into_iter()
                .find(|c| exec.contains(c))
        })
        .map_or(String::new(), |c| format!(" {c}"));
    let mut text = String::from("[Desktop Entry]\nType=Application\n");
    if field(embedded, "Name").is_none() {
        text += &format!("Name={name}\n");
    }
    // The runtime's optional self-integration prompt must not compete with this launcher.
    text += &format!("Exec=env DESKTOPINTEGRATION=1 {}{code}\n", exec_quote(path));
    if let Some(icon) = icon {
        text += &format!("Icon={icon}\n");
    }
    for (key, value) in embedded {
        let base = key.split('[').next().unwrap_or(key);
        if KEPT.contains(&base) || base.starts_with("X-") {
            text += &format!("{key}={value}\n");
        }
    }
    for key in ["X-AppImage-UpdateURL", "X-AppImage-Homepage"] {
        if field(embedded, key).is_none()
            && let Some(value) = field(previous, key)
        {
            text += &format!("{key}={value}\n");
        }
    }
    text
}
fn atomic_write(path: &Path, content: &[u8], mode: u32) -> Result<(), String> {
    let parent = path.parent().ok_or("Path has no parent")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    file.as_file()
        .set_permissions(fs::Permissions::from_mode(mode))
        .map_err(|e| e.to_string())?;
    file.write_all(content)
        .and_then(|_| file.as_file().sync_all())
        .map_err(|e| e.to_string())?;
    file.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}
fn safe_name(name: &str) -> String {
    name.chars()
        .filter(|c| c.is_ascii_alphanumeric() || "-_.+ ".contains(*c))
        .collect::<String>()
        .trim()
        .trim_start_matches(['.', '-'])
        .replace(' ', "-")
}
fn valid_id(id: &str) -> bool {
    !id.starts_with(['.', '-'])
        && !id.contains('/')
        && id.len() <= 255
        && id.to_lowercase().ends_with(".appimage")
}

struct Extracted {
    fields: Vec<(String, String)>,
    desktop_name: Option<String>,
    icon: Option<(Vec<u8>, &'static str)>,
}
/// Lexical resolution inside the payload; links can never leave its root.
fn payload_path(base: &Path, link: &Path) -> PathBuf {
    let mut path = if link.is_absolute() {
        PathBuf::from("/")
    } else {
        base.parent().unwrap_or(Path::new("/")).to_path_buf()
    };
    for part in link.components() {
        match part {
            std::path::Component::Normal(part) => path.push(part),
            std::path::Component::ParentDir => {
                path.pop();
            }
            _ => {}
        }
    }
    path
}
fn extract(image: &Path) -> Result<Extracted, String> {
    let unreadable = |e: &dyn std::fmt::Display| format!("Cannot read the AppImage: {e}");
    let mut file = fs::File::open(image).map_err(|e| unreadable(&e))?;
    let (_, offset) = elf_sections(&mut file).ok_or("Not a 64-bit little-endian AppImage")?;
    let mut magic = [0u8; 4];
    file.seek(SeekFrom::Start(offset))
        .map_err(|e| unreadable(&e))?;
    // shortcut: SquashFS payloads only; DwarFS images need a reader if one is ever installed.
    if file.read_exact(&mut magic).is_err() || magic != *b"hsqs" {
        return Err("Only SquashFS AppImages are supported".into());
    }
    let reader = FilesystemReader::from_reader_with_offset(BufReader::new(file), offset)
        .map_err(|e| unreadable(&e))?;
    let nodes = reader
        .files()
        .map(|n| (n.fullpath.clone(), n))
        .collect::<BTreeMap<_, &Node<SquashfsFileReader>>>();
    let read = |path: &str, limit: usize| -> Option<Vec<u8>> {
        let mut path = PathBuf::from(path);
        for _ in 0..8 {
            match &nodes.get(&path)?.inner {
                InnerNode::Symlink(link) => path = payload_path(&path, &link.link),
                InnerNode::File(file) if file.file_len() <= limit => {
                    let mut data = Vec::with_capacity(file.file_len());
                    reader.file(file).reader().read_to_end(&mut data).ok()?;
                    return Some(data);
                }
                _ => return None,
            }
        }
        None
    };
    let desktop_name = nodes
        .keys()
        .filter(|p| p.parent() == Some(Path::new("/")))
        .filter_map(|p| p.file_name()?.to_str())
        .find(|n| n.ends_with(".desktop"))
        .map(str::to_string);
    let fields = desktop_name
        .as_ref()
        .and_then(|n| read(&format!("/{n}"), 1 << 20))
        .map_or(vec![], |d| desktop_fields(&String::from_utf8_lossy(&d)));
    const ICON_LIMIT: usize = 16 << 20;
    let named = field(&fields, "Icon").filter(|n| slug(n)).and_then(|name| {
        ["svg", "png"]
            .into_iter()
            .find_map(|ext| Some((read(&format!("/{name}.{ext}"), ICON_LIMIT)?, ext)))
    });
    let icon = named.or_else(|| {
        read("/.DirIcon", ICON_LIMIT)
            .filter(|d| d.starts_with(b"\x89PNG"))
            .map(|d| (d, "png"))
    });
    Ok(Extracted {
        fields,
        desktop_name,
        icon,
    })
}

#[derive(Clone, Default, Serialize)]
struct Job {
    status: String,
    bytes: u64,
    total: u64,
    speed: u64,
    #[serde(skip)]
    cancel: Arc<AtomicBool>,
}
#[derive(Clone, Default)]
struct Outcome {
    latest: Option<Remote>,
    checked: bool,
    error: Option<String>,
}
struct Paths {
    dir: PathBuf,
    applications: PathBuf,
    system_applications: PathBuf,
    icons: PathBuf,
    bin: PathBuf,
    config: PathBuf,
}
struct Inner {
    paths: Paths,
    prefs: Mutex<Prefs>,
    config_error: Mutex<Option<String>>,
    jobs: Mutex<BTreeMap<String, Job>>,
    outcomes: Mutex<BTreeMap<String, Outcome>>,
    installing: Mutex<Vec<String>>,
    error: Mutex<Option<String>>,
    last_attempt: Mutex<u64>,
    dirty: AtomicBool,
}
/// Cloned into worker threads and the service main loop.
#[derive(Clone)]
pub struct AppImages(Arc<Inner>);
#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Check,
    Update,
}
struct Row {
    id: String,
    path: PathBuf,
    size: u64,
    desktop: Option<(PathBuf, Vec<(String, String)>)>,
    source: Option<(String, &'static str)>,
    updates: bool,
}

impl AppImages {
    pub fn real(config: PathBuf) -> Result<Self, String> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .ok_or("Absolute HOME required")?;
        let data = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| home.join(".local/share"));
        Ok(Self::new(Paths {
            dir: home.join("AppImages"),
            applications: data.join("applications"),
            system_applications: "/usr/share/applications".into(),
            icons: data.join("icons"),
            bin: home.join(".local/bin"),
            config,
        }))
    }
    fn new(paths: Paths) -> Self {
        let (prefs, config_error) = match fs::read_to_string(&paths.config) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (Prefs::default(), None),
            Err(e) => (Prefs::default(), Some(e.to_string())),
            Ok(text) => match toml::from_str(&text) {
                Ok(prefs) => (prefs, None),
                Err(e) => (Prefs::default(), Some(format!("Invalid {e}"))),
            },
        };
        Self(Arc::new(Inner {
            paths,
            prefs: Mutex::new(prefs),
            config_error: Mutex::new(config_error),
            jobs: Mutex::default(),
            outcomes: Mutex::default(),
            installing: Mutex::default(),
            error: Mutex::default(),
            last_attempt: Mutex::new(0),
            dirty: AtomicBool::new(false),
        }))
    }
    fn touch(&self) {
        self.0.dirty.store(true, Ordering::Relaxed);
    }
    /// True once per change so the one-second service tick publishes live progress.
    pub fn take_dirty(&self) -> bool {
        self.0.dirty.swap(false, Ordering::Relaxed)
    }
    fn save(&self, change: impl FnOnce(&mut Prefs)) -> Result<(), String> {
        if let Some(error) = self.0.config_error.lock().unwrap().clone() {
            return Err(format!("AppImage preferences were not changed: {error}"));
        }
        let mut prefs = self.0.prefs.lock().unwrap();
        let mut next = prefs.clone();
        change(&mut next);
        let text = toml::to_string(&next).map_err(|e| e.to_string())?;
        atomic_write(&self.0.paths.config, text.as_bytes(), 0o600)?;
        *prefs = next;
        self.touch();
        Ok(())
    }
    fn entries(&self) -> Vec<(PathBuf, Vec<(String, String)>)> {
        let mut entries = fs::read_dir(&self.0.paths.applications)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.path().extension().is_some_and(|x| x == "desktop"))
            .filter_map(|e| {
                let text = fs::read_to_string(e.path()).ok()?;
                Some((e.path(), desktop_fields(&text)))
            })
            .collect::<Vec<_>>();
        entries.sort_by(|a, b| a.0.cmp(&b.0));
        entries
    }
    fn rows(&self) -> Vec<Row> {
        let entries = self.entries();
        let prefs = self.0.prefs.lock().unwrap().clone();
        let mut rows = fs::read_dir(&self.0.paths.dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|entry| {
                let id = entry.file_name().to_string_lossy().into_owned();
                let path = entry.path();
                if !valid_id(&id) || !is_appimage(&path) {
                    return None;
                }
                let desktop = launcher(&entries, &path).cloned();
                let saved = prefs.apps.get(&id).cloned().unwrap_or_default();
                let source = saved
                    .source
                    .map(|s| (s, "custom"))
                    .or_else(|| embedded_update_info(&path).map(|s| (s, "embedded")))
                    .or_else(|| {
                        desktop
                            .as_ref()
                            .and_then(|(_, f)| field(f, "X-AppImage-UpdateURL"))
                            .map(|s| (s.to_string(), "desktop"))
                    });
                Some(Row {
                    size: entry.metadata().ok()?.len(),
                    id,
                    path,
                    desktop,
                    source,
                    updates: !saved.updates_disabled,
                })
            })
            .collect::<Vec<_>>();
        rows.sort_by_cached_key(|r| r.id.to_lowercase());
        rows
    }
    pub fn state(&self) -> Value {
        let prefs = self.0.prefs.lock().unwrap().clone();
        let jobs = self.0.jobs.lock().unwrap().clone();
        let outcomes = self.0.outcomes.lock().unwrap().clone();
        let apps = self
            .rows()
            .into_iter()
            .map(|row| {
                let fields = row.desktop.as_ref().map(|(_, f)| f.as_slice()).unwrap_or(&[]);
                let outcome = outcomes.get(&row.id).cloned().unwrap_or_default();
                json!({
                    "id": row.id,
                    "name": field(fields, "Name").map(str::to_string).unwrap_or_else(|| {
                        row.path.file_stem().unwrap_or_default().to_string_lossy().into_owned()
                    }),
                    "icon": field(fields, "Icon"),
                    "version": field(fields, "X-AppImage-Version"),
                    "path": row.path,
                    "size": row.size,
                    "integrated": row.desktop.is_some(),
                    "source": row.source.as_ref().map(|s| &s.0),
                    "source_origin": row.source.as_ref().map(|s| s.1),
                    "updates": row.updates,
                    "job": jobs.get(&row.id),
                    "checked": outcome.checked,
                    "available": outcome.latest.as_ref().map(|r| json!({"version": r.version, "size": r.size})),
                    "error": outcome.error,
                })
            })
            .collect::<Vec<_>>();
        json!({
            "api_version": 1,
            "directory": self.0.paths.dir,
            "auto_check": prefs.auto_check,
            "auto_update": prefs.auto_update,
            "last_check": prefs.last_check,
            "installing": *self.0.installing.lock().unwrap(),
            "error": self.0.error.lock().unwrap().clone().or(self.0.config_error.lock().unwrap().clone()),
            "apps": apps,
        })
    }
    pub fn read_setting(&self, id: &str) -> Value {
        let state = self.state();
        let value = match id {
            AUTO_CHECK => state["auto_check"].clone(),
            AUTO_UPDATE => state["auto_update"].clone(),
            _ => Value::Null,
        };
        json!({"id": id, "availability": "available", "value": value, "state": state})
    }
    pub fn set(&self, id: &str, value: &str) -> Result<Value, String> {
        match id {
            INSTALL => self.install(value),
            CHECK => self.start(value, Mode::Check, false),
            UPDATE => self.start(value, Mode::Update, false),
            CANCEL => self.cancel(value),
            SOURCE => self.set_source(value),
            INTEGRATE => self.integrate_now(value),
            OPEN => self.open(value),
            UNINSTALL => self.uninstall(value),
            AUTO_CHECK | AUTO_UPDATE => {
                let enabled: bool =
                    serde_json::from_str(value).map_err(|_| invalid("Use true or false"))?;
                self.save(|p| {
                    if id == AUTO_CHECK {
                        p.auto_check = enabled;
                    } else {
                        p.auto_update = enabled;
                    }
                })?;
                Ok(json!({"id": id, "value": enabled}))
            }
            _ => Err(invalid("Unknown AppImage setting")),
        }
    }
    fn row(&self, id: &str) -> Result<Row, String> {
        if !valid_id(id) {
            return Err(invalid("Invalid AppImage ID"));
        }
        self.rows()
            .into_iter()
            .find(|r| r.id == id)
            .ok_or_else(|| invalid("Unknown AppImage"))
    }
    fn idle(&self, id: &str) -> Result<(), String> {
        if self.0.jobs.lock().unwrap().contains_key(id) {
            return Err(format!("Conflict:{id} is busy"));
        }
        Ok(())
    }
    fn start(&self, value: &str, mode: Mode, automatic: bool) -> Result<Value, String> {
        let rows = self.rows();
        let all = value == "all";
        if !all {
            let row = self.row(value)?;
            if row.source.is_none() {
                return Err(format!("Unavailable:{value} has no update source"));
            }
        }
        let ids = {
            let mut jobs = self.0.jobs.lock().unwrap();
            let ids = rows
                .into_iter()
                .filter(|r| {
                    r.source.is_some()
                        && !jobs.contains_key(&r.id)
                        && if all { r.updates } else { r.id == value }
                })
                .map(|r| r.id)
                .collect::<Vec<_>>();
            for id in &ids {
                jobs.insert(
                    id.clone(),
                    Job {
                        status: "queued".into(),
                        ..Job::default()
                    },
                );
            }
            ids
        };
        self.touch();
        let worker = self.clone();
        let started = ids.clone();
        std::thread::spawn(move || {
            let mut clean = true;
            for id in &ids {
                clean &= worker.process(id, mode);
            }
            if all && (clean || !automatic) {
                let _ = worker.save(|p| p.last_check = now());
            }
        });
        Ok(json!({"started": started}))
    }
    fn set_job(&self, id: &str, change: impl FnOnce(&mut Job)) {
        if let Some(job) = self.0.jobs.lock().unwrap().get_mut(id) {
            change(job);
        }
        self.touch();
    }
    fn cancel_flag(&self, id: &str) -> Arc<AtomicBool> {
        self.0
            .jobs
            .lock()
            .unwrap()
            .get(id)
            .map(|j| j.cancel.clone())
            .unwrap_or_default()
    }
    /// Returns false when the attempt failed, so automatic checks retry sooner.
    fn process(&self, id: &str, mode: Mode) -> bool {
        let result = self.check_and_update(id, mode);
        self.0.jobs.lock().unwrap().remove(id);
        let ok = result.is_ok();
        let mut outcomes = self.0.outcomes.lock().unwrap();
        let outcome = outcomes.entry(id.into()).or_default();
        match result {
            Ok(latest) => {
                *outcome = Outcome {
                    latest,
                    checked: true,
                    error: None,
                };
            }
            Err(error) if error == "Cancelled" => outcome.error = None,
            Err(error) => outcome.error = Some(error),
        }
        drop(outcomes);
        self.touch();
        ok
    }
    fn check_and_update(&self, id: &str, mode: Mode) -> Result<Option<Remote>, String> {
        let row = self
            .row(id)
            .map_err(|e| e.replace("InvalidArgument:", ""))?;
        let source = row.source.as_ref().ok_or("No update source")?;
        self.set_job(id, |j| j.status = "checking".into());
        let remote =
            resolve(&parse_source(&source.0).map_err(|e| e.replace("InvalidArgument:", ""))?)?;
        if is_current(&remote, &row.path)? {
            return Ok(None);
        }
        if mode == Mode::Check {
            return Ok(Some(remote));
        }
        let part = self.0.paths.dir.join(format!(".{id}.part"));
        let result = self.download(id, &remote, &row.path, &part).and_then(|_| {
            if !is_appimage(&part) {
                return Err(
                    "The download is not an AppImage; the installed version was kept".into(),
                );
            }
            if let Some((tool, digest)) = &remote.digest
                && hash(tool, &part)? != *digest
            {
                return Err(
                    "The download failed checksum verification; the installed version was kept"
                        .into(),
                );
            }
            fs::set_permissions(&part, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())
        });
        if let Err(error) = result {
            let _ = fs::remove_file(&part);
            return Err(error);
        }
        self.set_job(id, |j| j.status = "installing".into());
        // Rename keeps the path stable: launchers, command links and running copies stay valid.
        fs::rename(&part, &row.path).map_err(|e| e.to_string())?;
        self.integrate(&row.path, remote.version.as_deref())
            .map_err(|e| format!("Updated, but the launcher was not refreshed: {e}"))?;
        Ok(None)
    }
    /// A delta when the release publishes one; a damaged delta falls back to the whole file.
    fn download(&self, id: &str, remote: &Remote, seed: &Path, part: &Path) -> Result<(), String> {
        self.set_job(id, |j| j.total = remote.size);
        let cancel = self.cancel_flag(id);
        let delta = remote
            .zsync
            .as_ref()
            .map(|url| self.delta(id, url, seed, part, &cancel));
        match (delta, &remote.url) {
            (Some(Ok(())), _) => Ok(()),
            (Some(Err(e)), None) => Err(e),
            (Some(Err(e)), _) if e == "Cancelled" => Err(e),
            (_, Some(url)) => self.whole(id, url, remote.size, part, &cancel),
            (None, None) => Err("The release has no download".into()),
        }
    }
    fn delta(
        &self,
        id: &str,
        url: &str,
        seed: &Path,
        part: &Path,
        cancel: &Arc<AtomicBool>,
    ) -> Result<(), String> {
        let failed = |e: zsync_rs::assembly::AssemblyError| {
            if cancel.load(Ordering::Relaxed) {
                "Cancelled".to_string()
            } else {
                format!("Delta update failed: {e}")
            }
        };
        let mut assembly = zsync_rs::ZsyncAssembly::from_url_with_client(
            url,
            part,
            zsync_rs::http::HttpClient::with_agent(agent()),
        )
        .map_err(failed)?;
        assembly.set_abort_flag(cancel.clone());
        let worker = self.clone();
        let job = id.to_string();
        assembly.set_scan_progress_callback(move |done, total| {
            worker.set_job(&job, |j| {
                j.status = "comparing".into();
                (j.bytes, j.total) = (done, total);
            });
        });
        let worker = self.clone();
        let job = id.to_string();
        let meter = Mutex::new(Meter::new());
        assembly.set_progress_callback(move |done, total| {
            let speed = meter.lock().unwrap().sample(done);
            worker.set_job(&job, |j| {
                j.status = "downloading".into();
                (j.bytes, j.total) = (done, total);
                j.speed = speed.unwrap_or(j.speed);
            });
        });
        assembly.submit_source_file(seed).map_err(failed)?;
        assembly.submit_self_referential().map_err(failed)?;
        while assembly.download_missing_blocks().map_err(failed)? > 0 {}
        assembly.complete().map_err(failed)
    }
    fn whole(
        &self,
        id: &str,
        url: &str,
        size: u64,
        part: &Path,
        cancel: &AtomicBool,
    ) -> Result<(), String> {
        let response = agent()
            .get(url)
            .call()
            .map_err(|e| format!("Download failed: {e}"))?;
        let mut reader = response.into_body().into_reader().take(size + 1);
        let mut file = fs::File::create(part).map_err(|e| e.to_string())?;
        let mut buffer = vec![0; 1 << 18];
        let mut bytes = 0;
        let mut meter = Meter::new();
        self.set_job(id, |j| j.status = "downloading".into());
        loop {
            if cancel.load(Ordering::Relaxed) {
                return Err("Cancelled".into());
            }
            let read = reader
                .read(&mut buffer)
                .map_err(|e| format!("Download failed: {e}"))?;
            if read == 0 {
                break;
            }
            file.write_all(&buffer[..read]).map_err(|e| e.to_string())?;
            bytes += read as u64;
            let speed = meter.sample(bytes);
            self.set_job(id, |j| {
                j.bytes = bytes;
                j.speed = speed.unwrap_or(j.speed);
            });
        }
        if bytes != size {
            return Err(format!("Download ended at {bytes} of {size} bytes"));
        }
        file.sync_all().map_err(|e| e.to_string())
    }
    fn cancel(&self, id: &str) -> Result<Value, String> {
        let mut jobs = self.0.jobs.lock().unwrap();
        let job = jobs
            .get_mut(id)
            .ok_or_else(|| invalid("Nothing to cancel"))?;
        job.cancel.store(true, Ordering::Relaxed);
        drop(jobs);
        self.touch();
        Ok(json!({"cancelling": id}))
    }
    fn install(&self, value: &str) -> Result<Value, String> {
        let source = PathBuf::from(value.trim());
        if !source.is_absolute() {
            return Err(invalid("Use an absolute AppImage path"));
        }
        if !source.is_file() || !is_appimage(&source) {
            return Err(invalid("The file is not an AppImage"));
        }
        if source.parent() == Some(&*self.0.paths.dir) {
            return Err(invalid("This file is already in the AppImage folder"));
        }
        let label = source
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        self.0.installing.lock().unwrap().push(label.clone());
        *self.0.error.lock().unwrap() = None;
        self.touch();
        let worker = self.clone();
        let name = label.clone();
        std::thread::spawn(move || {
            let result = worker.install_now(&source);
            worker.0.installing.lock().unwrap().retain(|n| *n != name);
            *worker.0.error.lock().unwrap() = result.err().map(|e| format!("{name}: {e}"));
            worker.touch();
        });
        Ok(json!({"installing": label}))
    }
    fn install_now(&self, source: &Path) -> Result<(), String> {
        let dir = &self.0.paths.dir;
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        // The original stays where the user left it; only the managed copy is ever executed.
        let part = tempfile::Builder::new()
            .prefix(".install-")
            .suffix(".part")
            .tempfile_in(dir)
            .map_err(|e| e.to_string())?;
        fs::copy(source, part.path()).map_err(|e| format!("Cannot copy the AppImage: {e}"))?;
        fs::set_permissions(part.path(), fs::Permissions::from_mode(0o755))
            .map_err(|e| e.to_string())?;
        let extracted = extract(part.path())?;
        let stem = source
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        let stem = safe_name(field(&extracted.fields, "Name").unwrap_or(&stem));
        if stem.is_empty() {
            return Err("The application has no usable name".into());
        }
        let target = dir.join(format!("{stem}.AppImage"));
        if target.exists() {
            return Err(format!(
                "{stem} is already installed; update it or move it to Trash first"
            ));
        }
        part.persist(&target).map_err(|e| e.to_string())?;
        self.write_entry(&target, &extracted, None)
    }
    fn integrate_now(&self, id: &str) -> Result<Value, String> {
        self.idle(id)?;
        let row = self.row(id)?;
        self.integrate(&row.path, None)?;
        self.touch();
        Ok(json!({"integrated": id}))
    }
    fn integrate(&self, path: &Path, version: Option<&str>) -> Result<(), String> {
        let extracted = extract(path)?;
        self.write_entry(path, &extracted, version)
    }
    fn write_entry(
        &self,
        path: &Path,
        extracted: &Extracted,
        version: Option<&str>,
    ) -> Result<(), String> {
        let paths = &self.0.paths;
        let entries = self.entries();
        let previous = launcher(&entries, path);
        let file = match previous {
            Some((file, _)) => file.clone(),
            None => {
                let stem = path.file_stem().unwrap_or_default().to_string_lossy();
                let wanted = extracted
                    .desktop_name
                    .as_deref()
                    .map(safe_name)
                    .filter(|n| !n.is_empty() && n.ends_with(".desktop"))
                    .unwrap_or_else(|| format!("appimage-{}.desktop", safe_name(&stem)));
                // Never shadow a package launcher or another application's entry.
                let taken = |n: &str| {
                    paths.applications.join(n).exists()
                        || paths.system_applications.join(n).exists()
                };
                let name = if taken(&wanted) {
                    format!("appimage-{}.desktop", safe_name(&stem))
                } else {
                    wanted
                };
                if taken(&name) {
                    return Err(format!(
                        "Launcher {name} already belongs to another application"
                    ));
                }
                paths.applications.join(name)
            }
        };
        let empty = vec![];
        let old = previous.map_or(&empty, |(_, f)| f);
        let icon = match &extracted.icon {
            Some((data, ext)) => {
                let stem = field(&extracted.fields, "Icon")
                    .filter(|n| slug(n))
                    .map(str::to_string)
                    .unwrap_or_else(|| {
                        safe_name(&path.file_stem().unwrap_or_default().to_string_lossy())
                    });
                let target = paths.icons.join(format!("{stem}.{ext}"));
                atomic_write(&target, data, 0o644)?;
                Some(target.to_string_lossy().into_owned())
            }
            None => field(old, "Icon").map(str::to_string),
        };
        let mut fields = extracted.fields.clone();
        if let Some(version) = version {
            fields.retain(|(k, _)| k != "X-AppImage-Version");
            fields.push(("X-AppImage-Version".into(), version.into()));
        }
        let text = render_entry(&fields, old, path, icon.as_deref());
        atomic_write(&file, text.as_bytes(), 0o644)?;
        refresh_desktop_database(&paths.applications);
        Ok(())
    }
    fn set_source(&self, value: &str) -> Result<Value, String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Request {
            id: String,
            source: Option<String>,
            updates: bool,
        }
        let request: Request = serde_json::from_str(value)
            .map_err(|e| invalid(&format!("Invalid source request: {e}")))?;
        self.row(&request.id)?;
        let source = request
            .source
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        if let Some(source) = &source {
            parse_source(source)?;
        }
        self.save(|p| {
            p.apps.insert(
                request.id.clone(),
                AppPrefs {
                    source,
                    updates_disabled: !request.updates,
                },
            );
        })?;
        self.0.outcomes.lock().unwrap().remove(&request.id);
        Ok(json!({"id": request.id}))
    }
    fn open(&self, id: &str) -> Result<Value, String> {
        let row = self.row(id)?;
        let mut child = Command::new(&row.path)
            .env("DESKTOPINTEGRATION", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("Cannot open {id}: {e}"))?;
        let pid = child.id();
        std::thread::spawn(move || {
            let _ = child.wait();
        });
        Ok(json!({"opened": id, "pid": pid}))
    }
    fn uninstall(&self, id: &str) -> Result<Value, String> {
        self.idle(id)?;
        let row = self.row(id)?;
        gio::File::for_path(&row.path)
            .trash(gio::Cancellable::NONE)
            .map_err(|e| format!("Cannot move {id} to Trash: {e}"))?;
        let mut leftovers = vec![];
        // The application's own handlers would point at a file that no longer exists.
        for (file, fields) in self.entries() {
            if desktop_refers(&fields, &row.path)
                && let Err(e) = fs::remove_file(&file)
            {
                leftovers.push(format!("{}: {e}", file.display()));
            }
        }
        if let Some((_, fields)) = &row.desktop {
            if let Some(icon) = field(fields, "Icon") {
                let in_use = self
                    .entries()
                    .iter()
                    .any(|(_, f)| field(f, "Icon") == Some(icon));
                if !in_use {
                    self.remove_icon(icon);
                }
            }
            refresh_desktop_database(&self.0.paths.applications);
        }
        for link in fs::read_dir(&self.0.paths.bin)
            .into_iter()
            .flatten()
            .flatten()
        {
            if fs::read_link(link.path()).is_ok_and(|target| target == row.path)
                && let Err(e) = fs::remove_file(link.path())
            {
                leftovers.push(format!("{}: {e}", link.path().display()));
            }
        }
        self.0.outcomes.lock().unwrap().remove(id);
        if self.0.prefs.lock().unwrap().apps.contains_key(id) {
            self.save(|p| {
                p.apps.remove(id);
            })?;
        }
        self.touch();
        if !leftovers.is_empty() {
            return Err(format!(
                "Moved to Trash, but could not remove: {}",
                leftovers.join(", ")
            ));
        }
        Ok(json!({"removed": id}))
    }
    /// Only icons inside the private user folder: entries may name a system icon.
    fn remove_icon(&self, icon: &str) {
        let icons = &self.0.paths.icons;
        let candidates = if Path::new(icon).is_absolute() {
            vec![PathBuf::from(icon)]
        } else if slug(icon) {
            ["png", "svg"]
                .iter()
                .map(|e| icons.join(format!("{icon}.{e}")))
                .collect()
        } else {
            vec![]
        };
        for path in candidates {
            if path.parent() == Some(icons) {
                let _ = fs::remove_file(path);
            }
        }
    }
    /// Called periodically by the service; attempts are spaced so failures do not hammer servers.
    pub fn auto_tick(&self) {
        let prefs = self.0.prefs.lock().unwrap().clone();
        let mut attempt = self.0.last_attempt.lock().unwrap();
        if due(&prefs, *attempt, now()) {
            *attempt = now();
            drop(attempt);
            let mode = if prefs.auto_update {
                Mode::Update
            } else {
                Mode::Check
            };
            let _ = self.start("all", mode, true);
        }
    }
    /// Lets workers notice cancellation so a service exit leaves no partial file behind.
    pub fn shutdown(&self) {
        for job in self.0.jobs.lock().unwrap().values_mut() {
            job.cancel.store(true, Ordering::Relaxed);
        }
        for _ in 0..20 {
            if self.0.jobs.lock().unwrap().is_empty() {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}
/// Bytes per second, refreshed about once a second.
struct Meter {
    mark: Instant,
    bytes: u64,
}
impl Meter {
    fn new() -> Self {
        Self {
            mark: Instant::now(),
            bytes: 0,
        }
    }
    fn sample(&mut self, bytes: u64) -> Option<u64> {
        let elapsed = self.mark.elapsed().as_secs_f64();
        if elapsed < 1.0 {
            return None;
        }
        let speed = (bytes.saturating_sub(self.bytes) as f64 / elapsed) as u64;
        (self.mark, self.bytes) = (Instant::now(), bytes);
        Some(speed)
    }
}
fn due(prefs: &Prefs, attempt: u64, now: u64) -> bool {
    prefs.auto_check
        && now.saturating_sub(prefs.last_check) >= DAY
        && now.saturating_sub(attempt) >= RETRY
}
fn refresh_desktop_database(applications: &Path) {
    let _ = Command::new("update-desktop-database")
        .arg(applications)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn managed_launchers_require_a_real_library_image_as_the_executable() {
        let root = tempfile::tempdir().unwrap();
        let image = root.path().join("Example App.AppImage");
        fs::write(&image, b"\x7fELF\0\0\0\0AI\x02").unwrap();
        let quoted = exec_quote(&image);
        assert_eq!(
            managed_launcher(
                &format!("env DESKTOPINTEGRATION=1 {quoted} %U"),
                root.path()
            ),
            Some(image.clone())
        );
        assert_eq!(managed_launcher(&quoted, root.path()), Some(image.clone()));
        assert!(managed_launcher(&format!("editor {quoted}"), root.path()).is_none());
        assert!(managed_launcher(&quoted, &root.path().join("other")).is_none());
        fs::write(&image, b"not an AppImage").unwrap();
        assert!(managed_launcher(&quoted, root.path()).is_none());
    }

    fn asset(name: &str) -> Asset {
        Asset {
            name: name.into(),
            size: 1,
            browser_download_url: format!("https://example.org/{name}"),
            digest: None,
        }
    }
    fn manager(root: &Path) -> AppImages {
        AppImages::new(Paths {
            dir: root.join("AppImages"),
            applications: root.join("applications"),
            system_applications: root.join("system"),
            icons: root.join("icons"),
            bin: root.join("bin"),
            config: root.join("config/appimages.toml"),
        })
    }
    fn fake_image(path: &Path) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        let mut bytes = b"\x7fELF\x02\x01\x01\x00AI\x02".to_vec();
        bytes.resize(64, 0);
        fs::write(path, bytes).unwrap();
    }
    #[test]
    fn parses_update_sources_and_rejects_unsafe_ones() {
        assert_eq!(
            parse_source("https://github.com/o/r/").unwrap(),
            Source::Github {
                owner: "o".into(),
                repo: "r".into(),
                tag: "latest".into(),
                glob: None
            }
        );
        assert!(matches!(
            parse_source("gh-releases-zsync|o|r|latest|r-*-x86_64.AppImage.zsync").unwrap(),
            Source::Github { glob: Some(_), .. }
        ));
        assert_eq!(
            parse_source("https://example.org/a.AppImage.zsync").unwrap(),
            Source::Zsync("https://example.org/a.AppImage.zsync".into())
        );
        for bad in [
            "http://example.org/a.zsync",
            "zsync|http://example.org/a.zsync",
            "https://github.com/o",
            "https://github.com/../r/x",
            "gh-releases-zsync|o/../x|r|latest|*",
            "https://example.org/a b.zsync",
            "file:///etc/passwd",
            "",
        ] {
            assert!(parse_source(bad).is_err(), "{bad}");
        }
    }
    #[test]
    fn picks_this_architecture_and_honours_the_zsync_glob() {
        let assets = [
            asset("a-1-linux-aarch64.AppImage"),
            asset("a-1-linux-aarch64.AppImage.zsync"),
            asset("a-1-linux-x86_64.AppImage"),
            asset("a-1-linux-x86_64.AppImage.zsync"),
            asset("a-1.deb"),
        ];
        assert_eq!(
            pick_asset(&assets, None).unwrap().name,
            "a-1-linux-x86_64.AppImage"
        );
        assert_eq!(
            pick_asset(&assets, Some("a-*-x86_64.AppImage.zsync"))
                .unwrap()
                .name,
            "a-1-linux-x86_64.AppImage"
        );
        assert!(pick_asset(&assets, Some("b-*.zsync")).is_none());
        assert!(pick_asset(&assets[..2], None).is_none());
        assert!(
            glob_match("a*b*c", "a1b2c") && !glob_match("a*b*c", "a1c") && !glob_match("a*a", "a")
        );
    }
    #[test]
    fn current_build_is_decided_by_checksum_then_size() {
        let root = tempfile::tempdir().unwrap();
        let file = root.path().join("x");
        fs::write(&file, "hello").unwrap();
        let mut remote = Remote {
            version: None,
            url: None,
            zsync: None,
            size: 5,
            digest: Some((
                "sha256sum",
                "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824".into(),
            )),
        };
        assert!(is_current(&remote, &file).unwrap());
        remote.digest = Some(("sha256sum", "00".into()));
        assert!(!is_current(&remote, &file).unwrap());
        remote.digest = None;
        assert!(is_current(&remote, &file).unwrap());
        remote.size = 6;
        assert!(!is_current(&remote, &file).unwrap());
    }
    #[test]
    fn entries_never_keep_commands_from_the_image_and_quote_the_path() {
        let embedded = desktop_fields(
            "[Desktop Entry]\nName=A\nName[zh]=B\nExec=evil --x %U\nTryExec=evil\nIcon=a\nActions=Bad;\ncategory=x\nCategories=Office;\n[Desktop Action Bad]\nExec=rm -rf /\n",
        );
        let previous =
            desktop_fields("[Desktop Entry]\nX-AppImage-UpdateURL=https://github.com/o/r\n");
        let path = Path::new("/h/My $App.AppImage");
        let text = render_entry(&embedded, &previous, path, Some("/i/a.png"));
        assert!(text.contains("Exec=env DESKTOPINTEGRATION=1 \"/h/My \\\\$App.AppImage\" %U\n"));
        assert!(text.contains("Name[zh]=B\n") && text.contains("Icon=/i/a.png\n"));
        assert!(text.contains("X-AppImage-UpdateURL=https://github.com/o/r\n"));
        assert!(!text.contains("evil") && !text.contains("rm -rf") && !text.contains("Actions"));
        assert!(text.contains("Categories=Office;\n") && !text.contains("category="));
        assert!(desktop_refers(&desktop_fields(&text), path));
    }
    #[test]
    fn reads_update_information_and_the_payload_offset_from_the_elf() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("a.AppImage");
        let info = b"zsync|https://e.org/a.zsync\0\0\0";
        let strings = b"\0.shstrtab\0.upd_info\0";
        let mut b = vec![0u8; 64];
        b[..4].copy_from_slice(b"\x7fELF");
        b[4] = 2;
        b[5] = 1;
        let info_at = b.len() as u64;
        b.extend_from_slice(info);
        let strings_at = b.len() as u64;
        b.extend_from_slice(strings);
        let table = b.len() as u64;
        let section = |name: u32, at: u64, size: u64| {
            let mut s = vec![0u8; 64];
            s[..4].copy_from_slice(&name.to_le_bytes());
            s[24..32].copy_from_slice(&at.to_le_bytes());
            s[32..40].copy_from_slice(&size.to_le_bytes());
            s
        };
        b.extend(section(1, strings_at, strings.len() as u64));
        b.extend(section(11, info_at, info.len() as u64));
        b[40..48].copy_from_slice(&table.to_le_bytes());
        b[58..60].copy_from_slice(&64u16.to_le_bytes());
        b[60..62].copy_from_slice(&2u16.to_le_bytes());
        b[62..64].copy_from_slice(&0u16.to_le_bytes());
        fs::write(&path, &b).unwrap();
        assert_eq!(
            embedded_update_info(&path).unwrap(),
            "zsync|https://e.org/a.zsync"
        );
        let (_, end) = elf_sections(&mut fs::File::open(&path).unwrap()).unwrap();
        assert_eq!(end, b.len() as u64);
        let error = extract(&path).err().unwrap();
        assert!(error.contains("SquashFS"), "{error}");
        // A section table pointing past the file must be ignored, not read.
        b[40..48].copy_from_slice(&u64::MAX.to_le_bytes());
        fs::write(&path, &b).unwrap();
        assert!(embedded_update_info(&path).is_none());
    }
    #[test]
    fn payload_links_cannot_leave_the_image() {
        let at = |base: &str, link: &str| payload_path(Path::new(base), Path::new(link));
        assert_eq!(at("/.DirIcon", "app.png"), Path::new("/app.png"));
        assert_eq!(
            at("/a.desktop", "usr/share/a.desktop"),
            Path::new("/usr/share/a.desktop")
        );
        assert_eq!(
            at("/.DirIcon", "../../etc/passwd"),
            Path::new("/etc/passwd")
        );
        assert_eq!(at("/x/y", "/abs"), Path::new("/abs"));
    }
    #[test]
    fn source_priority_and_validation_preserve_saved_preferences() {
        let root = tempfile::tempdir().unwrap();
        let apps = manager(root.path());
        let image = root.path().join("AppImages/A.AppImage");
        fake_image(&image);
        fake_image(&root.path().join("AppImages/.hidden.AppImage"));
        fs::write(root.path().join("AppImages/note.AppImage"), "not an image").unwrap();
        fs::create_dir_all(root.path().join("applications")).unwrap();
        fs::write(
            root.path().join("applications/a.desktop"),
            format!(
                "[Desktop Entry]\nName=Alpha\nExec=\"{}\"\nX-AppImage-UpdateURL=https://github.com/o/d\n",
                image.display()
            ),
        )
        .unwrap();
        // An application's hidden URL handler sorts first but is not its launcher.
        fs::write(
            root.path().join("applications/0-handler.desktop"),
            format!(
                "[Desktop Entry]\nName=Handler\nNoDisplay=true\nExec={} %u\n",
                image.display()
            ),
        )
        .unwrap();
        let state = apps.state();
        assert_eq!(state["apps"].as_array().unwrap().len(), 1);
        assert_eq!(state["apps"][0]["name"], "Alpha");
        assert_eq!(state["apps"][0]["source_origin"], "desktop");
        apps.set(
            SOURCE,
            r#"{"id":"A.AppImage","source":"https://github.com/o/c","updates":false}"#,
        )
        .unwrap();
        let state = apps.state();
        assert_eq!(state["apps"][0]["source_origin"], "custom");
        assert_eq!(state["apps"][0]["updates"], false);
        assert!(
            apps.set(
                SOURCE,
                r#"{"id":"A.AppImage","source":"http://x/a.zsync","updates":true}"#
            )
            .is_err()
        );
        assert!(
            apps.set(
                SOURCE,
                r#"{"id":"../A.AppImage","source":null,"updates":true}"#
            )
            .is_err()
        );
        assert_eq!(apps.state()["apps"][0]["source"], "https://github.com/o/c");
        // Reloaded from disk.
        assert_eq!(
            manager(root.path()).state()["apps"][0]["source_origin"],
            "custom"
        );
        // A damaged file is reported and never overwritten.
        fs::write(root.path().join("config/appimages.toml"), "bad = [").unwrap();
        let damaged = manager(root.path());
        assert!(damaged.state()["error"].is_string());
        assert!(damaged.set(AUTO_CHECK, "false").is_err());
        assert_eq!(
            fs::read_to_string(root.path().join("config/appimages.toml")).unwrap(),
            "bad = ["
        );
    }
    #[test]
    fn install_rejects_non_images_and_paths_outside_the_contract() {
        let root = tempfile::tempdir().unwrap();
        let apps = manager(root.path());
        let text = root.path().join("x.AppImage");
        fs::write(&text, "not an image").unwrap();
        for bad in [
            "relative.AppImage",
            text.to_str().unwrap(),
            "/nonexistent/a.AppImage",
        ] {
            assert!(
                apps.set(INSTALL, bad)
                    .unwrap_err()
                    .starts_with("InvalidArgument")
            );
        }
        assert!(apps.set(UNINSTALL, "../../etc/passwd").is_err());
        assert!(apps.set(OPEN, "Missing.AppImage").is_err());
        assert!(apps.set(AUTO_CHECK, "maybe").is_err());
    }
    #[test]
    fn automatic_checks_wait_a_day_and_space_failed_attempts() {
        let mut prefs = Prefs {
            last_check: 1_000,
            ..Prefs::default()
        };
        assert!(!due(&prefs, 0, 1_000 + DAY - 1));
        assert!(due(&prefs, 0, 1_000 + DAY));
        assert!(!due(&prefs, 1_000 + DAY, 1_000 + DAY + RETRY - 1));
        prefs.auto_check = false;
        assert!(!due(&prefs, 0, 1_000 + DAY));
    }
    #[test]
    fn icon_removal_stays_inside_the_user_icon_folder() {
        let root = tempfile::tempdir().unwrap();
        let apps = manager(root.path());
        let image = root.path().join("AppImages/A.AppImage");
        fake_image(&image);
        fs::create_dir_all(root.path().join("applications")).unwrap();
        fs::create_dir_all(root.path().join("bin")).unwrap();
        fs::create_dir_all(root.path().join("icons")).unwrap();
        let icon = root.path().join("icons/a.png");
        let shared = root.path().join("icons/shared.png");
        fs::write(&icon, "i").unwrap();
        fs::write(&shared, "i").unwrap();
        apps.remove_icon("../a");
        apps.remove_icon("/etc/passwd");
        assert!(icon.exists());
        apps.remove_icon(icon.to_str().unwrap());
        assert!(!icon.exists());
    }
}
