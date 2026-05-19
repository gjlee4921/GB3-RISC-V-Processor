`default_nettype none

module inverter(
	input in,
	output out
);
	assign out = ~in;

endmodule 