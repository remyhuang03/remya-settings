#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SystemThemeMode {
    Light,
    Dark,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ThemeTargetStatus {
    Detected,
    Applied,
    Unchanged,
    Unavailable,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct ThemeTargetResult {
    pub name: String,
    pub status: ThemeTargetStatus,
    pub detail: String,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct SystemThemeState {
    pub mode: Option<SystemThemeMode>,
    pub targets: Vec<ThemeTargetResult>,
}

pub fn read_system_theme() -> Result<SystemThemeState, String> {
    crate::system_theme::read()
}

pub fn apply_system_theme(mode: SystemThemeMode) -> Result<SystemThemeState, String> {
    crate::system_theme::apply(mode)
}
