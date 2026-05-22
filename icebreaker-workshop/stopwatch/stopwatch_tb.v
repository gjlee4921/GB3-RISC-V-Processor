`timescale 1ns/1ps


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
		forever #41 CLK = ~CLK; //#41 gives a 82ns period, ~12MHz clock
	end

	task run_pulses;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                repeat(1200001) @(posedge CLK);
            end
        end
    endtask

	// e.g. press_button(1, 1, 0, 0); simulates pressing BTN1 for 100 clock cycles then releasing it
	task press_button;
        input reg btn_n_val;
        input reg btn1_val;
        input reg btn2_val;
        input reg btn3_val;
        begin
            BTN_N = btn_n_val;
            BTN1  = btn1_val;
            BTN2  = btn2_val;
            BTN3  = btn3_val;
            repeat(100) @(posedge CLK);
            BTN_N = 1;
            BTN1  = 0;
            BTN2  = 0;
            BTN3  = 0;
            repeat(100) @(posedge CLK);
        end
    endtask

	initial begin
      	BTN_N = 1;
    	BTN1  = 0;
    	BTN2  = 0;
    	BTN3  = 0;
		$dumpfile("stopwatch_tb.vcd");   
		$dumpvars(0, stopwatch_testbench);
      
        repeat(2048) @(posedge CLK); //allow time for clkdiv_pulse to go to 1

        $monitor("time=%3d, BTN_N=%b, BTN1=%b, BTN2=%b, BTN3=%b, LED1=%b, LED2=%b, LED3=%b, LED4=%b, LED5=%b", $time, BTN_N, BTN1, BTN2, BTN3, LED1, LED2, LED3, LED4, LED5);
		

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
 





		$display("TEST 2: Start stopwatch");
		press_button(1, 0, 0, 1);

        run_pulses(2);
        $display("After 2 pulses: display_value ,7seg pins = %b%b%b%b%b%b%b%b",
            P1A1,P1A2,P1A3,P1A4,P1A7,P1A8,P1A9,P1A10);

		$display("TEST 3: Stop stopwatch");
        press_button(1, 1, 0, 0);
        $display("Stopwatch stopped");

        run_pulses(1);
        $display("After 1 more pulse ,stopped");
        $display("After 1 pulse: display_value ,7seg pins = %b%b%b%b%b%b%b%b",
            P1A1,P1A2,P1A3,P1A4,P1A7,P1A8,P1A9,P1A10);

		$display("TEST 4: Lap time");
        press_button(1, 0, 0, 1); // start
        run_pulses(1);
        press_button(1, 0, 1, 0); // lap
        $display("Lap captured, lap_timeout counting down");
        run_pulses(1);

		$display("TEST 5: Reset");
        press_button(0, 0, 0, 0); // reset
        $display("After RESET: display should be 0, running=0");
      	$display("display_value ,7seg pins = %b%b%b%b%b%b%b%b",
            P1A1,P1A2,P1A3,P1A4,P1A7,P1A8,P1A9,P1A10);

        run_pulses(1);
        $display("After reset + 1 pulse");
        $display("display_value ,7seg pins = %b%b%b%b%b%b%b%b",
            P1A1,P1A2,P1A3,P1A4,P1A7,P1A8,P1A9,P1A10);


        $display("All tests complete.");
        $finish;




		
	
	end

endmodule
