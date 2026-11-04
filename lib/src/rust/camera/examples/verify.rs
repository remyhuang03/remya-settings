//! Explicit hardware verification: restore every adjusted value before exiting.
use remya_settings_camera::{Backend, native::Native};
use std::collections::BTreeMap;
fn main() {
    let cameras = Native.read().unwrap();
    for camera in cameras.iter().filter(|c| !c.controls.is_empty()) {
        for (field, c) in &camera.controls {
            let value = if c.value < c.max {
                c.value + c.step.max(0.1)
            } else {
                c.value - c.step.max(0.1)
            };
            let result = Native
                .write(camera, &BTreeMap::from([(field.clone(), value)]))
                .and_then(|_| Native.read())
                .map(|all| {
                    all.into_iter()
                        .find(|x| x.serial == camera.serial)
                        .unwrap()
                        .controls[field]
                        .value
                });
            let restore = Native.write(camera, &BTreeMap::from([(field.clone(), c.value)]));
            restore.unwrap();
            assert_eq!(result.unwrap(), value, "{field}");
            assert_eq!(
                Native
                    .read()
                    .unwrap()
                    .into_iter()
                    .find(|x| x.serial == camera.serial)
                    .unwrap()
                    .controls[field]
                    .value,
                c.value
            );
        }
    }
    println!("Native parameter writes and restoration passed");
}
