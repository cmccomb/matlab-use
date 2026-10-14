classdef Use < dynamicprops
    %USE Load a checksum-verified MATLAB file or ZIP for this object lifetime.
    %   U = USE(SOURCE, SHA256) accepts a local .m/.zip file or an HTTPS URL.
    %   SHA256 is the expected 64-character hexadecimal digest of the file.
    %   Public functions in the package are exposed as handles on U. Delete
    %   U to remove its folders from the MATLAB path and its temporary files.

    properties (Access = private)
        directory = ''
        path_variable = ''
    end

    methods
        function obj = Use(source, expected_sha256)
            if nargin ~= 2
                error('Use:Arguments', 'Provide a source and its expected SHA-256 digest.');
            end
            source = Use.text_scalar(source, 'source');
            expected_sha256 = lower(Use.text_scalar(expected_sha256, 'SHA-256 digest'));
            if isempty(regexp(expected_sha256, '^[0-9a-f]{64}$', 'once'))
                error('Use:Digest', 'The SHA-256 digest must have 64 hexadecimal characters.');
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
                if ~strcmp(actual_sha256, expected_sha256)
                    error('Use:ChecksumMismatch', ...
                        'SHA-256 mismatch: expected %s, received %s.', ...
                        expected_sha256, actual_sha256);
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
