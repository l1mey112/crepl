import flag
import os

[param]
struct CREPLopts {
	force_cc string
}

fn main(){
	mut fp := flag.new_flag_parser(os.args)

	fp.application("crepl")
	fp.version(version_str)
	fp.description('Compile and execute C code on the fly as you type it. Prefers tcc as the CC')
	fp.skip_executable()

	pref_cc := fp.string('cc', 0, '', 'specify custom CC')
	pref_ver := fp.bool('version', `v`, false, fp.default_version_label)

	if pref_ver {
		println('$fp.application_name $fp.application_version')
		exit(0)
	}

	fp.finalize() or {
		eprintln(err.msg())
		exit(1)
	}

	crepl(force_cc: pref_cc)
}