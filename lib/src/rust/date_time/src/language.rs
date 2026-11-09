//! Display language (`LANG`) and regional formats through systemd-localed.
//!
//! localed owns `/etc/locale.conf`; Settings keeps its own copy in `language.toml`
//! for reconciliation. Writes need root, so the service sends the assignments from
//! [`Language::plan`] to its privileged process, which calls [`write_locale`].
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::BTreeMap, fs, path::PathBuf, process::Command};

pub const FEATURE: &str = "language";
pub const DISPLAY: &str = "language.display";
pub const FORMAT: &str = "language.format";
pub const LOCALES: &str = "locales";
pub const PREVIEW: &str = "format-preview:";
/// The categories the regional format sets. Messages, sorting and character
/// classes follow the display language.
pub const CATEGORIES: [&str; 5] = [
    "LC_TIME",
    "LC_NUMERIC",
    "LC_MONETARY",
    "LC_PAPER",
    "LC_MEASUREMENT",
];

pub fn is_setting(id: &str) -> bool {
    id == DISPLAY || id == FORMAT
}

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Prefs {
    pub language: String,
    /// Each category's locale, or "" when it follows the display language.
    pub formats: BTreeMap<String, String>,
}

impl Prefs {
    /// The locale every category uses, "" when all follow the display language,
    /// or null when they differ.
    fn format(&self) -> Value {
        let first = &self.formats[CATEGORIES[0]];
        if self.formats.values().all(|v| v == first) {
            json!(first)
        } else {
            Value::Null
        }
    }

    fn options(&self) -> Value {
        json!({DISPLAY: self.language, FORMAT: self.format()})
    }

    /// The localed assignments; a category that follows the display language is
    /// sent as `LANG`'s value, which localed drops (it rejects empty values).
    fn assignments(&self) -> Vec<String> {
        let mut values = vec![format!("LANG={}", self.language)];
        for category in CATEGORIES {
            let locale = &self.formats[category];
            let locale = if locale.is_empty() {
                &self.language
            } else {
                locale
            };
            values.push(format!("{category}={locale}"));
        }
        values
    }
}

pub fn normalize(locale: &str) -> String {
    crate::services::normalize_locale(locale)
}

/// `locale -a` spells UTF-8 as `utf8`; `/etc/locale.conf` conventionally uses `UTF-8`.
fn canonical_id(name: &str) -> String {
    name.replacen(".utf8", ".UTF-8", 1)
}

/// The installed spelling of `locale`, if it is installed.
fn installed_id<'a>(locale: &str, installed: &'a [(String, String)]) -> Option<&'a str> {
    installed
        .iter()
        .map(|(id, _)| id.as_str())
        .find(|id| normalize(id) == normalize(locale))
}

/// Reads localed assignments as preferences; a category equal to `LANG` follows it.
fn observe(values: &[String], installed: &[(String, String)]) -> Result<Prefs, String> {
    let get = |key: &str| {
        values
            .iter()
            .find_map(|v| v.strip_prefix(key)?.strip_prefix('='))
            .filter(|v| !v.is_empty())
    };
    let language = get("LANG").ok_or("The system language (LANG) is not set")?;
    let language = installed_id(language, installed)
        .ok_or_else(|| format!("The system language {language} is not an installed locale"))?;
    let mut formats = BTreeMap::new();
    for category in CATEGORIES {
        let value = match get(category) {
            Some(v) if normalize(v) != normalize(language) => installed_id(v, installed)
                .ok_or_else(|| format!("{category} uses {v}, which is not an installed locale"))?,
            _ => "",
        };
        formats.insert(category.to_owned(), value.to_owned());
    }
    Ok(Prefs {
        language: language.to_owned(),
        formats,
    })
}

/// Saved preferences must name installed locales and every format category.
fn validate(prefs: &Prefs, installed: &[(String, String)]) -> Result<Prefs, String> {
    let error = || "Invalid saved language preferences".to_owned();
    let language = installed_id(&prefs.language, installed).ok_or_else(error)?;
    if prefs.formats.len() != CATEGORIES.len() {
        return Err(error());
    }
    let mut formats = BTreeMap::new();
    for category in CATEGORIES {
        let value = prefs.formats.get(category).ok_or_else(error)?;
        let value = match value.as_str() {
            "" => "",
            v if normalize(v) == normalize(language) => "",
            v => installed_id(v, installed).ok_or_else(error)?,
        };
        formats.insert(category.to_owned(), value.to_owned());
    }
    Ok(Prefs {
        language: language.to_owned(),
        formats,
    })
}

