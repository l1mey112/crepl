import readline
import os
import term
import strings

/* [if trace?]
fn trace(str string){
	eprintln(":: $str")
} */

fn (mut c CREPL) accum_source() string {
	// better to allocate all in one go...
	mut len := end.len
	for b in c.source_buckets {
		len += b.source.len
	}
	mut a := strings.new_builder(len)
	for b in c.source_buckets {
		if b.source.len == 0 {
			continue
		}
		a << b.source
	}
	a.write_string(end)
	return a.str()
}

struct HistoryRecord {
	history_idx int
	source_bucket int = -1
}

struct SourceBucket {
mut:
	source strings.Builder
}

const source_bucket_count = 5

struct CREPL {
	cc string
	cc_exe string
mut:
	readline readline.Readline
	prompt string = prompt_default 

	source_buckets []SourceBucket = []SourceBucket{len: source_bucket_count}
	history []HistoryRecord
	last_edit_idx int = -1
	current_idx int

	ctx &SourceBucket = unsafe { nil } // wooo scary!!!
	ctxidx int = -1

	brace_level int
	multiline_source strings.Builder
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
		if r.history.len == 0 {
			init_all_buckets(mut r)
		} else {
			history := r.history[r.current_idx]
			unsafe {
				r.source_buckets[history.source_bucket].source.len = history.history_idx
			}
		}
		return false
	}
	output := os.execute("./$tmp_exe").output
	if output.len != 0 {
		println(output)
	}
	return true
}
fn new_crepl() CREPL {
	cc_exe, cc := get_cc_dir()
	mut history := []HistoryRecord{cap: 20}
	//history << HistoryRecord{begin.len, 4}
	return CREPL {
		cc_exe: cc_exe
		cc: cc
		history: history
		multiline_source: strings.new_builder(40)
	}
}

const include_header = 
"#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>
"
const begin =
"
int main(){
"
const end =
"	return 0;
}"

fn (mut r CREPL) init_bucket (a int, data string) {
	r.source_buckets[a].source.write_string(data)
}
fn init_all_buckets(mut r CREPL) {
	for mut i in r.source_buckets {
		i = SourceBucket {}
		i.source = strings.new_builder(120)
	}
	r.init_bucket(0,include_header)
	r.init_bucket(4,begin)
}
// 0. #includes
// 1. Structs and typedefs
// 2. Function declarations (hoisted)
// 3. Function bodies
// 4. Main Function
// p.s: this is such an upgrade from igcc

fn reset_crepl(mut r CREPL) {
	unsafe {
		r.multiline_source.len = 0
		r.history.len = 1
	}
	init_all_buckets(mut r)
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

fn (mut r CREPL) undo()? {
	if r.current_idx <= 0 {
		return error('')
	} else {
		r.current_idx--
		history := r.history[r.current_idx]
		unsafe { r.source_buckets[history.source_bucket].source.len = history.history_idx }
	}
}

const welcome =
/* cool placeholder text */
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

fn info(str string) string {
	return term.magenta(str)
}

fn main(){
	mut r := new_crepl()
	init_all_buckets(mut r)
	if !is_pipe {
		println(welcome)
		println(r.cc_exe)
		println('')
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
					panic("cc version exited with nonzero exit code")
				}
				print(info(exec.output))
			}
			'dump' {
				println("r.history = $r.history")
				println("r.last_edit_idx = $r.last_edit_idx")
				println("r.current_idx = $r.current_idx")
				println("r.ctxidx = $r.ctxidx")
			}
			'run' {
				r.call_cc()
			}
			'reset' {
				reset_crepl(mut r)
			}
			'undo' {
				r.undo() or {
					println(info("Nothing to undo"))
				}
			}
			'redo' {
				if r.current_idx < r.last_edit_idx {
					r.current_idx++
					history := r.history[r.current_idx]
					unsafe { r.source_buckets[history.source_bucket].source.len = history.history_idx }
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

				mut old_len := 0
				if line.starts_with('#') {
					r.ctx = &r.source_buckets[0]
					r.ctxidx = 0
					old_len = r.ctx.source.len
				} else {
					r.ctx = &r.source_buckets[4]
					r.ctxidx = 4
					old_len = r.ctx.source.len
					r.ctx.source.write_u8(`\t`)
				}

				if do_flush {
					r.ctx.source.writeln(r.multiline_source.str())
					// sets length to 0, does not free; keeps cap
				} else {
					r.ctx.source.writeln(line)
				}


				if r.call_cc() {
					r.current_idx++
					r.last_edit_idx = r.current_idx
					if r.history.len <= r.current_idx {
						r.history << HistoryRecord {
							history_idx: old_len
							source_bucket: r.ctxidx
						}
					} else {
						r.history[r.current_idx] = HistoryRecord {
							history_idx: old_len
							source_bucket: r.ctxidx
						}
					}
					
					if r.history.len <= r.current_idx+1 {
						r.history << HistoryRecord {
							history_idx: r.ctx.source.len
							source_bucket: r.ctxidx
						}
					} else {
						r.history[r.current_idx+1] = HistoryRecord {
							history_idx: r.ctx.source.len
							source_bucket: r.ctxidx
						}
					}
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
				// let the compilier deal with them
				return false
			}
			r.brace_level--
		}
	}
	return o_br != r.brace_level && r.brace_level == 0
	// short circut action!
}