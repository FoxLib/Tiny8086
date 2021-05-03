all: program.hex
	iverilog -g2005-sv -DICARUS=1 -o main.qqq icarus.v core.v alu.v
	vvp main.qqq >> /dev/null
program.hex: program.asm
	fasm program.asm
	php hex.php program.bin > program.hex
	rm program.bin
wave:
	gtkwave main.vcd
gtkw:
	gtkwave main.gtkw
clean:
	rm -f *.rpt *.summary *.sof *.done *.pin *.qws *.bak *.smsg *.qws *.vcd \
		  *.qqq *.jic *.map *.qqq undo_redo.txt PLLJ_PLLSPE_INFO.txt
	rm -rf db incremental_db simulation timing















