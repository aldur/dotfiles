function gpg-yubikey-encrypt
    # Encrypts with the GPG keys stored within your GPG.
    gpg --encrypt --no-throw-keyids --armor --output $argv.gpg --recipient 2D8785CE6E3B69AB --recipient FADB481FA744FFDF $argv
end

