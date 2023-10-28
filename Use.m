classdef Use < dynamicprops
    properties(Access = private)
        path_variable % stores the set of paths
        directory
    end
    methods
        function obj = Use(url)
            % Name a temporary directory, make it, and save the file
            obj.directory = strcat(tempdir, string(posixtime(datetime)), '/');
            mkdir(obj.directory);

            % get parts of URL and download file
            [~, name, ext] = fileparts(url);
            filepath = strcat(obj.directory, '/', name, ext);
            websave(filepath, url);

            % If file is compressed
            if strcmp(ext, '.zip')
                unzip(filepath, obj.directory);
                delete(filepath);
            end

            % Make a path variable
            obj.path_variable = genpath(obj.directory);
            addpath(obj.path_variable);

            % Add functions in path
            mfiles = dir(fullfile(obj.directory, '**/*.m'));
            for i=1:1:length(mfiles)
                [~, name, ~] = fileparts(mfiles(i).name);
                if isfunction(name) == 1
                    addprop(obj, name);           
                    eval(strcat('obj.', name, ' = @', name, ';'));
                end
            end
    
            function is_a_function = isfunction(function_name)
                try    
                    nargin(function_name);
                    is_a_function = true;
                catch error
                    is_a_function = false;
                end
            end
        end

        function delete(obj)
            disp('clearing')
            rmpath(obj.path_variable)
            rmdir(obj.directory, 's')
        end
    end
end