/// What the feature reads from the system.
pub trait System: Send {
    /// localed `Locale` assignments such as `LANG=en_US.UTF-8`.
    fn locale(&self) -> Result<Vec<String>, String>;
    /// Generated locales as `(id, label)`.
    fn installed(&self) -> Result<Vec<(String, String)>, String>;
}

pub struct RealSystem;
impl System for RealSystem {
    fn locale(&self) -> Result<Vec<String>, String> {
        crate::timedate::Timedate::connect()?.locale_values()
    }

    fn installed(&self) -> Result<Vec<(String, String)>, String> {
        installed()
    }
}

pub struct Language<S> {
    system: S,
    path: PathBuf,
    installed: Vec<(String, String)>,
    saved: Option<Prefs>,
    observed: Option<Prefs>,
    pending: Option<Prefs>,
    error: Option<String>,
}

impl<S: System> Language<S> {
    pub fn new(system: S, path: PathBuf) -> Self {
        Self {
            system,
            path,
            installed: vec![],
            saved: None,
            observed: None,
            pending: None,
            error: None,
        }
    }

    fn read(&mut self) -> Result<(), String> {
        self.observed = None;
        self.installed = self.system.installed()?;
        let observed = observe(&self.system.locale()?, &self.installed)?;
        self.saved = match fs::read_to_string(&self.path) {
            Ok(text) => {
                let prefs: Prefs =
                    toml::from_str(&text).map_err(|e| format!("{}: {e}", self.path.display()))?;
                Some(validate(&prefs, &self.installed)?)
            }
            // First use adopts what the system does now and changes nothing.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                self.save(&observed)?;
                Some(observed.clone())
            }
            Err(e) => return Err(format!("{}: {e}", self.path.display())),
        };
        self.observed = Some(observed);
        Ok(())
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.read();
        self.error = result.as_ref().err().cloned();
        result
    }

    fn save(&self, prefs: &Prefs) -> Result<(), String> {
        let text = toml::to_string(prefs).map_err(|e| e.to_string())?;
        atomic_write(&self.path, text.as_bytes())
    }

    fn conflicts(&self) -> Vec<&'static str> {
        let (Some(saved), Some(observed)) = (&self.saved, &self.observed) else {
            return vec![];
        };
        let mut ids = vec![];
        if saved.language != observed.language {
            ids.push(DISPLAY);
        }
        if saved.formats != observed.formats {
            ids.push(FORMAT);
        }
        ids
    }

    pub fn state(&self) -> Value {
        let shown = self.saved.as_ref().or(self.observed.as_ref());
        json!({
            "options": shown.map(Prefs::options),
            "formats": shown.map(|p| &p.formats),
            "saved": self.saved.as_ref().map(Prefs::options),
            "system": self.observed.as_ref().map(Prefs::options),
            "saved_formats": self.saved.as_ref().map(|p| &p.formats),
            "system_formats": self.observed.as_ref().map(|p| &p.formats),
            "conflict": !self.conflicts().is_empty(),
            "conflicts": self.conflicts(),
            "categories": CATEGORIES,
            "write_blocked": Value::Null,
            "error": self.error,
        })
    }

    pub fn setting_value(&self, id: &str) -> Value {
        self.state()["options"][id].clone()
    }

    /// Installed locales with readable names, for the pickers.
    pub fn locales(&self) -> Result<Value, String> {
        let installed = self.system.installed()?;
        Ok(
            json!({"options": installed.iter().map(|(id, label)| json!({"id": id, "label": label})).collect::<Vec<_>>()}),
        )
    }

    /// Validates a change and returns the localed assignments to write; pass the
    /// write's result to [`Language::finish`].
    pub fn plan(&mut self, id: &str, input: &str) -> Result<Vec<String>, String> {
        let value: Value = serde_json::from_str(input).map_err(|_| invalid("Expected JSON"))?;
        let locale = value
            .as_str()
            .ok_or_else(|| invalid("Expected a locale string"))?;
        self.refresh()?;
        let locale = match (id, locale) {
            (FORMAT, "") => "",
            (DISPLAY | FORMAT, v) => installed_id(v, &self.installed)
                .ok_or_else(|| invalid("Choose an installed locale"))?,
            _ => return Err(invalid("Unknown setting")),
        }
        .to_owned();
        if !self.conflicts().is_empty() {
            return Err("Resolve the language settings conflict first".into());
        }
        let mut next = self
            .saved
            .clone()
            .ok_or("Language settings are not initialized")?;
        if id == DISPLAY {
            next.language = locale;
        } else {
            for value in next.formats.values_mut() {
                *value = locale.clone();
            }
        }
        let next = validate(&next, &self.installed).map_err(|e| invalid(&e))?;
        let values = next.assignments();
        self.pending = Some(next);
        Ok(values)
    }

    /// `system` adopts the system values and returns None; `settings` returns the
    /// assignments that restore the saved values.
    pub fn resolve(&mut self, source: &str) -> Result<Option<Vec<String>>, String> {
        self.refresh()?;
        match source {
            "system" => {
                let observed = self.observed.clone().ok_or("Nothing was read")?;
                self.save(&observed)?;
                self.saved = Some(observed);
                Ok(None)
            }
            "settings" => {
                let saved = self.saved.clone().ok_or("Nothing is saved yet")?;
                let values = saved.assignments();
                self.pending = Some(saved);
                Ok(Some(values))
            }
            _ => Err(invalid("Unknown resolution")),
        }
    }

    /// Verifies the system against the planned values and saves them.
    pub fn finish(&mut self, written: Result<(), String>) -> Result<Value, String> {
        let result = (|| {
            let pending = self.pending.take().ok_or("No language change is pending")?;
            written?;
            let observed = observe(&self.system.locale()?, &self.installed)?;
            if observed != pending {
                return Err("Locale readback does not match the request".to_owned());
            }
            self.save(&observed)?;
            self.saved = Some(observed);
            Ok(())
        })();
        let _ = self.refresh();
        if let Err(message) = &result
            && !message.starts_with("InvalidArgument:")
        {
            self.error = Some(message.clone());
        }
        result.map(|_| self.state())
    }
}

