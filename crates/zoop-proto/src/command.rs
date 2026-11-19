//! Commands the phone writes to `fd4b0002`.
//!
//! Inner packet: `[35][seq][command][args…]`. The first argument byte matters and
//! differs per command: the strap silently ignores a HELLO sent with the wrong one.

use crate::{ProtoError, ProtoResult, framing::encode_frame};

const REQUEST_DESTINATION: u8 = 0x00;
const REQUEST_SOURCE: u8 = 0x01;

/// The fixed CLIENT_HELLO the official app sends after subscribing (GET_HELLO with
/// argument 0x01, sequence 1). Byte-exact to hardware captures.
pub const CLIENT_HELLO: [u8; 16] = [
    0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    ToggleRealtimeHr,
    AbortHistoricalTransmits,
    SendHistoricalData,
    HistoricalDataResult,
    GetBatteryLevel,
    GetDataRange,
    GetAdvertisingName,
    GetHello,
    GetClock,
}

impl Command {
    pub const fn code(self) -> u8 {
        match self {
            Self::ToggleRealtimeHr => 3,
            Self::AbortHistoricalTransmits => 20,
            Self::SendHistoricalData => 22,
            Self::HistoricalDataResult => 23,
            Self::GetBatteryLevel => 26,
            Self::GetDataRange => 34,
            Self::GetAdvertisingName => 141,
            Self::GetHello => 145,
            Self::GetClock => 147,
        }
    }
}

/// Builds a COMMAND frame. `args` includes the per-command first byte.
pub fn build_command(command: Command, sequence: u8, args: &[u8]) -> Vec<u8> {
    let mut inner = Vec::with_capacity(3 + args.len());
    inner.extend_from_slice(&[crate::PacketType::COMMAND, sequence, command.code()]);
    inner.extend_from_slice(args);
    encode_frame(&inner, REQUEST_DESTINATION, REQUEST_SOURCE)
}

/// Ask where the history ring buffer stands. Argument byte 0x00.
pub fn get_data_range(sequence: u8) -> Vec<u8> {
    build_command(Command::GetDataRange, sequence, &[0x00])
}

/// Start (or continue) the stored-data offload. Argument byte 0x00.
pub fn send_historical_data(sequence: u8) -> Vec<u8> {
    build_command(Command::SendHistoricalData, sequence, &[0x00])
}

/// Acknowledge one committed chunk by echoing its HISTORY_END token verbatim after a
/// 0x01 argument byte. Without this the strap stops after the first chunk.
///
/// # Errors
///
/// The token is not exactly 8 bytes.
pub fn history_ack(sequence: u8, token: &[u8]) -> ProtoResult<Vec<u8>> {
    if token.len() != 8 {
        return Err(ProtoError::BadToken { len: token.len() });
    }
    let mut args = Vec::with_capacity(9);
    args.push(0x01);
    args.extend_from_slice(token);
    Ok(build_command(
        Command::HistoricalDataResult,
        sequence,
        &args,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_matches_the_captured_constant() {
        assert_eq!(
            build_command(Command::GetHello, 1, &[0x01]),
            CLIENT_HELLO.to_vec()
        );
    }

    #[test]
    fn ack_echoes_token_after_flag_byte() {
        let token = [1, 2, 3, 4, 5, 6, 7, 8];
        let frame = history_ack(9, &token).unwrap();
        let parsed = crate::Frame::parse(&frame).unwrap();
        assert_eq!(parsed.inner(), &[35, 9, 23, 0x01, 1, 2, 3, 4, 5, 6, 7, 8]);
        assert_eq!(
            history_ack(0, &[1, 2, 3]),
            Err(ProtoError::BadToken { len: 3 })
        );
    }
}
