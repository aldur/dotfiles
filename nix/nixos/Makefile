all: 
	scp -r ~/Desktop/learning_nix/nixos/* root@192.168.65.2:/etc/nixos
	ssh root@192.168.65.2 "nixos-rebuild switch --flake '/etc/nixos#nixos'"

