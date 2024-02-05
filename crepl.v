import readline
import os
import term
import strings

/* [if trace?]
fn trace(str string){
	eprintln(":: $str")
} */

fn (mut c CREPL) accum_source(bu int, s string) string {
	// better to allocate all in one go...
	mut len := end_file.len + s.len
	for b in c.source_buckets {
		len += b.source.len
	}
	mut a := strings.new_builder(len)
	for idx, b in c.source_buckets {
		a << b.source
		if idx == bu {
			a.writeln(s)
		}
	}
	a.write_string(end_file)
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

	brace_bucket int = -1
	brace_level int
	multiline_source strings.Builder

	last_successful bool
	last_output string = ' '

	pref_pin bool
}

const cc_list = {
	"tcc"     : {"version":"-v"}
	"gcc"     : {"version":"--version"}
	"clang"   : {"version":"--version"}
	"msvc"    : {"version":"--version"}
	"___generic" : {"version":"--version"} // cant take any chances
}

fn get_cc_dir(force_cc string) (string, string) {
	if force_cc != '' {
		if force_cc in cc_list {
			if path := os.find_abs_path_of_executable(force_cc) {
				return path, force_cc
			}
		}
		if os.exists(force_cc) && os.is_executable(force_cc) {
			return force_cc, '___generic'
		}
		path := os.find_abs_path_of_executable(force_cc) or {
			eprintln('Failed to find specified C compiler: $force_cc')
			exit(1)
		}
		return path, '___generic'
	}
	
	for cc in cc_list.keys() {
		path := os.find_abs_path_of_executable(cc) or {
			continue
		}
		return path, cc
	}
	eprintln("Cannot find a C compiler!")
	eprintln("Checked for 'tcc', 'gcc' and 'clang', try specifying '--cc'?")
	exit(1)
}

