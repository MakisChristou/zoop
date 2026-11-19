//! The two checksums in a format-1 frame.

const CRC16_MODBUS_INIT: u16 = 0xFFFF;
const CRC16_MODBUS_POLY_REFLECTED: u16 = 0xA001;
const CRC32_INIT: u32 = 0xFFFF_FFFF;
const CRC32_POLY_REFLECTED: u32 = 0xEDB8_8320;

/// CRC-16/MODBUS: polynomial 0x8005 reflected, init 0xFFFF, no final XOR.
/// Covers the first six header bytes.
pub fn crc16_modbus(bytes: &[u8]) -> u16 {
    let mut crc = CRC16_MODBUS_INIT;
    for &byte in bytes {
        crc ^= u16::from(byte);
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                (crc >> 1) ^ CRC16_MODBUS_POLY_REFLECTED
            } else {
                crc >> 1
            };
        }
    }
    crc
}

/// Standard CRC-32 (zlib / PNG). Covers the inner packet.
pub fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = CRC32_INIT;
    for &byte in bytes {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                (crc >> 1) ^ CRC32_POLY_REFLECTED
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crc16_modbus_check_value() {
        // Standard check value for "123456789".
        assert_eq!(crc16_modbus(b"123456789"), 0x4B37);
    }

    #[test]
    fn crc32_check_value() {
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
        assert_eq!(crc32(b""), 0);
    }
}
