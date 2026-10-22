//! Text normalization and the stable line hash.

/// Trims and collapses every whitespace run to one space, preserving case.
pub(crate) fn normalize_text(input: &str) -> String {
    let mut normalized = String::with_capacity(input.len());
    for word in input.split_whitespace() {
        if !normalized.is_empty() {
            normalized.push(' ');
        }
        normalized.push_str(word);
    }
    normalized
}

/// The first 16 bytes of the BLAKE3 hash of the normalized text.
pub(crate) fn line_hash(normalized: &str) -> [u8; 16] {
    let digest = blake3::hash(normalized.as_bytes());
    let mut hash = [0_u8; 16];
    hash.copy_from_slice(&digest.as_bytes()[..16]);
    hash
}

#[cfg(test)]
mod tests {
    use super::{line_hash, normalize_text};

    #[test]
    fn collapses_inner_whitespace_and_keeps_case() {
        assert_eq!(
            normalize_text("  Hello\t\tWorld \n Again  "),
            "Hello World Again"
        );
    }

    #[test]
    fn whitespace_only_normalizes_to_empty() {
        assert_eq!(normalize_text(" \t\n "), "");
    }

    #[test]
    fn hash_is_stable_and_sixteen_bytes() {
        let first = line_hash("Hello World");
        let second = line_hash("Hello World");
        assert_eq!(first, second);
        assert_eq!(first.len(), 16);
        assert_ne!(first, line_hash("Hello world"));
    }
}
