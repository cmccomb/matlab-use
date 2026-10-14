function test_use
%TEST_USE Offline checks for verified single-file and ZIP imports.
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
    imported = Use(source_file, digest);
    assert(imported.use_fixture_add(4) == 5);
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

    try
        Use('http://example.com/test.m', digest);
        error('Expected HTTP to be rejected.');
    catch err
        assert(strcmp(err.identifier, 'Use:Source'));
    end
    disp('USE TESTS PASSED');
end
