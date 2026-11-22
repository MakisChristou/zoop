//! Fixed widget footprints keep owner layouts bounded and collision-free.
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Placement {
    pub key: String,
    pub x: u16,
    pub y: u16,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size: Option<String>,
}
fn size(key: &str, preset: Option<&str>) -> (u16, u16) {
    match key {
        "daily_rings" | "activity_heatmap" => (2, 3),
        "by_sport" => (1, 3),
        "recent_workouts" => (1, 8),
        _ => (if preset == Some("wide") { 2 } else { 1 }, 4),
    }
}
pub(super) fn valid(items: &[Placement], keys: &[String]) -> bool {
    if items.is_empty() {
        return true;
    }
    if items.len() != keys.len() {
        return false;
    }
    for (i, a) in items.iter().enumerate() {
        if a.size
            .as_deref()
            .is_some_and(|v| !["standard", "wide"].contains(&v))
            || (a.size.as_deref() == Some("wide")
                && [
                    "daily_rings",
                    "activity_heatmap",
                    "by_sport",
                    "recent_workouts",
                ]
                .contains(&a.key.as_str()))
        {
            return false;
        }
        let (w, h) = size(&a.key, a.size.as_deref());
        if !keys.contains(&a.key) || a.x > 2 - w || a.y > 96 || a.y + h > 104 {
            return false;
        }
        for b in &items[..i] {
            let (bw, bh) = size(&b.key, b.size.as_deref());
            if a.key == b.key
                || (a.x < b.x + bw && a.x + w > b.x && a.y < b.y + bh && a.y + h > b.y)
            {
                return false;
            }
        }
    }
    true
}
