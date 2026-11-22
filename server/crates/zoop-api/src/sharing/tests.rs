use super::*;
fn config(range: &str) -> Config {
    Config {
        title: "My dashboard".into(),
        display_name: String::new(),
        show_photo: false,
        range: range.into(),
        from: None,
        to: None,
        widgets: vec!["steps".into()],
        layout: vec![],
        heatmap_year: false,
    }
}
fn date(s: &str) -> NaiveDate {
    s.parse().unwrap()
}
#[test]
fn default_is_exactly_thirty_days() {
    let c = config("last30");
    assert_eq!(
        window(&c, date("2026-03-02"), date("2020-01-01"), Some(2020)).unwrap(),
        (date("2026-02-01"), date("2026-03-02"))
    );
}
#[test]
fn history_is_paged_and_bounded() {
    let c = config("all");
    assert_eq!(
        window(&c, date("2026-11-20"), date("2020-05-04"), Some(2020)).unwrap(),
        (date("2020-05-04"), date("2020-12-31"))
    );
    assert!(window(&c, date("2026-11-20"), date("2020-05-04"), Some(2019)).is_err());
    assert_eq!(
        window(&c, date("2026-11-20"), date("2020-05-04"), Some(2024)).unwrap(),
        (date("2024-01-01"), date("2024-12-31"))
    );
}
#[test]
fn fixed_range_cannot_expand() {
    let mut c = config("fixed");
    c.from = Some(date("2026-01-05"));
    c.to = Some(date("2026-02-05"));
    assert_eq!(
        window(&c, date("2026-11-20"), date("2020-01-01"), Some(2020)).unwrap(),
        (date("2026-01-05"), date("2026-02-05"))
    );
    c.from = Some(date("2027-01-01"));
    c.to = Some(date("2027-02-01"));
    assert!(window(&c, date("2026-11-20"), date("2020-01-01"), None).is_err());
}
#[test]
fn rejects_unknown_duplicate_and_empty_widgets() {
    let mut c = config("last30");
    assert!(validate(&c).is_ok());
    c.widgets = vec!["raw_frames".into()];
    assert!(validate(&c).is_err());
    c.widgets = vec!["steps".into(), "steps".into()];
    assert!(validate(&c).is_err());
    c.widgets.clear();
    assert!(validate(&c).is_err());
}

#[test]
fn layout_rejects_overlaps_unknown_keys_and_out_of_bounds() {
    let mut c = config("last30");
    c.widgets = vec!["daily_rings".into(), "steps".into()];
    c.layout = vec![
        layout::Placement {
            size: None,
            key: "daily_rings".into(),
            x: 0,
            y: 0,
        },
        layout::Placement {
            size: None,
            key: "steps".into(),
            x: 0,
            y: 3,
        },
    ];
    assert!(validate(&c).is_ok());
    c.layout[1].y = 2;
    assert!(validate(&c).is_err());
    c.layout[1].y = 3;
    c.layout[0].x = 1;
    assert!(validate(&c).is_err());
    c.layout[0].x = 0;
    c.layout[1].y = u16::MAX;
    assert!(validate(&c).is_err());
    c.layout[1].y = 3;
    c.layout[1].key = "weight".into();
    assert!(validate(&c).is_err());
    c.layout.clear();
    assert!(validate(&c).is_ok());
}
