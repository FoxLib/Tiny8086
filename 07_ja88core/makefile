all:
	iverilog -g2005-sv -DICARUS=1 -o tb.qqq tb.v core88.v alu.v portctl.v sd.v
	vvp tb.qqq >> /dev/null
vcd:
	gtkwave tb.vcd
wave:
	gtkwave tb.gtkw
mif:
	quartus_cdb de0 -c de0 --update_mif
	quartus_asm --read_settings_files=on --write_settings_files=off de0 -c de0
clean:
	rm -rf *.vcd *.qqq