/// Runs in the privileged process: only `LANG` and the format categories, each an
/// installed locale, reach localed.
pub fn write_locale(values: &[String]) -> Result<(), String> {
    let installed = installed()?;
    if values.len() != CATEGORIES.len() + 1 {
        return Err("Expected LANG and every format category".into());
    }
    for (value, key) in values.iter().zip(std::iter::once("LANG").chain(CATEGORIES)) {
        let locale = value
            .strip_prefix(key)
            .and_then(|v| v.strip_prefix('='))
            .ok_or("Unexpected locale assignment")?;
        installed_id(locale, &installed).ok_or("Choose an installed locale")?;
    }
    crate::timedate::Timedate::connect()?.set_locale(values)
}

/// Generated locales with names from their `LC_IDENTIFICATION`, plus C and POSIX.
pub fn installed() -> Result<Vec<(String, String)>, String> {
    let names = crate::services::list_locales()?;
    let output = Command::new("locale")
        .args(["-a", "-v"])
        .output()
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err("Cannot describe installed locales".into());
    }
    let labels = labels(&String::from_utf8_lossy(&output.stdout));
    let mut locales: Vec<(String, String)> = names
        .iter()
        .filter(|n| !n.is_empty())
        .map(|name| {
            let label = labels
                .get(name)
                .cloned()
                .unwrap_or_else(|| format!("Untranslated ({})", canonical_id(name)));
            (canonical_id(name), label)
        })
        .collect();
    locales.sort_by(|a, b| a.1.cmp(&b.1).then(a.0.cmp(&b.0)));
    Ok(locales)
}

