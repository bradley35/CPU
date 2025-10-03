#!/usr/bin/env -S rust-script
//! ```cargo
//! [dependencies]
//! ```
// Single file, no Cargo.toml needed. Cargo.toml is kept for VSCode Intellisense
use std::env;
use std::fs;
use std::io::BufReader;
use std::io::Read;
use std::io::Write;
use std::path::Path;

fn main() -> Result<(), std::io::Error> {
    let args: Vec<String> = env::args().collect();
    let bin = args.get(1).expect("Bin must be provided");
    if bin.len() < 1 {
        panic!("Bin must be provided");
    }
    let number_of_blocks = args
        .get(2)
        .and_then(|x| x.parse::<usize>().ok())
        .unwrap_or(16);
    println!("Splitting {} into {:0} blocks", bin, number_of_blocks);
    let path = Path::new(bin).parent().unwrap_or(Path::new("."));
    let existing_files = fs::read_dir(path)?;
    existing_files
        .filter_map(|res| res.ok())
        .map(|dir_entry| dir_entry.path())
        .filter_map(|path| {
            if path.extension().map_or(false, |ext| ext == "chunk") {
                Some(path)
            } else {
                None
            }
        })
        .for_each(|f| {
            fs::remove_file(f).expect("Error removing file");
        });

    let mut write_files: Vec<fs::File> = (0..number_of_blocks)
        .map(|n| {
            let file_path: String = path.to_str().unwrap().to_string() + &format!("/c{}.chunk", n);
            fs::File::create_new(file_path).expect("Error opening file")
        })
        .collect();
    let bin_file = fs::File::open(bin).expect("File could not be opened");
    let mut reader = BufReader::new(bin_file);
    let mut dw_buffer = [0u8; 8];
    let mut current_file: usize = 0;
    while let _n @ 1..=8 = reader.read(&mut dw_buffer).expect("Unknown error") {
        //println!("Got {} bytes: {:?}", n, &dw_buffer[..n]);
        writeln!(
            write_files[current_file],
            "{:016x}",
            u64::from_le_bytes(dw_buffer)
        )
        .expect("Write Error");
        dw_buffer.fill(0);
        current_file = current_file + 1;
        if current_file == number_of_blocks {
            current_file = 0;
        }
    }

    drop(write_files);
    println!("File splitting complete");
    return Ok(());
}
