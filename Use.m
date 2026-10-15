classdef Use < dynamicprops
    %USE Load a MATLAB file or ZIP for this object lifetime.
    %   U = USE(SOURCE) accepts a local .m/.zip file or an HTTPS URL.
    %   U = USE(SOURCE, SHA256) checks the expected 64-character digest.
    %   Public functions in the package are exposed as handles on U. Delete
    %   U to remove its folders from the MATLAB path and its temporary files.

    properties (Access = private)
        directory = ''
        path_variable = ''
    end

    properties (SetAccess = private)
        Digest = '' % SHA-256 digest of the loaded file
        Verified = false % True when an expected digest was supplied and matched
    end

    methods
        function obj = Use(source, expected_sha256)
            if nargin < 1 || nargin > 2
                error('Use:Arguments', 'Provide a source and optional expected SHA-256 digest.');
            end
            source = Use.text_scalar(source, 'source');
            if nargin == 2
                expected_sha256 = lower(Use.text_scalar(expected_sha256, 'SHA-256 digest'));
                if isempty(regexp(expected_sha256, '^[0-9a-f]{64}$', 'once'))
                    error('Use:Digest', 'The SHA-256 digest must have 64 hexadecimal characters.');
                end
            end

            remote = startsWith(source, 'https://');
            if ~remote && contains(source, '://')
                error('Use:Source', 'Remote sources must use HTTPS.');
            end
            if remote
                source_path = regexp(source, '^[^?#]+', 'match', 'once');
            else
                source_path = source;
                if exist(source_path, 'file') ~= 2
                    error('Use:Source', 'The local source file does not exist.');
                end
            end
            [~, name, extension] = fileparts(source_path);
            extension = lower(extension);
            if ~any(strcmp(extension, {'.m', '.zip'})) || isempty(name)
                error('Use:Source', 'The source must be a .m file or .zip archive.');
            end

            obj.directory = tempname;
            mkdir(obj.directory);
            try
                downloaded_file = fullfile(obj.directory, ['artifact' extension]);
                if remote
                    websave(downloaded_file, source);
                else
                    copyfile(source, downloaded_file);
                end
                file_info = dir(downloaded_file);
                if file_info.bytes > 250e6
                    error('Use:ArtifactSize', 'The source file exceeds the 250 MB limit.');
                end
                actual_sha256 = Use.sha256(downloaded_file);
                obj.Digest = actual_sha256;
                if nargin == 2
                    if ~strcmp(actual_sha256, expected_sha256)
                        error('Use:ChecksumMismatch', ...
                            'SHA-256 mismatch: expected %s, received %s.', ...
                            expected_sha256, actual_sha256);
                    end
                    obj.Verified = true;
                elseif remote
                    warning('Use:UnverifiedSource', ...
                        'Loading unverified remote code. SHA-256: %s', actual_sha256);
                end

                source_directory = fullfile(obj.directory, 'source');
                mkdir(source_directory);
                if strcmp(extension, '.zip')
                    Use.check_zip_entries(downloaded_file);
                    unzip(downloaded_file, source_directory);
                else
                    copyfile(downloaded_file, fullfile(source_directory, [name extension]));
                end

                obj.path_variable = genpath(source_directory);
                addpath(obj.path_variable, '-begin');
                obj.expose_functions(source_directory);
            catch err
                delete(obj);
                rethrow(err);
            end
        end

        function delete(obj)
            if ~isempty(obj.path_variable)
                rmpath(obj.path_variable);
                obj.path_variable = '';
            end
            if ~isempty(obj.directory) && exist(obj.directory, 'dir') == 7
                rmdir(obj.directory, 's');
                obj.directory = '';
            end
        end
    end

    methods (Static)
        function obj = fromManifest(manifest_filename, dependency_name, cache_directory)
            %FROMMANIFEST Load a named, SHA-256-pinned dependency from JSON.
            %   U = USE.FROMMANIFEST(FILE, NAME) reuses a verified artifact
            %   from the user cache when available. A third argument selects
            %   another cache directory, which is useful for testing.
            if nargin < 2 || nargin > 3
                error('Use:ManifestArguments', ...
                    'Provide a manifest filename, dependency name, and optional cache directory.');
            end
            manifest_filename = Use.text_scalar(manifest_filename, 'manifest filename');
            dependency_name = Use.text_scalar(dependency_name, 'dependency name');
            if exist(manifest_filename, 'file') ~= 2
                error('Use:ManifestFile', 'The manifest file does not exist.');
            end
            if nargin < 3
                cache_directory = fullfile(prefdir, 'matlab-use', 'cache');
            else
                cache_directory = Use.text_scalar(cache_directory, 'cache directory');
            end

            manifest = jsondecode(fileread(manifest_filename));
            if ~isstruct(manifest) || ~isscalar(manifest) || ...
                    ~isfield(manifest, 'schemaVersion') || ...
                    ~isequal(manifest.schemaVersion, 1) || ...
                    ~isfield(manifest, 'dependencies') || ...
                    ~isstruct(manifest.dependencies)
                error('Use:ManifestFormat', ...
                    'Expected schemaVersion 1 and an array of dependency objects.');
            end
            dependencies = manifest.dependencies;
            names = cell(1, numel(dependencies));
            for k = 1:numel(dependencies)
                entry = dependencies(k);
                if ~isfield(entry, 'name') || ~isfield(entry, 'source') || ...
                        ~isfield(entry, 'sha256')
                    error('Use:ManifestFormat', ...
                        'Each dependency needs name, source, and sha256 fields.');
                end
                names{k} = Use.text_scalar(entry.name, 'dependency name');
            end
            if numel(unique(names)) ~= numel(names)
                error('Use:ManifestFormat', 'Dependency names must be unique.');
            end
            selected = find(strcmp(names, dependency_name), 1);
            if isempty(selected)
                error('Use:UnknownDependency', ...
                    'Dependency %s was not found in the manifest.', dependency_name);
            end

            entry = dependencies(selected);
            source = Use.text_scalar(entry.source, 'dependency source');
            digest = lower(Use.text_scalar(entry.sha256, 'SHA-256 digest'));
            if isempty(regexp(digest, '^[0-9a-f]{64}$', 'once'))
                error('Use:ManifestFormat', ...
                    'The dependency SHA-256 digest must have 64 hexadecimal characters.');
            end
            remote = startsWith(source, 'https://');
            if ~remote && contains(source, '://')
                error('Use:Source', 'Remote sources must use HTTPS.');
            end
            if remote
                source_path = regexp(source, '^[^?#]+', 'match', 'once');
            else
                if ~java.io.File(source).isAbsolute()
                    [manifest_folder, ~, ~] = fileparts(manifest_filename);
                    if isempty(manifest_folder)
                        manifest_folder = pwd;
                    end
                    source = fullfile(manifest_folder, source);
                end
                source_path = source;
            end
            [~, source_name, extension] = fileparts(source_path);
            extension = lower(extension);
            if ~any(strcmp(extension, {'.m', '.zip'}))
                error('Use:Source', 'The source must be a .m file or .zip archive.');
            end

            cache_entry_directory = fullfile(cache_directory, digest);
            cached_file = fullfile(cache_entry_directory, [source_name extension]);
            if exist(cached_file, 'file') == 2 && ...
                    strcmp(Use.sha256(cached_file), digest)
                obj = Use(cached_file, digest);
                return;
            end

            obj = Use(source, digest);
            temporary_cache_file = '';
            try
                if exist(cache_entry_directory, 'dir') ~= 7
                    mkdir(cache_entry_directory);
                end
                temporary_cache_file = [cached_file '.' char(java.util.UUID.randomUUID()) '.tmp'];
                copyfile(fullfile(obj.directory, ['artifact' extension]), temporary_cache_file);
                movefile(temporary_cache_file, cached_file, 'f');
            catch err
                if ~isempty(temporary_cache_file) && ...
                        exist(temporary_cache_file, 'file') == 2
                    delete(temporary_cache_file);
                end
                warning('Use:CacheWrite', 'Dependency loaded, but cache write failed: %s', err.message);
            end
        end

        function digest = sha256(filename)
            %SHA256 Calculate a file digest for a reviewed local artifact.
            filename = Use.text_scalar(filename, 'filename');
            [fid, message] = fopen(filename, 'rb');
            if fid < 0
                error('Use:File', 'Could not read file: %s', message);
            end
            close_file = onCleanup(@() fclose(fid)); %#ok<NASGU>
            calculator = java.security.MessageDigest.getInstance('SHA-256');
            while true
                bytes = fread(fid, 1024 * 1024, '*uint8');
                if isempty(bytes)
                    break;
                end
                calculator.update(bytes);
            end
            result = typecast(calculator.digest(), 'uint8');
            digest = lower(reshape(dec2hex(result, 2).', 1, []));
        end
    end

    methods (Access = private)
        function expose_functions(obj, source_directory)
            files = dir(fullfile(source_directory, '**', '*.m'));
            exported = {};
            for k = 1:numel(files)
                function_name = files(k).name(1:end-2);
                relative_folder = strrep(files(k).folder, source_directory, '');
                folder_parts = strsplit(relative_folder, filesep);
                special_folder = any(strcmp(folder_parts, 'private')) || ...
                    any(startsWith(folder_parts, '@')) || any(startsWith(folder_parts, '+'));
                if special_folder || ~isvarname(function_name) || ...
                        ismethod(obj, function_name) || isprop(obj, function_name)
                    continue;
                end
                if any(strcmp(exported, function_name))
                    error('Use:DuplicateFunction', ...
                        'The package contains duplicate function names: %s.', function_name);
                end
                source_file = fullfile(files(k).folder, files(k).name);
                if ~strcmp(which(function_name), source_file)
                    error('Use:ShadowedFunction', ...
                        'The function %s is shadowed on the MATLAB path.', function_name);
                end
                try
                    nargin(function_name);
                catch
                    continue; % A script cannot be exposed as a function handle.
                end
                addprop(obj, function_name);
                obj.(function_name) = str2func(function_name);
                exported{end+1} = function_name; %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function value = text_scalar(value, label)
            if isstring(value) && isscalar(value)
                value = char(value);
            end
            if ~ischar(value) || ~isrow(value) || isempty(value)
                error('Use:Text', '%s must be a nonempty text scalar.', label);
            end
        end

        function check_zip_entries(filename)
            archive = java.util.zip.ZipFile(filename);
            close_archive = onCleanup(@() archive.close()); %#ok<NASGU>
            entries = archive.entries();
            total_size = 0;
            count = 0;
            while entries.hasMoreElements()
                entry = entries.nextElement();
                entry_name = strrep(char(entry.getName()), '\', '/');
                parts = strsplit(entry_name, '/');
                if startsWith(entry_name, '/') || ...
                        ~isempty(regexp(entry_name, '^[A-Za-z]:', 'once')) || ...
                        any(strcmp(parts, '..'))
                    error('Use:ArchivePath', 'ZIP archive contains an unsafe path.');
                end
                count = count + 1;
                total_size = total_size + double(entry.getSize());
                if count > 10000 || total_size > 250e6 || entry.getSize() < 0
                    error('Use:ArchiveSize', 'ZIP archive exceeds the supported size limits.');
                end
            end
        end
    end
end
