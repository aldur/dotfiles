set yubikey_main '2D8785CE6E3B69AB'
set yubikey_back 'FADB481FA744FFDF'
set gpg_offline  '347B2D89DDDF596B'

function gpg-yubikey-encrypt
    # Encrypts with the GPG keys stored within your Yubikeys.
    gpg --encrypt --no-throw-keyids --armor --output $argv.gpg --recipient $yubikey_main --recipient $yubikey_back --recipient $gpg_offline $argv
end

function gpg-yubikey-encrypt-pipe
    # Encrypts with the GPG keys stored within your Yubikeys.
    gpg --encrypt --no-throw-keyids --armor --recipient $yubikey_main --recipient $yubikey_back --recipient $gpg_offline
end
