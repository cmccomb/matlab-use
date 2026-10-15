function test_use
%TEST_USE Offline checks for exploratory and verified imports.
    fixture_dir = tempname;
    mkdir(fixture_dir);
    remove_fixture = onCleanup(@() rmdir(fixture_dir, 's')); %#ok<NASGU>
    source_file = fullfile(fixture_dir, 'use_fixture_add.m');
    fid = fopen(source_file, 'w');
    fprintf(fid, 'function result = use_fixture_add(value)\nresult = value + 1;\nend\n');
    fclose(fid);

    initial_path = path;
    known_file = fullfile(fixture_dir, 'known.txt');
    fid = fopen(known_file, 'w');
    fwrite(fid, 'abc');
    fclose(fid);
    assert(strcmp(Use.sha256(known_file), ...
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'));

    digest = Use.sha256(source_file);
    assert(numel(digest) == 64);
    imported = Use(source_file);
    assert(imported.use_fixture_add(2) == 3);
    assert(strcmp(imported.Digest, digest));
    assert(~imported.Verified);
    delete(imported);
    assert(strcmp(path, initial_path));

    imported = Use(source_file, digest);
    assert(imported.use_fixture_add(4) == 5);
    assert(imported.Verified);
    delete(imported);
    assert(strcmp(path, initial_path));

    try
        Use(source_file, repmat('0', 1, 64));
        error('Expected a checksum mismatch.');
    catch err
        assert(strcmp(err.identifier, 'Use:ChecksumMismatch'));
    end
    assert(strcmp(path, initial_path));

    archive = fullfile(fixture_dir, 'fixture.zip');
    zip(archive, {'use_fixture_add.m'}, fixture_dir);
    imported = Use(archive, Use.sha256(archive));
    assert(imported.use_fixture_add(9) == 10);
    delete(imported);
    assert(strcmp(path, initial_path));

    unsafe_archive = fullfile(fixture_dir, 'unsafe.zip');
    output = java.util.zip.ZipOutputStream(java.io.FileOutputStream(unsafe_archive));
    output.putNextEntry(java.util.zip.ZipEntry('../outside.m'));
    output.write(uint8('unsafe'));
    output.closeEntry();
    output.close();
    try
        Use(unsafe_archive, Use.sha256(unsafe_archive));
        error('Expected an unsafe ZIP path to be rejected.');
    catch err
        assert(strcmp(err.identifier, 'Use:ArchivePath'));
    end
    assert(strcmp(path, initial_path));

    manifest_file = fullfile(fixture_dir, 'use.json');
    fid = fopen(manifest_file, 'w');
    fprintf(fid, ['{"schemaVersion":1,"dependencies":[' ...
        '{"name":"fixture","source":"use_fixture_add.m","sha256":"%s"}]}'], digest);
    fclose(fid);
    cache_directory = fullfile(fixture_dir, 'cache');
    imported = Use.fromManifest(manifest_file, 'fixture', cache_directory);
    assert(imported.use_fixture_add(11) == 12);
    assert(imported.Verified);
    delete(imported);
    cached_file = fullfile(cache_directory, digest, 'use_fixture_add.m');
    assert(exist(cached_file, 'file') == 2);
    assert(strcmp(Use.sha256(cached_file), digest));

    fid = fopen(cached_file, 'w');
    fwrite(fid, 'corrupt cache entry');
    fclose(fid);
    imported = Use.fromManifest(manifest_file, 'fixture', cache_directory);
    assert(imported.use_fixture_add(12) == 13);
    delete(imported);
    assert(strcmp(Use.sha256(cached_file), digest));

    delete(source_file);
    imported = Use.fromManifest(manifest_file, 'fixture', cache_directory);
    assert(imported.use_fixture_add(13) == 14);
    delete(imported);
    assert(strcmp(path, initial_path));
    try
        Use.fromManifest(manifest_file, 'unknown', cache_directory);
        error('Expected a missing dependency error.');
    catch err
        assert(strcmp(err.identifier, 'Use:UnknownDependency'));
    end

    try
        Use('http://example.com/test.m', digest);
        error('Expected HTTP to be rejected.');
    catch err
        assert(strcmp(err.identifier, 'Use:Source'));
    end
    disp('USE TESTS PASSED');
end
