import v.token
import term
import strings

const c_keywords = {
	'signed'   : term.bold
	'unsigned' : term.bold
	'const'    : term.bold
	'auto'     : term.bold
	'register' : term.bold
	'static'   : term.bold
	'volatile' : term.bold

	'enum'     : term.bold
	'struct'   : term.bold
	'typedef'  : term.bold
	'extern'   : term.bold
	'sizeof'   : term.bold
	'break'    : term.bold
	'case'     : term.bold
	'continue' : term.bold
	'default'  : term.bold
	'do'       : term.bold
	'else'     : term.bold
	'for'      : term.bold
	'if'       : term.bold
	'return'   : term.bold
	'switch'   : term.bold
	'union'    : term.bold
	'while'    : term.bold

	'double'   : term.bold
	'float'    : term.bold
	'char'     : term.bold
	'int'      : term.bold
	'long'     : term.bold
	'short'    : term.bold
	'void'     : term.bold
	'int8_t'   : term.bold
	'int16_t'  : term.bold
	'int32_t'  : term.bold
	'int64_t'  : term.bold
	'uint8_t'  : term.bold
	'uint16_t' : term.bold
	'uint32_t' : term.bold
	'uint64_t' : term.bold
} // wanna change it? change it!

[inline]
fn is_valid_name(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c == `_`
}

[direct_array_access]
fn skip_whitespace(rpos int, s string) int {
	mut pos := rpos
	for pos < s.len {
		c := s[pos]
		if c == 9 {
			pos++
			continue
		} // 9 = tab
		if !(c == 32 || (c > 8 && c < 14) || (c == 0x85) || (c == 0xa0)) {
			return pos
		} // 32 = space
		pos++
	}
	return pos
}

[direct_array_access]
fn march(rpos int, s string) (string, int) {
	mut pos := rpos
	start := pos
	pos++
	for pos < s.len {
		c := s[pos]
		if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_` {
			pos++
			continue
		}
		break
	}
	name := s[start..pos]
	pos--
	return name, pos
}

[direct_array_access]
fn march_string(rpos int, s string) (string, int){
	mut pos := rpos
	quote := s[pos]	
	start := pos

	for {
		pos++
		c := s[pos]
		if c == quote {
			break
		}
	} // no checks needed, compiler knows anyway

	mut lit := ''
	mut end := pos+1
	if start <= pos {
		lit = s[start..end]
	}
	return lit, pos
}

type Sc = fn (string) string

// personally, i think this is pretty optimised
// see improvements? tell me!
[direct_array_access]
fn format_c(s string) string {
	mut b := strings.new_builder(s.len+60) // ehh
	mut f := token.new_keywords_matcher_trie<Sc>(c_keywords)
		// does binary search on keywords

	// base scanner implementation taken from my `stas` lang
	mut pos := -1 // gets incremented anyway
	mut clean_pos := 0
	for {
		pos++
		pos = skip_whitespace(pos, s)
		if pos >= s.len { break }
		
		c := s[pos]
		
		if is_valid_name(c) {
			mut name := ''
			oldp := pos
			name, pos = march(pos, s)
			kind := f.find(name)
			if kind != -1 {
				b.write_string(s[clean_pos..oldp])     // flush
				b.write_string(c_keywords[name](name)) // write edited
				clean_pos = pos + 1
			}
		}

		// i assume malloc is called for string slices...
		// try builder.write_ptr(ptr &u8, len int) next
		
		match c {
			`#` {
				oldp := pos
				for pos < s.len && s[pos] !in [`\n`,`\r`] {
					pos++
				}
				pos++ // with newline char
				coloured_include := term.yellow(term.bold(s[oldp..pos]))

				b.write_string(s[clean_pos..oldp]) // flush
				b.write_string(coloured_include)   // write edited
				clean_pos = pos
				pos--
			}
			`'`, `"` {
				mut str := ''
				oldp := pos
				str, pos = march_string(pos, s)
				b.write_string(s[clean_pos..oldp]) // flush
				coloured_string := term.green(str)
				b.write_string(coloured_string)    // write edited
				clean_pos = pos + 1
			}
			`{`, `}`, `(`, `)` {
				coloured_char := term.magenta(c.ascii_str())
				b.write_string(s[clean_pos..pos]) // flush
				b.write_string(coloured_char)     // write edited
				
				clean_pos = pos + 1
			}
			`;` {
				coloured_char := term.dim(c.ascii_str())
				b.write_string(s[clean_pos..pos]) // flush
				b.write_string(coloured_char)     // write edited
				
				clean_pos = pos + 1
			}
			// only reused code is the {... and the ;
			// ill refactor later...
			else {}
		}
	}
	b.write_string(s[clean_pos..pos])

	return b.str()
}