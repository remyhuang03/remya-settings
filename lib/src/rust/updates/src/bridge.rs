use crate::{
    process,
    protocol::{self, BridgeRequest, Output},
};
use std::{
    io::{BufReader, Write},
    os::{fd::FromRawFd, unix::net::UnixStream},
};

pub fn run() -> Result<i32, String> {
    let uid = unsafe { libc::geteuid() };
    if uid == 0 {
        return Err("The updater bridge must run as the ordinary user".into());
    }
    let job = std::env::var("REMYA_UPDATE_JOB")
        .map_err(|_| "Updater bridge has no active private session")?;
    if !protocol::valid_job(&job) {
        return Err("Invalid updater job identity".into());
    }
    let fd = protocol::BRIDGE_FD;
    let mut kind = 0i32;
    let mut length = std::mem::size_of::<i32>() as libc::socklen_t;
    if unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_TYPE,
            (&mut kind as *mut i32).cast(),
            &mut length,
        )
    } != 0
        || kind != libc::SOCK_STREAM
    {
        return Err("Updater bridge has no inherited private channel".into());
    }
    let mut socket = unsafe { UnixStream::from_raw_fd(fd) };
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    let operation = protocol::parse_sudo(&args, &process::job_base(uid).join(&job))?;
    protocol::write_frame(&mut socket, &BridgeRequest { job, operation })?;
    let mut reader = BufReader::new(socket);
    while let Some(line) = protocol::read_frame(&mut reader)? {
        match serde_json::from_str::<Output>(&line).map_err(|e| e.to_string())? {
            Output::Text { text } => {
                print!("{text}");
                std::io::stdout().flush().map_err(|e| e.to_string())?;
            }
            Output::Exit { code } => return Ok(code),
            Output::Error { message } => return Err(message),
        }
    }
    Err("Updater authorization channel closed; no new package operation was started".into())
}
