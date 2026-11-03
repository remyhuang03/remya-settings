//! Read-only OS identity and the Settings-owned avatar; no desktop account writes.
use gdk_pixbuf::{InterpType, Pixbuf, PixbufLoader, prelude::*};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    cell::Cell,
    fs,
    io::Read,
    path::{Path, PathBuf},
    rc::Rc,
};

pub const USERNAME: &str = "your-info.a1aaf352";
pub const AVATAR: &str = "your-info.58484bbb";
pub const IDS: [&str; 2] = [USERNAME, AVATAR];
const MAX_BYTES: u64 = 32 << 20;
const MAX_PIXELS: i64 = 64_000_000;
const AVATAR_SIZE: i32 = 512;

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Crop {
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Upload {
    path: PathBuf,
    crop: Crop,
}

pub struct AccountInformation {
    avatar: PathBuf,
}
impl AccountInformation {
    pub fn new(avatar: PathBuf) -> Self {
        Self { avatar }
    }

    pub fn read(&self) -> Result<Value, String> {
        let username = gio::glib::user_name()
            .into_string()
            .map_err(|_| "Username is not valid UTF-8")?;
        let avatar = match fs::metadata(&self.avatar) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e.to_string()),
            Ok(metadata) => {
                if !metadata.is_file() || metadata.len() > MAX_BYTES {
                    Err("Saved avatar is not a regular image".into())
                } else {
                    Pixbuf::file_info(&self.avatar)
                        .filter(|(format, width, height)| {
                            format.name().as_deref() == Some("png")
                                && *width == AVATAR_SIZE
                                && *height == AVATAR_SIZE
                        })
                        .ok_or_else(|| "Saved avatar is not a 512 × 512 PNG".to_string())
                        .and_then(|_| metadata.modified().map_err(|e| e.to_string()))
                        .and_then(|time| {
                            time.duration_since(std::time::UNIX_EPOCH)
                                .map_err(|e| e.to_string())
                        })
                        .map(|time| Some(time.as_nanos().to_string()))
                }
            }
        };
        let (path, revision, error) = match avatar {
            Ok(Some(revision)) => (Some(&self.avatar), Some(revision), None),
            Ok(None) => (None, None, None),
            Err(error) => (None, None, Some(error)),
        };
        Ok(
            json!({"api_version": 1, "username": username, "avatar_path": path, "avatar_revision": revision, "error": error}),
        )
    }

    pub fn read_setting(&self, id: &str) -> Result<Value, String> {
        let state = self.read()?;
        let value = match id {
            USERNAME => &state["username"],
            _ => &state["avatar_path"],
        };
        Ok(json!({"id": id, "availability": "available", "value": value, "state": state}))
    }

    pub fn set(
        &self,
        id: &str,
        value: &str,
        write: fn(&Path, &[u8]) -> Result<(), String>,
    ) -> Result<Value, String> {
        if id != AVATAR {
            return Err("ReadOnly:Username is a read-only observation".into());
        }
        let upload: Upload = serde_json::from_str(value)
            .map_err(|e| invalid(&format!("Invalid avatar request: {e}")))?;
        let crop = upload.crop;
        if !upload.path.is_absolute()
            || [crop.left, crop.top, crop.right, crop.bottom]
                .iter()
                .any(|n| !n.is_finite() || !(0.0..=1.0).contains(n))
            || crop.left >= crop.right
            || crop.top >= crop.bottom
        {
            return Err(invalid(
                "Choose an absolute image path and a crop rectangle inside the image",
            ));
        }
        let mut file = fs::File::open(&upload.path)
            .map_err(|e| invalid(&format!("Cannot read image: {e}")))?;
        if !file.metadata().map_err(|e| e.to_string())?.is_file() {
            return Err(invalid("Choose a regular image file"));
        }
        let mut bytes = vec![];
        file.by_ref()
            .take(MAX_BYTES + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        if bytes.len() as u64 > MAX_BYTES {
            return Err(invalid("Choose an image no larger than 32 MiB"));
        }
        let supported = bytes.starts_with(b"\x89PNG\r\n\x1a\n")
            || bytes.starts_with(b"\xff\xd8\xff")
            || (bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP"));
        if !supported {
            return Err(invalid("Choose a PNG, JPEG or WebP image"));
        }
        let loader = PixbufLoader::new();
        let oversized = Rc::new(Cell::new(false));
        let limit = oversized.clone();
        loader.connect_size_prepared(move |loader, width, height| {
            if width <= 0
                || height <= 0
                || width > 16384
                || height > 16384
                || i64::from(width) * i64::from(height) > MAX_PIXELS
            {
                limit.set(true);
                loader.set_size(1, 1);
            }
        });
        let decoded = loader.write(&bytes);
        let closed = loader.close();
        decoded
            .and(closed)
            .map_err(|e| invalid(&format!("Cannot decode image: {e}")))?;
        if oversized.get() {
            return Err(invalid(
                "Choose an image up to 64 megapixels and 16,384 pixels per side",
            ));
        }
        let image = loader
            .pixbuf()
            .and_then(|p| p.apply_embedded_orientation())
            .ok_or_else(|| invalid("Cannot decode image"))?;
        let left = (crop.left * f64::from(image.width())).round() as i32;
        let top = (crop.top * f64::from(image.height())).round() as i32;
        let right = (crop.right * f64::from(image.width())).round() as i32;
        let bottom = (crop.bottom * f64::from(image.height())).round() as i32;
        if left >= right || top >= bottom {
            return Err(invalid("The crop rectangle is empty"));
        }
        let avatar = image
            .new_subpixbuf(left, top, right - left, bottom - top)
            .scale_simple(AVATAR_SIZE, AVATAR_SIZE, InterpType::Bilinear)
            .ok_or("Cannot resize avatar")?
            .save_to_bufferv("png", &[])
            .map_err(|e| e.to_string())?;
        if self.avatar.is_symlink() {
            return Err("Avatar path is a symbolic link; it was not overwritten".into());
        }
        write(&self.avatar, &avatar)?;
        self.read()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
        fs::write(path, bytes).map_err(|e| e.to_string())
    }
    #[test]
    fn crops_and_saves_a_real_avatar_and_retains_it_after_rejected_writes() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source.png");
        let pixels = Pixbuf::new(gdk_pixbuf::Colorspace::Rgb, false, 8, 4, 2).unwrap();
        pixels.fill(0xff0000ff);
        pixels.new_subpixbuf(2, 0, 2, 2).fill(0x0000ffff);
        fs::write(&source, pixels.save_to_bufferv("png", &[]).unwrap()).unwrap();
        let source_bytes = fs::read(&source).unwrap();
        let store = AccountInformation::new(root.path().join("avatar.png"));
        let request = json!({"path":source,"crop":{"left":0.5,"top":0,"right":1,"bottom":1}});
        let state = store.set(AVATAR, &request.to_string(), write).unwrap();
        assert!(state["avatar_path"].as_str().is_some());
        let saved = fs::read(&store.avatar).unwrap();
        let output = Pixbuf::from_file(&store.avatar).unwrap();
        assert_eq!((output.width(), output.height()), (512, 512));
        assert_eq!(&output.read_pixel_bytes()[..3], &[0, 0, 255]);
        assert!(
            store
                .set(USERNAME, "other", write)
                .unwrap_err()
                .starts_with("ReadOnly:")
        );
        let mut bad = request.clone();
        bad["crop"]["right"] = json!(2);
        assert!(store.set(AVATAR, &bad.to_string(), write).is_err());
        assert!(
            store
                .set(AVATAR, &request.to_string(), |_, _| Err(
                    "read-only destination".into()
                ))
                .is_err()
        );
        assert_eq!(fs::read(&store.avatar).unwrap(), saved);
        assert_eq!(fs::read(&source).unwrap(), source_bytes);
    }
}
