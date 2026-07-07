module transmit_control(
    input wire clk,
    input wire reset,
    
    input tx_done,
    input wire [31:0] tx_interval,
    input wire [31:0] sw_atten_p,
    output reg phy_tx_sw_atten,
    input wire [31:0] tx_num,

    output reg phy_tx_start 
);
    reg [31:0] phy_tx_cnt;
    reg [31:0] send_cnt;
    always@(posedge clk)begin
        if(reset | tx_done)begin
            phy_tx_cnt <= 1'b0;
        end
        else if(phy_tx_cnt == tx_interval )begin
            phy_tx_cnt <= phy_tx_cnt;
        end
        else if(send_cnt < tx_num)begin
            phy_tx_cnt <= phy_tx_cnt + 1'b1;
        end
        else begin
            phy_tx_cnt <= 1'b0;
        end
     end

    always@(posedge clk) begin
        if(reset | tx_done) begin
            phy_tx_sw_atten <= 1'b0;
        end
        else if(phy_tx_cnt >= sw_atten_p) begin
            phy_tx_sw_atten <= 1'b1;
        end
        else begin
            phy_tx_sw_atten <= phy_tx_sw_atten;
        end
    end 


    always@(posedge clk)begin
        if(reset)begin
            phy_tx_start <= 1'b0;
        end
        else if(phy_tx_cnt == tx_interval - 1)begin
            phy_tx_start <= 1'b1;
        end    
        else begin
            phy_tx_start <= 1'b0;
        end
    end
    
    always@(posedge clk)begin
        if(reset)
            send_cnt <= 1'b0;
        else if(phy_tx_start == 1)
            send_cnt <= send_cnt + 1'b1;
        else
            send_cnt <= send_cnt;
    end
endmodule
//`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////////
//// Company: 
//// Engineer: 
//// 
//// Create Date: 2022/06/05 17:10:28
//// Design Name: 
//// Module Name: transmit_control
//// Project Name: 
//// Target Devices: 
//// Tool Versions: 
//// Description: input send_interval to control the transmission interval, and calculate 
//// the minimum transmission interval through MCS and length. When the input 
//// interval is less than the minimum interval, the transmission interval is 
//// the minimum interval
//// 
//// Dependencies: 
//// 
//// Revision:
//// Revision 0.01 - File Created
//// Additional Comments:
//// 
////////////////////////////////////////////////////////////////////////////////////


//module transmit_control#(
//    parameter SENG_INTERVAL = 32'd5000,
//    parameter SEND_NUM = 32'd1000
    
//)(
//    input clk,
//    input reset,
////    input rst_tx,
//    input start_creat_data,

//    output reg start_interval
//    );
//    localparam MIN_DELAY = 32'd100;
   
////    reg rst_tx_d;
////    wire rst_tx_rising;
////    always@(posedge clk)begin
////        if(reset)begin
////            rst_tx_d <= 1'd0;
////        end
////        else begin
////            rst_tx_d <= rst_tx;
////        end
////    end  
////    assign rst_tx_rising = (~rst_tx_d) & rst_tx;

//    reg [31:0]count_num;
//    always@(posedge clk)begin
//        if(reset)begin
//            count_num <= 32'd0;
//        end
//        else begin
//            if(start_interval)begin
//                count_num <= count_num + 32'd1;
//            end
//            else if(count_num == SEND_NUM)begin
//                count_num <= 32'd0;
//            end
//            else begin
//                count_num <= count_num;
//            end
//        end
//    end
    
//    /*
//    reg [31:0]MIN_DELAY;
//    always@(posedge clk)begin
//        if(reset)begin
//            MIN_DELAY <= 32'd0;
//        end
//        else begin
//            case(count_num)
//                32'd1:
//                    MIN_DELAY <= 32'd2500;
//                32'd2:
//                    MIN_DELAY <= 32'd2350;  
//                32'd3:
//                    MIN_DELAY <= 32'd2100;
//                32'd4:
//                    MIN_DELAY <= 32'd1950;
//                32'd5:
//                    MIN_DELAY <= 32'd1700;
//                32'd6:
//                    MIN_DELAY <= 32'd2650;
//                default:
//                    MIN_DELAY <= 32'd2500;   
//            endcase
//        end
//    end
//    */
    
//    reg flag_creat;
//    always@(posedge clk)begin
//        if(reset)begin
//            flag_creat <= 1'd0;
//        end
//        else begin
//            if(start_creat_data)begin
//                flag_creat <= 1'd1;
//            end
//            else if(count_num == SEND_NUM)begin
//                flag_creat <= 1'd0;
//            end
//            else begin
//                flag_creat <= flag_creat;
//            end
//        end
//    end
    
//     wire [31:0] residue_interval;
//     assign residue_interval = SENG_INTERVAL>MIN_DELAY ? SENG_INTERVAL : MIN_DELAY;

//    reg flag_start;
//    reg [31:0] count_interval;
//    always@(posedge clk)begin
//        if(reset)begin
//            flag_start <= 1'd0;
//            count_interval <= 32'd0;
//        end
//        else if(~flag_creat)begin
//            flag_start <= 1'd0;
//            count_interval <= 32'd0;
//        end
//        else if(residue_interval)begin
//            if(count_interval==32'd0)begin
//                count_interval <= count_interval + 32'd1;
//                flag_start <= 1'd0;
//            end
//            else if(count_interval == residue_interval)begin
//                count_interval <= 32'd0;
//                flag_start <= 1'd1;
//            end
//            else begin
//                count_interval <= count_interval + 32'd1;
//            end
//        end
//        else begin
//            flag_start <= flag_start ;
//        end
//    end
//    reg start_creat_data_delay;
//    always@(posedge clk)begin
//        if(reset)begin
//            start_creat_data_delay <= 1'b0;
//        end
//        else begin
//            start_creat_data_delay <= start_creat_data;
//        end
//    end

//    always@(posedge clk)begin
//        if(reset)begin
//            start_interval <= 1'd0;
//        end
//        else begin
//            if(start_creat_data && ~start_creat_data_delay)begin
//                start_interval <= 1'd1;
//            end
//            else if(flag_start)begin
//                start_interval <= 1'd1;
//            end
//            else begin
//                start_interval <= 1'd0;
//            end
//        end
//    end
    
////    reg [3:0]start_interval_cnt;
////    always@(posedge clk)begin
////        if(reset)begin
////            start_interval_cnt <= 4'b0;
////        end
////        else if(start_interval_cnt == 4'd12)begin
////            start_interval_cnt <= 4'b0;
////        end
////        else begin
////            start_interval_cnt <= start_interval_cnt + 1'b1;
////        end   
////    end    
//endmodule

