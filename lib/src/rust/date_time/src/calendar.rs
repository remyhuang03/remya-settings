use std::process::Command;

fn time_locale(values: &[String]) -> &str {
    ["LC_TIME=", "LANG="]
        .into_iter()
        .find_map(|key| {
            values
                .iter()
                .find_map(|value| value.strip_prefix(key).filter(|locale| !locale.is_empty()))
        })
        .unwrap_or("C")
}

fn format(date: &str, locale: &str) -> Result<String, String> {
    if date.len() != 10
        || !date.bytes().enumerate().all(|(index, byte)| {
            if [4, 7].contains(&index) {
                byte == b'-'
            } else {
                byte.is_ascii_digit()
            }
        })
    {
        return Err("Invalid calendar date; expected YYYY-MM-DD".into());
    }
    if !crate::services::list_locales()?.iter().any(|installed| {
        !installed.is_empty()
            && crate::services::normalize_locale(installed)
                == crate::services::normalize_locale(locale)
    }) {
        return Err(format!("LC_TIME locale is not installed: {locale}"));
    }
    let result = Command::new("/usr/bin/date")
        .args(["--date", date, "+%x"])
        .env_remove("LC_ALL")
        .env("LC_TIME", locale)
        .env("TZ", "UTC0")
        .output()
        .map_err(|error| format!("Cannot format calendar date: {error}"))?;
    if !result.status.success() || !result.stderr.is_empty() {
        return Err(format!(
            "Cannot format calendar date: {}",
            String::from_utf8_lossy(&result.stderr).trim()
        ));
    }
    String::from_utf8(result.stdout)
        .map(|value| value.trim_end().to_owned())
        .map_err(|error| format!("Invalid formatted date: {error}"))
}

/// Use fresh localed preferences rather than the resident service's startup environment.
pub fn format_calendar_date(date: &str) -> Result<String, String> {
    let values = crate::timedate::Timedate::connect()?.locale_values()?;
    format(date, time_locale(&values))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calendar_dates_follow_lc_time_and_inherit_lang() {
        let values = vec!["LANG=en_US.UTF-8".into(), "LC_TIME=zh_CN.UTF-8".into()];
        assert_eq!(time_locale(&values), "zh_CN.UTF-8");
        assert_eq!(time_locale(&values[..1]), "en_US.UTF-8");
        assert_eq!(time_locale(&[]), "C");
        assert_eq!(format("2025-09-08", "C").unwrap(), "09/08/25");
        for invalid in ["2025-02-29", "2025-13-01", "2025-09-08 extra", "--help"] {
            assert!(format(invalid, "C").is_err());
        }
        assert!(format("2025-09-08", "invalid_LOCALE").is_err());
        let locales = crate::services::list_locales().unwrap();
        if locales.iter().any(|locale| locale == "en_US.utf8")
            && locales.iter().any(|locale| locale == "zh_CN.utf8")
        {
            assert_eq!(format("2025-09-08", "en_US.utf8").unwrap(), "09/08/2025");
            assert_eq!(
                format("2025-09-08", "zh_CN.utf8").unwrap(),
                "2025年09月08日"
            );
        }
    }
}
