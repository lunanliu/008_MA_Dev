function [iq, manifest] = load_frontend_waveform()
% Return frozen stream as complex doubles whose components are exact int16 codes.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
rows=strip(readlines(fullfile(root,'sim','data','autonomous_stream.mem')));
rows=rows(strlength(rows)>0);
assert(all(strlength(rows)==32),'Each beat must contain 128 hex bits');
iq=complex(zeros(numel(rows)*4,1));
for lane=0:3
    first=25-8*lane;
    words=uint32(hex2dec(char(extractBetween(rows,first,first+7))));
    iv=typecast(uint16(bitand(words,uint32(65535))),'int16');
    qv=typecast(uint16(bitshift(words,-16)),'int16');
    iq(lane+1:4:end)=complex(double(iv(:)),double(qv(:)));
end
manifest=jsondecode(fileread(fullfile(root,'sim','data','autonomous_manifest.json')));
assert(numel(iq)==manifest.accepted_samples,'Frozen waveform length');
end
