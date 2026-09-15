function paths = setup_t10_reference()
%SETUP_T10_REFERENCE Select this checkout's one frozen MATLAB source family.
matlabRoot = fileparts(mfilename('fullpath'));
paths.compute = configure_compute_threads();
paths.project = fileparts(matlabRoot);
paths.package = fullfile(matlabRoot,'source_snapshots','CLOSED002_rev02');
paths.t09Fixed = fullfile(matlabRoot,'source_snapshots','T09_FIXED007');
paths.data = fullfile(matlabRoot,'data','full023_case6001');
paths.output = fullfile(paths.project,'work','matlab');
addpath(paths.package,fullfile(paths.package,'common'),fullfile(paths.package,'helpers'));
end
