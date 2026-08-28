// Command appidmod builds a Citron LayeredFS data-only mod that replaces
// Outbound's retail Photon App ID with a test App ID, so the game talks to a
// OpenPak-controlled Photon application instead of the real one. See
// HANDOFF.md's proof-of-concept plan, step 4.
//
// It only ever writes files that actually contain the old ID, unmodified
// bytes elsewhere in each file are left untouched, and old/new must be the
// same length (both are 36-character Photon App ID GUIDs) so no offsets or
// length prefixes inside the game's data files need adjusting.
package main

import (
	"bytes"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
)

func main() {
	romfs := flag.String("romfs", "", "path to a dumped RomFS tree (Citron: Dump RomFS)")
	old := flag.String("old", "", "retail Photon App ID to replace")
	new_ := flag.String("new", "", "test Photon App ID to substitute")
	out := flag.String("out", "", "output mod romfs root, e.g. .../load/<TitleID>/legacy-test-app/romfs")
	flag.Parse()

	if *romfs == "" || *old == "" || *new_ == "" || *out == "" {
		flag.Usage()
		os.Exit(2)
	}
	if len(*old) != len(*new_) {
		log.Fatalf("old and new App IDs must be the same length (%d vs %d)", len(*old), len(*new_))
	}
	oldBytes, newBytes := []byte(*old), []byte(*new_)

	err := filepath.WalkDir(*romfs, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s: %w", path, err)
		}
		count := bytes.Count(data, oldBytes)
		if count == 0 {
			return nil
		}
		data = bytes.ReplaceAll(data, oldBytes, newBytes)

		rel, err := filepath.Rel(*romfs, path)
		if err != nil {
			return err
		}
		dest := filepath.Join(*out, rel)
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(dest, data, 0o644); err != nil {
			return err
		}
		fmt.Printf("%s: replaced %d occurrence(s) -> %s\n", rel, count, dest)
		return nil
	})
	if err != nil {
		log.Fatal(err)
	}
}
