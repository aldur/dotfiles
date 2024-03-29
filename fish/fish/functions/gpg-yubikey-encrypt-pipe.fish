source ~/.config/fish/functions/gpg_keys.fish

function gpg-yubikey-encrypt-pipe
    # Encrypts with the GPG keys stored within your Yubikeys.
    gpg --encrypt --no-throw-keyids --recipient $yubikey_main --recipient $yubikey_back --recipient $gpg_offline --recipient $yubikey_milan
end