fn (mut r CREPL) call_cc(b int, s string) bool {
	os.write_file(tmp_file, r.accum_source(b, s)) or { panic(err) }

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
	r.last_output = output
	// successful, write now
	if s.len != 0 {
		r.source_buckets[b].source.writeln(s)
	}
	return true
}
fn new_crepl(opts CREPLopts) CREPL {
	cc_exe, cc := get_cc_dir(opts.force_cc)
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
"int main(){
"
const end_file =
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
	r.init_bucket(1,'\n')
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
	r.last_successful = false
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

fn (mut r CREPL) undo()! {
	if r.current_idx <= 0 {
		return error('')
	} else {
		r.current_idx--
		history := r.history[r.current_idx]
		unsafe { r.source_buckets[history.source_bucket].source.len = history.history_idx }
	}
}

const crepl_text =
/* cool placeholder text */
"${term.bright_blue(term.bold('        '))}                                mm\n"+
"${term.bright_blue(term.bold('        '))}                              *@@@\n"+
"${term.bright_blue(term.bold('        '))}                                @@\n"+
"${term.bright_blue(term.bold(' m@@*@@ '))}*@@@m@@@   mm@*@@ *@@@@@@@@m    @@\n"+
"${term.bright_blue(term.bold('@@*  @@ '))}  @@* **  m@*   @@  @@   *@@    !@\n"+
"${term.bright_blue(term.bold('@!      '))}  @!      !@******  !@    @@    !@\n"+
"${term.bright_blue(term.bold('@!m    m'))}  @!      !@m    m  !@    !@    !@\n"+
"${term.bright_blue(term.bold('!!      '))}  !!      !!******  !@!   !!    !!\n"+
"${term.bright_blue(term.bold('!:!    !'))}  !:      :!!       !@   !!!    :!\n"+
"${term.bright_blue(term.bold(' : : :  '))}  :::      : : ::   :!: : :   : : \n"+
"${term.bright_blue(term.bold('        '))}                    ::            \n"+
"${term.bright_blue(term.bold('        '))}                  : : ::          "

const tmp_file = ".crepl_tmp.c"
const tmp_exe = ".crepl_tmp_exe"

fn info(str string) string {
	return term.magenta(str)
}

fn (mut r CREPL) list() {
	println(format_c(r.accum_source(-1,'')))
}

fn (mut r CREPL) pin() {
	term.erase_clear()
	r.list()
	println('')
}

// i have to make some compromises,
// this is not a language server!
const c_types = [
	'void'
	'int'
	'double'
	'float'
	'char'
	'long'
	'short'
	'int8_t'
	'int16_t'
	'int32_t'
	'int64_t'
	'uint8_t'
	'uint16_t'
	'uint32_t'
	'uint64_t'
]
// assume line is already stripped of whitespace from start to end
fn (mut r CREPL) parse_inital_line(s string) int {
	if s.contains("=") {
		return 4
	} // apparently?
	
	if s.starts_with('#') {
		return 0
	} else if
		s.starts_with('struct') || 
		s.starts_with('typedef') 
	{
		return 1
	}
	// function 'parsing'
	for ct in c_types {
		if s.starts_with(ct) {
			if !s.contains("(") {
				break
			}
			return 3
		}
	} // use binary search (highlight.v) yada yada yada
	return 4
}

const help_commands = {
	'exit   ' : ["Exit the program. Ctrl C and Ctrl D both do this"]
	'clear  ' : ["Clear the screen"]
	'list   ' : ["List the current program being fed to a CC"]
	'cc     ' : ["Display the path to the current CC"]
	'version' : ["Invoke the CC with the version argument"]
	'run    ' : ["Compile and run the program manually"]
	'reset  ' : ["Reset CREPL"]
	'pin    ' : ["Especially helpful when prototyping."
				 "Pin the current program and output to the top of"
			     "the screen, clear screen on a successful operation"]
	'undo   ' : ["Undo the last operation"]
	'redo   ' : ["Redo the last undone operation"]
	'help   ' : ["Display this message"]
}

const help_crepl = "
crepl compiles and executes your code on the fly as you type it.
With TCC, this can be incredibly fast. Use crepl for fast prototyping 
and all the times you need a sizeof().

crepl keeps an internal uncapped undo and redo buffer, the undo and redo
commands use this to step back and forth in a linear fashion.

Typing `{` and `}` denotes a new indentation and so the prompt will
change. Type your statements as usual and they will be formatted
properly. You must specify a brace character if you want to perform
multiline input.

On a compiler error, the input is not committed and thus does not need
to be undone.
"

const version_str = 'v0.1.0 - l-m.dev'

fn help(){
	println(version_str)
	println(help_crepl)
	for c, hc in help_commands {
		println("${c}   ${hc[0]}")
		for i := 1; i < hc.len; i++ {
			println("          ${hc[i]}")
		}
	}
	println('\nHope you like crepl!\n')
}

fn crepl(opts CREPLopts){
	mut r := new_crepl(opts)
	init_all_buckets(mut r)

	if !is_pipe {
		println(crepl_text)
		println('')
		println("Welcome! - lm${r.cc_exe:29}")
		println("Type 'help' for help.")
		if r.cc != 'tcc' && opts.force_cc == '' {
			println("\nIt appears you are not using TCC, please install it!")
			println("TCC is magnitudes faster at compiling C code")
		}
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
			'help' { help() continue}
			'exit' { break }
			'list' { r.list() continue }
			'cc' {
				println(info(r.cc_exe))
				continue
			}
			'version' {
				v_arg := cc_list[r.cc]["version"]
				exec := os.execute("$r.cc_exe $v_arg")
				if exec.exit_code != 0 {
					panic("cc version exited with nonzero exit code")
				}
				print(info(exec.output))
				continue
			}
			/* 'debug' {
				println("r.history = $r.history")
				println("r.last_edit_idx = $r.last_edit_idx")
				println("r.current_idx = $r.current_idx")
				continue
			} */
			'run' {
				r.call_cc(-1,'')
			}
			'reset' {
				reset_crepl(mut r)
				if r.pref_pin {
					r.pin()
				}
			}
			'pin' {
				r.pref_pin = !r.pref_pin
				if r.pref_pin {
					r.pin()
				} else {
					continue
				}
			}
			'undo' {
				r.undo() or {
					println(info("Nothing to undo"))
					continue
				}
			}
			'redo' {
				if r.current_idx < r.last_edit_idx {
					r.current_idx++
					history := r.history[r.current_idx]
					unsafe { r.source_buckets[history.source_bucket].source.len = history.history_idx }
				} else {
					println(info("Nothing to redo"))
					continue
				}
			}
			'clear' {
				term.erase_clear()
				continue
			}
			else {
				do_flush, just_entered := r.count_braces(line)

				if just_entered {
					r.brace_bucket = r.parse_inital_line(line)
				} 
				mut bucket := -1
				if r.brace_level == 0 && !do_flush {
					bucket = r.parse_inital_line(line)
				} else {
					bucket = r.brace_bucket
				}

				mut push := line
				if bucket == 4 {
					push = '\t' + push
				}

				if r.brace_level != 0 {
					r.prompt = prompt_indent
					if !just_entered {
						r.multiline_source.write_string('\t'.repeat(r.brace_level))
					} else {
						r.brace_bucket = bucket
					}
					r.multiline_source.writeln(push)
					continue
				}

				if do_flush {
					r.multiline_source.writeln(push)
					push = r.multiline_source.str()
				}

				r.push_history(bucket)
				r.last_successful = r.call_cc(bucket, push)

				if r.last_successful {
					r.current_idx++
					r.last_edit_idx = r.current_idx
					r.push_history(bucket) // this may be redundant?
				}
				
				if r.prompt != prompt_default {
					r.prompt = prompt_default
				}
			}
		}
		if r.last_successful {
			if r.pref_pin {
				r.pin()
			}
			if r.last_output.len != 0 {
				println(r.last_output)
				if r.pref_pin && r.last_output[r.last_output.len-1] != `\n` {
					println('')
				}
			}
		}
	}
	if !is_pipe {
		println('')
	}
	os.rm(tmp_file) or {}
	os.rm(tmp_exe) or {}
}

fn (mut r CREPL) push_history(b int) {
	if r.history.len <= r.current_idx {
		r.history << HistoryRecord {
			history_idx: r.source_buckets[b].source.len
			source_bucket: b
		}
	} else {
		r.history[r.current_idx] = HistoryRecord {
			history_idx: r.source_buckets[b].source.len
			source_bucket: b
		}
	} // if only there was a way to make this automatic
}

[direct_array_access]
fn (mut r CREPL) count_braces(s string) (bool,bool) {
	o_br := r.brace_level
	for letter in s {
		if letter == `{` {
			r.brace_level++
		} else if letter == `}` {
			if r.brace_level == 0 {
				// subject is uncooperative
				// terminate now
				// let the compilier deal with them
				return false, false
			}
			r.brace_level--
		}
	}
	return 
		o_br != r.brace_level && r.brace_level == 0,
		o_br == 0 && r.brace_level != 0
	// short circut action
}
