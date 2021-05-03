all:
	fasm tb.asm
	php ../dhex.php tb.bin > ../program.hex
	cd .. && make
	rm tb.bin
