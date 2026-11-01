//! The user unit that plays a video background through mpvpaper across sign-ins.
use serde::{Deserialize, Serialize};

pub const UNIT: &str = "top.remya.settings.video-background.service";
pub const FITS: [&str; 3] = ["cover", "contain", "fill"];
pub const PAUSES: [&str; 3] = ["keep", "pause", "stop"];

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Video {
    pub path: String,
    pub fit: String,
    pub pause: String,
}

fn mpv_options(fit: &str) -> String {
    let scale = match fit {
        "contain" => "",
        "fill" => " keepaspect=no",
        _ => " panscan=1.0",
    };
    format!("no-audio loop hwdec=auto load-scripts=no{scale}")
}

fn quoted(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('%', "%%")
        .replace('$', "$$");
    format!("\"{escaped}\"")
}

/// The bottom layer keeps video above hyprpaper whichever of them starts first.
pub fn render_unit(video: &Video) -> String {
    let pause = match video.pause.as_str() {
        "pause" => "--auto-pause ",
        "stop" => "--auto-stop ",
        _ => "",
    };
    format!(
        "# Managed by Remy'a Settings. Change the background in Settings.\n\
         [Unit]\n\
         Description=Remy'a Settings video background\n\
         PartOf=graphical-session.target\n\
         After=graphical-session.target hyprpaper.service\n\
         ConditionEnvironment=WAYLAND_DISPLAY\n\n\
         [Service]\n\
         ExecStart=mpvpaper {pause}--layer bottom --mpv-options {} \"*\" {}\n\
         Slice=session.slice\n\n\
         [Install]\n\
         WantedBy=graphical-session.target\n\n\
         [X-Remya]\n\
         Path={}\n\
         Fit={}\n\
         Pause={}\n",
        quoted(&mpv_options(&video.fit)),
        quoted(&video.path),
        video.path,
        video.fit,
        video.pause,
    )
}

pub fn parse_unit(text: &str) -> Result<Video, String> {
    let (_, tail) = text
        .split_once("[X-Remya]\n")
        .ok_or("The video background unit was edited outside Settings")?;
    let field = |key: &str| {
        tail.lines()
            .find_map(|line| line.strip_prefix(key))
            .map(str::to_owned)
            .ok_or_else(|| format!("The video background unit has no {key}"))
    };
    let video = Video {
        path: field("Path=")?,
        fit: field("Fit=")?,
        pause: field("Pause=")?,
    };
    if !FITS.contains(&video.fit.as_str()) || !PAUSES.contains(&video.pause.as_str()) {
        return Err("The video background unit has invalid values".into());
    }
    Ok(video)
}

/// Reads an mpvpaper started by something else, such as a shell wallpaper script.
pub fn parse_command_line(args: &[String]) -> Option<Video> {
    let path = args.last().filter(|p| p.starts_with('/'))?.clone();
    let joined = args.join(" ");
    let fit = if joined.contains("keepaspect=no") {
        "fill"
    } else if joined.contains("panscan=1") {
        "cover"
    } else {
        "contain"
    };
    let pause = if args.iter().any(|a| a == "--auto-stop" || a == "-s") {
        "stop"
    } else if args.iter().any(|a| a == "--auto-pause" || a == "-p") {
        "pause"
    } else {
        "keep"
    };
    Some(Video {
        path,
        fit: fit.into(),
        pause: pause.into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unit_round_trips_and_escapes_systemd_specifiers() {
        let video = Video {
            path: "/home/a b/100%$.mp4".into(),
            fit: "fill".into(),
            pause: "stop".into(),
        };
        let unit = render_unit(&video);
        assert!(unit.contains("\"/home/a b/100%%$$.mp4\""));
        assert!(unit.contains("--auto-stop --layer bottom"));
        assert!(unit.contains("keepaspect=no"));
        assert_eq!(parse_unit(&unit).unwrap(), video);
        assert!(parse_unit("[Unit]\n").is_err());
    }

    #[test]
    fn external_mpvpaper_arguments_are_understood() {
        let args = [
            "mpvpaper",
            "-s",
            "-o",
            "no-audio loop panscan=1.0",
            "DP-1",
            "/v.mp4",
        ]
        .map(String::from);
        assert_eq!(
            parse_command_line(&args).unwrap(),
            Video {
                path: "/v.mp4".into(),
                fit: "cover".into(),
                pause: "stop".into()
            }
        );
        assert!(parse_command_line(&["mpvpaper".to_owned()]).is_none());
    }
}
