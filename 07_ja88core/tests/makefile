all: 01_jmpmov.o 14_add.o
	php ../bios/bin2hex.php 01_jmpmov.s.bin > ../bios.hex
%.o: %.s
	as $< -o $@
	objcopy -O binary --only-section=.text $@ $<.bin
clean:
	rm *.o
