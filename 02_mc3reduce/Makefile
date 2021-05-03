all:
	iverilog -g2005-sv -DICARUS=1 -o main.qqq main.v cpu.v port_controller.v
	vvp main.qqq >> /dev/null
	rm main.qqq
