use std::env;
use std::path::PathBuf;

fn main() {
	// Windows cross-compilation with MinGW: GNU ld doesn't auto-export
	// #[no_mangle] symbols from cdylib. Pass a .def file to export the
	// VST3 factory entry point and the Windows DLL init/exit functions.
	if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
		let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
		let def_path = out_dir.join("exports.def");

		std::fs::write(
			&def_path,
			"EXPORTS\n  GetPluginFactory\n  InitDll\n  ExitDll\n",
		)
		.unwrap();

		// GNU ld accepts .def files as regular inputs for PE targets
		println!("cargo:rustc-link-arg=-Wl,{}", def_path.display());
		println!("cargo:rerun-if-changed=build.rs");
	}
}
