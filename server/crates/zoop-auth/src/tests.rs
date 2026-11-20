use super::*;

#[test]
fn hashes_are_salted_and_verify() {
    let a = hash_password("correct horse battery").unwrap();
    let b = hash_password("correct horse battery").unwrap();
    assert_ne!(a, b);
    assert!(a.starts_with("$argon2id$"));
    assert!(verify_password("correct horse battery", &a));
    assert!(!verify_password("incorrect password", &a));
    assert!(!verify_password("password", "broken"));
}
#[test]
fn tokens_and_bounds() {
    let a = random_token().unwrap();
    assert_eq!(a.len(), 64);
    assert_ne!(a, random_token().unwrap());
    assert_ne!(a, digest(&a));
    assert!(hash_password("short").is_err());
    assert!(hash_password(&"x".repeat(257)).is_err());
}
