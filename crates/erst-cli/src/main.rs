//! The erst command line tool and MCP server.

mod activity;
mod cli;
mod data_dir;
mod format;
mod mcp;
mod moment;
mod search;
mod stats;

use std::io::{self, Write};
use std::process::ExitCode;

use anyhow::Result;
use clap::Parser;

use crate::cli::{Cli, Command};

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => report(&error),
    }
}

fn run(cli: Cli) -> Result<()> {
    let data_dir = data_dir::resolve(cli.data_dir)?;
    let store = data_dir::open(&data_dir)?;
    let now_ms = erst_core::now_ms();
    match cli.command {
        Command::Search(args) => with_stdout(|out| search::run(&store, &args, now_ms, out)),
        Command::Moment(args) => with_stdout(|out| moment::run(&store, &args, out)),
        Command::Stats(args) => with_stdout(|out| stats::run(&store, &args, now_ms, out)),
        Command::Activity(args) => with_stdout(|out| activity::run(&store, &args, now_ms, out)),
        Command::Mcp => mcp::serve(&store),
    }
}

fn with_stdout(action: impl FnOnce(&mut io::StdoutLock<'_>) -> Result<()>) -> Result<()> {
    let stdout = io::stdout();
    let mut out = stdout.lock();
    action(&mut out)?;
    out.flush()?;
    Ok(())
}

/// Turns an error into a message and a status. Piped output closing early is success.
fn report(error: &anyhow::Error) -> ExitCode {
    let io_error = error
        .chain()
        .find_map(|cause| cause.downcast_ref::<io::Error>());
    if let Some(io_error) = io_error {
        if io_error.kind() == io::ErrorKind::BrokenPipe {
            return ExitCode::SUCCESS;
        }
        if io_error.kind() == io::ErrorKind::NotFound {
            let _ = writeln!(io::stderr(), "{io_error}");
            return ExitCode::from(2);
        }
    }
    let _ = writeln!(io::stderr(), "error: {error:#}");
    ExitCode::FAILURE
}
