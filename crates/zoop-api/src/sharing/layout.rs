//! Fixed widget footprints keep owner layouts bounded and collision-free.
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Placement {
    pub key: String,
    pub x: u16,
    pub y: u16,
}
fn size(key: &str) -> (u16, u16) {
    match key {
        "daily_rings" | "activity_heatmap" => (2, 3),
        "by_sport" => (1, 3),
        "recent_workouts" => (1, 8),
        _ => (1, 4),
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
        let (w, h) = size(&a.key);
        if !keys.contains(&a.key) || a.x > 2 - w || a.y > 96 || a.y + h > 104 {
            return false;
        }
        for b in &items[..i] {
            let (bw, bh) = size(&b.key);
            if a.key == b.key
                || (a.x < b.x + bw && a.x + w > b.x && a.y < b.y + bh && a.y + h > b.y)
            {
                return false;
            }
        }
    }
    true
}
