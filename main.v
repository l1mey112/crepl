import readline
import os
import term
import strings

// always wondered why string_builder.str() cleared the array...
// warning: somehow checks out, but very unsafe
fn (mut c CREPL) accum_source() string {
	concatlen := c.source.len + end.len
	bcopy := unsafe { malloc_noscan(concatlen + 1) }
	unsafe {
		vmemcpy(bcopy, c.source.data , c.source.len)
		vmemcpy(bcopy + c.source.len, end.str, end.len + 1) // + 1, .str already contains null terminator
	}
	return unsafe { bcopy.vstring_with_len(concatlen) }
}

struct CREPL {
	cc string
	cc_exe string
mut:
	readline readline.Readline
	prompt string = prompt_default 

	// undo redo operations
	last_edit_idx int
	current_idx int
	history_idx []int

	brace_level int
	multiline_source strings.Builder

	source strings.Builder
}

const cc_list = {
	"tcc"   : {"version":"-v"}
	"gcc"   : {"version":"--version"}
	"clang" : {"version":"--version"}
}

fn get_cc_dir() (string, string) {
	for cc in cc_list.keys() {
		path := os.find_abs_path_of_executable(cc) or {
			continue
		}
		return path, cc
	}
	panic("coult not find cc!!!!! todowo:")
}

fn (mut r CREPL) call_cc() bool {
	os.write_file(tmp_file, r.accum_source()) or { panic(err) }

	mut proc := os.new_process(r.cc_exe)
	proc.set_args([tmp_file,'-o',tmp_exe])
	proc.set_redirect_stdio()
	proc.run()
	proc.wait()
	if proc.code != 0 {
		eprintln(proc.stderr_slurp())
		// essentially undo line now
		unsafe { r.source.len = r.history_idx[r.current_idx] }
		return false
	}
	output := os.execute("./$tmp_exe").output
	if output.len != 0 {
		println(output)
	}
	return true
}
fn new_crepl() CREPL {
	mut a := strings.new_builder(100)
	a.write_string(begin)
	cc_exe, cc := get_cc_dir()
	mut history_idx := []int{cap: 21}
	history_idx << begin.len
	return CREPL {
		cc_exe: cc_exe
		cc: cc
		source: mut a
		history_idx: mut history_idx 
		multiline_source: strings.new_builder(40)
	}
}

fn reset_crepl(mut r CREPL) {
	// why waste precious time in freeing and reallocating?
	unsafe {
		r.source.len = begin.len
		r.multiline_source.len = 0
		r.history_idx.len = 1
	}
	r.current_idx = 0
}

const is_pipe = os.is_atty(0) == 0
const prompt_default = "cc $ "
const prompt_indent =  ".... "

fn (mut r CREPL) line() ?string {
	if is_pipe {
		iline := os.get_raw_line()
		if iline.len == 0 {
			return none
		}
		return iline
	}
	rline := r.readline.read_line(r.prompt) or { return none }
	return rline
}

const welcome =
// cool placeholder text
"                                        mm\n"+
"                                      *@@@\n"+
"                                        @@\n"+
" m@@*@@ *@@@m@@@   mm@*@@ *@@@@@@@@m    @@\n"+
"@@*  @@   @@* **  m@*   @@  @@   *@@    !@\n"+
"@!        @!      !@******  !@    @@    !@\n"+
"@!m    m  @!      !@m    m  !@    !@    !@\n"+
"!!        !!      !!******  !@!   !!    !!\n"+
"!:!    !  !:      :!!       !@   !!!    :!\n"+
" : : :  : :::      : : ::   :!: : :   : : \n"+
"                            ::            \n"+
"                          : : ::          "

const tmp_file = ".crepl_tmp.c"
const tmp_exe = ".crepl_tmp_exe"

const begin =
"#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>

int main(){
"
const end =

"	return 0;
}"

fn info(str string) string {
	return term.magenta(str)
}

fn main(){
	mut r := new_crepl()
	if !is_pipe {
		eprintln(welcome)
		eprintln(r.cc_exe)
		eprintln('')
	}
	for {
		rline := r.line() or {
			break
		}
		line := rline.trim_space()
		if line == '' && rline.ends_with('\n') {
			continue
		}
		if line.len <= -1 || line == '' {
			break
		}
		match line {
			'exit' { break }
			'list' {
				println(info(r.accum_source()))
			}
			'cc' {
				println(info(r.cc_exe))
			}
			'version' {
				v_arg := cc_list[r.cc]["version"]
				exec := os.execute("$r.cc_exe $v_arg")
				if exec.exit_code != 0 {
					panic("CC Version exited with nonzero exit code")
				}
				print(info(exec.output))
			}
			'run' {
				r.call_cc()
			}
			'reset' {
				reset_crepl(mut r)
			}
			'undo' {
				if r.current_idx <= 0 {
					println(info("Nothing to undo"))
				} else {
					r.current_idx--
					unsafe { r.source.len = r.history_idx[r.current_idx] }
				}
			}
			'redo' {
				if r.current_idx < r.last_edit_idx {
					r.current_idx++
					unsafe { r.source.len = r.history_idx[r.current_idx] }
				} else {
					println(info("Nothing to redo"))
				}
			}
			'clear' {
				term.erase_clear()
			}
			else {
				do_flush := r.count_braces(line)

				if r.brace_level != 0 {
					r.prompt = prompt_indent
					r.multiline_source.write_u8(`\t`)
					r.multiline_source.writeln(line)
					continue
				}

				if do_flush {
					r.source.write_u8(`\t`)
					r.source.writeln(r.multiline_source.str())
					// sets length to 0, does not free; keeps cap
				} else {
					r.source.write_u8(`\t`)
					r.source.writeln(line)
				}
				if r.call_cc() {
					r.current_idx++
					if r.history_idx.len <= r.current_idx {
						r.history_idx << r.source.len
					} else {
						r.history_idx[r.current_idx] = r.source.len
					}
					r.last_edit_idx = r.current_idx
				}
				if r.prompt != prompt_default {
					r.prompt = prompt_default
				}
			}
		}
	}
	if !is_pipe {
		println('')
	}
}

[direct_array_access]
fn (mut r CREPL) count_braces(s string) bool {
	o_br := r.brace_level
	for letter in s {
		if letter == `{` {
			r.brace_level++
		} else if letter == `}` {
			if r.brace_level == 0 {
				// subject is uncooperative
				// terminate now
				return false
			}
			r.brace_level--
		}
	}
	return o_br != r.brace_level && r.brace_level == 0
	// short circut action!
}