//! Private profile-photo round trips, device isolation and bounded uploads.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use image::{Rgb, RgbImage, codecs::jpeg::JpegEncoder};
use snoop_api::{AppState, build_router};
use support::{DEVICE, Db};
use tower::ServiceExt;

async fn request(
    db: &Db,
    method: &str,
    device: &str,
    bytes: Vec<u8>,
    auth: bool,
) -> (u16, Vec<u8>) {
    let mut request = Request::builder()
        .method(method)
        .uri(format!("/v1/devices/{device}/profile/photo"))
        .header("content-type", "image/jpeg");
    if auth {
        request = request.header("authorization", "Bearer test-token");
    }
    let response = build_router(AppState::new(db.store.clone(), "test-token".into()))
        .oneshot(request.body(Body::from(bytes)).unwrap())
        .await
        .unwrap();
    (
        response.status().as_u16(),
        to_bytes(response.into_body(), 1024 * 1024)
            .await
            .unwrap()
            .to_vec(),
    )
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn photo_upload_read_replace_remove_and_auth() {
    let db = Db::new().await;
    let mut photo = Vec::new();
    JpegEncoder::new(&mut photo)
        .encode_image(&RgbImage::from_pixel(32, 32, Rgb([40, 80, 120])))
        .unwrap();
    for method in ["GET", "PUT", "DELETE"] {
        assert_eq!(
            request(&db, method, DEVICE, photo.clone(), false).await.0,
            401
        );
    }
    assert_eq!(request(&db, "GET", DEVICE, vec![], true).await.0, 404);
    assert_eq!(
        request(&db, "PUT", DEVICE, b"invalid".to_vec(), true)
            .await
            .0,
        400
    );
    assert_eq!(
        request(&db, "PUT", DEVICE, vec![0; 262145], true).await.0,
        413
    );
    assert_eq!(
        request(&db, "PUT", "OTHER", photo.clone(), true).await.0,
        404
    );
    let (status, saved) = request(&db, "PUT", DEVICE, photo.clone(), true).await;
    assert_eq!(status, 200);
    assert_eq!(
        request(&db, "GET", DEVICE, vec![], true).await,
        (200, saved)
    );
    assert_eq!(request(&db, "GET", "OTHER", vec![], true).await.0, 404);
    assert_eq!(request(&db, "PUT", DEVICE, photo, true).await.0, 200);
    assert_eq!(db.count("SELECT count(*) FROM profile_photos").await, 1);
    assert_eq!(request(&db, "DELETE", "OTHER", vec![], true).await.0, 204);
    assert_eq!(db.count("SELECT count(*) FROM profile_photos").await, 1);
    assert_eq!(request(&db, "DELETE", DEVICE, vec![], true).await.0, 204);
    assert_eq!(request(&db, "GET", DEVICE, vec![], true).await.0, 404);
    assert_eq!(request(&db, "DELETE", DEVICE, vec![], true).await.0, 204);
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 0);
}
