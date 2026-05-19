`timescale 1ps/1ps


module stopwatch_testbench ();
	reg CLK;
	reg BTN_N;
	reg BTN1;
	reg BTN2;
	reg BTN3;
	wire LED1, LED2, LED3, LED4, LED5;
	wire P1A1, P1A2, P1A3, P1A4, P1A7, P1A8, P1A9, P1A10;



	top top_dut(
		.CLK(CLK),
		.BTN_N(BTN_N),
		.BTN1(BTN1),
		.BTN2(BTN2),
		.BTN3(BTN3),
		.LED1(LED1),
		.LED2(LED2),
		.LED3(LED3),
		.LED4(LED4),
		.LED5(LED5),
		.P1A1(P1A1),
		.P1A2(P1A2),
		.P1A3(P1A3),
		.P1A4(P1A4),
		.P1A7(P1A7),
		.P1A8(P1A8),
		.P1A9(P1A9),
		.P1A10(P1A10)
		
	);


	initial begin
		CLK = 1'b0;
		forever #1 CLK = ~CLK;
	end




	initial begin
		$monitor("time=%3d, BTN_N=%b, BTN1=%b, BTN2=%b, BTN3=%b, LED1=%b, LED2=%b, LED3=%b, LED4=%b, LED5=%b \n", 
              $time, BTN_N, BTN1, BTN2, BTN3, LED1, LED2, LED3, LED4, LED5);
		

		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0000;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0001;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0010;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0011;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0100;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0101;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0110;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b0111;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1000;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1001;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1010;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1011;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1100;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1101;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1110;
		#20
		{BTN_N, BTN1, BTN2, BTN3}  = 4'b1111;
		#20
		$finish;


		
	
	end

endmodule
