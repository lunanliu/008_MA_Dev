function digestHex = bistatic_sha256(inputValue, inputIsFile)
%BISTATIC_SHA256 Return a lowercase SHA-256 digest for bytes or a file.

if nargin < 2
    inputIsFile = false;
end

if inputIsFile
    fid = fopen(inputValue, 'rb');
    if fid < 0
        error('bistatic:FileOpen', 'Cannot open file for hashing: %s', inputValue);
    end
    cleaner = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
else
    if ischar(inputValue) || isstring(inputValue)
        bytes = unicode2native(char(inputValue), 'UTF-8');
    else
        bytes = uint8(inputValue(:));
    end
end

md = java.security.MessageDigest.getInstance('SHA-256');
md.update(uint8(bytes));
digest = typecast(md.digest(), 'uint8');
digestHex = lower(reshape(dec2hex(digest, 2).', 1, []));
end
