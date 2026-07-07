`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/21 16:06:20
// Design Name: 
// Module Name: Creat_data
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Creat_data(
    input clk_240m,
    input rst,
    input tx_done,
    
    input [31:0]tx_interval,
    input [31:0]tx_num,
    input [2:0]data_ram_type_test,
     input  [3:0] VHT_MCS_test,
     input  [11:0]LENGTH_test,
    input [31:0] sw_atten_p,
    
    input [9:0]phy_tx_bram_addr,
    output phy_tx_sw_atten,
    output [63:0] data_test_out,
    output start_tesdata,
    // =========================================================================
    // [FILTER_TEST v2.1] 802.11 MAC 帧头 VIO 控制端口 — 透传到 testdata_Generate
    // =========================================================================
    input  [ 7:0]  fc_ctrl,        // [7:6]=FC_tofrom_ds, [5:2]=FC_subtype, [1:0]=FC_type
    input  [47:0]  vio_addr1,      // Address 1 (RA)
    input  [47:0]  vio_addr2,      // Address 2 (TA)
    input  [47:0]  vio_addr3,      // Address 3 (DA/BSSID)
    input  [ 2:0]  frame_pattern,  // 预设帧类型选择
    input          en_mac_hdr       // MAC 帧头使能

    );
    wire start_interval;
    
    transmit_control transmit_control(
    .clk(clk_240m),
    .reset(rst),
    
    .tx_done(tx_done),
    .tx_interval(tx_interval),
    .sw_atten_p(sw_atten_p),
    .tx_num(tx_num),
    .phy_tx_sw_atten(phy_tx_sw_atten),
    
    .phy_tx_start(start_interval) 
);

testdata_Generate testdata_Generate_inst(
    .clk(clk_240m),
    .reset(rst  |tx_done ),
    .start_interval(start_interval),
      
    .data_ram_type(data_ram_type_test),//0~7
    .length(LENGTH_test),
    .MCS_num(VHT_MCS_test),
    .addr_rd(phy_tx_bram_addr),

    // ---- [FILTER_TEST v2.1] MAC 帧头信号透传 ----
    .fc_ctrl        (fc_ctrl),
    .vio_addr1      (vio_addr1),
    .vio_addr2      (vio_addr2),
    .vio_addr3      (vio_addr3),
    .frame_pattern  (frame_pattern),
    .en_mac_hdr     (en_mac_hdr),

    
    .data(data_test_out),
    .start_data_out_1(start_tesdata)
    );
    
    
endmodule
