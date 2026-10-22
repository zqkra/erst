//! Search query parsing and safe FTS5 expression building.

use crate::time::{local_day_containing, local_day_of_text};

/// A search input split into structured filters and full-text pieces.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ParsedQuery {
    /// Plain search terms, in the order they were typed.
    pub terms: Vec<String>,
    /// Quoted phrases, in the order they were typed.
    pub phrases: Vec<String>,
    /// Exact app name from `app:...`.
    pub app: Option<String>,
    /// Inclusive lower time bound in Unix milliseconds.
    pub since_ms: Option<i64>,
    /// Exclusive upper time bound in Unix milliseconds.
    pub until_ms: Option<i64>,
}

impl ParsedQuery {
    /// Builds an FTS5 `MATCH` expression for the terms and phrases.
    ///
    /// Every piece is a double quoted string with inner quotes doubled. The
    /// last plain term gets a prefix marker, so `pinn` becomes `"pinn"*`.
    /// Terms come first, then phrases. Returns `None` when there is no text to
    /// search for.
    pub fn fts_match(&self) -> Option<String> {
        let mut parts: Vec<String> = Vec::with_capacity(self.terms.len() + self.phrases.len());
        let last_term = self.terms.iter().rposition(|term| !term.is_empty());
        for (index, term) in self.terms.iter().enumerate() {
            if term.is_empty() {
                continue;
            }
            let mut quoted = quote_for_fts(term);
            if Some(index) == last_term {
                quoted.push('*');
            }
            parts.push(quoted);
        }
        for phrase in &self.phrases {
            if !phrase.is_empty() {
                parts.push(quote_for_fts(phrase));
            }
        }
        if parts.is_empty() {
            None
        } else {
            Some(parts.join(" "))
        }
    }

    /// Whether the query has no terms, phrases, or filters at all.
    pub fn is_empty(&self) -> bool {
        self.terms.is_empty()
            && self.phrases.is_empty()
            && self.app.is_none()
            && self.since_ms.is_none()
            && self.until_ms.is_none()
    }
}

/// Parses a search input into terms, phrases, and filters.
///
/// Supports `app:Safari`, `app:"Visual Studio Code"`, quoted phrases,
/// standalone `today` and `yesterday`, `since:YYYY-MM-DD` (from its local
/// midnight), and `until:YYYY-MM-DD` (through the end of that local day).
/// Dates that do not exist and unknown prefixes stay as plain terms. Recognized
/// tokens are applied in order, so a later one replaces an earlier one.
///
/// `offset_ms_at` maps an instant to its UTC offset in milliseconds, so every
/// local day starts and ends at the right instant, including on a daylight
/// saving day.
pub fn parse(input: &str, now_ms: i64, offset_ms_at: impl Fn(i64) -> i64) -> ParsedQuery {
    let offset: &dyn Fn(i64) -> i64 = &offset_ms_at;
    let mut query = ParsedQuery::default();
    for token in tokenize(input) {
        match token {
            Token::Phrase(phrase) => {
                if !phrase.is_empty() {
                    query.phrases.push(phrase);
                }
            }
            Token::Prefixed { prefix, value } => {
                apply_prefixed(&mut query, &prefix, &value, offset);
            }
            Token::Word(word) => apply_word(&mut query, &word, now_ms, offset),
        }
    }
    query
}

enum Token {
    Word(String),
    Phrase(String),
    Prefixed { prefix: String, value: String },
}

fn apply_word(query: &mut ParsedQuery, word: &str, now_ms: i64, offset: &dyn Fn(i64) -> i64) {
    if word.eq_ignore_ascii_case("today") {
        let today = local_day_containing(now_ms, offset);
        query.since_ms = Some(today.start_ms);
        query.until_ms = Some(today.end_ms);
        return;
    }
    if word.eq_ignore_ascii_case("yesterday") {
        let today = local_day_containing(now_ms, offset);
        let yesterday = local_day_containing(today.start_ms.saturating_sub(1), offset);
        query.since_ms = Some(yesterday.start_ms);
        query.until_ms = Some(yesterday.end_ms);
        return;
    }
    let Some((prefix, value)) = word.split_once(':') else {
        push_term(query, word);
        return;
    };
    match prefix {
        "app" if !value.is_empty() => query.app = Some(value.to_owned()),
        "since" => apply_since(query, prefix, value, offset),
        "until" => apply_until(query, prefix, value, offset),
        _ => push_term(query, word),
    }
}

fn apply_prefixed(query: &mut ParsedQuery, prefix: &str, value: &str, offset: &dyn Fn(i64) -> i64) {
    match prefix {
        "app" if !value.is_empty() => query.app = Some(value.to_owned()),
        "since" => apply_since(query, prefix, value, offset),
        "until" => apply_until(query, prefix, value, offset),
        _ => push_term(query, &format!("{prefix}:{value}")),
    }
}

fn apply_since(query: &mut ParsedQuery, prefix: &str, value: &str, offset: &dyn Fn(i64) -> i64) {
    match local_day_of_text(value, offset) {
        Some(day) => query.since_ms = Some(day.start_ms),
        None => push_term(query, &format!("{prefix}:{value}")),
    }
}

fn apply_until(query: &mut ParsedQuery, prefix: &str, value: &str, offset: &dyn Fn(i64) -> i64) {
    match local_day_of_text(value, offset) {
        Some(day) => query.until_ms = Some(day.end_ms),
        None => push_term(query, &format!("{prefix}:{value}")),
    }
}

fn push_term(query: &mut ParsedQuery, term: &str) {
    if !term.is_empty() {
        query.terms.push(term.to_owned());
    }
}

fn quote_for_fts(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

fn tokenize(input: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let mut cursor = 0;
    while cursor < input.len() {
        let rest = &input[cursor..];
        let Some(first) = rest.chars().next() else {
            break;
        };
        if first.is_whitespace() {
            cursor += first.len_utf8();
            continue;
        }
        if first == '"' {
            let (value, next) = read_quoted(input, cursor + 1);
            tokens.push(Token::Phrase(value));
            cursor = next;
            continue;
        }
        let start = cursor;
        let mut end = cursor;
        let mut prefixed = None;
        for (offset, character) in input[start..].char_indices() {
            let at = start + offset;
            if character.is_whitespace() {
                break;
            }
            if character == '"' && at > start && input[start..at].ends_with(':') {
                let prefix = input[start..at - 1].to_owned();
                let (value, next) = read_quoted(input, at + 1);
                prefixed = Some((prefix, value));
                end = next;
                break;
            }
            end = at + character.len_utf8();
        }
        if let Some((prefix, value)) = prefixed {
            tokens.push(Token::Prefixed { prefix, value });
        } else {
            tokens.push(Token::Word(input[start..end].to_owned()));
        }
        cursor = end;
    }
    tokens
}

fn read_quoted(input: &str, start: usize) -> (String, usize) {
    let mut value = String::new();
    let mut chars = input[start..].char_indices().peekable();
    while let Some((offset, character)) = chars.next() {
        match character {
            '"' => return (value, start + offset + 1),
            '\\' if chars.peek().is_some_and(|&(_, next)| next == '"') => {
                chars.next();
                value.push('"');
            }
            _ => value.push(character),
        }
    }
    (value, input.len())
}

#[cfg(test)]
mod tests;
