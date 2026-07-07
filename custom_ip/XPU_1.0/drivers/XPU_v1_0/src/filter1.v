// Xianjun jiao. putaoshu@msn.com; xianjun.jiao@imec.be;
//
// === 802.11 Rx 帧过滤器 - 3级层次化匹配 (L0→L1→L2) ===
// 替换原 pkt_filter_ctl.v
// 寄存器定义严格匹配: HA_Rx_Frame_Filter_Reg.xlsx
//
// === 9寄存器架构 (v2.1, 新增 L2-Reg4/Reg5 支持 BSSID 过滤) ===
//   L0-Reg0: L0分类使能 + UPDATE_VALID
//   L1-Reg0: CTRL子类型 + DATA子类型
//   L1-Reg1: MANAGE子类型 + USR子类型
//   L2-Reg0: TOUCH/MR/NMR + THIS_LDC + FC_USR + EN_ADDR1/2/FC/BSSID + UPDATE_VALID
//   L2-Reg1: ADDR1[31:0]
//   L2-Reg2: ADDR1[47:32] + ADDR2[15:0]
//   L2-Reg3: ADDR2[47:16]
//   L2-Reg4: BSSID[31:0]                       (NEW v2.1)
//   L2-Reg5: BSSID[47:32] + BSSID_UV @ [28]    (NEW v2.1)
//
// === 3级 TOUCH 控制 (按级别对应) ===
//   TOUCH0/MR0/NMR0 → L0 (帧大类判定)    TOUCH1/MR1/NMR1 → L1 (子类型判定)
//   TOUCH2/MR2/NMR2 → L2 (复合匹配判定)   THIS_LDC → L2 透传
//
// === L2 复合匹配 (使能位控制的 AND 逻辑) ===  (NEW v2.1)
//   l2_match = (EN_ADDR1 ? addr1_match : 1) & (EN_ADDR2 ? addr2_match : 1)
//            & (EN_FC    ? fc_match    : 1) & (EN_BSSID ? bssid_match : 1)
//
// === BSSID 提取逻辑 (参考原 pkt_filter_ctl.v) ===  (NEW v2.1)
//   FC_tofrom_ds==2'b10 (From DS) → BSSID = addr1
//   FC_tofrom_ds==2'b01 (To DS)   → BSSID = addr2
//   FC_tofrom_ds==2'b00 (Ad-hoc)  → BSSID = addr3
//   FC_tofrom_ds==2'b11 (Mesh)    → BSSID 无效
//
// === DC优先级链 (触发即PASS) ===
//   L0_ALL_DC > L1_xx_DC > THIS_LDC
//
// === ABNORMAL 保护 (NEW v2.1) ===
//   signal_len < 14 → ST_ABNORMAL → DROP