/// Readable names from `locale -a -v`: "Language (Territory)", with any modifier
/// or non-UTF-8 character set so that similar locales stay distinguishable.
fn labels(text: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for block in text.split("locale: ").skip(1) {
        let Some(name) = block.split_whitespace().next() else {
            continue;
        };
        let field = |key: &str| {
            block.lines().find_map(|line| {
                let (k, v) = line.split_once('|')?;
                (k.trim() == key).then(|| v.trim().to_owned())
            })
        };
        let Some(language) = field("language").filter(|l| !l.is_empty()) else {
            out.insert(
                name.to_owned(),
                format!("Untranslated ({})", canonical_id(name)),
            );
            continue;
        };
        let mut details: Vec<String> = field("territory").into_iter().collect();
        if let Some((_, modifier)) = name.split_once('@') {
            details.push(modifier.to_owned());
        }
        if let Some(codeset) = field("codeset").filter(|c| c != "UTF-8") {
            details.push(codeset);
        }
        let label = if details.is_empty() {
            language
        } else {
            format!("{language} ({})", details.join(", "))
        };
        out.insert(name.to_owned(), label);
    }
    out
}

/// `locale -k` output as key/value pairs, with string quotes removed.
fn keywords(text: &str) -> BTreeMap<String, String> {
    text.lines()
        .filter_map(|line| line.split_once('='))
        .map(|(k, v)| (k.to_owned(), v.trim_matches('"').to_owned()))
        .collect()
}

/// Inserts `separator` between digit groups; glibc grouping repeats its last size,
/// and -1 stops grouping.
fn group(digits: &str, separator: &str, grouping: &str) -> String {
    let sizes: Vec<i64> = grouping
        .split(';')
        .filter_map(|s| s.trim().parse().ok())
        .collect();
    if separator.is_empty() || sizes.is_empty() {
        return digits.to_owned();
    }
    let mut parts = vec![];
    let mut rest = digits;
    let mut size = 0;
    for index in 0.. {
        if let Some(&next) = sizes.get(index).filter(|s| **s != 0) {
            size = next;
        }
        if size <= 0 || rest.len() <= size as usize {
            break;
        }
        let (head, tail) = rest.split_at(rest.len() - size as usize);
        parts.push(tail);
        rest = head;
    }
    parts.push(rest);
    parts.reverse();
    parts.join(separator)
}

fn number(value: f64, digits: usize, point: &str, separator: &str, grouping: &str) -> String {
    let text = format!("{value:.digits$}");
    let (whole, fraction) = text.split_once('.').unwrap_or((&text, ""));
    let whole = group(whole, separator, grouping);
    if fraction.is_empty() {
        whole
    } else {
        format!(
            "{whole}{}{fraction}",
            if point.is_empty() { "." } else { point }
        )
    }
}

/// The preview card's text from a locale's `locale -k` and `date` output.
fn describe(k: &BTreeMap<String, String>) -> Value {
    let get = |key: &str| k.get(key).map(String::as_str).unwrap_or_default();
    let int = |key: &str| get(key).parse::<i64>().unwrap_or(-1);
    let decimal = number(
        1234567.89,
        2,
        get("decimal_point"),
        get("thousands_sep"),
        get("grouping"),
    );
    let mon_point = Some(get("mon_decimal_point"))
        .filter(|p| !p.is_empty())
        .unwrap_or(get("decimal_point"));
    let digits = usize::try_from(int("frac_digits")).unwrap_or(2);
    let amount = number(
        1234.56,
        digits,
        mon_point,
        get("mon_thousands_sep"),
        get("mon_grouping"),
    );
    let symbol = Some(get("currency_symbol"))
        .filter(|s| !s.is_empty())
        .unwrap_or(get("int_curr_symbol").trim());
    let space = if int("p_sep_by_space") == 1 { " " } else { "" };
    let currency = match (symbol, int("p_cs_precedes")) {
        ("", _) => amount,
        (s, 0) => format!("{amount}{space}{s}"),
        (s, _) => format!("{s}{space}{amount}"),
    };
    let paper = match (int("width"), int("height")) {
        (210, 297) => "A4".to_owned(),
        (216, 279) => "US Letter".to_owned(),
        (w, h) => format!("{w} × {h} mm"),
    };
    json!({
        "number": decimal,
        "currency": currency,
        "measurement": if int("measurement") == 2 { "US customary" } else { "Metric" },
        "paper": paper,
    })
}

