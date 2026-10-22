//! The text layout of one frame, packed into one blob.
//!
//! A frame shows about 150 lines, and most of them are still on screen in the
//! next frame. One row per line plus a line index cost about 41 bytes a line;
//! packed here, sorted top to bottom with varints, a line costs about 10.
//!
//! Version 1: a version byte, the placement count as a varint, then for each
//! placement in `(y, x, line_id)` order five varints: `line_id << 2 | source`,
//! `y` minus the previous placement's `y`, `x`, `w`, and `h`.

use crate::error::StoreError;
use crate::model::LineSource;

const VERSION: u8 = 1;
const SOURCE_BITS: u32 = 2;
const SOURCE_MASK: u64 = (1 << SOURCE_BITS) - 1;
/// A varint of a `u64` takes at most ten bytes.
const MAX_VARINT_BYTES: usize = 10;
const VARINT_PAYLOAD_BITS: u32 = 7;
const VARINT_PAYLOAD_MASK: u8 = 0x7f;
const VARINT_CONTINUES: u8 = 0x80;

/// Where one line sits on a frame, in the frame's 0..=10000 coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Placement {
    pub line_id: i64,
    pub x: u16,
    pub y: u16,
    pub w: u16,
    pub h: u16,
    pub source: LineSource,
}

/// Packs placements, sorted top to bottom. The same line at the same spot
/// twice keeps its first placement, as the old `(frame, line, y, x)` key did.
pub(crate) fn encode(mut placements: Vec<Placement>) -> Vec<u8> {
    placements.sort_by_key(|placement| (placement.y, placement.x, placement.line_id));
    placements.dedup_by(|later, earlier| {
        later.line_id == earlier.line_id && later.y == earlier.y && later.x == earlier.x
    });
    let mut bytes = Vec::with_capacity(2 + placements.len() * MAX_VARINT_BYTES);
    bytes.push(VERSION);
    put_varint(&mut bytes, placements.len() as u64);
    let mut previous_y = 0;
    for placement in &placements {
        let line_id = u64::try_from(placement.line_id).unwrap_or(0);
        put_varint(
            &mut bytes,
            line_id << SOURCE_BITS | source_code(placement.source),
        );
        put_varint(&mut bytes, u64::from(placement.y - previous_y));
        put_varint(&mut bytes, u64::from(placement.x));
        put_varint(&mut bytes, u64::from(placement.w));
        put_varint(&mut bytes, u64::from(placement.h));
        previous_y = placement.y;
    }
    bytes
}

/// Unpacks a layout written by [`encode`], top to bottom.
///
/// # Errors
///
/// Returns [`StoreError::InvalidLayout`] for an unknown version, a truncated
/// blob, a value out of range, or bytes left over.
pub(crate) fn decode(bytes: &[u8]) -> Result<Vec<Placement>, StoreError> {
    let mut reader = Reader { bytes, offset: 0 };
    if reader.byte()? != VERSION {
        return Err(StoreError::InvalidLayout("unknown layout version"));
    }
    let count = usize::try_from(reader.varint()?)
        .map_err(|_| StoreError::InvalidLayout("placement count out of range"))?;
    // Each placement takes at least five bytes, so a forged count cannot reserve more.
    let mut placements = Vec::with_capacity(count.min(bytes.len() / 5));
    let mut y = 0_u16;
    for _ in 0..count {
        let identity = reader.varint()?;
        let line_id = i64::try_from(identity >> SOURCE_BITS)
            .map_err(|_| StoreError::InvalidLayout("line id out of range"))?;
        y = y
            .checked_add(reader.coordinate()?)
            .ok_or(StoreError::InvalidLayout("y out of range"))?;
        placements.push(Placement {
            line_id,
            x: reader.coordinate()?,
            y,
            w: reader.coordinate()?,
            h: reader.coordinate()?,
            source: LineSource::from_code(i64::try_from(identity & SOURCE_MASK).unwrap_or(0)),
        });
    }
    if reader.offset != bytes.len() {
        return Err(StoreError::InvalidLayout("bytes after the last placement"));
    }
    Ok(placements)
}

fn source_code(source: LineSource) -> u64 {
    u64::try_from(source.code()).unwrap_or(0)
}

