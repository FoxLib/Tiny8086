all:
	fasm bios.asm
	php ../dhex.php bios.bin > ../program.hex
	cd .. && make
	rm bios.bin
