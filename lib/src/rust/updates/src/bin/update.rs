//! Root-owned system updater, started by the Settings service through pkexec.
use remya_settings_updates::{UPDATER_VERSION, updater};
use std::os::unix::process::CommandExt;

fn main() {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if args == ["version"] {
        println!("{UPDATER_VERSION}");
        return;
    }
    let all = match updater::parse(
        &args,
        unsafe { libc::geteuid() },
        std::env::var("PKEXEC_UID").ok(),
    ) {
        Ok(all) => all,
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(2);
        }
    };
    let error = match updater::command(all) {
        // exec keeps the transaction's exit status; on success this never returns.
        Ok(mut command) => command.exec().to_string(),
        Err(error) => error,
    };
    eprintln!("{error}");
    std::process::exit(1);
}
