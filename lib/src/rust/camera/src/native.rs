//! Bounded native PipeWire requests. Never opens /dev/video devices directly.
use crate::{Backend, Camera, Control, FIELDS};
use pipewire as pw;
use pw::spa::{
    param::ParamType,
    pod::{ChoiceValue, Pod, Value, deserialize::PodDeserializer, serialize::PodSerializer},
    utils::ChoiceEnum,
};
use std::{
    cell::{Cell, RefCell},
    collections::BTreeMap,
    io::Cursor,
    rc::Rc,
    time::{Duration, Instant},
};

pub struct Native;
fn number(value: &Value) -> Option<f64> {
    match value {
        Value::Int(v) => Some(*v as f64),
        Value::Float(v) => Some(*v as f64),
        Value::Double(v) => Some(*v),
        _ => None,
    }
}
fn field(key: u32) -> Option<&'static str> {
    match key {
        0x20001 => Some(FIELDS[0]),
        0x20002 => Some(FIELDS[1]),
        0x20003 => Some(FIELDS[2]),
        0x20008 => Some(FIELDS[3]),
        _ => None,
    }
}
fn key(field: &str) -> u32 {
    match field {
        "brightness" => 0x20001,
        "contrast" => 0x20002,
        "saturation" => 0x20003,
        "sharpness" => 0x20008,
        _ => unreachable!(),
    }
}
fn control(value: &Value) -> Option<Control> {
    macro_rules! choice {
        ($c:expr) => {
            match &$c.1 {
                ChoiceEnum::Range { default, min, max } => {
                    Some((*default as f64, *min as f64, *max as f64, 0.))
                }
                ChoiceEnum::Step {
                    default,
                    min,
                    max,
                    step,
                } => Some((*default as f64, *min as f64, *max as f64, *step as f64)),
                _ => None,
            }
        };
    }
    let (default, min, max, step) = match value {
        Value::Choice(ChoiceValue::Int(c)) => choice!(c),
        Value::Choice(ChoiceValue::Float(c)) => choice!(c),
        Value::Choice(ChoiceValue::Double(c)) => choice!(c),
        _ => None,
    }?;
    (min.is_finite()
        && max.is_finite()
        && default.is_finite()
        && step.is_finite()
        && min < max
        && step >= 0.
        && default >= min
        && default <= max)
        .then_some(Control {
            value: f64::NAN,
            default,
            min,
            max,
            step,
            writable: true,
        })
}
fn roundtrip(loop_: &pw::main_loop::MainLoopRc, core: &pw::core::CoreRc) -> Result<(), String> {
    let done = Rc::new(Cell::new(false));
    let flag = done.clone();
    let error = Rc::new(RefCell::new(None));
    let err = error.clone();
    let pending = core.sync(0).map_err(|e| e.to_string())?;
    let _listener = core
        .add_listener_local()
        .done(move |id, seq| {
            if id == 0 && seq == pending {
                flag.set(true);
            }
        })
        .error(move |_, _, _, message| {
            *err.borrow_mut() = Some(message.to_owned());
        })
        .register();
    let deadline = Instant::now() + Duration::from_secs(3);
    while !done.get() {
        loop_
            .loop_()
            .iterate(pw::loop_::Timeout::Finite(Duration::from_millis(20)));
        if let Some(message) = error.borrow().as_ref() {
            return Err(format!("PipeWire: {message}"));
        }
        if Instant::now() >= deadline {
            return Err("PipeWire camera request timed out".into());
        }
    }
    Ok(())
}
fn request(change: Option<(&Camera, &BTreeMap<String, f64>)>) -> Result<Vec<Camera>, String> {
    pw::init();
    let loop_ = pw::main_loop::MainLoopRc::new(None).map_err(|e| e.to_string())?;
    let context = pw::context::ContextRc::new(&loop_, None).map_err(|e| e.to_string())?;
    let core = context
        .connect_rc(None)
        .map_err(|e| format!("Cannot connect to PipeWire: {e}"))?;
    let registry = core.get_registry_rc().map_err(|e| e.to_string())?;
    let cameras = Rc::new(RefCell::new(BTreeMap::<u32, Camera>::new()));
    let nodes = Rc::new(RefCell::new(Vec::new()));
    let registry_weak = registry.downgrade();
    let inventory = cameras.clone();
    let proxies = nodes.clone();
    let _listener = registry
        .add_listener_local()
        .global(move |global| {
            let Some(props) = global.props.as_ref() else {
                return;
            };
            if global.type_ != pw::types::ObjectType::Node
                || props.get("media.class") != Some("Video/Source")
            {
                return;
            }
            let (Some(name), Some(serial)) = (
                props.get("node.name"),
                props.get("object.serial").and_then(|s| s.parse().ok()),
            ) else {
                return;
            };
            let Some(registry) = registry_weak.upgrade() else {
                return;
            };
            let Ok(node) = registry.bind::<pw::node::Node, _>(global) else {
                return;
            };
            let id = global.id;
            let writable = global
                .permissions
                .contains(pw::permissions::PermissionFlags::W);
            inventory.borrow_mut().insert(
                id,
                Camera {
                    name: name.into(),
                    serial,
                    framerate: None,
                    description: props.get("node.description").unwrap_or(name).into(),
                    controls: BTreeMap::new(),
                },
            );
            let result = inventory.clone();
            let listener = node
                .add_listener_local()
                .param(move |_, param, _, _, pod| {
                    let Some(pod) = pod else { return };
                    let Ok((_, Value::Object(object))) =
                        PodDeserializer::deserialize_any_from(pod.as_bytes())
                    else {
                        return;
                    };
                    let mut cameras = result.borrow_mut();
                    let Some(camera) = cameras.get_mut(&id) else {
                        return;
                    };
                    if param == ParamType::EnumFormat {
                        if camera.framerate.is_none() {
                            for p in &object.properties {
                                if p.key == 0x20004 {
                                    let f = match &p.value {
                                        Value::Fraction(f) => Some(*f),
                                        Value::Choice(ChoiceValue::Fraction(c)) => match &c.1 {
                                            ChoiceEnum::None(f)
                                            | ChoiceEnum::Range { default: f, .. }
                                            | ChoiceEnum::Step { default: f, .. }
                                            | ChoiceEnum::Enum { default: f, .. } => Some(*f),
                                            _ => None,
                                        },
                                        _ => None,
                                    };
                                    if let Some(f) = f
                                        && f.num > 0
                                        && f.denom > 0
                                    {
                                        camera.framerate = Some((f.num, f.denom));
                                    }
                                }
                            }
                        }
                    } else if param == ParamType::PropInfo {
                        let prop = object.properties.iter().find(|p| p.key == 1).and_then(|p| {
                            if let Value::Id(v) = &p.value {
                                field(v.0)
                            } else {
                                None
                            }
                        });
                        if let Some(field) = prop
                            && let Some(mut c) = object
                                .properties
                                .iter()
                                .find(|p| p.key == 3)
                                .and_then(|p| control(&p.value))
                        {
                            c.writable = writable;
                            camera.controls.insert(field.into(), c);
                        }
                    } else if param == ParamType::Props {
                        for p in object.properties {
                            if let Some(field) = field(p.key)
                                && let Some(value) = number(&p.value)
                                && let Some(c) = camera.controls.get_mut(field)
                            {
                                c.value = value;
                            }
                        }
                    }
                })
                .register();
            node.enum_params(0, Some(ParamType::PropInfo), 0, u32::MAX);
            node.enum_params(0, Some(ParamType::EnumFormat), 0, u32::MAX);
            node.enum_params(0, Some(ParamType::Props), 0, u32::MAX);
            proxies.borrow_mut().push((id, node, listener));
        })
        .register();
    roundtrip(&loop_, &core)?;
    roundtrip(&loop_, &core)?;
    if let Some((wanted, values)) = change {
        let id = cameras
            .borrow()
            .iter()
            .find(|(_, c)| c.name == wanted.name && c.serial == wanted.serial)
            .map(|(id, _)| *id)
            .ok_or("Camera identity changed")?;
        let nodes = nodes.borrow();
        let (_, node, _) = nodes
            .iter()
            .find(|(i, _, _)| *i == id)
            .ok_or("Camera disappeared")?;
        let properties = values
            .iter()
            .map(|(f, v)| pw::spa::pod::Property {
                key: key(f),
                flags: pw::spa::pod::PropertyFlags::empty(),
                value: Value::Float(*v as f32),
            })
            .collect();
        let value = Value::Object(pw::spa::pod::Object {
            type_: pw::spa::utils::SpaTypes::ObjectParamProps.as_raw(),
            id: ParamType::Props.as_raw(),
            properties,
        });
        let (bytes, _) =
            PodSerializer::serialize(Cursor::new(Vec::new()), &value).map_err(|e| e.to_string())?;
        node.set_param(
            ParamType::Props,
            0,
            Pod::from_bytes(bytes.get_ref()).ok_or("Invalid camera parameter")?,
        );
        roundtrip(&loop_, &core)?;
    }
    let result: Vec<Camera> = cameras.borrow().values().cloned().collect();
    if result
        .iter()
        .any(|c| c.controls.values().any(|v| !v.value.is_finite()))
    {
        return Err("Incomplete camera parameter readback".into());
    }
    Ok(result)
}
impl Backend for Native {
    fn read(&mut self) -> Result<Vec<Camera>, String> {
        request(None)
    }
    fn write(&mut self, camera: &Camera, values: &BTreeMap<String, f64>) -> Result<(), String> {
        request(Some((camera, values))).map(|_| ())
    }
}
