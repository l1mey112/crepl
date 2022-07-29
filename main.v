import readline
import os
//import term
import strings

// always wondered why string_builder.str() cleared the array...
fn (mut c CREPL) accum_source() string {
	c.source << u8(0)
	bcopy := unsafe { &u8(memdup_noscan(c.source.data, c.source.len)) }
	s := unsafe { bcopy.vstring_with_len(c.source.len - 1) }
	unsafe { c.source.len-- }
	return s
}
// will allocate a new string
// since its only being used for a short lifetime...
// TODO: remove extra allocations

struct CREPL {
	cc_exe string
mut:
	readline readline.Readline
	prompt string = prompt_default

	source strings.Builder
}

const cc_list = [
	"tcc"
	"gcc"
	"clang"
]

fn get_cc_dir() string {
	for cc in cc_list {
		return os.find_abs_path_of_executable(cc) or {
			continue
		}
	}
	panic("coult not find cc!!!!!")
}
fn (mut c CREPL) call_cc() bool {
	os.write_file(tmp_file, c.accum_source()) or { panic(err) }

	mut proc := os.new_process(c.cc_exe)
	proc.set_args([tmp_file,'-o',tmp_exe])
	proc.run()
	proc.wait()
	if proc.code != 0 {
		eprintln(proc.stderr_slurp())
		return false
	}
	println(os.execute("./$tmp_exe").output)
	return true
}
fn new_crepl() CREPL {
	return CREPL{
		cc_exe: get_cc_dir() 
		source: strings.new_builder(100)
	}
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
"                                        mm  \n"+
"                                      *@@@  \n"+
"                                        @@  \n"+
" m@@*@@ *@@@m@@@   mm@*@@ *@@@@@@@@m    @@  \n"+
"@@*  @@   @@* **  m@*   @@  @@   *@@    !@  \n"+
"@!        @!      !@******  !@    @@    !@  \n"+
"@!m    m  @!      !@m    m  !@    !@    !@  \n"+
"!!        !!      !!******  !@!   !!    !!  \n"+
"!:!    !  !:      :!!       !@   !!!    :!  \n"+
" : : :  : :::      : : ::   :!: : :   : : : \n"+
"                            ::              \n"+
"                          : : ::            "

const tmp_file = ".crepl_tmp.c"
const tmp_exe = ".crepl_tmp_exe"

fn main(){
	mut r := new_crepl()
	if !is_pipe {
		eprintln(welcome)
		eprintln(r.cc_exe)
		eprintln('')
	}
	defer {
		if !is_pipe {
			println('')
		}
	}
	for {
		rline := r.line() or {
			break
		}
		line := rline.trim_space()
		if line == '' && rline.ends_with('\n') {
			continue
		}
		if line.len <= -1 || line == '' || line == 'exit' {
			break
		}
		r.source.writeln(line)
		r.call_cc()
	}
}