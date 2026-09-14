function setup_cfo_project()
% Register the independent approved model only. Does not start an experiment.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'matlab','golden'),fullfile(root,'matlab','bittrue'),fullfile(root,'matlab','waveform'));
fprintf('CFO independent model root: %s\n',root);
end