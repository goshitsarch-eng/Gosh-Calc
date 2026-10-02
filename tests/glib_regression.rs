#![cfg(all(feature = "desktop", target_os = "linux"))]
use glib::variant::ToVariant;

#[test]
fn variant_string_iterator_handles_c_out_argument_correctly() {
    let values = vec!["alpha", "βeta", "中文"];
    let variant = values.to_variant();
    assert_eq!(
        variant.array_iter_str().unwrap().collect::<Vec<_>>(),
        values
    );
    assert_eq!(
        variant.array_iter_str().unwrap().rev().collect::<Vec<_>>(),
        vec!["中文", "βeta", "alpha"]
    );
    assert_eq!(variant.array_iter_str().unwrap().nth(1), Some("βeta"));
    assert_eq!(variant.array_iter_str().unwrap().nth_back(1), Some("βeta"));
    assert_eq!(variant.array_iter_str().unwrap().last(), Some("中文"));
}
