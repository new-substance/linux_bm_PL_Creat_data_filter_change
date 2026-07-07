`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/05/23 15:07:43
// Design Name: 
// Module Name: creat_test_data
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


module testdata_Generate(
    input clk,
    input reset,
    input start_interval,
//    input  test_mode,
//    input  [9:0]  addr_wr,
//    input  [63:0] data_in,
    input  [9:0]  addr_rd,
    input  [2:0] data_ram_type,//0~4 
    input  [11:0]length,
    input  [3:0] MCS_num,
//    input        SHORT_GI,
    
    output [63:0] data,
    output  wire start_data_out_1,
    // =========================================================================
    // [FILTER_TEST v2.1] VIO 可控 802.11 MAC 帧头信号
    // 用于通过物理层发包测试 RX 端 pkt_filter (filter.v) 的三级过滤功能
    // 当 en_mac_hdr=0 时行为完全不变，保持向后兼容
    // =========================================================================
    input  [ 7:0]  fc_ctrl,        // [7:6]=FC_tofrom_ds, [5:2]=FC_subtype, [1:0]=FC_type
    input  [47:0]  vio_addr1,      // 802.11 Address 1 (RA)
    input  [47:0]  vio_addr2,      // 802.11 Address 2 (TA)
    input  [47:0]  vio_addr3,      // 802.11 Address 3 (DA/BSSID)
    input  [ 2:0]  frame_pattern,  // 预设帧类型 [0]=自定义 [1]=Beacon [2]=Data [3]=ACK [4]=RTS [5]=ProbeReq [6]=QoS_Data [7]=Null
    input          en_mac_hdr       // =1:插入802.11 MAC帧头; =0:仅SIGNAL+净荷(legacy)
    );
reg w_r_state;//1 w 0 r
reg [3:0]MCS;
always @( posedge clk) begin
  if (reset) begin
    MCS <= 4'b0;
  end
  else begin
    case(MCS_num)
        4'd0:begin
            MCS <= 4'b1011;
        end
        4'd1:begin
            MCS <= 4'b1111;
        end
        4'd2:begin
            MCS <= 4'b1010;
        end
        4'd3:begin
            MCS <= 4'b1110;
        end
        4'd4:begin
            MCS <= 4'b1001;
        end
        4'd5:begin
            MCS <= 4'b1101;
        end    
        4'd6:begin
            MCS <= 4'b1000;
        end    
        4'd7:begin
            MCS <= 4'b1100;
        end    
        default:begin
            MCS <= 4'b1011;
        end
    endcase 
  end
end
reg [63:0] data_buffer;
reg [63:0] rand_data;
reg [15:0] add_data;
reg [9:0] count1;
reg [9:0] count_delay1;
reg creat_finish;
reg creat_finish_delay;
wire [11:0]  ram_addr_in;
wire [63:0] ram_data_in;

reg P;
reg start_data_out;
//assign addr_max = length[11:3] + 3'd4;

// =========================================================================
// [FILTER_TEST v2.1] MAC 帧头译码逻辑
// 根据 frame_pattern 选择预定义 802.11 帧头或使用 VIO 自定义值
// FC 字段布局 (802.11-2016 S9.2.4.1):
//   [15]=Order, [14]=Protected, [13]=More_Data, [12]=Pwr_Mgmt,
//   [11]=Retry, [10]=More_Frag, [9]=From_DS, [8]=To_DS,
//   [7:4]=Subtype, [3:2]=Type, [1:0]=Protocol_Version(=0)
//
// 预设地址分配:
//   广播:    48'hFFFF_FFFF_FFFF
//   本机MAC: 48'h0000_0000_0001  (默认测试用)
//   远端MAC: 48'h0000_0000_0002
//   测试BSSID:48'h1122_3344_5566
// =========================================================================
reg  [15:0]  sel_fc;         // 选中的 Frame Control
reg  [47:0]  sel_addr1;      // 选中的 Address 1
reg  [47:0]  sel_addr2;      // 选中的 Address 2
reg  [47:0]  sel_addr3;      // 选中的 Address 3
reg  [15:0]  sel_duration;   // 选中的 Duration/ID
reg  [15:0]  sel_seq_ctrl;   // 选中的 Sequence Control

// [FILTER_TEST v2.1] 预定义帧类型查找表
// 信号位宽: FC_type[1:0], FC_subtype[3:0], FC_tofrom_ds[1:0] 在 FC[15:0] 中
always @(*) begin
    case (frame_pattern)
        3'd0: begin  // 自定义 -- 全部由 VIO fc_ctrl/vio_addr* 控制
            sel_fc       = {7'd0, fc_ctrl[7], fc_ctrl[6], fc_ctrl[5:2], fc_ctrl[1:0], 2'b00};
            sel_addr1    = vio_addr1;
            sel_addr2    = vio_addr2;
            sel_addr3    = vio_addr3;
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'd0;
        end
        3'd1: begin  // Beacon: Type=00(Mgmt), Subtype=1000(Beacon)
            sel_fc       = 16'h0080;
            sel_addr1    = 48'hFFFF_FFFF_FFFF;    // DA = Broadcast
            sel_addr2    = 48'h0000_0000_0001;    // SA = 测试源地址
            sel_addr3    = 48'h1122_3344_5566;    // BSSID = 测试 BSSID
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'd0;
        end
        3'd2: begin  // Data (To DS): Type=10(Data), Subtype=0000, To_DS=1
            sel_fc       = 16'h0802;              // 0000_1000_0000_0010
            sel_addr1    = 48'h1122_3344_5566;    // RA/BSSID (AP 地址)
            sel_addr2    = 48'h0000_0000_0001;    // TA/SA (源地址)
            sel_addr3    = 48'h0000_0000_0002;    // DA (目标地址)
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'h0000;
        end
        3'd3: begin  // ACK: Type=01(Ctrl), Subtype=1101(ACK)
            sel_fc       = 16'h00D4;              // 0000_0000_1101_0100
            sel_addr1    = 48'h0000_0000_0001;    // RA
            sel_addr2    = 48'd0;                 // Ctrl 帧无 addr2
            sel_addr3    = 48'd0;                 // Ctrl 帧无 addr3
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'd0;
        end
        3'd4: begin  // RTS: Type=01(Ctrl), Subtype=1011(RTS)
            sel_fc       = 16'h00B4;              // 0000_0000_1011_0100
            sel_addr1    = 48'h0000_0000_0001;    // RA
            sel_addr2    = 48'h0000_0000_0002;    // TA
            sel_addr3    = 48'd0;
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'd0;
        end
        3'd5: begin  // Probe Request: Type=00(Mgmt), Subtype=0100
            sel_fc       = 16'h0040;
            sel_addr1    = 48'hFFFF_FFFF_FFFF;    // DA = Broadcast
            sel_addr2    = 48'h0000_0000_0001;    // SA
            sel_addr3    = 48'hFFFF_FFFF_FFFF;    // BSSID = Wildcard
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'd0;
        end
        3'd6: begin  // QoS Data (To DS): Type=10, Subtype=1000
            sel_fc       = 16'h0882;
            sel_addr1    = 48'h1122_3344_5566;    // RA/BSSID
            sel_addr2    = 48'h0000_0000_0001;    // TA/SA
            sel_addr3    = 48'h0000_0000_0002;    // DA
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'h0000;
        end
        3'd7: begin  // Null Data: Type=10, Subtype=0100
            sel_fc       = 16'h0842;
            sel_addr1    = 48'h1122_3344_5566;    // RA/BSSID
            sel_addr2    = 48'h0000_0000_0001;    // TA/SA
            sel_addr3    = 48'h0000_0000_0002;    // DA
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'd0;
        end
        default: begin  // 未定义 -- 空帧
            sel_fc       = 16'd0;
            sel_addr1    = 48'd0;
            sel_addr2    = 48'd0;
            sel_addr3    = 48'd0;
            sel_duration = 16'd0;
            sel_seq_ctrl = 16'd0;
        end
    endcase
end

always @( posedge clk) begin
  if (reset) begin
    rand_data <= 16'd0;
  end
  else begin
    rand_data <= $random;  // 511code matlab creat ?
  end
end

always @( posedge clk) begin
  if (reset) begin
    add_data <= 16'd0;
  end
  else begin
    if (count1 >= 10'd1) begin
      add_data <= (count1 - 3'd1) << 2; //count1*4
    end
    else begin
      add_data <= 16'd0;
    end
  end
end

always @(posedge clk) begin
  if(reset)begin
    count1 <= 10'd0;
    creat_finish <= 1'd0;
    w_r_state <= 1'd0;
  end
  else begin
    if (count1 == 10'd259 ) begin
      count1 <= count1;
      creat_finish = 1'd1;
      w_r_state <= 1'd0;
    end
    else if (count1 == 10'd0 ) begin
      count1 <= count1 + start_interval;
      creat_finish <= 1'd0;
      w_r_state <= 1'd1;
    end
    else begin
      count1 <= count1 + 10'd1;
      creat_finish <= 1'd0;
      w_r_state <= 1'd1;
    end
  end
end

always @(posedge clk)begin
  if (reset) begin
    creat_finish_delay <= 1'd0;
    start_data_out   <= 1'b0;
  end
  else begin
     creat_finish_delay <= creat_finish;
     start_data_out  <= creat_finish  && ~creat_finish_delay;
  end
end

    reg start_data_out_delay1;
    reg start_data_out_delay2;
    reg start_data_out_delay3;
    reg start_data_out_delay4;
    reg start_data_out_delay5;
    reg start_data_out_delay6;
    reg start_data_out_delay7;
    reg start_data_out_delay8;
    reg start_data_out_delay9;
    reg start_data_out_delay10;
    reg start_data_out_delay11;
    always@(posedge clk)begin
        start_data_out_delay1 <= start_data_out;
        start_data_out_delay2 <= start_data_out_delay1;
        start_data_out_delay3 <= start_data_out_delay2;
        start_data_out_delay4 <= start_data_out_delay3;
        start_data_out_delay5 <= start_data_out_delay4;
        start_data_out_delay6 <= start_data_out_delay5;
        start_data_out_delay7 <= start_data_out_delay6;
        start_data_out_delay8 <= start_data_out_delay7;
        start_data_out_delay9 <= start_data_out_delay8;
        start_data_out_delay10 <= start_data_out_delay9;
        start_data_out_delay11 <= start_data_out_delay10;
    end
    assign start_data_out_1 = start_data_out+start_data_out_delay1+start_data_out_delay2+start_data_out_delay3+start_data_out_delay4+start_data_out_delay5+start_data_out_delay6+start_data_out_delay7+start_data_out_delay8+start_data_out_delay9+start_data_out_delay10+start_data_out_delay11;
    
always@(posedge clk)begin
    if(reset)begin
        P <= 1'b0; 
    end
    else begin
        P <= MCS[0]^MCS[1]^MCS[2]^MCS[3]^length[0]^length[1]^length[2]^length[3]^length[4]^length[5]^length[6]^length[7]^length[8]^length[9]^length[10]^length[11]^1'b0;
    end
end

always @(posedge clk) begin
  if (reset) begin
    data_buffer <= 64'd0;
    count_delay1 <= 10'd0;
  end
  else begin
    count_delay1 <= count1;
    // [FILTER_TEST v2.1] 当 en_mac_hdr=1 时，在 BRAM Word 2-5 插入完整 802.11 MAC 帧头
    //
    // 802.11 OFDM 帧格式 (按字节发送顺序):
    //   byte[0:2]  = SIGNAL (3B)    → Word0[23:0]
    //   byte[3:4]  = SERVICE (2B)    → Word0[39:24]  ← 扰码器种子, 标准要求=0x0000
    //   byte[5:7]  = Reserved (3B)   → Word0[63:40]
    //   byte[8:15] = Reserved (8B)   → Word1 = 64'b0
    //   -------- PHY 头结束 (Word0 + Word1 = 16 字节) --------
    //   byte[16:17]= Frame Control   → Word2[15:0]
    //   byte[18:19]= Duration/ID     → Word2[31:16]
    //   byte[20:21]= Addr1[15:0]     → Word2[47:32]
    //   byte[22:23]= Addr1[31:16]    → Word2[63:48]
    //   byte[24:25]= Addr1[47:32]    → Word3[15:0]
    //   byte[26:27]= Addr2[15:0]     → Word3[31:16]
    //   byte[28:29]= Addr2[31:16]    → Word3[47:32]
    //   byte[30:31]= Addr2[47:32]    → Word3[63:48]
    //   byte[32:33]= Addr3[15:0]     → Word4[15:0]
    //   byte[34:35]= Addr3[31:16]    → Word4[31:16]
    //   byte[36:37]= Addr3[47:32]    → Word4[47:32]
    //   byte[38:39]= Seq Control     → Word4[63:48]
    //   byte[40:47]= Addr4 (预留)     → Word5 = 64'd0
    //   -------- MAC 帧头结束 (Word2~Word5 = 32 字节) --------
    //   byte[48:N] = 净荷           → Word6+
    //
    // PHY 头 = Word0 + Word1 = 16 字节 (基带固定要求, 与原始 testdata_Generate.v 一致)
    // MAC 帧头 = Word2~Word5 = 4 字 = 32 字节
    // 字节映射受 ofdm_tx_802_11g/ofdm_rx_802_11g IP 内部字节序影响,
    // 首次使用时需通过 Walking-Ones 帧验证

    if (count1 == 10'd0) begin
      data_buffer <= {46'd0,P,length,1'b0,MCS};// SIGNAL -- 不变
    end
    // ---- [FILTER_TEST v2.1] MAC 帧头插入 BEGIN ----
    else if (en_mac_hdr && (count1 >= 10'd2) && (count1 <= 10'd5)) begin
        case (count1)
            10'd2: data_buffer <= {sel_addr1[31:16],     // [63:48] addr1 bytes 3,2
                                   sel_addr1[15:0],      // [47:32] addr1 bytes 1,0
                                   sel_duration[15:0],   // [31:16] Duration bytes 1,0
                                   sel_fc[15:0]};        // [15:0]  Frame Control bytes 1,0
            10'd3: data_buffer <= {sel_addr2[47:32],     // [63:48] addr2 bytes 5,4
                                   sel_addr2[31:16],     // [47:32] addr2 bytes 3,2
                                   sel_addr2[15:0],      // [31:16] addr2 bytes 1,0
                                   sel_addr1[47:32]};    // [15:0]  addr1 bytes 5,4
            10'd4: data_buffer <= {sel_seq_ctrl[15:0],   // [63:48] Sequence Control bytes 1,0
                                   sel_addr3[47:32],     // [47:32] addr3 bytes 5,4
                                   sel_addr3[31:16],     // [31:16] addr3 bytes 3,2
                                   sel_addr3[15:0]};     // [15:0]  addr3 bytes 1,0
            10'd5: data_buffer <= 64'd0;                 // Addr4 placeholder (预留)
            default: data_buffer <= 64'd0;
        endcase
    end
    // ---- [FILTER_TEST v2.1] MAC 帧头插入 END ----
    else if (count1 == 10'd1) begin
      data_buffer <= 64'b0;// PHY Reserved: Word 1 = 0 (en_mac_hdr=0/1 通用)
    end
    else begin                              // 净荷 (en_mac_hdr=1 从 Word 6 开始; =0 从 Word 2 开始)
      if (data_ram_type == 3'd0) begin
        data_buffer <= 64'b0; //0000
      end
      if (data_ram_type == 3'd1) begin
        data_buffer <= 64'hffff_ffffff_ffffff; //1111
      end
       if (data_ram_type == 3'd2) begin
        data_buffer <= 64'haaaa_aaaaaa_aaaaaa;//1010
      end
      if (data_ram_type == 3'd3) begin
        data_buffer <= rand_data;            //random
      end
       if (data_ram_type == 3'd4) begin
        data_buffer <= {{add_data+10'd3},{add_data+10'd2},{add_data+10'd1},{add_data}}; //add
      end
    end
  end
end

//assign ram_addr_in = count1;
assign ram_addr_in = count_delay1;
assign ram_data_in = data_buffer;


creat_test_data creat_test_data_inst (
  .clka(clk),    // input wire clka
  .wea(w_r_state),      // input wire [0 : 0] wea
  .addra(ram_addr_in[8:0]),  // input wire [11 : 0] addra
  .dina(ram_data_in),    // input wire [63 : 0] dina
  .clkb(clk),    // input wire clkb
  .addrb(addr_rd[8:0]),  // input wire [11 : 0] addrb
  .doutb(data)  // output wire [63 : 0] doutb
);
    
endmodule
