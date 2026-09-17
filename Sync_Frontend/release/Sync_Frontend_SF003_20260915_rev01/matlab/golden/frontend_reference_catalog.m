function catalog = frontend_reference_catalog()
% Independent local copies of the selected historical mathematical models.
% No experiment is started by this entry point.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(root,'matlab','reference_source');
addpath(source);
catalog=struct;
catalog.floatingMetric=@t04_sc_metric_rolling;
catalog.floatingFineTiming=@t05_local_fine_sync_floating;
catalog.integerCoarseTiming=@t04_integer_sc_core_q3_45;
catalog.mathematicalFixedPointFineTiming=@t05_local_fine_sync_bittrue;
catalog.sourceManifest=fullfile(root,'reports','provenance','matlab_reference_import.csv');
catalog.frozenInput=fullfile(root,'sim','data','autonomous_stream.mem');
catalog.inputAndTruthManifest=fullfile(root,'sim','data','autonomous_manifest.json');
catalog.warning='Historical fixed-window models require their documented local coordinates/options; mathematical DDS is not vendor bit exact. Continuous capture is checked by the passive RTL testbench.';
end
