# matlab-use

`Use` loads a reviewed MATLAB `.m` file or ZIP archive from a local path or
HTTPS URL. It checks the file's SHA-256 digest before adding the code to the
MATLAB path. Functions are exposed as handles on the returned object, and
deleting the object removes the temporary files and path entries.

## Example

This example uses a fixed revision of [`rand_index`](https://github.com/cmccomb/rand_index).
The digest is for the exact `.m` file at that revision.

```matlab
url = ['https://raw.githubusercontent.com/cmccomb/rand_index/' ...
       'b4ba97ff9a6a9bb0fb8ea773d1f36f8fd55f3850/rand_index.m'];
sha256 = '0f87777b730e1f61fe4f4189ebeddd4b81fe92bf60b6c7d4076d1180aacba74f';
dependency = Use(url, sha256);
score = dependency.rand_index([1 1 2 2], [4 4 7 7]);
delete(dependency);
```

You can also pass a local `.m` or `.zip` file. `Use.sha256(filename)` computes
its digest. For remote code, obtain and record the expected digest from a
trusted, independently reviewed copy before calling `Use`. A checksum pins
bytes; it does not establish that the code is trustworthy.

## Current behavior

- Requires a 64-character SHA-256 digest and rejects a mismatched download.
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

`Use` is a convenience loader for a small, reviewed dependency. It does not
resolve transitive dependencies, provide an isolated execution environment, or
verify signatures. MATLAB code loaded through it runs with your MATLAB session's
normal permissions. It is currently tested with MATLAB R2025b.

## Development

Run `test_use` in MATLAB. The tests use local fixtures and do not need network
access. GitHub Actions runs them on pull requests and changes to `main`.

## License

MIT. See [LICENSE](LICENSE).
