//! The crate error type.

use std::fmt;

use crate::time::MAX_BUCKETS;

/// Something the caller passed to a pure function was not usable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreError {
    /// A thumbnail with zero size or a luma buffer that does not match it.
    InvalidThumbnail {
        /// Human readable explanation of the mismatch.
        reason: String,
    },
    /// A request asked for more buckets than [`MAX_BUCKETS`] allows.
    TooManyBuckets {
        /// Buckets the request needs.
        count: u64,
    },
}

impl fmt::Display for CoreError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidThumbnail { reason } => write!(formatter, "invalid thumbnail: {reason}"),
            Self::TooManyBuckets { count } => write!(
                formatter,
                "the range needs {count} buckets, more than the limit of {MAX_BUCKETS}"
            ),
        }
    }
}

impl std::error::Error for CoreError {}

#[cfg(test)]
mod tests {
    use super::CoreError;

    #[test]
    fn displays_the_reason() {
        let error = CoreError::InvalidThumbnail {
            reason: String::from("width is zero"),
        };
        assert_eq!(error.to_string(), "invalid thumbnail: width is zero");
    }

    #[test]
    fn is_a_std_error() {
        let error = CoreError::InvalidThumbnail {
            reason: String::from("bad size"),
        };
        let boxed: Box<dyn std::error::Error> = Box::new(error);
        assert_eq!(boxed.to_string(), "invalid thumbnail: bad size");
    }

    #[test]
    fn names_the_bucket_count_and_the_limit() {
        let error = CoreError::TooManyBuckets { count: 17_800_000 };
        assert_eq!(
            error.to_string(),
            "the range needs 17800000 buckets, more than the limit of 4096"
        );
    }
}
