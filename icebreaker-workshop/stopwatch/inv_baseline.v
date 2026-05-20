// Cause yosys to throw an error when we implicitly declare nets
`default_nettype none
module top (
	input  wire BTN_N,
	output wire LED1,
);
	// Single inverter
	assign LED1 = !BTN_N;

endmodule
