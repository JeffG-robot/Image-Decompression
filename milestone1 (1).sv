//Milestone 1 module
`ifndef DISABLE_DEFAULT_NET
`timescale 1ns/100ps
`default_nettype none
`endif
`include "define_state.h"

//multiplier module, which will be instantiated four times 
module Multiplier (
	input int Mult_op_1, Mult_op_2,
	output int Mult_result
);

	logic [63:0] Mult_result_long;
	assign Mult_result_long = Mult_op_1 * Mult_op_2;
	assign Mult_result = Mult_result_long[31:0];

endmodule

module milestone1(
	input logic CLOCK_50_I,
	input logic Resetn,
	input logic start, //start bit, used for leaving idle state
	input logic [15:0] SRAM_read_data,
	output logic [15:0] SRAM_write_data,
	output logic [17:0] SRAM_address,
	output logic SRAM_we_n,
	output logic m1_done
);

milestone_state_type milestone_state; //initialize this from define state file

logic [7:0] reg_u [5:0]; //shift register for u values
logic [7:0] reg_v [5:0]; //shift register for v values 
logic [7:0] reg_y [1:0]; //register for y values  

logic read_cycle_en; //to keep track of whether we need to increment address for Y/U/V or not
logic [31:0] R_even;
logic [31:0] G_even;
logic [31:0] B_even;
logic [31:0] R_odd;
logic [31:0] G_odd;
logic [31:0] B_odd;

logic [31:0] value_u_prime_even;
logic [31:0] value_u_prime_odd;
logic [31:0] value_v_prime_even;
logic [31:0] value_v_prime_odd;

logic [31:0] calculate_odd_u_prime;
logic [31:0] calculate_odd_v_prime;

logic [31:0] compA_even;
logic [31:0] compB_even;
logic [31:0] compC_even;
logic [31:0] compD_even;
logic [31:0] compA_odd;
logic [31:0] compB_odd;
logic [31:0] compC_odd;
logic [31:0] compD_odd;

logic [0:0] check_odd;

//initialize address counters for Y, U, and V
logic [17:0] address_y;
logic [17:0] address_u;
logic [17:0] address_v;
logic [17:0] address_RGB;

logic [7:0] row_counter;
logic [7:0] cc_counter;

//initialize input and output registers for multipliers
logic [31:0] Mult_op_1, Mult_op_2, Mult_result;
logic [31:0] Mult_result_long;

logic [31:0] mult1_op1, mult1_op2;
logic [31:0] mult2_op1, mult2_op2;
logic [31:0] mult3_op1, mult3_op2;
logic [31:0] mult4_op1, mult4_op2;

//initialize output registers for multipliers
logic signed [31:0] mult1_out;
logic signed [31:0] mult2_out;
logic signed [31:0] mult3_out;
logic signed [31:0] mult4_out;

//32 bit signed constant ints for interpolation
logic signed [31:0] signed_21;
logic signed [31:0] signed_neg_52;
logic signed [31:0] signed_159;
logic signed [31:0] signed_128;

//32 bit signed constant ints for colourspace conversion
logic signed [31:0] signed_16;
logic signed [31:0] signed_76284;
logic signed [31:0] signed_neg_25624;
logic signed [31:0] signed_132251;
logic signed [31:0] signed_104595;
logic signed [31:0] signed_neg_53281;

//instantiate the four multipliers needed here
Multiplier mult1(
	.Mult_op_1(mult1_op1),
	.Mult_op_2(mult1_op2),
	.Mult_result(mult1_out)
);

Multiplier mult2(
	.Mult_op_1(mult2_op1),
	.Mult_op_2(mult2_op2),
	.Mult_result(mult2_out)
);

Multiplier mult3(
	.Mult_op_1(mult3_op1),
	.Mult_op_2(mult3_op2),
	.Mult_result(mult3_out)
);

Multiplier mult4(
	.Mult_op_1(mult4_op1),
	.Mult_op_2(mult4_op2),
	.Mult_result(mult4_out)
);

always_comb begin
	r_clip = (R_even[31] == 1'd1)?8'd0:((|R_even[30:24])?8'd255:R_even[23:16]);
	g_clip = (G_even[31] == 1'd1)?8'd0:((|G_even[30:24])?8'd255:G_even[23:16]);
	b_clip = (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
end

always @(posedge CLOCK_50_I or negedge Resetn) begin
	if (~Resetn) begin
	//initialize all variables and registers as base values
		R_even <= 32'd0;
		G_even <= 32'd0;
		B_even <= 32'd0;
		R_odd <= 32'd0;
		G_odd <= 32'd0;
		B_odd <= 32'd0;
		
		value_u_prime_even <= 32'd0;
		value_u_prime_odd <= 32'd0;
		value_v_prime_even <= 32'd0;
		value_v_prime_odd <= 32'd0;
		
		calculate_odd_u_prime <= 32'd0;
		calculate_odd_v_prime <= 32'd0;
		
		compA_even <= 32'd0;
		compB_even <= 32'd0;
		compC_even <= 32'd0;
		compD_even <= 32'd0;
		compA_odd <= 32'd0;
		compB_odd <= 32'd0;
		compC_odd <= 32'd0;
		compD_odd <= 32'd0;
		
		check_odd <= 1'b1;
		read_cycle_en <= 16'd0;
		
		//starting positions of y, u, v, and RGB in the memory
		address_y <= 18'd0;
		address_u <= 18'd38400;
		address_v <= 18'd57600;
		address_RGB <= 18'd146944;

		row_counter <= 8'd0;
		cc_counter <= 8'd5;
		
		reg_u[0] <= 8'd0; //index 0 is U [(j-5)/2]
		reg_u[1] <= 8'd0; //index 1 is U [(j-3)/2]
		reg_u[2] <= 8'd0; //index 2 is U [(j-1)/2]
		reg_u[3] <= 8'd0; //index 3 is U [(j+1)/2]
		reg_u[4] <= 8'd0; //index 4 is U [(j+3)/2]
		reg_u[5] <= 8'd0; //index 5 is U [(j+5)/2]

		reg_v[0] <= 8'd0; //index 0 is V [(j-5)/2]
		reg_v[1] <= 8'd0; //index 1 is V [(j-3)/2]
		reg_v[2] <= 8'd0; //index 2 is V [(j-1)/2]
		reg_v[3] <= 8'd0; //index 3 is V [(j+1)/2]
		reg_v[4] <= 8'd0; //index 4 is V [(j+3)/2]
		reg_v[5] <= 8'd0; //index 5 is V [(j+5)/2]
		
		reg_y[0] <= 8'd0; 
		reg_y[1] <= 8'd0;
				
		//values of the constants to be used in the multipliers 
		signed_21 <= 32'd21;
		signed_neg_52 <= -32'd52;
		signed_159 <= 32'd159;
		signed_128 <= 32'd128;		
		
		signed_16 <= 32'd16;		
		signed_76284 <= 32'd76284;
		signed_neg_25624 <= -32'd25624;
		signed_132251 <= 32'd132251;
		signed_104595 <= 32'd104595;
		signed_neg_53281 <= -32'd53281;
		
		m1_done <= 1'b0;
		
	end else begin
		case(milestone_state)
			
			IDLE: begin
			 if(start)begin
			   milestone_state <= LEAD_IN_NEG_1;
			 end
			end
			
			//lead in states - 3 clock cycle delay between reading and updating values
			LEAD_IN_NEG_1: begin				
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_u; 
				address_u <= address_u + 18'd1; 
				
				cc_counter <= 8'd5;
				milestone_state <= LEAD_IN_0;
			end
						
			LEAD_IN_0: begin 
				check_odd <= 1'b1;
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_v; 
				address_v <= address_v + 18'd1; 
				
				milestone_state <= LEAD_IN_1;
			end
			
			LEAD_IN_1: begin 
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_u; 
				address_u <= address_u + 18'd1;							
				
				milestone_state <= LEAD_IN_2;
			end
			
			LEAD_IN_2: begin 
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_v; 
				address_v <= address_v + 18'd1; 
				
				reg_u[0] <= SRAM_read_data[15:8];//read U0 (even)
				reg_u[1] <= SRAM_read_data[15:8];//read U0 (even)
				reg_u[2] <= SRAM_read_data[15:8];//read U0 (even)
				reg_u[3] <= SRAM_read_data[15:8];//read U0 (even)
				reg_u[4] <= SRAM_read_data[15:8];//read U0 (even)
				reg_u[5] <= SRAM_read_data[7:0];	//read U1 (odd) at bottom					
				
				milestone_state <= LEAD_IN_3;
			end
			
			LEAD_IN_3: begin								
				reg_v[0] <= SRAM_read_data[15:8];//read V0 (even)
				reg_v[1] <= SRAM_read_data[15:8];//read V0 (even)
				reg_v[2] <= SRAM_read_data[15:8];//read V0 (even)
				reg_v[3] <= SRAM_read_data[15:8];//read V0 (even)
				reg_v[4] <= SRAM_read_data[15:8];//read V0 (even)
				reg_v[5] <= SRAM_read_data[7:0]; //read V1 (odd)
								
				milestone_state <= LEAD_IN_4;
			end
			
			LEAD_IN_4: begin							
				reg_u[0] <= reg_u[2];
				reg_u[1] <= reg_u[3];
				reg_u[2] <= reg_u[4];
				reg_u[3] <= reg_u[5];				
				reg_u[4] <= SRAM_read_data[15:8];//read U2 (even)
				reg_u[5] <= SRAM_read_data[7:0]; //read U3 (odd)
										
				milestone_state <= LEAD_IN_5;
			end
			
			LEAD_IN_5: begin 
				reg_v[0] <= reg_v[2];
				reg_v[1] <= reg_v[3];
				reg_v[2] <= reg_v[4];
				reg_v[3] <= reg_v[5];				
				reg_v[4] <= SRAM_read_data[15:8];//read V2 (even)
				reg_v[5] <= SRAM_read_data[7:0]; //read V3 (odd)						
								
				mult1_op1 <= signed_21;
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
								
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
				milestone_state <= LEAD_IN_6;
			end
			
			LEAD_IN_6: begin 					
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_y; 
				address_y <= address_y + 18'd1;
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
				
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;
				
				milestone_state <= LEAD_IN_9;
			end
			
			//not used
			LEAD_IN_7: begin
				milestone_state <= LEAD_IN_8;
			end
			//not used
			LEAD_IN_8: begin							
				milestone_state <= LEAD_IN_9;
			end
			
			LEAD_IN_9: begin 
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_u; 
				//address_u <= address_u + 18'd1;
				
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				milestone_state <= LEAD_IN_10;
			end
			
			LEAD_IN_10: begin 
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_v; 
				//address_v <= address_v + 18'd1;
								
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				milestone_state <= LEAD_IN_11;
			end
			
			LEAD_IN_11: begin 
												
				reg_y[0] <= SRAM_read_data[15:8];//read Y0 (even)
				reg_y[1] <= SRAM_read_data[7:0]; //read Y1 (odd)
								
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				milestone_state <= LEAD_IN_12;
			end
			
			LEAD_IN_12: begin				
				reg_u[0] <= reg_u[1];
				reg_u[1] <= reg_u[2];
				reg_u[2] <= reg_u[3];
				reg_u[3] <= reg_u[4];	
				reg_u[4] <= reg_u[5];
				reg_u[5] <= SRAM_read_data[15:8]; //read U4 (even)
				
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				milestone_state <= LEAD_IN_13;
			end
			
			LEAD_IN_13: begin						
				reg_v[0] <= reg_v[1];
				reg_v[1] <= reg_v[2];
				reg_v[2] <= reg_v[3];
				reg_v[3] <= reg_v[4];
				reg_v[4] <= reg_v[5];
				reg_v[5] <= SRAM_read_data[15:8];	//read V4 (even)
				
				value_u_prime_even <= reg_u[1];
				value_u_prime_odd <= calculate_odd_u_prime + mult1_out + signed_128;
				value_v_prime_even <= reg_v[2];
				value_v_prime_odd <= calculate_odd_v_prime + mult2_out + signed_128;
				
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
				
				//matrix calculation using Y0 for the R value CSC
				mult3_op1 <= signed_76284;
				mult3_op2 <= (reg_y[0] - signed_16);
				
				//matrix calculation using Y1 for the R value CSC
				mult4_op1 <= signed_76284;
				mult4_op2 <= (reg_y[1] - signed_16);
				
				milestone_state <= LEAD_IN_14;
			end
			
			LEAD_IN_14: begin				
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_y; 
				address_y <= address_y + 18'd1;
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
				
				//matrix calculation using V'0 = V0 for the R value CSC
				mult3_op1 <= signed_104595;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				//matrix calculation using V'1 for the R value CSC
				mult4_op1 <= signed_104595;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;	
				
				compA_even <= mult3_out;
				compA_odd <= mult4_out;
				
				milestone_state <= LEAD_IN_15;
			end
			
			LEAD_IN_15: begin
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_u; 
				address_u <= address_u + 18'd1;
								
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_25624;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_25624;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;
				
				milestone_state <= LEAD_IN_16;
			end
			
			LEAD_IN_16: begin
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_v; 			
				address_v <= address_v + 18'd1;
				
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_53281;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_53281;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compC_even <= mult3_out;
				compC_odd <= mult4_out;
				
				milestone_state <= LEAD_IN_17;
			end
			
			LEAD_IN_17: begin												
				
				reg_y[0] <= SRAM_read_data[15:8];
				reg_y[1] <= SRAM_read_data[7:0]; 
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				mult3_op1 <= signed_132251;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_132251;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compD_even <= mult3_out;
				compD_odd <= mult4_out;
				
				milestone_state <= LEAD_IN_18;
			end
			
			LEAD_IN_18: begin
																
				if (check_odd == 1'b1) begin
					reg_u[5] <= SRAM_read_data[7:0];	//read U5 (odd)
				end else begin
					reg_u[5] <= SRAM_read_data[15:8]; 
				end
				check_odd <= ~check_odd;
								
				reg_u[0] <= reg_u[1];
				reg_u[1] <= reg_u[2];
				reg_u[2] <= reg_u[3];
				reg_u[3] <= reg_u[4];
				reg_u[4] <= reg_u[5];
				
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;							
				
				R_even <= compA_even + compB_even;
				G_even <= compA_even + compC_even + compD_even;
				B_even <= compA_even + mult3_out;
				R_odd <= compA_odd + compB_odd;
				G_odd <= compA_odd + compC_odd + compD_odd;
				B_odd <= compA_odd + mult4_out;
				
				milestone_state <= COMMON_0;
			end
			
			//common case states - state 19
			COMMON_0: begin			
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
			
				//write R0 G0 values to the SRAM, account for clipped values 
				SRAM_write_data <= {r_clip,g_clip};
				
				if (check_odd == 1'b1) begin					
					reg_v[5] <= SRAM_read_data[7:0];	//read V5 (odd)					
				end else begin
					reg_v[5] <= SRAM_read_data[15:8]; 
				end
				check_odd <= ~check_odd;
				reg_v[0] <= reg_v[1];
				reg_v[1] <= reg_v[2];
				reg_v[2] <= reg_v[3];
				reg_v[3] <= reg_v[4];
				reg_v[4] <= reg_v[5];
								
				value_u_prime_even <= reg_u[1];
				value_u_prime_odd <= calculate_odd_u_prime + mult1_out + signed_128;
				value_v_prime_even <= reg_v[2];
				value_v_prime_odd <= calculate_odd_v_prime + mult2_out + signed_128;
			
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
			
				mult3_op1 <= signed_76284;
				mult3_op2 <= (reg_y[0] - signed_16);
				
				mult4_op1 <= signed_76284;
				mult4_op2 <= (reg_y[1] - signed_16);							
			
				milestone_state <= COMMON_1;
			end
			
			//state 20
			COMMON_1: begin				
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_y;				
				address_y <= address_y + 18'd1;						
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
				
				//matrix calculation using V'0 = V0 for the R value CSC
				mult3_op1 <= signed_104595;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				//matrix calculation using V'1 for the R value CSC
				mult4_op1 <= signed_104595;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
			
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;	
			
				compA_even <= mult3_out;
				compA_odd <= mult4_out;					
			
				milestone_state <= COMMON_2;
			end
			
			//state 21
			COMMON_2: begin				
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_u; 
				if (check_odd == 1'b0) begin	
					address_u <= address_u + 18'd1;
				end
			
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_25624;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_25624;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;
			
				milestone_state <= COMMON_3;
			end
			
			//state 22
			COMMON_3: begin			
				SRAM_we_n <= 1'b1;
				SRAM_address <= address_v; 
				if (check_odd == 1'b0) begin		
					address_v <= address_v + 18'd1;
				end
				
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_53281;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_53281;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
			
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compC_even <= mult3_out;
				compC_odd <= mult4_out;
			
				milestone_state <= COMMON_4;
			end
			
			//state 23
			COMMON_4: begin
				SRAM_we_n <= 1'b0;
				SRAM_address <= address_RGB;	
				address_RGB <= address_RGB + 18'd1;	 								
				
				//write B0 R1 values to the SRAM
				SRAM_write_data <= (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
				SRAM_write_data <= (R_odd[31] == 1'd1)?8'd0:((|R_odd[30:24])?8'd255:R_odd[23:16]);
								
				reg_y[0] <= SRAM_read_data[15:8];
				reg_y[1] <= SRAM_read_data[7:0];
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				mult3_op1 <= signed_132251;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_132251;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compD_even <= mult3_out;
				compD_odd <= mult4_out;
				
				cc_counter <= cc_counter + 8'd1;
				milestone_state <= COMMON_5;
			end
			
			//state 24
			COMMON_5: begin				
				SRAM_we_n <= 1'b0;
				SRAM_address <= address_RGB;				
				address_RGB <= address_RGB + 18'd1;	
				
				//write G1 B1 values to the SRAM
				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);
				SRAM_write_data <= (B_odd[31] == 1'd1)?8'd0:((|B_odd[30:24])?8'd255:B_odd[23:16]);
				
				if (check_odd == 1'b0) begin					
					reg_u[5] <= SRAM_read_data[15:8];	//read U6 (even)					
				end else begin
					reg_u[5] <= SRAM_read_data[7:0]; 
				end
				
				reg_u[0] <= reg_u[1];
				reg_u[1] <= reg_u[2];
				reg_u[2] <= reg_u[3];
				reg_u[3] <= reg_u[4];
				reg_u[4] <= reg_u[5];
												
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;							
				
				R_even <= compA_even + compB_even;
				G_even <= compA_even + compC_even + compD_even;
				B_even <= compA_even + mult3_out;
				R_odd <= compA_odd + compB_odd;
				G_odd <= compA_odd + compC_odd + compD_odd;
				B_odd <= compA_odd + mult4_out;		
				
				if (cc_counter == 8'd159) begin
					milestone_state <= LEAD_OUT_A1;
				end else begin
					milestone_state <= COMMON_0;
				end			
			end
			
			//lead out cases - stop reading u and v from SRAM
			LEAD_OUT_A1: begin	
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
				
				SRAM_write_data <= (R_even[31] == 1'd1)?8'd0:((|R_even[30:24])?8'd255:R_even[23:16]);
				SRAM_write_data <= (G_even[31] == 1'd1)?8'd0:((|G_even[30:24])?8'd255:G_even[23:16]);
								
				if (check_odd == 1'b0) begin
					reg_v[5] <= SRAM_read_data[7:0];	//read V159 (odd) 
				end else begin
					reg_v[5] <= SRAM_read_data[15:8];	
				end
				check_odd <= ~check_odd;
				
				reg_v[0] <= reg_v[1];
				reg_v[1] <= reg_v[2];
				reg_v[2] <= reg_v[3];
				reg_v[3] <= reg_v[4];
				reg_v[4] <= reg_v[5];
				
				value_u_prime_even <= reg_u[1];
				value_u_prime_odd <= calculate_odd_u_prime + mult1_out + signed_128;
				value_v_prime_even <= reg_v[2];
				value_v_prime_odd <= calculate_odd_v_prime + mult2_out + signed_128;
			
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
			
				mult3_op1 <= signed_76284;
				mult3_op2 <= (reg_y[0] - signed_16);
				
				mult4_op1 <= signed_76284;
				mult4_op2 <= (reg_y[1] - signed_16);					
			
				milestone_state <= LEAD_OUT_A2;
			end
			
			LEAD_OUT_A2: begin		
				SRAM_we_n <= 1'b1;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
								
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
								
				mult3_op1 <= signed_104595;
				mult3_op2 <= (value_v_prime_even - signed_128);
								
				mult4_op1 <= signed_104595;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;	
				
				compA_even <= mult3_out;
				compA_odd <= mult4_out;
				
				milestone_state <= LEAD_OUT_A3;
			end
			
			LEAD_OUT_A3: begin												
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_25624;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_25624;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_A4;
			end
			
			LEAD_OUT_A4: begin		
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_53281;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_53281;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_A5;
			end
			
			LEAD_OUT_A5: begin		
				SRAM_we_n <= 1'b0;			 								
				reg_y[0] <= SRAM_read_data[15:8];
				reg_y[1] <= SRAM_read_data[7:0];
				
				SRAM_write_data <= (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);								
								
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				mult3_op1 <= signed_132251;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_132251;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compD_even <= mult3_out;
				compD_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_A6;
			end
			
			LEAD_OUT_A6: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;

				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);
				SRAM_write_data <= (B_odd[31] == 1'd1)?8'd0:((|B_odd[30:24])?8'd255:B_odd[23:16]);
				
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;							
				
				R_even <= compA_even + compB_even;
				G_even <= compA_even + compC_even + compD_even;
				B_even <= compA_even + mult3_out;
				R_odd <= compA_odd + compB_odd;
				G_odd <= compA_odd + compC_odd + compD_odd;
				B_odd <= compA_odd + mult4_out;
			
				milestone_state <= LEAD_OUT_B1;
			end
			
			LEAD_OUT_B1: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
				
				check_odd <= ~check_odd;
				SRAM_write_data <= (R_even[31] == 1'd1)?8'd0:((|R_even[30:24])?8'd255:R_even[23:16]);
				SRAM_write_data <= (G_even[31] == 1'd1)?8'd0:((|G_even[30:24])?8'd255:G_even[23:16]);			
				
				value_u_prime_even <= reg_u[1];
				value_u_prime_odd <= calculate_odd_u_prime + mult1_out + signed_128;
				value_v_prime_even <= reg_v[2];
				value_v_prime_odd <= calculate_odd_v_prime + mult2_out + signed_128;
			
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
			
				mult3_op1 <= signed_76284;
				mult3_op2 <= (reg_y[0] - signed_16);
				
				mult4_op1 <= signed_76284;
				mult4_op2 <= (reg_y[1] - signed_16);		
				
				milestone_state <= LEAD_OUT_B2;
			end
			
			LEAD_OUT_B2: begin		
				SRAM_we_n <= 1'b1;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;			
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
								
				mult3_op1 <= signed_104595;
				mult3_op2 <= (value_v_prime_even - signed_128);
								
				mult4_op1 <= signed_104595;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;	
				
				compA_even <= mult3_out;
				compA_odd <= mult4_out;
				
				milestone_state <= LEAD_OUT_B3;
			end
			
			LEAD_OUT_B3: begin		
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_25624;
				mult3_op2 <= (value_u_prime_even[15:8] - signed_128);
				
				mult4_op1 <= signed_neg_25624;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_B4;
			end
			
			LEAD_OUT_B4: begin		
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_53281;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_53281;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_B5;
			end
			
			LEAD_OUT_B5: begin		
				SRAM_we_n <= 1'b0;			 								
				
				reg_y[0] <= SRAM_read_data[15:8];
				reg_y[1] <= SRAM_read_data[7:0];
				
				SRAM_write_data <= (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);		
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				mult3_op1 <= signed_132251;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_132251;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compD_even <= mult3_out;
				compD_odd <= mult4_out;							
			
				milestone_state <= LEAD_OUT_B6;
			end
			
			LEAD_OUT_B6: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;

				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);
				SRAM_write_data <= (B_odd[31] == 1'd1)?8'd0:((|B_odd[30:24])?8'd255:B_odd[23:16]);
								
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;							
				
				R_even <= compA_even + compB_even;
				G_even <= compA_even + compC_even + compD_even;
				B_even <= compA_even + mult3_out;
				R_odd <= compA_odd + compB_odd;
				G_odd <= compA_odd + compC_odd + compD_odd;
				B_odd <= compA_odd + mult4_out;					
			
				milestone_state <= LEAD_OUT_C1;
			end
			
			LEAD_OUT_C1: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
				
				check_odd <= ~check_odd;
				SRAM_write_data <= (R_even[31] == 1'd1)?8'd0:((|R_even[30:24])?8'd255:R_even[23:16]);
				SRAM_write_data <= (G_even[31] == 1'd1)?8'd0:((|G_even[30:24])?8'd255:G_even[23:16]);						
				
				value_u_prime_even <= reg_u[1];
				value_u_prime_odd <= calculate_odd_u_prime + mult1_out + signed_128;
				value_v_prime_even <= reg_v[2];
				value_v_prime_odd <= calculate_odd_v_prime + mult2_out + signed_128;
			
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
			
				mult3_op1 <= signed_76284;
				mult3_op2 <= (reg_y[0] - signed_16);
				
				mult4_op1 <= signed_76284;
				mult4_op2 <= (reg_y[1] - signed_16);					
			
				milestone_state <= LEAD_OUT_C2;
			end
			
			LEAD_OUT_C2: begin		
				SRAM_we_n <= 1'b1;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;		
							
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
								
				mult3_op1 <= signed_104595;
				mult3_op2 <= (value_v_prime_even[15:8] - signed_128);
								
				mult4_op1 <= signed_104595;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;	
				
				compA_even <= mult3_out;
				compA_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_C3;
			end
			
			LEAD_OUT_C3: begin		
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_25624;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_25624;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_C4;
			end
			
			LEAD_OUT_C4: begin							
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_53281;
				mult3_op2 <= (value_v_prime_even[15:8] - signed_128);
				
				mult4_op1 <= signed_neg_53281;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_C5;
			end
			
			LEAD_OUT_C5: begin		
				SRAM_we_n <= 1'b0;			 								
								
				reg_y[0] <= SRAM_read_data[15:8];
				reg_y[1] <= SRAM_read_data[7:0];
				
				SRAM_write_data <= (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
				SRAM_write_data <= (R_odd[31] == 1'd1)?8'd0:((|R_odd[30:24])?8'd255:R_odd[23:16]);
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				mult3_op1 <= signed_132251;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_132251;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compD_even <= mult3_out;
				compD_odd <= mult4_out;						
			
				milestone_state <= LEAD_OUT_C6;
			end
			
			LEAD_OUT_C6: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
				
				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);
				SRAM_write_data <= (B_odd[31] == 1'd1)?8'd0:((|B_odd[30:24])?8'd255:B_odd[23:16]);
								
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;							
				
				R_even <= compA_even + compB_even;
				G_even <= compA_even + compC_even + compD_even;
				B_even <= compA_even + mult3_out;
				R_odd <= compA_odd + compB_odd;
				G_odd <= compA_odd + compC_odd + compD_odd;
				B_odd <= compA_odd + mult4_out;						
			
				milestone_state <= LEAD_OUT_D1;
			end
			
			LEAD_OUT_D1: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
				
				check_odd <= ~check_odd;
				SRAM_write_data <= (R_even[31] == 1'd1)?8'd0:((|R_even[30:24])?8'd255:R_even[23:16]);
				SRAM_write_data <= (G_even[31] == 1'd1)?8'd0:((|G_even[30:24])?8'd255:G_even[23:16]);	
				
				value_u_prime_even <= reg_u[1];
				value_u_prime_odd <= calculate_odd_u_prime + mult1_out + signed_128;
				value_v_prime_even <= reg_v[2];
				value_v_prime_odd <= calculate_odd_v_prime + mult2_out + signed_128;
			
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
			
				mult3_op1 <= signed_76284;
				mult3_op2 <= (reg_y[0] - signed_16);
				
				mult4_op1 <= signed_76284;
				mult4_op2 <= (reg_y[1] - signed_16);						
			
				milestone_state <= LEAD_OUT_D2;
			end
			
			LEAD_OUT_D2: begin		
				SRAM_we_n <= 1'b1;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;					
							
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
								
				mult3_op1 <= signed_104595;
				mult3_op2 <= (value_v_prime_even - signed_128);
								
				mult4_op1 <= signed_104595;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;	
				
				compA_even <= mult3_out;
				compA_odd <= mult4_out;								
			
				milestone_state <= LEAD_OUT_D3;
			end
			
			LEAD_OUT_D3: begin		
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_25624;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_25624;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_D4;
			end
			
			LEAD_OUT_D4: begin		
				SRAM_we_n <= 1'b1;
				
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_53281;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_53281;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;						
			
				milestone_state <= LEAD_OUT_D5;
			end
			
			LEAD_OUT_D5: begin		
				SRAM_we_n <= 1'b0;
				
				reg_y[0] <= SRAM_read_data[15:8];
				reg_y[1] <= SRAM_read_data[7:0];
				
				SRAM_write_data <= (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
				SRAM_write_data <= (R_odd[31] == 1'd1)?8'd0:((|R_odd[30:24])?8'd255:R_odd[23:16]);
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				mult3_op1 <= signed_132251;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_132251;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compD_even <= mult3_out;
				compD_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_D6;
			end
			
			LEAD_OUT_D6: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;

				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);
				SRAM_write_data <= (B_odd[31] == 1'd1)?8'd0:((|B_odd[30:24])?8'd255:B_odd[23:16]);
								
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;							
				
				R_even <= compA_even + compB_even;
				G_even <= compA_even + compC_even + compD_even;
				B_even <= compA_even + mult3_out;
				R_odd <= compA_odd + compB_odd;
				G_odd <= compA_odd + compC_odd + compD_odd;
				B_odd <= compA_odd + mult4_out;					
			
				milestone_state <= LEAD_OUT_E1;
			end
			
			LEAD_OUT_E1: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;

				check_odd <= ~check_odd;
				SRAM_write_data <= (R_even[31] == 1'd1)?8'd0:((|R_even[30:24])?8'd255:R_even[23:16]);
				SRAM_write_data <= (G_even[31] == 1'd1)?8'd0:((|G_even[30:24])?8'd255:G_even[23:16]);							
				
				value_u_prime_even <= reg_u[1];
				value_u_prime_odd <= calculate_odd_u_prime + mult1_out + signed_128;
				value_v_prime_even <= reg_v[2];
				value_v_prime_odd <= calculate_odd_v_prime + mult2_out + signed_128;
			
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[0]; //load j-5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[1]; //load j-3*21 for multiplier 2
			
				mult3_op1 <= signed_76284;
				mult3_op2 <= (reg_y[0] - signed_16);
				
				mult4_op1 <= signed_76284;
				mult4_op2 <= (reg_y[1] - signed_16);									
			
				milestone_state <= LEAD_OUT_E2;
			end
			
			LEAD_OUT_E2: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;					
			
				SRAM_write_data <= (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
				SRAM_write_data <= (R_odd[31] == 1'd1)?8'd0:((|R_odd[30:24])?8'd255:R_odd[23:16]);
				
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[1]; //load j-3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[1]; //load j-3*-52 for multiplier 2
								
				mult3_op1 <= signed_104595;
				mult3_op2 <= (value_v_prime_even - signed_128);
								
				mult4_op1 <= signed_104595;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= mult1_out;
				calculate_odd_v_prime <= mult2_out;	
				
				compA_even <= mult3_out;
				compA_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_E3;
			end
			
			LEAD_OUT_E3: begin		
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[2]; //load j-1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[2]; //load j-1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_25624;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_25624;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_E4;
			end
			
			LEAD_OUT_E4: begin		
				mult1_op1 <= signed_159;
				mult1_op2 <= reg_u[3]; //load j+1*159 for multiplier 1
				
				mult2_op1 <= signed_159;
				mult2_op2 <= reg_v[3]; //load j+1*159 for multiplier 2
				
				mult3_op1 <= signed_neg_53281;
				mult3_op2 <= (value_v_prime_even - signed_128);
				
				mult4_op1 <= signed_neg_53281;
				mult4_op2 <= (value_v_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compB_even <= mult3_out;
				compB_odd <= mult4_out;					
			
				milestone_state <= LEAD_OUT_E5;
			end
			
			LEAD_OUT_E5: begin		
								
				mult1_op1 <= signed_neg_52;
				mult1_op2 <= reg_u[4]; //load j+3*-52 for multiplier 1
				
				mult2_op1 <= signed_neg_52;
				mult2_op2 <= reg_v[4]; //load j+3*-52 for multiplier 2
				
				mult3_op1 <= signed_132251;
				mult3_op2 <= (value_u_prime_even - signed_128);
				
				mult4_op1 <= signed_132251;
				mult4_op2 <= (value_u_prime_odd[15:8] - signed_128);
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;
				
				compD_even <= mult3_out;
				compD_odd <= mult4_out;						
			
				milestone_state <= LEAD_OUT_E6;
			end
			
			LEAD_OUT_E6: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;

				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);
				SRAM_write_data <= (B_odd[31] == 1'd1)?8'd0:((|B_odd[30:24])?8'd255:B_odd[23:16]);
								
				mult1_op1 <= signed_21;		
				mult1_op2 <= reg_u[5]; //load j+5*21 for multiplier 1
				
				mult2_op1 <= signed_21;
				mult2_op2 <= reg_v[5]; //load j+5*21 for multiplier 2
				
				calculate_odd_u_prime <= calculate_odd_u_prime + mult1_out;
				calculate_odd_v_prime <= calculate_odd_v_prime + mult2_out;							
				
				R_even <= compA_even + compB_even;
				G_even <= compA_even + compC_even + compD_even;
				B_even <= compA_even + mult3_out;
				R_odd <= compA_odd + compB_odd;
				G_odd <= compA_odd + compC_odd + compD_odd;
				B_odd <= compA_odd + mult4_out;					
			
				milestone_state <= LEAD_OUT_F1;
			end
			
			LEAD_OUT_F1: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;
				
				SRAM_write_data <= (R_even[31] == 1'd1)?8'd0:((|R_even[30:24])?8'd255:R_even[23:16]);
				SRAM_write_data <= (G_even[31] == 1'd1)?8'd0:((|G_even[30:24])?8'd255:G_even[23:16]);
							
				milestone_state <= LEAD_OUT_F2;
			end
			
			LEAD_OUT_F2: begin		
				SRAM_we_n <= 1'b0;				 
				SRAM_address <= address_RGB;								
				address_RGB <= address_RGB + 18'd1;	
				
				SRAM_write_data <= (B_even[31] == 1'd1)?8'd0:((|B_even[30:24])?8'd255:B_even[23:16]);
				SRAM_write_data <= (R_odd[31] == 1'd1)?8'd0:((|R_odd[30:24])?8'd255:R_odd[23:16]);
				
				row_counter <= row_counter + 8'd1;
				milestone_state <= LEAD_OUT_F3;
			end
			
			LEAD_OUT_F3: begin
				SRAM_we_n <= 1'b0;
				SRAM_address <= address_RGB;
				
				SRAM_write_data <= (G_odd[31] == 1'd1)?8'd0:((|G_odd[30:24])?8'd255:G_odd[23:16]);
				SRAM_write_data <= (B_odd[31] == 1'd1)?8'd0:((|B_odd[30:24])?8'd255:B_odd[23:16]);
				
				if (row_counter == 8'd240) begin
					milestone_state <= LEAD_OUT_F4;
				end else begin
					milestone_state <= LEAD_IN_0;
				end
			end
			
			LEAD_OUT_F4: begin				
					milestone_state <= LEAD_OUT_F5;				
			end
			
			LEAD_OUT_F5: begin				
					milestone_state <= LEAD_OUT_F6;				
			end
			
			LEAD_OUT_F6: begin				
					milestone_state <= IDLE;				
			end
			
			default: milestone_state <= IDLE;
			endcase
			
		end
	end
endmodule	