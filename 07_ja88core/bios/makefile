all:
	fasm bios.asm
	php bin2hex.php bios.bin > ../bios.hex
	php bin2mif.php bios.bin > ../de0/bios.mif
	cp bios.bin ../em
	cd .. && make
	cd ../em/ && ./machine88
