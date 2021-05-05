all:
	fasm bios.asm
	php bin2hex.php bios.bin > ../bios.hex
	cd .. && make
