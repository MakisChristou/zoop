use super::*;
use image::{Rgb, RgbImage};

fn jpeg(width: u32) -> Vec<u8> {
    let mut bytes = Vec::new();
    JpegEncoder::new(&mut bytes)
        .encode_image(&RgbImage::from_pixel(width, 8, Rgb([10, 20, 30])))
        .unwrap();
    bytes
}
#[test]
fn rejects_invalid_oversized_and_overdimension_images() {
    assert!(normalize(b"not a photo").is_err());
    assert!(normalize(&vec![0; MAX_BYTES + 1]).is_err());
    assert!(normalize(&jpeg(MAX_DIMENSION + 1)).is_err());
}
#[test]
fn normalizes_pixels_and_removes_source_metadata() {
    let mut original = jpeg(8);
    let metadata = b"private-location";
    let mut marker = vec![0xff, 0xfe, 0, u8::try_from(metadata.len() + 2).unwrap()];
    marker.extend_from_slice(metadata);
    original.splice(2..2, marker);
    let normalized = normalize(&original).unwrap();
    assert!(!normalized.windows(metadata.len()).any(|w| w == metadata));
    let decoded = image::load_from_memory_with_format(&normalized, ImageFormat::Jpeg).unwrap();
    assert_eq!((decoded.width(), decoded.height()), (8, 8));
}
