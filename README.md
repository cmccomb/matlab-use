# matlab-use

`Use` loads a MATLAB `.m` file or ZIP archive from a local path or HTTPS URL.
Functions are exposed as handles on the returned object, and deleting the
object removes the temporary files and path entries. Supply a SHA-256 digest
when you need to pin the exact bytes.

## Example

For a quick exploration, pass a local file or HTTPS URL:

```matlab
dependency = Use('my_function.m');
dependency.my_function(42);
disp(dependency.Digest);
delete(dependency);
```

This reproducible example uses a fixed revision of
[`rand_index`](https://github.com/cmccomb/rand_index). The digest is for the
exact `.m` file at that revision.

```matlab
url = ['https://raw.githubusercontent.com/cmccomb/rand_index/' ...
       'b4ba97ff9a6a9bb0fb8ea773d1f36f8fd55f3850/rand_index.m'];
sha256 = '0f87777b730e1f61fe4f4189ebeddd4b81fe92bf60b6c7d4076d1180aacba74f';
dependency = Use(url, sha256);
score = dependency.rand_index([1 1 2 2], [4 4 7 7]);
delete(dependency);
```

`Use.sha256(filename)` computes a local file's digest. Every `Use` object
exposes the loaded file's `Digest` and a `Verified` flag. An HTTPS call without
an expected digest emits a warning and reports the computed digest, so you
can pin it later. For shared or repeatable work, obtain the expected digest
from a trusted, independently reviewed copy before calling `Use`. A checksum
pins bytes; it does not establish that the code is trustworthy.

## Project manifest and cache

Store pinned dependencies in a JSON manifest. The
[example manifest](examples/use.json) records a fixed `rand_index` source and
digest:

```matlab
dependency = Use.fromManifest('examples/use.json', 'rand_index');
score = dependency.rand_index([1 1 2 2], [4 4 7 7]);
delete(dependency);
```

The manifest format has `schemaVersion: 1` and a `dependencies` array. Each
entry has a unique `name`, a `source` ending in `.m` or `.zip`, and a required
`sha256` digest. Local sources are resolved relative to the manifest file.
`Use.fromManifest(manifest, name, cacheDirectory)` selects a custom cache;
otherwise the cache is stored under MATLAB's `prefdir`.

The cache uses a directory named by digest and preserves the source filename,
which MATLAB needs for `.m` functions. Every cache hit is checked against the
manifest digest before use. A missing or corrupt entry is fetched
from its source and verified before it is cached. A valid cached copy can be
used even when its original source is temporarily unavailable. Delete the
cached files to reclaim disk space; the next load will fetch them again.

## Current behavior

- Computes SHA-256 for every source. An optional expected digest must contain
  64 hexadecimal characters; a mismatch stops the load.
- Accepts HTTPS URLs and local `.m` or `.zip` files. HTTP URLs are rejected.
- Adds extracted folders to the MATLAB path for the object's lifetime. Delete
  the object when finished; `clear dependency` also calls its destructor when
  no other reference remains.
- Exposes public function files as handles. Scripts, class folders, package
  folders, and `private` folders are not exposed as properties. Duplicate or
  shadowed function names produce an error.
- Checks ZIP entry paths and limits an archive to 10,000 entries and 250 MB of
  declared uncompressed data before extraction.
- Uses a new temporary directory for each instance and cleans up after errors.

`Use` is a convenience loader for a small dependency. It does not
resolve transitive dependencies, provide an isolated execution environment, or
verify signatures. MATLAB code loaded through it runs with your MATLAB session's
normal permissions. It is currently tested with MATLAB R2025b.

## Development

Run `test_use` in MATLAB. The tests use local fixtures and do not need network
access. GitHub Actions runs them on pull requests and changes to `main`.

## License

MIT. See [LICENSE](LICENSE).
