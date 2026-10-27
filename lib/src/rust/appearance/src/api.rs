#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SystemThemeMode {
    Light,
    Dark,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ThemeTargetStatus {
    Detected,
    Applied,
    Unchanged,
    Unavailable,
}

#[derive(Clone, Debug)]
pub struct ThemeTargetResult {
    pub name: String,
    pub status: ThemeTargetStatus,
    pub detail: String,
}

#[derive(Clone, Debug)]
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
