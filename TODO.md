<div align="center">
  <a href="README.md"><img src="assets/brand/icon-512.png" alt="Asabunko" height="44"></a>
</div>

# Roadmap

Each task here is a choice of the owner. A task leaves this list when its
release is out. The reason for each choice is in
[docs/decisions.md](docs/decisions.md).

## Next

- 0.5.0: LNReader plugins for novels on the web, in JavaScriptCore.
- 0.6.0: Aidoku sources, in a WebAssembly runtime.
- 0.7.0: Paperback 0.9 extensions, in JavaScriptCore.
- 0.8.0: Suwayomi servers, for the extensions of Mihon.
- 1.0.0: all of these, with a backup of the library.

## Checks on a real iPhone

- The import of a CBR and of a RAR5 from the Files app. The tests make ZIP,
  7z, and TAR archives, but no tool on the Mac writes a RAR.
- The import of a large archive, with 500 pages or more.
