# Extract the supported-version table and reject conflicting EOL entries.
# Output: major<TAB>release<TAB>eol-month<TAB>release-date
function trim(value) {
  gsub(/\r/, "", value)
  gsub(/\*\*/, "", value)
  gsub(sprintf("%c", 96), "", value)
  sub(/^[[:space:]]+/, "", value)
  sub(/[[:space:]]+$/, "", value)
  return value
}
function columns(line, out,    count, field_index, raw) {
  line = trim(line)
  sub(/^\|/, "", line)
  sub(/\|$/, "", line)
  count = split(line, raw, "|")
  for (field_index = 1; field_index <= count; field_index++) {
    out[field_index] = trim(raw[field_index])
  }
  return count
}
function failure(message) {
  print "Nextcloud wiki parser: " message > "/dev/stderr"
  invalid = 1
  exit 1
}
BEGIN { section = ""; state = 0; supported = 0; eol_rows = 0 }
{
  heading = trim($0)
  if (heading ~ /^#+[[:space:]]+/) {
    sub(/^#+[[:space:]]+/, "", heading)
    heading = tolower(heading)
    if (heading ~ /^currently (supported|maintained) versions?$/) {
      if (supported_section++) failure("duplicate supported section")
      section = "supported"
      state = 0
    } else if (heading == "eol versions") {
      section = "eol"
      state = 0
      eol_section++
    } else {
      section = ""
    }
    next
  }
  if (section == "" || $0 !~ /^[[:space:]]*\|/) next

  count = columns($0, parts)
  if (state == 0) {
    if (section == "supported") {
      delete field_index
      for (i = 1; i <= count; i++) field_index[tolower(parts[i])] = i
      if (!("version code" in field_index) || !("release date" in field_index) ||
          !("end of life" in field_index) || !("current version" in field_index)) {
        failure("supported table header changed")
      }
    }
    header_columns = count
    state = 1
    next
  }
  if (state == 1) {
    if (count != header_columns) failure("separator column count changed")
    for (i = 1; i <= count; i++) {
      if (parts[i] !~ /^:?-{3,}:?$/) failure("invalid Markdown table separator")
    }
    state = 2
    next
  }
  if (count != header_columns) failure("table row column count changed")
  if (section == "supported") {
    major = parts[field_index["version code"]]
    current = parts[field_index["current version"]]
    split(current, release_fields, /[[:space:]]+/)
    release = release_fields[1]
    if (major !~ /^[0-9]+$/ || release !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {
      failure("invalid current release or major " major)
    }
    if (int(major) != int(release) || int(major) < 20 || int(major) > 99) {
      failure("major does not match current release " release)
    }
    if (seen[major]++) failure("duplicate supported major " major)
    supported++
    versions[supported] = major "\t" release "\t" parts[field_index["end of life"]] "\t" parts[field_index["release date"]]
    supported_majors[major] = 1
  } else if (section == "eol" && parts[1] ~ /^[0-9]+$/) {
    eol_majors[parts[1]] = 1
    eol_rows++
  }
}
END {
  if (invalid) exit 1
  if (supported_section != 1 || supported < 1 || supported > 5 ||
      eol_section != 1 || eol_rows < 1) {
    failure("supported/EOL sections or their version tables are missing")
  }
  for (major in supported_majors) {
    if (major in eol_majors) failure("version " major " is both supported and EOL")
  }
  for (i = 1; i <= supported; i++) print versions[i]
}
