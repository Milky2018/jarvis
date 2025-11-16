///|
/// URL encoding utilities

///|
/// Simple URL encoding function
fn url_encode(s : String) -> String {
  let builder = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    match c {
      ' ' => builder.write_string("+")
      'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => {
        // Safe characters - write directly using string slice
        let start = i
        let end = i + 1
        let slice = s[start:end].to_string() catch { _ => "" }
        builder.write_string(slice)
      }
      _ => {
        // Percent encode: convert char to UTF-8 bytes and encode each byte as %XX
        let code = c.reinterpret_as_uint().reinterpret_as_int()
        // For simplicity, handle BMP characters (U+0000 to U+FFFF)
        if code < 0x80 {
          // 1-byte UTF-8 (0xxxxxxx)
          builder.write_string("%")
          write_hex_byte(builder, code.to_byte())
        } else if code < 0x800 {
          // 2-byte UTF-8 (110xxxxx 10xxxxxx)
          let byte1 = (0xC0 | (code >> 6)).to_byte()
          let byte2 = (0x80 | (code & 0x3F)).to_byte()
          builder.write_string("%")
          write_hex_byte(builder, byte1)
          builder.write_string("%")
          write_hex_byte(builder, byte2)
        } else if code < 0x10000 {
          // 3-byte UTF-8 (1110xxxx 10xxxxxx 10xxxxxx)
          let byte1 = (0xE0 | (code >> 12)).to_byte()
          let byte2 = (0x80 | ((code >> 6) & 0x3F)).to_byte()
          let byte3 = (0x80 | (code & 0x3F)).to_byte()
          builder.write_string("%")
          write_hex_byte(builder, byte1)
          builder.write_string("%")
          write_hex_byte(builder, byte2)
          builder.write_string("%")
          write_hex_byte(builder, byte3)
        } else {
          // 4-byte UTF-8 (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
          let byte1 = (0xF0 | (code >> 18)).to_byte()
          let byte2 = (0x80 | ((code >> 12) & 0x3F)).to_byte()
          let byte3 = (0x80 | ((code >> 6) & 0x3F)).to_byte()
          let byte4 = (0x80 | (code & 0x3F)).to_byte()
          builder.write_string("%")
          write_hex_byte(builder, byte1)
          builder.write_string("%")
          write_hex_byte(builder, byte2)
          builder.write_string("%")
          write_hex_byte(builder, byte3)
          builder.write_string("%")
          write_hex_byte(builder, byte4)
        }
      }
    }
  }
  builder.to_string()
}

///|
/// Write a byte as two hex digits to a StringBuilder
fn write_hex_byte(builder : StringBuilder, byte : Byte) -> Unit {
  let b = byte.to_int()
  let high = (b >> 4) & 0xF
  let low = b & 0xF
  builder.write_string(hex_digit(high))
  builder.write_string(hex_digit(low))
}

///|
/// Convert a number (0-15) to hex digit string
fn hex_digit(n : Int) -> String {
  if n < 10 {
    Int::unsafe_to_char('0'.to_int() + n).to_string()
  } else {
    Int::unsafe_to_char('A'.to_int() + (n - 10)).to_string()
  }
}

///|
/// Tests for url_encode function
test "url_encode: spaces" {
  inspect(url_encode("hello world"), content="hello+world")
}

///|
test "url_encode: alphanumeric and safe chars" {
  inspect(url_encode("ABC123-_.~"), content="ABC123-_.~")
}

///|
test "url_encode: special characters" {
  // @ (0x40) should be percent-encoded as %40
  inspect(url_encode("hello@world"), content="hello%40world")
}

///|
test "url_encode: empty string" {
  inspect(url_encode(""), content="")
}

///|
test "url_encode: multiple spaces" {
  inspect(url_encode("a b c"), content="a+b+c")
}

///|
test "url_encode: mixed safe and unsafe" {
  inspect(url_encode("foo bar-baz_qux.test~ok"), content="foo+bar-baz_qux.test~ok")
}

///|
test "url_encode: Chinese characters" {
  // "你" = U+4F60 = UTF-8: E4 BD A0
  // "好" = U+597D = UTF-8: E5 A5 BD
  // "世" = U+4E16 = UTF-8: E4 B8 96
  // "界" = U+754C = UTF-8: E7 95 8C
  inspect(
    url_encode("你好世界"), content="%E4%BD%A0%E5%A5%BD%E4%B8%96%E7%95%8C",
  )
}

///|
test "url_encode: symbols and punctuation" {
  inspect(
    url_encode("hello!@#$%^&*()"), content="hello%21%40%23%24%25%5E%26%2A%28%29",
  )
}
