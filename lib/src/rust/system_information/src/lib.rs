pub mod account;
pub mod hostname;

use serde_json::{Value, json};
use sysinfo::{CpuRefreshKind, MemoryRefreshKind, Motherboard, Product, RefreshKind, System};

pub const IDS: [&str; 16] = [
    "about.4433eb13",
    "about.b4366749",
    "about.d014ab77",
    "about.96af9884",
    "about.d0a7f225",
    "about.manufacturer",
    "about.model",
    "about.model-version",
    "about.board-manufacturer",
    "about.board-model",
    "about.firmware-manufacturer",
    "about.firmware-version",
    "about.firmware-date",
    "about.cpu-cores",
    "about.cpu-threads",
    "about.kernel-version",
];

fn firmware_date(raw: &str) -> Result<String, String> {
    if raw.len() != 10
        || !raw.bytes().enumerate().all(|(i, b)| {
            if [2, 5].contains(&i) {
                b == b'/'
            } else {
                b.is_ascii_digit()
            }
        })
    {
        return Err("Invalid firmware date; expected MM/DD/YYYY".into());
    }
    remya_settings_date_time::format_calendar_date(&format!(
        "{}-{}-{}",
        &raw[6..10],
        &raw[..2],
        &raw[3..5]
    ))
}

fn field(result: Result<String, String>) -> Value {
    match result.and_then(|s| {
        let value = s.trim();
        if value.is_empty()
            || [
                "to be filled by o.e.m.",
                "default string",
                "not specified",
                "unknown",
                "none",
                "n/a",
            ]
            .contains(&value.to_ascii_lowercase().as_str())
        {
            Err("Information not provided by the system or firmware".into())
        } else {
            Ok(value.to_owned())
        }
    }) {
        Ok(value) => json!({"value":value,"error":null}),
        Err(error) => json!({"value":null,"error":error}),
    }
}

/// Read-only observations: never persist or reconcile these as system preferences.
pub fn read() -> Value {
    let system = System::new_with_specifics(
        RefreshKind::nothing()
            .with_cpu(CpuRefreshKind::nothing())
            .with_memory(MemoryRefreshKind::nothing().with_ram()),
    )
    .map_err(|e| e.to_string());
    let processor = system.as_ref().map_err(Clone::clone).and_then(|s| {
        let brands = s
            .cpus()
            .iter()
            .map(|c| c.brand())
            .filter(|s| !s.is_empty())
            .collect::<std::collections::BTreeSet<_>>();
        if brands.is_empty() {
            return Err("Processor model unavailable".into());
        }
        Ok(brands.into_iter().collect::<Vec<_>>().join(" / "))
    });
    let memory = system.as_ref().map_err(Clone::clone).and_then(|s| {
        let bytes = s.total_memory();
        if bytes == 0 {
            return Err("System memory unavailable".into());
        }
        Ok(format!("{:.2} GiB", bytes as f64 / 1_073_741_824.0))
    });
    let board = Motherboard::new().map_err(|e| e.to_string());
    let board_value = |get: fn(&Motherboard) -> Option<String>| {
        board.as_ref().map_err(Clone::clone).and_then(|board| {
            get(board).ok_or_else(|| "Motherboard information unavailable".into())
        })
    };
    let firmware = |name: &str| {
        let path = format!("/sys/class/dmi/id/{name}");
        std::fs::read_to_string(&path)
            .map(|s| s.trim().to_owned())
            .map_err(|e| format!("Firmware information unavailable: {e}"))
    };
    json!({"api_version":1,"values":{
        IDS[0]:field(System::host_name().map_err(|e|e.to_string())),
        IDS[1]:field(processor),
        IDS[2]:field(memory),
        IDS[3]:field(Ok(System::cpu_arch())),
        IDS[4]:field(System::long_os_version().map_err(|e|e.to_string())),
        IDS[5]:field(Product::vendor_name().map_err(|e|e.to_string())),
        IDS[6]:field(Product::name().map_err(|e|e.to_string())),
        IDS[7]:field(Product::version().map_err(|e|e.to_string())),
        IDS[8]:field(board_value(Motherboard::vendor_name)),
        IDS[9]:field(board_value(Motherboard::name)),
        IDS[10]:field(firmware("bios_vendor")),
        IDS[11]:field(firmware("bios_version")),
        IDS[12]:field(firmware("bios_date").and_then(|raw|firmware_date(&raw))),
        IDS[13]:field(System::physical_core_count().map(|n|n.to_string()).map_err(|e|e.to_string())),
        IDS[14]:field(system.as_ref().map(|s|s.cpus().len().to_string()).map_err(Clone::clone)),
        IDS[15]:field(System::kernel_version().map_err(|e|e.to_string())),
    }})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn failed_fields_never_become_sample_values() {
        for invalid in ["", "9/8/25", "invalid", "09/08/2025 extra"] {
            assert!(firmware_date(invalid).is_err());
        }
        for unavailable in [
            " ",
            "To Be Filled By O.E.M.",
            "Default string",
            "Unknown",
            "None",
            "N/A",
        ] {
            assert!(field(Ok(unavailable.into()))["value"].is_null());
        }
        assert_eq!(field(Ok(" HP ".into()))["value"], "HP");
        assert_eq!(field(Err("denied".into()))["error"], "denied");
        let state = read();
        assert_eq!(state["values"].as_object().unwrap().len(), IDS.len());
        for id in IDS {
            let field = &state["values"][id];
            assert_ne!(field["value"].is_string(), field["error"].is_string());
            assert!(!field["value"].as_str().unwrap_or("").contains('\u{00b7}'));
        }
    }
}