/// How a locale formats a fixed sample date, time, number and amount.
pub fn preview(locale: &str) -> Result<Value, String> {
    let installed = installed()?;
    let locale =
        installed_id(locale, &installed).ok_or_else(|| invalid("Choose an installed locale"))?;
    let run = |program: &str, args: &[&str]| -> Result<String, String> {
        let output = Command::new(program)
            .args(args)
            .env_remove("LANGUAGE")
            .env("LC_ALL", locale)
            .env("TZ", "UTC0")
            .output()
            .map_err(|e| format!("{program}: {e}"))?;
        if !output.status.success() || !output.stderr.is_empty() {
            return Err(format!(
                "Cannot preview {locale}: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        String::from_utf8(output.stdout).map_err(|e| e.to_string())
    };
    let keys = run(
        "locale",
        &[
            "-k",
            "LC_NUMERIC",
            "LC_MONETARY",
            "LC_MEASUREMENT",
            "LC_PAPER",
        ],
    )?;
    let dates = run(
        "/usr/bin/date",
        &["--date", "2026-03-14 15:09:00", "+%x%n%X%n%A"],
    )?;
    let mut lines = dates.lines();
    let mut value = describe(&keywords(&keys));
    value["locale"] = json!(locale);
    for key in ["date", "time", "weekday"] {
        value[key] = json!(lines.next().unwrap_or_default());
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Clone)]
    struct Fake(Arc<Mutex<Vec<String>>>);
    impl System for Fake {
        fn locale(&self) -> Result<Vec<String>, String> {
            Ok(self.0.lock().unwrap().clone())
        }
        fn installed(&self) -> Result<Vec<(String, String)>, String> {
            Ok(["C", "en_US.UTF-8", "zh_CN.UTF-8", "de_DE.UTF-8"]
                .map(|id| (id.to_owned(), id.to_owned()))
                .to_vec())
        }
    }

    /// Applies assignments the way localed does: merged, with `LANG` duplicates dropped.
    fn localed(fake: &Fake, values: &[String]) {
        let mut state = fake.0.lock().unwrap();
        for value in values {
            let key = value.split_once('=').unwrap().0;
            state.retain(|old| old.split_once('=').unwrap().0 != key);
            state.push(value.clone());
        }
        let lang = state
            .iter()
            .find_map(|v| v.strip_prefix("LANG="))
            .unwrap()
            .to_owned();
        state.retain(|v| v.starts_with("LANG=") || v.split_once('=').unwrap().1 != lang);
    }

    fn setup(values: &[&str]) -> (tempfile::TempDir, Fake, Language<Fake>) {
        let dir = tempfile::tempdir().unwrap();
        let fake = Fake(Arc::new(Mutex::new(
            values.iter().map(|v| v.to_string()).collect(),
        )));
        let language = Language::new(fake.clone(), dir.path().join("language.toml"));
        (dir, fake, language)
    }

    fn set(
        language: &mut Language<Fake>,
        fake: &Fake,
        id: &str,
        value: &str,
    ) -> Result<Value, String> {
        let values = language.plan(id, &json!(value).to_string())?;
        localed(fake, &values);
        language.finish(Ok(()))
    }

    #[test]
    fn first_use_adopts_the_system_and_equal_categories_follow_lang() {
        let (dir, _, mut language) = setup(&[
            "LANG=en_US.utf8",
            "LC_TIME=zh_CN.UTF-8",
            "LC_NUMERIC=en_US.UTF-8",
            "LC_CTYPE=C",
        ]);
        language.refresh().unwrap();
        let state = language.state();
        assert_eq!(state["options"][DISPLAY], "en_US.UTF-8");
        assert_eq!(state["options"][FORMAT], Value::Null);
        assert_eq!(state["formats"]["LC_TIME"], "zh_CN.UTF-8");
        assert_eq!(state["formats"]["LC_NUMERIC"], "");
        assert_eq!(state["conflict"], false);
        assert!(dir.path().join("language.toml").exists());
        // Detection failures leave the feature uninitialized.
        let (dir, _, mut unset) = setup(&["LC_TIME=C"]);
        assert!(unset.refresh().unwrap_err().contains("LANG"));
        assert!(!dir.path().join("language.toml").exists());
        let (_, _, mut missing) = setup(&["LANG=fr_FR.UTF-8"]);
        assert!(missing.refresh().unwrap_err().contains("installed"));
    }

    #[test]
    fn changes_write_every_category_and_keep_other_variables() {
        let (_, fake, mut language) = setup(&["LANG=en_US.UTF-8", "LC_CTYPE=C"]);
        language.refresh().unwrap();
        let state = set(&mut language, &fake, FORMAT, "de_DE.UTF-8").unwrap();
        assert_eq!(state["options"][FORMAT], "de_DE.UTF-8");
        assert!(
            fake.0
                .lock()
                .unwrap()
                .contains(&"LC_PAPER=de_DE.UTF-8".into())
        );
        let state = set(&mut language, &fake, DISPLAY, "zh_CN.utf8").unwrap();
        assert_eq!(state["options"][DISPLAY], "zh_CN.UTF-8");
        assert_eq!(state["options"][FORMAT], "de_DE.UTF-8");
        // A format equal to the display language follows it.
        let state = set(&mut language, &fake, FORMAT, "zh_CN.UTF-8").unwrap();
        assert_eq!(state["options"][FORMAT], "");
        set(&mut language, &fake, FORMAT, "").unwrap();
        assert_eq!(
            *fake.0.lock().unwrap(),
            vec!["LC_CTYPE=C".to_owned(), "LANG=zh_CN.UTF-8".to_owned()]
        );
        for bad in ["fr_FR.UTF-8", "", "en_US.UTF-8; rm"] {
            if bad.is_empty() {
                assert!(language.plan(DISPLAY, "\"\"").is_err());
            } else {
                assert!(
                    language
                        .plan(FORMAT, &json!(bad).to_string())
                        .unwrap_err()
                        .starts_with("InvalidArgument:")
                );
            }
        }
        assert!(language.plan(FORMAT, "7").is_err());
        assert!(language.plan("language.other", "\"C\"").is_err());
    }

    #[test]
    fn failures_stay_visible_and_keep_the_saved_values() {
        let (_, fake, mut language) = setup(&["LANG=en_US.UTF-8"]);
        language.refresh().unwrap();
        language.plan(DISPLAY, "\"de_DE.UTF-8\"").unwrap();
        let error = language.finish(Err("Not authorized".into())).unwrap_err();
        assert_eq!(error, "Not authorized");
        assert_eq!(language.state()["error"], "Not authorized");
        assert_eq!(language.state()["options"][DISPLAY], "en_US.UTF-8");
        // localed accepting the call but reporting something else is a failure.
        language.plan(DISPLAY, "\"de_DE.UTF-8\"").unwrap();
        assert!(language.finish(Ok(())).unwrap_err().contains("readback"));
        assert_eq!(language.state()["saved"][DISPLAY], "en_US.UTF-8");
        assert!(fake.0.lock().unwrap().contains(&"LANG=en_US.UTF-8".into()));
    }

    #[test]
    fn conflicts_block_writes_until_resolved_either_way() {
        let (_, fake, mut language) = setup(&["LANG=en_US.UTF-8"]);
        language.refresh().unwrap();
        localed(
            &fake,
            &["LANG=de_DE.UTF-8".into(), "LC_TIME=zh_CN.UTF-8".into()],
        );
        language.refresh().unwrap();
        let state = language.state();
        assert_eq!(state["conflicts"], json!([DISPLAY, FORMAT]));
        assert_eq!(state["system"][DISPLAY], "de_DE.UTF-8");
        assert_eq!(state["saved"][DISPLAY], "en_US.UTF-8");
        assert!(
            language
                .plan(FORMAT, "\"\"")
                .unwrap_err()
                .contains("conflict")
        );
        let values = language.resolve("settings").unwrap().unwrap();
        assert_eq!(values[0], "LANG=en_US.UTF-8");
        assert_eq!(values[1], "LC_TIME=en_US.UTF-8");
        localed(&fake, &values);
        assert_eq!(language.finish(Ok(())).unwrap()["conflict"], false);
        assert_eq!(*fake.0.lock().unwrap(), vec!["LANG=en_US.UTF-8".to_owned()]);
        localed(&fake, &["LANG=de_DE.UTF-8".into()]);
        assert_eq!(language.resolve("system").unwrap(), None);
        language.refresh().unwrap();
        assert_eq!(language.state()["saved"][DISPLAY], "de_DE.UTF-8");
        assert_eq!(language.state()["conflict"], false);
        assert!(language.resolve("other").is_err());
    }

    #[test]
    fn saved_files_are_validated() {
        let (dir, _, mut language) = setup(&["LANG=en_US.UTF-8"]);
        fs::write(
            dir.path().join("language.toml"),
            "language = \"fr_FR.UTF-8\"\n[formats]\nLC_TIME = \"\"\n",
        )
        .unwrap();
        assert!(language.refresh().is_err());
        assert_eq!(language.state()["options"], Value::Null);
    }

    #[test]
    fn privileged_writes_accept_only_lang_and_format_categories() {
        for values in [
            vec!["LANG=C".to_owned()],
            vec!["LC_ALL=C".to_owned(); 6],
            vec!["LANG=nope".to_owned(); 6],
        ] {
            assert!(write_locale(&values).is_err());
        }
    }

    #[test]
    fn numbers_and_currency_follow_locale_keywords() {
        assert_eq!(group("1234567", ",", "3"), "1,234,567");
        assert_eq!(group("1234567", ",", "3;2"), "12,34,567");
        assert_eq!(group("1234567", "", "3"), "1234567");
        assert_eq!(group("1234567", ".", "-1"), "1234567");
        assert_eq!(group("123", ",", "3"), "123");
        let de = keywords(
            "decimal_point=\",\"\nthousands_sep=\".\"\ngrouping=3;3\ncurrency_symbol=\"€\"\n\
             mon_decimal_point=\",\"\nmon_thousands_sep=\".\"\nmon_grouping=3;3\nfrac_digits=2\n\
             p_cs_precedes=0\np_sep_by_space=1\nmeasurement=1\nheight=297\nwidth=210\n",
        );
        let value = describe(&de);
        assert_eq!(value["number"], "1.234.567,89");
        assert_eq!(value["currency"], "1.234,56 €");
        assert_eq!(value["paper"], "A4");
        assert_eq!(value["measurement"], "Metric");
        let c = keywords(
            "decimal_point=\".\"\nthousands_sep=\"\"\ngrouping=-1\ncurrency_symbol=\"\"\n\
             int_curr_symbol=\"\"\nfrac_digits=-1\np_cs_precedes=-1\nmeasurement=2\nheight=279\nwidth=216\n",
        );
        let value = describe(&c);
        assert_eq!(value["number"], "1234567.89");
        assert_eq!(value["currency"], "1234.56");
        assert_eq!(value["paper"], "US Letter");
        assert_eq!(value["measurement"], "US customary");
    }

    #[test]
    fn locale_labels_name_language_territory_and_differences() {
        let labels = labels(
            "locale: en_US.utf8      archive: /usr/lib/locale/locale-archive\n---\n\
             title | English locale for the USA\n language | American English\nterritory | United States\n codeset | UTF-8\n\n\
             locale: sr_RS.utf8@latin archive: x\n---\n language | Serbian\nterritory | Serbia\n codeset | UTF-8\n\n\
             locale: de_DE@euro archive: x\n---\n language | German\nterritory | Germany\n codeset | ISO-8859-15\n\n\
             locale: C.utf8 directory: x\n---\n title | C locale\n codeset | UTF-8\n",
        );
        assert_eq!(labels["en_US.utf8"], "American English (United States)");
        assert_eq!(labels["sr_RS.utf8@latin"], "Serbian (Serbia, latin)");
        assert_eq!(labels["de_DE@euro"], "German (Germany, euro, ISO-8859-15)");
        assert_eq!(labels["C.utf8"], "Untranslated (C.UTF-8)");
        assert_eq!(canonical_id("sr_RS.utf8@latin"), "sr_RS.UTF-8@latin");
    }

    #[test]
    fn previews_use_the_real_locale() {
        let value = preview("C").unwrap();
        assert_eq!(value["date"], "03/14/26");
        assert_eq!(value["time"], "15:09:00");
        assert_eq!(value["weekday"], "Saturday");
        assert_eq!(value["number"], "1234567.89");
        assert!(preview("fr_FR.nope").is_err());
        if installed()
            .unwrap()
            .iter()
            .any(|(id, _)| id == "en_US.UTF-8")
        {
            let value = preview("en_US.UTF-8").unwrap();
            assert_eq!(value["currency"], "$1,234.56");
            assert_eq!(value["paper"], "US Letter");
        }
    }
}
