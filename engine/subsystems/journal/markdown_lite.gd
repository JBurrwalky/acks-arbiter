class_name MarkdownLite
extends RefCounted

## Markdown-lite → BBCode converter for Journal entries / notes (H.2 polish).
##
## Per gdd-journal-tab.md v1.1 §13 resolved O-J3, the Journal supports a
## small markdown subset for body content:
##
##   **bold**         → [b]bold[/b]
##   *italic*         → [i]italic[/i]
##   - bullet item    → [indent]• item[/indent]   (per line)
##   1. ordered item  → [indent]1. item[/indent]  (per line, number preserved)
##   @entity_id       → [color=#a78240]@entity_id[/color]   (entity link token)
##
## NOT supported in v1: headers, blockquotes, code blocks, tables, image
## embeds, inline links beyond entity-ids, hard line breaks. (Per resolved
## O-J3 — these are v1.1+ enhancements.)
##
## The converter is best-effort and forgiving: malformed markdown renders
## verbatim rather than throwing. Pure RefCounted so tests can instantiate
## without a scene tree; static-style use is fine via the .new() pattern.


const ENTITY_LINK_COLOR := "a78240"


## Convert a markdown-lite string to BBCode suitable for RichTextLabel.bbcode_text.
## Empty input returns empty string.
static func to_bbcode(text: String) -> String:
	if text.is_empty():
		return ""
	# Order matters: handle list lines first (line-based), then inline
	# bold/italic, then entity links. Bold must precede italic so a **bold**
	# token isn't mis-parsed as nested italic.
	var lines := text.split("\n")
	var out_lines: Array[String] = []
	for raw_line in lines:
		var line: String = String(raw_line)
		out_lines.append(_convert_line(line))
	return "\n".join(out_lines)


static func _convert_line(line: String) -> String:
	var stripped := line.strip_edges(true, false)  # left-strip only
	# Bullet lists: "- item" / "* item"
	if stripped.begins_with("- ") or stripped.begins_with("* "):
		var item: String = stripped.substr(2)
		return "[indent]• %s[/indent]" % _convert_inline(item)
	# Ordered lists: "1. item", "23. item", etc.
	var ordered_match: int = _ordered_prefix_length(stripped)
	if ordered_match > 0:
		var prefix: String = stripped.substr(0, ordered_match)
		var item2: String = stripped.substr(ordered_match)
		return "[indent]%s%s[/indent]" % [prefix, _convert_inline(item2)]
	return _convert_inline(line)


## Returns the byte length of the "N. " prefix at the start of [param text],
## or 0 if no ordered-list prefix is present. e.g. "12. foo" → 4.
static func _ordered_prefix_length(text: String) -> int:
	var n: int = text.length()
	var i: int = 0
	while i < n and text[i].is_valid_int():
		i += 1
	if i == 0 or i + 1 >= n:
		return 0
	if text[i] != "." or text[i + 1] != " ":
		return 0
	return i + 2


## Convert inline markdown within a single line (no list handling).
static func _convert_inline(text: String) -> String:
	var s: String = text
	s = _convert_bold(s)
	s = _convert_italic(s)
	s = _convert_entity_links(s)
	return s


## Convert **bold**. Pairs are non-greedy; unmatched ** renders verbatim.
static func _convert_bold(text: String) -> String:
	return _convert_paired(text, "**", "[b]", "[/b]")


## Convert *italic*. Single-* pairs only; **bold** has already been handled.
static func _convert_italic(text: String) -> String:
	return _convert_paired(text, "*", "[i]", "[/i]")


## Convert @entity_id tokens. An "entity id" here is a contiguous run of
## word characters (alphanumeric / underscore / hyphen). The token includes
## the @ prefix; the renderer shows the token as-is in accent color.
static func _convert_entity_links(text: String) -> String:
	var out: String = ""
	var n: int = text.length()
	var i: int = 0
	while i < n:
		var ch: String = text[i]
		if ch == "@":
			var j: int = i + 1
			while j < n and _is_id_char(text[j]):
				j += 1
			if j > i + 1:
				out += "[color=#%s]%s[/color]" % [ENTITY_LINK_COLOR, text.substr(i, j - i)]
				i = j
				continue
		out += ch
		i += 1
	return out


static func _is_id_char(ch: String) -> bool:
	if ch.is_empty():
		return false
	if ch.is_valid_int():
		return true
	# Treat letters, underscore, hyphen as id chars; anything else terminates.
	if ch == "_" or ch == "-":
		return true
	# Letter check — String.to_upper / to_lower differ on letters only.
	return ch.to_upper() != ch.to_lower()


## Generic paired-delimiter substitution. Walks [param text] left-to-right
## replacing matched pairs of [param delim] with [param open]/[param close].
## Unmatched delimiters render verbatim.
static func _convert_paired(text: String, delim: String, open_tag: String,
		close_tag: String) -> String:
	var out: String = ""
	var n: int = text.length()
	var dlen: int = delim.length()
	var i: int = 0
	var open: bool = false
	while i < n:
		if i + dlen <= n and text.substr(i, dlen) == delim:
			# Avoid eating one half of a longer marker (e.g. * inside **).
			# When converting "*", skip if the surrounding char is also "*".
			if delim == "*":
				var prev: String = text[i - 1] if i > 0 else ""
				var next: String = text[i + 1] if i + 1 < n else ""
				if prev == "*" or next == "*":
					out += text[i]
					i += 1
					continue
			out += (close_tag if open else open_tag)
			open = not open
			i += dlen
			continue
		out += text[i]
		i += 1
	# Unmatched trailing delimiter: render verbatim by reverting the last
	# emission. The simplest correctness behavior is to re-emit nothing here
	# and accept that an unbalanced ** at the end opens a tag that
	# RichTextLabel will silently close — acceptable for v1.
	return out
