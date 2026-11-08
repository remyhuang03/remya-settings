//! Airplane mode is derived from live radios, never restored at startup.
use crate::nm;
use remya_settings_bluetooth::Bluetooth;
use serde_json::{Value, json};

pub const ENABLED: &str = "airplane.enabled";
pub const WIFI: &str = "airplane.wifi";

trait Radios {
    fn network(&self) -> Result<(bool, bool), String>;
    fn bluetooth(&self) -> Result<Value, String>;
    fn set_network(&self, property: &str, enabled: bool) -> Result<(), String>;
    fn set_bluetooth(&self, enabled: bool) -> Result<(), String>;
}

impl Radios for Bluetooth {
    fn network(&self) -> Result<(bool, bool), String> {
        nm::radios()
    }
    fn bluetooth(&self) -> Result<Value, String> {
        self.read()
    }
    fn set_network(&self, property: &str, enabled: bool) -> Result<(), String> {
        nm::set_radio(property, enabled)
    }
    fn set_bluetooth(&self, enabled: bool) -> Result<(), String> {
        self.set_all_powered(enabled).map(drop)
    }
}

fn observe(radios: &impl Radios) -> Result<Value, String> {
    let (wifi, wwan) = radios.network()?;
    let bluetooth = radios.bluetooth()?;
    if bluetooth["available"] != true {
        return Err(format!(
            "Unavailable:{}",
            bluetooth["error"]
                .as_str()
                .unwrap_or("BlueZ is unavailable")
        ));
    }
    let adapters = bluetooth["adapters"]
        .as_array()
        .ok_or("Missing Bluetooth adapters")?;
    let mut powered = false;
    for adapter in adapters {
        powered |= adapter["powered"]
            .as_bool()
            .ok_or("Missing Bluetooth power state")?;
    }
    Ok(
        json!({"api_version":1,"available":true,"enabled":!wifi && !wwan && !powered,
        "wifi_enabled":wifi,"wwan_enabled":wwan,"bluetooth_enabled":powered,
        "adapters":adapters}),
    )
}

pub fn read(bluetooth: &Bluetooth) -> Result<Value, String> {
    observe(bluetooth)
}

fn change(radios: &impl Radios, id: &str, value: &str) -> Result<Value, String> {
    let enabled = match value {
        "true" => true,
        "false" => false,
        _ => return Err("InvalidArgument:Use true or false".into()),
    };
    let before = observe(radios)?;
    let mut errors = vec![];
    let mut network = |property, actual, desired| {
        if actual != desired
            && let Err(error) = radios.set_network(property, desired)
        {
            errors.push(error);
        }
    };
    match id {
        WIFI => network("WirelessEnabled", before["wifi_enabled"] == true, enabled),
        ENABLED => {
            network("WirelessEnabled", before["wifi_enabled"] == true, !enabled);
            network("WwanEnabled", before["wwan_enabled"] == true, !enabled);
            if let Err(error) = radios.set_bluetooth(!enabled) {
                errors.push(error);
            }
        }
        _ => return Err("InvalidArgument:Unknown airplane setting".into()),
    }
    // Never undo a successful radio shutdown after another radio fails.
    let after = observe(radios)?;
    if !errors.is_empty() {
        return Err(format!(
            "Radio changes partially failed: {}",
            errors.join("; ")
        ));
    }
    let matches = if id == WIFI {
        after["wifi_enabled"] == enabled
    } else if enabled {
        after["enabled"] == true
    } else {
        after["wifi_enabled"] == true
            && after["wwan_enabled"] == true
            && after["adapters"]
                .as_array()
                .unwrap()
                .iter()
                .all(|a| a["powered"] == true)
    };
    if !matches {
        return Err("Radio readback did not match the requested state".into());
    }
    Ok(after)
}

pub fn set(bluetooth: &Bluetooth, id: &str, value: &str) -> Result<Value, String> {
    change(bluetooth, id, value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};
    struct Fake {
        wifi: Cell<bool>,
        wwan: Cell<bool>,
        adapters: RefCell<Vec<bool>>,
        fail: Cell<bool>,
        stale: Cell<bool>,
        available: Cell<bool>,
    }
    impl Fake {
        fn new() -> Self {
            Self {
                wifi: Cell::new(true),
                wwan: Cell::new(true),
                adapters: RefCell::new(vec![true, false]),
                fail: Cell::new(false),
                stale: Cell::new(false),
                available: Cell::new(true),
            }
        }
    }
    impl Radios for Fake {
        fn network(&self) -> Result<(bool, bool), String> {
            Ok((self.wifi.get(), self.wwan.get()))
        }
        fn bluetooth(&self) -> Result<Value, String> {
            Ok(
                json!({"available":self.available.get(),"adapters":self.adapters.borrow().iter().map(|p| json!({"powered":p})).collect::<Vec<_>>()}),
            )
        }
        fn set_network(&self, property: &str, enabled: bool) -> Result<(), String> {
            if !self.stale.get() {
                if property == "WirelessEnabled" {
                    self.wifi.set(enabled)
                } else {
                    self.wwan.set(enabled)
                }
            }
            Ok(())
        }
        fn set_bluetooth(&self, enabled: bool) -> Result<(), String> {
            if self.fail.get() {
                return Err("blocked".into());
            }
            self.adapters.borrow_mut().fill(enabled);
            Ok(())
        }
    }
    #[test]
    fn all_radios_and_external_changes_are_observed() {
        let f = Fake::new();
        assert_eq!(change(&f, ENABLED, "true").unwrap()["enabled"], true);
        assert!(f.adapters.borrow().iter().all(|p| !p));
        f.wifi.set(true);
        assert_eq!(observe(&f).unwrap()["enabled"], false);
        change(&f, ENABLED, "false").unwrap();
        assert!(f.wwan.get() && f.adapters.borrow().iter().all(|p| *p));
        change(&f, WIFI, "false").unwrap();
        assert!(f.wwan.get());
    }
    #[test]
    fn missing_bluez_invalid_input_partial_failure_and_readback_are_errors() {
        let f = Fake::new();
        assert!(change(&f, ENABLED, "yes").is_err());
        assert!(f.wifi.get());
        f.available.set(false);
        assert!(change(&f, ENABLED, "true").is_err());
        assert!(f.wifi.get());
        f.available.set(true);
        f.fail.set(true);
        assert!(
            change(&f, ENABLED, "true")
                .unwrap_err()
                .contains("partially failed")
        );
        assert!(!f.wifi.get() && !f.wwan.get());
        f.fail.set(false);
        f.stale.set(true);
        assert!(
            change(&f, ENABLED, "false")
                .unwrap_err()
                .contains("readback")
        );
    }
    #[test]
    fn no_bluetooth_adapter_is_a_valid_empty_inventory() {
        let f = Fake::new();
        f.adapters.borrow_mut().clear();
        assert_eq!(change(&f, ENABLED, "true").unwrap()["enabled"], true);
        assert_eq!(change(&f, ENABLED, "false").unwrap()["enabled"], false);
    }
}