fn put_varint(bytes: &mut Vec<u8>, mut value: u64) {
    loop {
        // Seven bits always fit a byte.
        let low = u8::try_from(value & u64::from(VARINT_PAYLOAD_MASK)).unwrap_or(0);
        value >>= VARINT_PAYLOAD_BITS;
        if value == 0 {
            bytes.push(low);
            return;
        }
        bytes.push(low | VARINT_CONTINUES);
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl Reader<'_> {
    fn byte(&mut self) -> Result<u8, StoreError> {
        let byte = *self
            .bytes
            .get(self.offset)
            .ok_or(StoreError::InvalidLayout("layout ends early"))?;
        self.offset += 1;
        Ok(byte)
    }

    fn varint(&mut self) -> Result<u64, StoreError> {
        let mut value = 0_u64;
        for index in 0..MAX_VARINT_BYTES {
            let byte = self.byte()?;
            let shift = VARINT_PAYLOAD_BITS * u32::try_from(index).unwrap_or(0);
            value |= u64::from(byte & VARINT_PAYLOAD_MASK)
                .checked_shl(shift)
                .ok_or(StoreError::InvalidLayout("varint too long"))?;
            if byte & VARINT_CONTINUES == 0 {
                return Ok(value);
            }
        }
        Err(StoreError::InvalidLayout("varint too long"))
    }

    fn coordinate(&mut self) -> Result<u16, StoreError> {
        u16::try_from(self.varint()?)
            .map_err(|_| StoreError::InvalidLayout("coordinate out of range"))
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use super::{Placement, decode, encode};
    use crate::error::StoreError;
    use crate::model::LineSource;

    fn placement(line_id: i64, x: u16, y: u16, source: LineSource) -> Placement {
        Placement {
            line_id,
            x,
            y,
            w: 3_000,
            h: 180,
            source,
        }
    }

    #[test]
    fn a_layout_reads_back_sorted_top_to_bottom() {
        let lines = vec![
            placement(7, 500, 9_000, LineSource::Ocr),
            placement(1, 200, 100, LineSource::Accessibility),
            placement(39_210, 0, 100, LineSource::Title),
            placement(3, 10_000, 10_000, LineSource::Ocr),
        ];
        let decoded = decode(&encode(lines.clone())).unwrap();
        let mut expected = lines;
        expected.sort_by_key(|line| (line.y, line.x, line.line_id));
        assert_eq!(decoded, expected);
    }

    #[test]
    fn an_empty_layout_is_two_bytes() {
        let bytes = encode(Vec::new());
        assert_eq!(bytes.len(), 2);
        assert_eq!(decode(&bytes).unwrap(), Vec::new());
    }

    #[test]
    fn the_same_line_at_the_same_spot_is_stored_once() {
        let mut twice = placement(5, 100, 200, LineSource::Ocr);
        let first = twice;
        twice.w = 1;
        let decoded = decode(&encode(vec![first, twice])).unwrap();
        assert_eq!(decoded, vec![first]);
    }

    #[test]
    fn a_typical_line_takes_about_ten_bytes() {
        let lines: Vec<Placement> = (0..150)
            .map(|index| {
                placement(
                    30_000 + index,
                    400,
                    u16::try_from(index * 60).unwrap(),
                    LineSource::Ocr,
                )
            })
            .collect();
        let bytes = encode(lines);
        assert!(bytes.len() <= 150 * 10 + 3, "{} bytes", bytes.len());
    }

    #[test]
    fn damaged_layouts_are_rejected() {
        let bytes = encode(vec![placement(9, 1, 2, LineSource::Ocr)]);
        for (damaged, reason) in [
            (vec![2_u8, 0], "unknown layout version"),
            (bytes[..bytes.len() - 1].to_vec(), "layout ends early"),
            (
                [bytes.clone(), vec![0]].concat(),
                "bytes after the last placement",
            ),
            (
                vec![1, 1, 4, 0, 0xff, 0xff, 0x7f, 0, 0],
                "coordinate out of range",
            ),
            (
                vec![
                    1, 1, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
                ],
                "varint too long",
            ),
        ] {
            match decode(&damaged) {
                Err(StoreError::InvalidLayout(found)) => assert_eq!(found, reason),
                other => panic!("expected {reason}, got {other:?}"),
            }
        }
    }

    #[test]
    fn a_forged_count_does_not_reserve_memory() {
        let error = decode(&[1, 0xff, 0xff, 0xff, 0xff, 0x0f]).unwrap_err();
        assert!(matches!(
            error,
            StoreError::InvalidLayout("layout ends early")
        ));
    }
}
