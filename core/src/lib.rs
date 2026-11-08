use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// Swift owns network requests; Rust normalizes provider responses.
fn normalize(input: &str) -> Result<String, serde_json::Error> {
    let root: Value = serde_json::from_str(input)?;
    let data = root.get("data").unwrap_or(&root);
    let rows = data.as_array().cloned().unwrap_or_else(|| vec![data.clone()]);
    let titles: Vec<Value> = rows.iter().filter_map(|r| {
        let id = r["alias"].as_str().map(str::to_owned)
            .or_else(|| r["id"].as_i64().map(|v| v.to_string()))?;
        let poster = r.pointer("/poster/optimized/preview").or_else(|| r.pointer("/poster/preview")).and_then(Value::as_str).unwrap_or("");
        let poster = if poster.starts_with("//") { format!("https:{poster}") }
            else if poster.starts_with('/') { format!("https://anilibria.top{poster}") } else { poster.to_owned() };
        Some(json!({"id": id, "title": r.pointer("/name/main").and_then(Value::as_str).unwrap_or(&id),
            "description": r["description"].as_str().unwrap_or(""), "poster": poster}))
    }).collect();
    Ok(serde_json::to_string(&titles)?)
}

/// Input must be a valid, null-terminated UTF-8 string, alive for this call.
#[no_mangle]
pub unsafe extern "C" fn anicrn_normalize(input: *const c_char) -> *mut c_char {
    if input.is_null() { return std::ptr::null_mut(); }
    let result = CStr::from_ptr(input).to_str().ok().and_then(|s| normalize(s).ok());
    result.and_then(|s| CString::new(s).ok()).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// Free each returned pointer exactly once, with no subsequent access.
#[no_mangle]
pub unsafe extern "C" fn anicrn_free(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn normalizes_wrapped_release() {
        let v: Value = serde_json::from_str(&normalize(r#"{"data":[{"id":1,"name":{"main":"Тест"},"poster":{"preview":"/a.jpg"}}]}"#).unwrap()).unwrap();
        assert_eq!(v[0]["id"], "1");
        assert_eq!(v[0]["poster"], "https://anilibria.top/a.jpg");
        assert_eq!(v[0]["title"], "Тест");
    }
    #[test]
    fn malformed_response_is_error() { assert!(normalize("oops").is_err()); }
}
