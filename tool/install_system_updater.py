#!/usr/bin/env python3
"""Install the root-owned system updater and its polkit rule. Run once with sudo.

The rule lets the invoking user run only the fixed repository upgrade
(`remya-settings-update upgrade [--include-held]`) without a password, so the
resident Settings service can run manual and daily updates unattended.
Remove with: sudo rm /usr/local/libexec/remya-settings-update /etc/polkit-1/rules.d/50-top.remya.settings.update.rules
"""
import os
from pathlib import Path
import pwd
import re
import tempfile

UPDATER = Path("/usr/local/libexec/remya-settings-update")
RULE = Path("/etc/polkit-1/rules.d/50-top.remya.settings.update.rules")
MARKER = "// Installed by remya_settings tool/install_system_updater.py"


def rule(user):
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", user):
        raise ValueError(f"Unsupported user name: {user!r}")
    commands = " ||\n            ".join(
        f'command == "{UPDATER} {arguments}"' for arguments in ("upgrade", "upgrade --include-held"))
    return f"""{MARKER}
// Lets {user} run only the fixed Remya Settings repository upgrade without a password.
polkit.addRule(function(action, subject) {{
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "{UPDATER}" &&
        subject.user == "{user}") {{
        var command = action.lookup("command_line");
        if ({commands}) {{
            return polkit.Result.YES;
        }}
    }}
}});
"""


def write_atomic(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(descriptor, "wb") as file:
            file.write(data)
            os.fchown(file.fileno(), 0, 0)
            os.fchmod(file.fileno(), mode)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def main(root, environment):
    if os.geteuid() != 0:
        raise SystemExit("Run with sudo: sudo python tool/install_system_updater.py")
    user = environment.get("SUDO_USER", "")
    if not user or user == "root":
        raise SystemExit("Run with sudo from the ordinary account that uses Settings")
    pwd.getpwnam(user)
    source = root / "build/linux/x64/release/bundle/libexec/remya-settings-update"
    if not source.is_file():
        raise SystemExit("Run fvm flutter build linux --release first")
    if RULE.exists() and MARKER not in RULE.read_text():
        raise SystemExit(f"Refusing to replace unrelated polkit rule: {RULE}")
    text = rule(user)
    write_atomic(UPDATER, source.read_bytes(), 0o755)
    write_atomic(RULE, text.encode(), 0o644)
    print(f"Installed {UPDATER}")
    print(f"Installed {RULE} for {user}")


if __name__ == "__main__":
    main(Path(__file__).resolve().parents[1], os.environ)
