function info = inspect_full023_reference()
%INSPECT_FULL023_REFERENCE Read saved MAT inventories; do not generate data.
p = setup_t10_reference();
names = {'raw_input.mat','first_resampled.mat','second_z2.mat','source_descriptor.mat'};
info = struct();
for k = 1:numel(names)
    file = fullfile(p.data,names{k});
    assert(isfile(file),'Missing frozen reference: %s',file);
    key = matlab.lang.makeValidName(names{k});
    info.(key) = whos('-file',file);
    fprintf('
%s
',names{k});
    disp(struct2table(info.(key)));
end
end
