//! UniFFI facade that exposes the Erst engine to Swift.
//!
//! [`Engine`] orchestrates `erst-core` and `erst-store`; the modules below only
//! map between crate types and the records Swift sees.

#![allow(clippy::missing_errors_doc)] // every fallible method returns the documented ErstError

mod convert;
mod engine;
mod error;
mod records;
mod settings;
mod track;
mod zone;

pub use engine::Engine;
pub use error::ErstError;
pub use records::*;
pub use track::*;

uniffi::setup_scaffolding!();
