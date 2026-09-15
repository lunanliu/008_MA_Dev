function info = configure_compute_threads()
%CONFIGURE_COMPUTE_THREADS Restore MATLAB's automatic numerical threading.
% Start MATLAB without -singleCompThread. No pool or numerical experiment starts here.
info.previous_max_threads = maxNumCompThreads;
try
    maxNumCompThreads('automatic');
catch cause
    error('T10:ThreadConfiguration', ...
        'Could not enable automatic threads. Restart without -singleCompThread. Detail: %s', cause.message);
end
info.max_threads = maxNumCompThreads;
info.version = version;
info.parallel_toolbox_available = license('test','Distrib_Computing_Toolbox');
fprintf('T10_MATLAB_THREADS mode=automatic max_threads=%d previous=%d\n', ...
    info.max_threads, info.previous_max_threads);
if info.max_threads == 1
    warning('T10:SingleComputeThread', ...
        'MATLAB still reports one compute thread; inspect launch flags and host limits before a long run.');
end
end
