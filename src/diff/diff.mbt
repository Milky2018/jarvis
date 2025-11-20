///|
/// Diff utilities for file comparison
/// Provides line-based diff algorithms for displaying file changes

///|
/// Color constants (duplicated for package independence)
const COLOR_RED : String = "\u001b[31m"

///|
const COLOR_GREEN : String = "\u001b[32m"

///|
const COLOR_RESET : String = "\u001b[0m"

///|
/// Simple line-based diff algorithm
/// Returns: (common_prefix_lines, removed_lines, added_lines, common_suffix_lines)
pub fn compute_line_diff(
  old_text : String,
  new_text : String,
) -> (Array[String], Array[String], Array[String], Array[String]) {
  let old_lines_view = old_text.split("\n")
  let old_lines : Array[String] = []
  for line in old_lines_view {
    old_lines.push(line.to_string())
  }
  let new_lines_view = new_text.split("\n")
  let new_lines : Array[String] = []
  for line in new_lines_view {
    new_lines.push(line.to_string())
  }

  // Find common prefix
  let mut prefix_len = 0
  while prefix_len < old_lines.length() &&
        prefix_len < new_lines.length() &&
        old_lines[prefix_len] == new_lines[prefix_len] {
    prefix_len = prefix_len + 1
  }

  // Find common suffix (excluding prefix)
  let mut suffix_len = 0
  while suffix_len < old_lines.length() - prefix_len &&
        suffix_len < new_lines.length() - prefix_len &&
        old_lines[old_lines.length() - 1 - suffix_len] ==
        new_lines[new_lines.length() - 1 - suffix_len] {
    suffix_len = suffix_len + 1
  }

  // Extract parts
  let prefix : Array[String] = []
  for i = 0; i < prefix_len; i = i + 1 {
    prefix.push(old_lines[i])
  }
  let removed : Array[String] = []
  for i = prefix_len; i < old_lines.length() - suffix_len; i = i + 1 {
    removed.push(old_lines[i])
  }
  let added : Array[String] = []
  for i = prefix_len; i < new_lines.length() - suffix_len; i = i + 1 {
    added.push(new_lines[i])
  }
  let suffix : Array[String] = []
  for i = old_lines.length() - suffix_len; i < old_lines.length(); i = i + 1 {
    suffix.push(old_lines[i])
  }
  (prefix, removed, added, suffix)
}

///|
/// Format diff output with colors and context
/// Shows 3 lines of context before/after changes
pub fn format_diff(
  prefix : Array[String],
  removed : Array[String],
  added : Array[String],
  suffix : Array[String],
) -> String {
  let builder = StringBuilder::new()
  let mut line_num = 1

  // Calculate max line number for width alignment
  let total_lines = prefix.length() + added.length() + suffix.length()
  let max_width = if total_lines < 10 {
    1
  } else if total_lines < 100 {
    2
  } else if total_lines < 1000 {
    3
  } else {
    4
  }

  // Show context before changes (limited to 3 lines)
  let context_before = if prefix.length() > 3 { 3 } else { prefix.length() }
  let skip_prefix = prefix.length() - context_before
  if skip_prefix > 0 {
    builder.write_string("... (")
    builder.write_string(skip_prefix.to_string())
    builder.write_string(" unchanged lines)\n")
    line_num = line_num + skip_prefix
  }
  for i = prefix.length() - context_before; i < prefix.length(); i = i + 1 {
    write_line_number(builder, line_num, max_width)
    builder.write_string(prefix[i])
    builder.write_string("\n")
    line_num = line_num + 1
  }

  // Show removed lines (red)
  if removed.length() > 0 {
    for line in removed {
      builder.write_string(COLOR_RED)
      builder.write_string("- ")
      builder.write_string(line)
      builder.write_string(COLOR_RESET)
      builder.write_string("\n")
    }
  }

  // Show added lines (green)
  if added.length() > 0 {
    for line in added {
      builder.write_string(COLOR_GREEN)
      builder.write_string("+ ")
      builder.write_string(line)
      builder.write_string(COLOR_RESET)
      builder.write_string("\n")
    }
  }
  line_num = line_num + added.length()

  // Show context after changes (limited to 3 lines)
  let context_after = if suffix.length() > 3 { 3 } else { suffix.length() }
  for i = 0; i < context_after; i = i + 1 {
    write_line_number(builder, line_num, max_width)
    builder.write_string(suffix[i])
    builder.write_string("\n")
    line_num = line_num + 1
  }
  let skip_suffix = suffix.length() - context_after
  if skip_suffix > 0 {
    builder.write_string("... (")
    builder.write_string(skip_suffix.to_string())
    builder.write_string(" unchanged lines)\n")
  }
  builder.to_string()
}

