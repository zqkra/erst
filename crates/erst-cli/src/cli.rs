//! Command line surface of the `erst` binary.

use std::path::PathBuf;

use clap::{Args, Parser, Subcommand};

/// Search and inspect the local Erst memory of your screen.
#[derive(Debug, Parser)]
#[command(name = "erst", version, about, long_about = None)]
pub struct Cli {
    /// Directory that holds erst.sqlite. Defaults to the app data directory.
    #[arg(long, global = true, value_name = "PATH")]
    pub data_dir: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Command,
}

/// One command per way of reading the database.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// Search the text Erst read from your screen.
    Search(SearchArgs),
    /// Print every text line of one moment, in reading order.
    Moment(MomentArgs),
    /// Show storage usage and recorded frames.
    Stats(StatsArgs),
    /// Show time spent per app, website, and category.
    Activity(ActivityArgs),
    /// Serve the MCP protocol over stdio for agents.
    Mcp,
}

/// Search terms plus narrowing filters and output format.
#[derive(Debug, Args)]
pub struct SearchArgs {
    /// Words to search for. Supports app:Safari, today, since:2026-10-01, "exact phrase".
    #[arg(required = true, num_args = 1.., value_name = "QUERY")]
    pub query: Vec<String>,

    /// Maximum number of moments to print.
    #[arg(long, default_value_t = 20, value_parser = clap::value_parser!(u32).range(1..), value_name = "N")]
    pub limit: u32,

    /// Print a JSON array instead of aligned text.
    #[arg(long)]
    pub json: bool,
}

/// One moment, by the frame ID that search printed.
#[derive(Debug, Args)]
pub struct MomentArgs {
    /// The frame ID of a moment from `erst search`.
    #[arg(value_name = "FRAME_ID", value_parser = clap::value_parser!(i64).range(1..))]
    pub frame_id: i64,

    /// Print a JSON object instead of text.
    #[arg(long)]
    pub json: bool,
}

/// Storage statistics, optionally as JSON.
#[derive(Debug, Args)]
pub struct StatsArgs {
    /// Print a JSON object instead of aligned text.
    #[arg(long)]
    pub json: bool,
}

/// Activity for one local day, optionally as JSON.
#[derive(Debug, Args)]
pub struct ActivityArgs {
    /// Local day in YYYY-MM-DD. Defaults to today.
    #[arg(long, value_name = "YYYY-MM-DD")]
    pub day: Option<String>,

    /// Print a JSON object instead of aligned text.
    #[arg(long)]
    pub json: bool,
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use clap::Parser;

    use super::{Cli, Command};

    fn parse(args: &[&str]) -> Cli {
        Cli::try_parse_from(args).unwrap()
    }

    #[test]
    fn moment_takes_a_positive_frame_id_and_json() {
        let cli = parse(&["erst", "moment", "42", "--json"]);
        let Command::Moment(args) = cli.command else {
            panic!("expected moment");
        };
        assert_eq!(args.frame_id, 42);
        assert!(args.json);
        assert!(Cli::try_parse_from(["erst", "moment", "0"]).is_err());
    }

    #[test]
    fn search_defaults_to_twenty_moments_and_text() {
        let cli = parse(&["erst", "search", "zebra"]);
        let Command::Search(args) = cli.command else {
            panic!("expected search");
        };
        assert_eq!(args.limit, 20);
        assert!(!args.json);
        assert_eq!(args.query, vec!["zebra"]);
    }

    #[test]
    fn search_keeps_every_word_in_order() {
        let cli = parse(&[
            "erst",
            "search",
            "zebra",
            "crossing",
            "app:\"Visual Studio Code\"",
        ]);
        let Command::Search(args) = cli.command else {
            panic!("expected search");
        };
        assert_eq!(
            args.query,
            vec!["zebra", "crossing", "app:\"Visual Studio Code\""]
        );
    }

    #[test]
    fn search_accepts_limit_and_json() {
        let cli = parse(&["erst", "search", "zebra", "--limit", "5", "--json"]);
        let Command::Search(args) = cli.command else {
            panic!("expected search");
        };
        assert_eq!(args.limit, 5);
        assert!(args.json);
    }

    #[test]
    fn search_rejects_a_zero_limit() {
        assert!(Cli::try_parse_from(["erst", "search", "zebra", "--limit", "0"]).is_err());
    }

    #[test]
    fn data_dir_is_global_and_works_before_or_after_the_command() {
        let before = parse(&["erst", "--data-dir", "/tmp/erst", "stats"]);
        assert_eq!(
            before.data_dir.as_deref(),
            Some(std::path::Path::new("/tmp/erst"))
        );
        let after = parse(&["erst", "stats", "--data-dir", "/tmp/erst", "--json"]);
        assert_eq!(
            after.data_dir.as_deref(),
            Some(std::path::Path::new("/tmp/erst"))
        );
    }

    #[test]
    fn activity_day_is_optional() {
        let cli = parse(&["erst", "activity", "--day", "2026-10-20", "--json"]);
        let Command::Activity(args) = cli.command else {
            panic!("expected activity");
        };
        assert_eq!(args.day.as_deref(), Some("2026-10-20"));
        assert!(args.json);
    }

    #[test]
    fn mcp_needs_no_arguments() {
        let cli = parse(&["erst", "mcp"]);
        assert!(matches!(cli.command, Command::Mcp));
    }

    #[test]
    fn unknown_command_fails() {
        assert!(Cli::try_parse_from(["erst", "export"]).is_err());
    }

    #[test]
    fn search_requires_a_query() {
        assert!(Cli::try_parse_from(["erst", "search"]).is_err());
    }
}
