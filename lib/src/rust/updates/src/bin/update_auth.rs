fn main() {
    let code = remya_settings_updates::bridge::run().unwrap_or_else(|error| {
        eprintln!("{error}");
        1
    });
    std::process::exit(code);
}