///|
/// Write line number with padding to ensure equal width
fn write_line_number(
  builder : StringBuilder,
  line_num : Int,
  width : Int,
) -> Unit {
  let num_str = line_num.to_string()
  let padding = width - num_str.length()

  // Add leading spaces for alignment
  for i = 0; i < padding; i = i + 1 {
    builder.write_string(" ")
  }
  builder.write_string(num_str)
  builder.write_string(": ")
}

///|
test "compute_line_diff: simple change" {
  let old_text = "line1\nline2\nline3"
  let new_text = "line1\nmodified\nline3"
  let (prefix, removed, added, suffix) = compute_line_diff(old_text, new_text)
  inspect(prefix.length(), content="1")
  inspect(prefix[0], content="line1")
  inspect(removed.length(), content="1")
  inspect(removed[0], content="line2")
  inspect(added.length(), content="1")
  inspect(added[0], content="modified")
  inspect(suffix.length(), content="1")
  inspect(suffix[0], content="line3")
}

///|
test "compute_line_diff: add lines" {
  let old_text = "line1\nline3"
  let new_text = "line1\nline2\nline3"
  let (prefix, removed, added, suffix) = compute_line_diff(old_text, new_text)
  inspect(prefix.length(), content="1")
  inspect(prefix[0], content="line1")
  inspect(removed.length(), content="0")
  inspect(added.length(), content="1")
  inspect(added[0], content="line2")
  inspect(suffix.length(), content="1")
  inspect(suffix[0], content="line3")
}

///|
test "compute_line_diff: remove lines" {
  let old_text = "line1\nline2\nline3"
  let new_text = "line1\nline3"
  let (prefix, removed, added, suffix) = compute_line_diff(old_text, new_text)
  inspect(prefix.length(), content="1")
  inspect(prefix[0], content="line1")
  inspect(removed.length(), content="1")
  inspect(removed[0], content="line2")
  inspect(added.length(), content="0")
  inspect(suffix.length(), content="1")
  inspect(suffix[0], content="line3")
}

///|
test "compute_line_diff: identical texts" {
  let old_text = "line1\nline2\nline3"
  let new_text = "line1\nline2\nline3"
  let (prefix, removed, added, suffix) = compute_line_diff(old_text, new_text)
  inspect(prefix.length(), content="3")
  inspect(removed.length(), content="0")
  inspect(added.length(), content="0")
  inspect(suffix.length(), content="0")
}

///|
test "compute_line_diff: empty to content" {
  let old_text = ""
  let new_text = "line1\nline2"
  let (prefix, removed, added, suffix) = compute_line_diff(old_text, new_text)
  inspect(prefix.length(), content="0")
  inspect(removed.length(), content="1") // Empty string splits into [""]
  inspect(added.length(), content="2")
  inspect(suffix.length(), content="0")
}

///|
test "format_diff: basic output" {
  let prefix : Array[String] = ["line1"]
  let removed : Array[String] = ["old_line"]
  let added : Array[String] = ["new_line"]
  let suffix : Array[String] = ["line3"]
  let result = format_diff(prefix, removed, added, suffix)
  inspect(result.contains("1: line1"), content="true")
  inspect(result.contains("- old_line"), content="true")
  inspect(result.contains("+ new_line"), content="true")
  inspect(result.contains("3: line3"), content="true")
}