`timescale 1 ns / 1 ps

module pkt_filter #(
    parameter integer C_S_AXI_DATA_WIDTH = 32
) (
    input  wire                              clk,
    input  wire                              rstn,

    // 9个配置寄存器 (v2.1: +2 for BSSID)
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l0_ctrl,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l1_cfg0,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l1_cfg1,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l2_cfg0,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l2_cfg1,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l2_cfg2,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l2_cfg3,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l2_cfg4,   // NEW v2.1: BSSID[31:0]
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     reg_l2_cfg5,   // NEW v2.1: BSSID[47:32] + UV@[28]

    // 帧数据输入
    input  wire [47:0]                       self_mac_addr,
    input  wire [47:0]                       self_bssid,
    input  wire                              ht_unsupport,
    input  wire                              pkt_header_valid_strobe,
    input  wire [ 1:0]                       FC_type,
    input  wire [ 3:0]                       FC_subtype,
    input  wire [ 1:0]                       FC_tofrom_ds,
    input  wire                              FC_DI_valid,
    input  wire [15:0]                       signal_len,
    input  wire                              sig_valid,
    input  wire [47:0]                       addr1,
    input  wire                              addr1_valid,
    input  wire [47:0]                       addr2,
    input  wire                              addr2_valid,
    input  wire [47:0]                       addr3,
    input  wire                              addr3_valid,

    // 过滤结果输出
    output wire                              block_rx_dma_ban_to_ps,
    output reg                               block_rx_dma_to_ps_valid,
    output wire [15:0]                       allow_rx_dma_to_ps_test,
    output wire [ 8:0]                       high_priority_discard_test,
    output wire [ 2:0]                       filter_state_test
);


// =============================================================================
// 第1部分: 常量定义
// =============================================================================

// MR/NMR结果码
localparam [1:0] RES_SUCCESS = 2'b00;   // DIRECT_SUCCESS
localparam [1:0] RES_FAIL    = 2'b01;   // DIRECT_FAIL
localparam [1:0] RES_NEXT    = 2'b10;   // MATCH_NEXT (继续同级下一项)

// f_chk_attr返回码 (用于FSM分流)
localparam [1:0] CHK_PASS = 2'b00;
localparam [1:0] CHK_FAIL = 2'b01;
localparam [1:0] CHK_NEXT = 2'b10;

// FSM状态
localparam [2:0]
    ST_IDLE     = 3'd0,
    ST_L0       = 3'd1,
    ST_L1       = 3'd2,
    ST_L2       = 3'd3,
    ST_ABNORMAL = 3'd4;   // NEW v2.1: signal_len < 14 → 直接 DROP


// =============================================================================
// 第2部分: 影子寄存器 + UPDATE_VALID (原子更新机制)
// =============================================================================
// UPDATE_VALID:
//   L0-Reg0[28], L1-Reg0[28], L1-Reg1[28] - 各自独立
//   L2-Reg0[31:28] = {L2-R3_UV, L2-R2_UV, L2-R1_UV, L2-R0_UV}
//   L2-Reg5[28]    = BSSID_UV - 同时锁存 L2-Reg4 + L2-Reg5         (NEW v2.1)

wire l0_upd_valid   = reg_l0_ctrl[28];
wire l1_0_upd_valid = reg_l1_cfg0[28];
wire l1_1_upd_valid = reg_l1_cfg1[28];
wire l2_0_upd_valid = reg_l2_cfg0[28];
wire l2_1_upd_valid = reg_l2_cfg0[29];
wire l2_2_upd_valid = reg_l2_cfg0[30];
wire l2_3_upd_valid = reg_l2_cfg0[31];
wire bssid_upd_valid = reg_l2_cfg5[28];   // NEW v2.1: BSSID UV, 同时锁存 Reg4+Reg5

reg [31:0] shdw_l0_ctrl;
reg [31:0] shdw_l1_cfg0;
reg [31:0] shdw_l1_cfg1;
reg [31:0] shdw_l2_cfg0;
reg [31:0] shdw_l2_cfg1;
reg [31:0] shdw_l2_cfg2;
reg [31:0] shdw_l2_cfg3;
reg [31:0] shdw_l2_cfg4;   // NEW v2.1
reg [31:0] shdw_l2_cfg5;   // NEW v2.1

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        shdw_l0_ctrl <= 32'd0;
        shdw_l1_cfg0 <= 32'd0;
        shdw_l1_cfg1 <= 32'd0;
        shdw_l2_cfg0 <= 32'd0;
        shdw_l2_cfg1 <= 32'd0;
        shdw_l2_cfg2 <= 32'd0;
        shdw_l2_cfg3 <= 32'd0;
        shdw_l2_cfg4 <= 32'd0;   // NEW v2.1
        shdw_l2_cfg5 <= 32'd0;   // NEW v2.1
    end else begin
        if (l0_upd_valid)    shdw_l0_ctrl <= reg_l0_ctrl;
        if (l1_0_upd_valid)  shdw_l1_cfg0 <= reg_l1_cfg0;
        if (l1_1_upd_valid)  shdw_l1_cfg1 <= reg_l1_cfg1;
        if (l2_0_upd_valid)  shdw_l2_cfg0 <= reg_l2_cfg0;
        if (l2_1_upd_valid)  shdw_l2_cfg1 <= reg_l2_cfg1;
        if (l2_2_upd_valid)  shdw_l2_cfg2 <= reg_l2_cfg2;
        if (l2_3_upd_valid)  shdw_l2_cfg3 <= reg_l2_cfg3;
        // NEW v2.1: BSSID_UV 同时锁存 Reg4 + Reg5
        if (bssid_upd_valid) begin
            shdw_l2_cfg4 <= reg_l2_cfg4;
            shdw_l2_cfg5 <= reg_l2_cfg5;
        end
    end
end


// =============================================================================
// 第3部分: 寄存器位提取 (全部使用影子值)
// =============================================================================

// ---- L0-Reg0: L0分类使能 ----
//   [0] ALL_DC  [1] EN_CTRL  [2] EN_DATA  [3] EN_MANAGE  [4] EN_USR
wire L0_ALL_DC   = shdw_l0_ctrl[0];
wire L0EN_CTRL   = shdw_l0_ctrl[1];
wire L0EN_DATA   = shdw_l0_ctrl[2];
wire L0EN_MANAGE = shdw_l0_ctrl[3];
wire L0EN_USR    = shdw_l0_ctrl[4];

// ---- L1-Reg0: CTRL子类型 + DATA子类型 ----
//   CTRL [9:0]: [0]DC [1]RTS [2]CTS [3]ACK [4]BAR [5]MTID_BAR [6]BA [7]MTID_BA [8]PS_POLL [9]CF_ABOUT
//   DATA [21:16]: [16]DC [17]BROADCAST [18]MULTICAST [19]SELF_MAC [20]UNIQUE_MAC [21]UNICAST
wire L1_CTRL_DC         = shdw_l1_cfg0[0];
wire L1EN_CTRL_RTS      = shdw_l1_cfg0[1];
wire L1EN_CTRL_CTS      = shdw_l1_cfg0[2];
wire L1EN_CTRL_ACK      = shdw_l1_cfg0[3];
wire L1EN_CTRL_BAR      = shdw_l1_cfg0[4];
wire L1EN_CTRL_MTID_BAR = shdw_l1_cfg0[5];
wire L1EN_CTRL_BA       = shdw_l1_cfg0[6];
wire L1EN_CTRL_MTID_BA  = shdw_l1_cfg0[7];
wire L1EN_CTRL_PS_POLL  = shdw_l1_cfg0[8];
wire L1EN_CTRL_CF_ABOUT = shdw_l1_cfg0[9];

wire L1_DATA_DC        = shdw_l1_cfg0[16];
wire L1ATTR_BROADCAST  = shdw_l1_cfg0[17];
wire L1ATTR_MULTICAST  = shdw_l1_cfg0[18];
wire L1ATTR_SELF_MAC   = shdw_l1_cfg0[19];
wire L1ATTR_UNIQUE_MAC = shdw_l1_cfg0[20];
wire L1ATTR_UNICAST    = shdw_l1_cfg0[21];

// ---- L1-Reg1: MANAGE子类型 + USR子类型 ----
//   MANAGE [11:0]: [0]DC [1]BEACON [2]ASSOC_REQ [3]ASSOC_REP [4]REASSOC_REQ
//                   [5]REASSOC_REP [6]DEASSOC [7]DETECT_REQ [8]DETECT_REP
//                   [9]AUTH [10]DEAUTH [11]OTHER
//   USR [21:16]: [16]DC [17]HA_MERCURY [18]HA_EHBEACON [19]HA_DATA [20]RESERVE0 [21]RESERVE1
wire L1_MANAGE_DC           = shdw_l1_cfg1[0];
wire L1EN_MANAGE_BEACON     = shdw_l1_cfg1[1];
wire L1EN_MANAGE_ASSOC_REQ  = shdw_l1_cfg1[2];
wire L1EN_MANAGE_ASSOC_REP  = shdw_l1_cfg1[3];
wire L1EN_MANAGE_REASSOC_REQ = shdw_l1_cfg1[4];
wire L1EN_MANAGE_REASSOC_REP = shdw_l1_cfg1[5];
wire L1EN_MANAGE_DEASSOC    = shdw_l1_cfg1[6];
wire L1EN_MANAGE_DETECT_REQ = shdw_l1_cfg1[7];
wire L1EN_MANAGE_DETECT_REP = shdw_l1_cfg1[8];
wire L1EN_MANAGE_AUTH       = shdw_l1_cfg1[9];
wire L1EN_MANAGE_DEAUTH     = shdw_l1_cfg1[10];
wire L1EN_MANAGE_OTHER      = shdw_l1_cfg1[11];

wire L1_USR_DC           = shdw_l1_cfg1[16];
wire L1EN_USR_HA_MERCURY = shdw_l1_cfg1[17];
wire L1EN_USR_HA_EHBEACON= shdw_l1_cfg1[18];
wire L1EN_USR_HA_DATA    = shdw_l1_cfg1[19];
wire L1EN_USR_RESERVE0   = shdw_l1_cfg1[20];
wire L1EN_USR_RESERVE1   = shdw_l1_cfg1[21];

// ---- L2-Reg0: TOUCH/MR/NMR + L2使能位 + THIS_LDC + FC_USR ----
//   [0] THIS_LDC
//   [1] TOUCH0   [3:2] MR0    [5:4] NMR0    → L0 级控制
//   [6] TOUCH1   [8:7] MR1    [10:9] NMR1    → L1 级控制
//   [11] TOUCH2  [13:12] MR2  [15:14] NMR2   → L2 级控制
//   [23:16] FC_USR[7:0]
//   [24] EN_BSSID  [25] EN_FC  [26] EN_ADDR2  [27] EN_ADDR1   (NEW v2.1)
wire        THIS_LDC    = shdw_l2_cfg0[0];
wire        TOUCH0      = shdw_l2_cfg0[1];
wire [1:0]  MR0         = shdw_l2_cfg0[3:2];
wire [1:0]  NMR0        = shdw_l2_cfg0[5:4];
wire        TOUCH1      = shdw_l2_cfg0[6];
wire [1:0]  MR1         = shdw_l2_cfg0[8:7];
wire [1:0]  NMR1        = shdw_l2_cfg0[10:9];
wire        TOUCH2      = shdw_l2_cfg0[11];
wire [1:0]  MR2         = shdw_l2_cfg0[13:12];
wire [1:0]  NMR2        = shdw_l2_cfg0[15:14];
wire [7:0]  FC_USR_VAL  = shdw_l2_cfg0[23:16];
// NEW v2.1: L2 复合匹配使能位
wire        EN_BSSID    = shdw_l2_cfg0[24];
wire        EN_FC       = shdw_l2_cfg0[25];
wire        EN_ADDR2    = shdw_l2_cfg0[26];
wire        EN_ADDR1    = shdw_l2_cfg0[27];

// ---- ADDR1/ADDR2 (字节小端连续存放) ----
//   ADDR1[31:0] = L2-Reg1[31:0]      ADDR1[47:32] = L2-Reg2[15:0]
//   ADDR2[15:0] = L2-Reg2[31:16]     ADDR2[47:16] = L2-Reg3[31:0]
wire [47:0] ADDR1;
wire [47:0] ADDR2;

assign ADDR1[31:0]  = shdw_l2_cfg1[31:0];
assign ADDR1[47:32] = shdw_l2_cfg2[15:0];

assign ADDR2[15:0]  = shdw_l2_cfg2[31:16];
assign ADDR2[47:16] = shdw_l2_cfg3[31:0];

// ---- BSSID 目标值 (NEW v2.1) ----
//   BSSID[31:0]  = L2-Reg4[31:0]
//   BSSID[47:32] = L2-Reg5[15:0]
wire [47:0] CFG_BSSID;
assign CFG_BSSID[31:0]  = shdw_l2_cfg4[31:0];
assign CFG_BSSID[47:32] = shdw_l2_cfg5[15:0];


// =============================================================================
// 第4部分: 属性检查函数 f_chk_attr
//
//   匹配逻辑 (按优先级):
//     1. DONTTOUCH (TOUCH=0)         → 跳过本级, 继续同级下一项 → CHK_NEXT
//     2. DISABLE   (TOUCH=1, 条件满足→MR=01) → CHK_FAIL
//     3. DONTCARE  (TOUCH=1, 条件满足→MR=00) → CHK_PASS
//     4. NEXTLEVEL (TOUCH=1, 条件满足→MR=10) → CHK_NEXT
//     5. TOUCH     (TOUCH=1, MR≠NMR) → 满足用MR, 不满足用NMR
//
//   寄存器编码: 可通过MR/NMR值组合实现所有模式:
//     DONTCARE  = MR=00,NMR=00 (无论条件, 始终PASS)
//     DISABLE   = MR=01,NMR=01 (无论条件, 始终FAIL)
//     NEXTLEVEL = MR=10,NMR=10 (无论条件, 始终NEXT)
// =============================================================================
function [1:0] f_chk_attr;
    input       touch;
    input [1:0] mr;
    input [1:0] nmr;
    input       match;
    reg [1:0]   res;
    begin
        if (!touch) begin
            f_chk_attr = CHK_NEXT;                     // DONTTOUCH
        end else begin
            res = match ? mr : nmr;
            case (res)
                RES_SUCCESS: f_chk_attr = CHK_PASS;
                RES_FAIL:    f_chk_attr = CHK_FAIL;
                RES_NEXT:    f_chk_attr = CHK_NEXT;
                default:     f_chk_attr = CHK_FAIL;
            endcase
        end
    end
endfunction


// =============================================================================
// 第5部分: 帧数据锁存
// =============================================================================
reg [47:0] r_addr1, r_addr2, r_addr3;
reg        r_addr1_v, r_addr2_v, r_addr3_v;
reg [ 1:0] r_FC_type;
reg [ 3:0] r_FC_subtype;
reg [ 1:0] r_FC_tofrom_ds;

// NEW v2.1: BSSID 提取寄存器 (参考原 pkt_filter_ctl.v)
reg [47:0] r_bssid;
reg        r_bssid_v;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        r_addr1        <= 48'd0;
        r_addr2        <= 48'd0;
        r_addr3        <= 48'd0;
        r_addr1_v      <= 1'b0;
        r_addr2_v      <= 1'b0;
        r_addr3_v      <= 1'b0;
        r_FC_type      <= 2'd0;
        r_FC_subtype   <= 4'd0;
        r_FC_tofrom_ds <= 2'd0;
        r_bssid        <= 48'd0;        // NEW v2.1
        r_bssid_v      <= 1'b0;         // NEW v2.1
    end else begin
        // 新帧到来时清除有效标志
        // NEW v2.1: 同时清除 BSSID 有效标志
        if (pkt_header_valid_strobe) begin
            r_addr1_v <= 1'b0;
            r_addr2_v <= 1'b0;
            r_addr3_v <= 1'b0;
            r_bssid_v <= 1'b0;            // NEW v2.1
        end
        if (addr1_valid) begin r_addr1 <= addr1; r_addr1_v <= 1'b1; end
        if (addr2_valid) begin r_addr2 <= addr2; r_addr2_v <= 1'b1; end
        if (addr3_valid) begin r_addr3 <= addr3; r_addr3_v <= 1'b1; end
        if (FC_DI_valid) begin
            r_FC_type      <= FC_type;
            r_FC_subtype   <= FC_subtype;
            r_FC_tofrom_ds <= FC_tofrom_ds;
        end

        // NEW v2.1: BSSID 提取 - 根据 FC_tofrom_ds 从对应地址字段抓取 BSSID
        // 参考 802.11 标准 + 原 pkt_filter_ctl.v 逻辑:
        //   From DS (2'b10): BSSID = addr1
        //   To DS   (2'b01): BSSID = addr2
        //   Ad-hoc  (2'b00): BSSID = addr3
        //   Mesh    (2'b11): 不提取
        if (addr1_valid && r_FC_tofrom_ds == 2'b10) begin
            r_bssid   <= addr1;
            r_bssid_v <= 1'b1;
        end
        if (addr2_valid && r_FC_tofrom_ds == 2'b01) begin
            r_bssid   <= addr2;
            r_bssid_v <= 1'b1;
        end
        if (addr3_valid && r_FC_tofrom_ds == 2'b00) begin
            r_bssid   <= addr3;
            r_bssid_v <= 1'b1;
        end
    end
end

wire [7:0] fc_usr_val = {r_FC_type, r_FC_subtype, r_FC_tofrom_ds};


// =============================================================================
// 第6部分: L1 子类型命中 (帧解析 + 使能位组合)
// =============================================================================

// 帧大类识别
wire is_ctrl = (FC_type == 2'b01);
wire is_data = (FC_type == 2'b10);
wire is_mgmt = (FC_type == 2'b00);

// ---- CTRL子类型判定 ----
wire hit_rts        = is_ctrl && (FC_subtype == 4'b1011);
wire hit_cts        = is_ctrl && (FC_subtype == 4'b1100);
wire hit_ack        = is_ctrl && (FC_subtype == 4'b1101);
wire hit_bar        = is_ctrl && (FC_subtype == 4'b1000);
wire hit_ba         = is_ctrl && (FC_subtype == 4'b1001);
wire hit_ps_poll    = is_ctrl && (FC_subtype == 4'b1010);
wire hit_cf_end     = is_ctrl && (FC_subtype == 4'b1110);
wire hit_cf_end_ack = is_ctrl && (FC_subtype == 4'b1111);
wire hit_cf_about   = hit_cf_end || hit_cf_end_ack;

// ---- DATA地址分类 ----
wire addr_bc_one = (addr1 == 48'hFFFF_FFFF_FFFF);
wire addr_mc     = (addr1[47:24] == 24'h01005E) || (addr1[47:32] == 16'h3333);
wire addr_self   = (addr1 == self_mac_addr);

// ---- MANAGE子类型判定 ----
wire hit_beacon       = is_mgmt && (FC_subtype == 4'b1000);
wire hit_assoc_req    = is_mgmt && (FC_subtype == 4'b0000);
wire hit_assoc_resp   = is_mgmt && (FC_subtype == 4'b0001);
wire hit_reassoc_req  = is_mgmt && (FC_subtype == 4'b0010);
wire hit_reassoc_resp = is_mgmt && (FC_subtype == 4'b0011);
wire hit_disassoc     = is_mgmt && (FC_subtype == 4'b1010);
wire hit_auth         = is_mgmt && (FC_subtype == 4'b1011);
wire hit_deauth       = is_mgmt && (FC_subtype == 4'b1100);
wire hit_detect_req   = is_mgmt && (FC_subtype == 4'b0110);
wire hit_detect_rep   = is_mgmt && (FC_subtype == 4'b0111);
wire hit_mgmt_other   = is_mgmt && !hit_assoc_req  && !hit_assoc_resp &&
                        !hit_reassoc_req && !hit_reassoc_resp &&
                        !hit_beacon      && !hit_disassoc &&
                        !hit_auth        && !hit_deauth &&
                        !hit_detect_req  && !hit_detect_rep;

// ---- L1命中信号 (子类型 × 使能位) ----
wire l1_hit_ctrl =
    (L1EN_CTRL_RTS      && hit_rts)     ||
    (L1EN_CTRL_CTS      && hit_cts)     ||
    (L1EN_CTRL_ACK      && hit_ack)     ||
    (L1EN_CTRL_BAR      && hit_bar)     ||
    (L1EN_CTRL_MTID_BAR && hit_bar)     ||
    (L1EN_CTRL_BA       && hit_ba)      ||
    (L1EN_CTRL_MTID_BA  && hit_ba)      ||
    (L1EN_CTRL_PS_POLL  && hit_ps_poll) ||
    (L1EN_CTRL_CF_ABOUT && hit_cf_about);

wire l1_hit_data =
    (L1ATTR_BROADCAST  && is_data && addr_bc_one)  ||
    (L1ATTR_MULTICAST  && is_data && addr_mc && !addr_bc_one) ||
    (L1ATTR_SELF_MAC   && is_data && addr_self)   ||
    (L1ATTR_UNIQUE_MAC && is_data && !addr_self && !addr_mc && !addr_bc_one) ||
    (L1ATTR_UNICAST    && is_data && !addr_bc_one && !addr_mc);

wire l1_hit_mgmt =
    (L1EN_MANAGE_BEACON      && hit_beacon)       ||
    (L1EN_MANAGE_ASSOC_REQ   && hit_assoc_req)    ||
    (L1EN_MANAGE_ASSOC_REP   && hit_assoc_resp)   ||
    (L1EN_MANAGE_REASSOC_REQ && hit_reassoc_req)  ||
    (L1EN_MANAGE_REASSOC_REP && hit_reassoc_resp) ||
    (L1EN_MANAGE_DEASSOC     && hit_disassoc)     ||
    (L1EN_MANAGE_DETECT_REQ  && hit_detect_req)   ||
    (L1EN_MANAGE_DETECT_REP  && hit_detect_rep)   ||
    (L1EN_MANAGE_AUTH        && hit_auth)         ||
    (L1EN_MANAGE_DEAUTH      && hit_deauth)       ||
    (L1EN_MANAGE_OTHER       && hit_mgmt_other);

wire l1_hit_usr =
    L0EN_USR && (
        L1EN_USR_HA_MERCURY  ||
        L1EN_USR_HA_EHBEACON ||
        L1EN_USR_HA_DATA     ||
        L1EN_USR_RESERVE0    ||
        L1EN_USR_RESERVE1);

wire l1_hit = l1_hit_ctrl || l1_hit_data || l1_hit_mgmt || l1_hit_usr;


// =============================================================================
// 第7部分: 各级匹配条件 + TOUCH判定
// =============================================================================

// ---- L0: 帧大类匹配 → TOUCH0 判定 (v2.1: 恢复 TOUCH0 归属 L0) ----
wire       l0_match = (is_ctrl && L0EN_CTRL)  ||
                      (is_data && L0EN_DATA)  ||
                      (is_mgmt && L0EN_MANAGE)||
                      L0EN_USR;
wire [1:0] r_l0     = f_chk_attr(TOUCH0, MR0, NMR0, l0_match);

// ---- L1: L1_DC旁路 + 子类型匹配 → TOUCH1 判定 (v2.1: 恢复 TOUCH1 归属 L1) ----
wire l1_dc = (is_ctrl && L1_CTRL_DC)   ||
             (is_data && L1_DATA_DC)   ||
             (is_mgmt && L1_MANAGE_DC) ||
             (L0EN_USR && L1_USR_DC);
wire [1:0] r_l1 = f_chk_attr(TOUCH1, MR1, NMR1, l1_hit);

// ---- L2: 复合匹配 → TOUCH2 判定 (v2.1: TOUCH2 控制 L2 级) ----
//   四个子功能通过使能位控制参与 (未使能的子功能视为无条件满足)
//   NEW v2.1: 增加 BSSID 匹配
wire addr1_match = r_addr1_v && (r_addr1 == ADDR1);
wire addr2_match = r_addr2_v && (r_addr2 == ADDR2);
wire fc_match    = (fc_usr_val == FC_USR_VAL);
// NEW v2.1: BSSID 匹配 - r_bssid 从帧中提取 (根据 tofrom_ds), CFG_BSSID 为配置目标值
wire bssid_match = r_bssid_v && (r_bssid == CFG_BSSID);

// L2 复合匹配: 四个子功能 AND (未使能→视为 1)
wire l2_match = (EN_ADDR1 ? addr1_match : 1'b1)
              & (EN_ADDR2 ? addr2_match : 1'b1)
              & (EN_FC    ? fc_match    : 1'b1)
              & (EN_BSSID ? bssid_match : 1'b1);
wire [1:0] r_l2 = f_chk_attr(TOUCH2, MR2, NMR2, l2_match);


// =============================================================================
// 第8部分: 主过滤状态机
//
//   流程: IDLE → L0 → L1 → L2 → 输出
//   NEW v2.1: signal_len < 14 → ST_ABNORMAL → DROP
//
//   每级DC优先级链 (高于TOUCH):
//     L0: L0_ALL_DC → PASS
//     L1: L1_xx_DC  → PASS
//     L2: THIS_LDC  → PASS
//
//   末级处理: 非L2级的 NEXT → 进入下一级; L2 末级 NEXT → PASS
// =============================================================================

reg  [2:0] state;
reg        frame_pending;
reg        filter_pass;

assign block_rx_dma_ban_to_ps = block_rx_dma_to_ps_valid & (~filter_pass);
assign allow_rx_dma_to_ps_test = {15'd0, filter_pass};
assign high_priority_discard_test = 9'd0;
assign filter_state_test = state;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state                    <= ST_IDLE;
        frame_pending            <= 1'b0;
        filter_pass              <= 1'b0;
        block_rx_dma_to_ps_valid <= 1'b0;
    end else begin
        block_rx_dma_to_ps_valid <= 1'b0;

        case (state)

            // ---- IDLE: 等待帧头锁存 ----
            ST_IDLE: begin
                if (pkt_header_valid_strobe && !ht_unsupport) begin
                    // NEW v2.1: signal_len < 14 → 异常帧, 直接丢弃 (参考原 pkt_filter_ctl.v)
                    if (signal_len < 14) begin
                        filter_pass <= 1'b0;
                        block_rx_dma_to_ps_valid <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        frame_pending <= 1'b1;
                        filter_pass   <= 1'b0;
                    end
                end
                if (frame_pending && r_addr1_v) begin
                    frame_pending <= 1'b0;
                    state <= ST_L0;
                end
            end

            // ---- L0: 帧大类 (L0_ALL_DC > TOUCH0) ----
            ST_L0: begin
                if (L0_ALL_DC) begin
                    filter_pass <= 1'b1;
                    block_rx_dma_to_ps_valid <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    case (r_l0)
                        CHK_PASS: begin
                            filter_pass <= 1'b1;
                            block_rx_dma_to_ps_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                        CHK_FAIL: begin
                            filter_pass <= 1'b0;
                            block_rx_dma_to_ps_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                        default: state <= ST_L1;   // CHK_NEXT → 下一级
                    endcase
                end
            end

            // ---- L1: 子类型 (L1_DC > TOUCH1) ----
            ST_L1: begin
                if (l1_dc) begin
                    filter_pass <= 1'b1;
                    block_rx_dma_to_ps_valid <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    case (r_l1)
                        CHK_PASS: begin
                            filter_pass <= 1'b1;
                            block_rx_dma_to_ps_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                        CHK_FAIL: begin
                            filter_pass <= 1'b0;
                            block_rx_dma_to_ps_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                        default: state <= ST_L2;   // CHK_NEXT → 下一级
                    endcase
                end
            end

            // ---- L2: 复合匹配 (THIS_LDC > TOUCH2) ----
            //   末级: NEXT → PASS
            ST_L2: begin
                if (THIS_LDC) begin
                    filter_pass <= 1'b1;
                    block_rx_dma_to_ps_valid <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    case (r_l2)
                        CHK_PASS: begin
                            filter_pass <= 1'b1;
                            block_rx_dma_to_ps_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                        CHK_FAIL: begin
                            filter_pass <= 1'b0;
                            block_rx_dma_to_ps_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                        default: begin   // CHK_NEXT → 末级, 等同于 PASS
                            filter_pass <= 1'b1;
                            block_rx_dma_to_ps_valid <= 1'b1;
                            state <= ST_IDLE;
                        end
                    endcase
                end
            end

            // ---- ABNORMAL: signal_len < 14 → 直接丢弃 (NEW v2.1) ----
            ST_ABNORMAL: begin
                filter_pass <= 1'b0;
                block_rx_dma_to_ps_valid <= 1'b1;
                state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

// =============================================================================
// ILA Debug - 16 个独立探针, 每个信号/信号组独立可读
//
// Vivado Tcl (先创建 ILA IP):
//   create_debug_core u_ila_filter ila -properties {
//     C_DATA_DEPTH=4096 C_EN_STRG_QUAL=1
//     C_PROBE0_WIDTH=3  C_PROBE1_WIDTH=1  C_PROBE2_WIDTH=1
//     C_PROBE3_WIDTH=1  C_PROBE4_WIDTH=2  C_PROBE5_WIDTH=1
//     C_PROBE6_WIDTH=1  C_PROBE7_WIDTH=2  C_PROBE8_WIDTH=1
//     C_PROBE9_WIDTH=2  C_PROBE10_WIDTH=4 C_PROBE11_WIDTH=5
//     C_PROBE12_WIDTH=5 C_PROBE13_WIDTH=5 C_PROBE14_WIDTH=5
//     C_PROBE15_WIDTH=4 C_PROBE16_WIDTH=4 C_PROBE17_WIDTH=5
//     C_PROBE18_WIDTH=7}
// =============================================================================

// synthesis translate_off
// ILA not available in simulation - skipped for ModelSim
// synthesis translate_on
ila_filter u_ila_filter (
    .clk        (clk),

    // ── FSM & 判决 ──
    .probe0     (state),                    // [2:0] IDLE/L0/L1/L2/ABNORMAL
    .probe1     (frame_pending),            // 帧处理中
    .probe2     (filter_pass),              // 1=PASS  0=DROP

    // ── L0 管道 ──
    .probe3     (l0_match),                 // L0 帧大类匹配
    .probe4     (r_l0),                     // [1:0] L0 TOUCH: PASS/FAIL/NEXT

    // ── L1 管道 ──
    .probe5     (l1_dc),                    // L1 旁路
    .probe6     (l1_hit),                   // L1 子类型命中
    .probe7     (r_l1),                     // [1:0] L1 TOUCH: PASS/FAIL/NEXT

    // ── L2 管道 ──
    .probe8     (l2_match),                 // L2 复合匹配
    .probe9     (r_l2),                     // [1:0] L2 TOUCH: PASS/FAIL/NEXT
    .probe10    ({addr1_match,              // ADDR1 对比
                  addr2_match,              // ADDR2 对比
                  fc_match,                 // FC   对比
                  bssid_match}),            // BSSID对比 (v2.1)

    // ── L0 配置 ──
    .probe11    ({L0_ALL_DC,                // L0 全旁路
                  L0EN_CTRL,                // 控制帧使能
                  L0EN_DATA,                // 数据帧使能
                  L0EN_MANAGE,              // 管理帧使能
                  L0EN_USR}),               // 用户帧使能

    // ── L0 TOUCH 配置 ──
    .probe12    ({TOUCH0, MR0, NMR0}),      // {使能, 命中动作, 未命中动作}

    // ── L1 TOUCH 配置 ──
    .probe13    ({TOUCH1, MR1, NMR1}),

    // ── L2 TOUCH 配置 ──
    .probe14    ({TOUCH2, MR2, NMR2}),

    // ── L2 使能 ──
    .probe15    ({THIS_LDC,                 // L2 全旁路
                  EN_ADDR1,                 // 使能 ADDR1 匹配
                  EN_ADDR2,                 // 使能 ADDR2 匹配
                  EN_BSSID}),               // 使能 BSSID 匹配 (v2.1)

    // ── L1 命中细节 ──
    .probe16    ({l1_hit_ctrl,              // CTRL 子类型命中
                  l1_hit_data,              // DATA 地址属性命中
                  l1_hit_mgmt,              // MANAGE 子类型命中
                  l1_hit_usr}),             // USR   子类型命中

    // ── 帧地址有效标志 ──
    .probe17    ({r_addr1_v,                // addr1 已锁存
                  r_addr2_v,                // addr2 已锁存
                  r_bssid_v,                // BSSID 提取成功
                  r_FC_tofrom_ds}),         // [1:0] BSSID 来源方向

    // ── 帧类型信息 ──
    .probe18    ({is_ctrl,                  // =1: 控制帧
                  is_data,                  // =1: 数据帧
                  is_mgmt,                  // =1: 管理帧
                  FC_subtype})              // [3:0] 802.11 子类型码
);

endmodule
