// filter.v v2.1 testbench -- 22 tests
`timescale 1 ns / 1 ps

module tb_filter;
    reg clk=0, rstn=0;
    reg [31:0] rL0, rL1_0, rL1_1, rL2_0, rL2_1, rL2_2, rL2_3, rL2_4, rL2_5;
    reg [47:0] mac=48'hAABB_CCDD_EEFF, bssid_self=48'h1122_3344_5566;
    reg ht=0, hdr=0;
    reg [1:0] fct=0, fcds=0;
    reg [3:0] fcs=0;
    reg fcdi=0;
    reg [15:0] slen=14;
    reg [47:0] a1=0, a2=0, a3=0;
    reg a1v=0, a2v=0, a3v=0;
    wire ban, valid;
    wire [2:0] st;
    integer pass=0, fail=0, w;
    `define UV 28
    `define UV 28
    `define L2_UV_ALL (4'hF << 28)
    `define L0_ALL_DC 0
    `define L0_CTRL 1
    `define L0_DATA 2
    `define L0_MGMT 3
    `define L0_USR 4
    `define L1_PS_POLL 8
    `define L1_DBROAD 17
    `define L1_DMULTI 18
    `define L1_DSELF 19
    `define L1_DUNI 21
    `define L1_MBEACON 1
    `define L1_MDETREQ 7
    `define L1_MDETREP 8
    `define L2_THIS 0
    `define L2_T0 1
    `define L2_MR0 2
    `define L2_NMR0 4
    `define L2_T1 6
    `define L2_MR1 7
    `define L2_NMR1 9
    `define L2_T2 11
    `define L2_MR2 12
    `define L2_NMR2 14
    `define L2_FCL 16
    `define L2_ENB 24
    `define L2_ENF 25
    `define L2_ENA2 26
    `define L2_ENA1 27
    `define FC_MGMT 2'd0
    `define FC_CTRL 2'd1
    `define FC_DATA 2'd2
    `define PASS 2'd0
    `define FAIL 2'd1
    `define NEXT 2'd2

    pkt_filter #(32) dut(.clk(clk),.rstn(rstn),
        .reg_l0_ctrl(rL0),.reg_l1_cfg0(rL1_0),.reg_l1_cfg1(rL1_1),
        .reg_l2_cfg0(rL2_0),.reg_l2_cfg1(rL2_1),.reg_l2_cfg2(rL2_2),.reg_l2_cfg3(rL2_3),
        .reg_l2_cfg4(rL2_4),.reg_l2_cfg5(rL2_5),
        .self_mac_addr(mac),.self_bssid(bssid_self),.ht_unsupport(ht),
        .pkt_header_valid_strobe(hdr),.FC_type(fct),.FC_subtype(fcs),.FC_tofrom_ds(fcds),
        .FC_DI_valid(fcdi),.signal_len(slen),.sig_valid(1'b0),
        .addr1(a1),.addr1_valid(a1v),.addr2(a2),.addr2_valid(a2v),.addr3(a3),.addr3_valid(a3v),
        .block_rx_dma_ban_to_ps(ban),.block_rx_dma_to_ps_valid(valid),.filter_state_test(st),
        .allow_rx_dma_to_ps_test(),.high_priority_discard_test());

    always #5 clk=~clk;
    task check; input [255:0] d; input e;
    begin w=0; while(!valid && w<12) begin @(posedge clk); w=w+1; end
    if(valid && !ban && e) begin $display(" [PASS] %0s",d); pass=pass+1; end
    else if(valid && ban && !e) begin $display(" [PASS] %0s",d); pass=pass+1; end
    else begin $display(" [FAIL] %0s (v=%0d ban=%0d exp=%0d st=%0d)",d,valid,ban,e,st); fail=fail+1; end
    end endtask

    task wr; input [31:0] a0,a1,a2,a3,a4,a5,a6,a7,a8;
    begin
    rL0<=a0&~(1<<`UV); rL1_0<=a1&~(1<<`UV); rL1_1<=a2&~(1<<`UV);
    rL2_1<=a4; rL2_2<=a5; rL2_3<=a6;
    rL2_4<=a7; rL2_5<=a8&~(1<<`UV);
    rL2_0<=a3&~(`L2_UV_ALL); @(posedge clk);
    rL0<=a0|(1<<`UV); rL1_0<=a1|(1<<`UV); rL1_1<=a2|(1<<`UV);
    rL2_5<=a8|(1<<`UV);
    rL2_0<=a3|(`L2_UV_ALL); @(posedge clk);
    end endtask

    task sframe; input [1:0] ft; input [3:0] fs; input [47:0] ad1; input [47:0] ad2;
    begin @(posedge clk); hdr<=1; fct<=ft; fcs<=fs; fcds<=0; fcdi<=1;
    slen<=(ft==`FC_CTRL)?14:20; a1<=ad1; a1v<=1; a2<=ad2; a2v<=1;
    @(posedge clk); hdr<=0; fcdi<=0; a1v<=0; a2v<=0; end endtask

    initial begin
        rL0=0; rL1_0=0; rL1_1=0; rL2_0=0; rL2_1=0; rL2_2=0; rL2_3=0; rL2_4=0; rL2_5=0;
        repeat(5) @(posedge clk); rstn=1; repeat(2) @(posedge clk);
        $display("--- T01: Reset ---");
        sframe(`FC_DATA,0,mac,0); check("[T01] Reset: TOUCH=0 DONTTOUCH -> PASS",1);

        $display("--- T02-T03: UV protocol ---");
        rL0<= (1<<`L0_ALL_DC)&~(1<<`UV); @(posedge clk);
        sframe(`FC_DATA,0,mac,0); check("[T02] UV=0: shadow=0 (TOUCH=0) -> PASS",1);
        rL0<= (1<<`L0_ALL_DC)|(1<<`UV); @(posedge clk);
        sframe(`FC_DATA,0,mac,0); check("[T03] UV=1 -> PASS",1);

        $display("--- T04: DEFAULT ---");
        wr( ((1<<`L0_CTRL)|(1<<`L0_DATA)|(1<<`L0_MGMT)),
            ((1<<`L1_PS_POLL)|(1<<`L1_DBROAD)|(1<<`L1_DMULTI)|(1<<`L1_DSELF)),
            ((1<<`L1_MBEACON)|(1<<`L1_MDETREQ)|(1<<`L1_MDETREP)),
            ((1<<`L2_THIS)|(1<<`L2_T0)|(`NEXT<<`L2_MR0)|(`FAIL<<`L2_NMR0)|(1<<`L2_T1)|(`NEXT<<`L2_MR1)|(`FAIL<<`L2_NMR1)|(0<<`L2_T2)|(`FAIL<<`L2_MR2)|(`FAIL<<`L2_NMR2)|(0<<`L2_FCL)|(0<<`L2_ENB)|(0<<`L2_ENF)|(0<<`L2_ENA2)|(0<<`L2_ENA1)),
            0,0,0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T04] DEFAULT -> PASS",1);

        $display("--- T05-T08: Subtype ---");
        sframe(`FC_CTRL,10,48'hFFFF_FFFF_FFFF,0); check("[T05] PS_POLL -> PASS",1);
        sframe(`FC_MGMT,8,48'hFFFF_FFFF_FFFF,0); check("[T06] BEACON -> PASS",1);
        sframe(`FC_MGMT,6,48'hFFFF_FFFF_FFFF,0); check("[T07] PROBE_REQ -> PASS",1);
        sframe(`FC_CTRL,13,48'hAABB_CCDD_EEFF,0); check("[T08] ACK -> BLOCK",0);

        $display("--- T09: BLOCKALL ---");
        wr(0,0,0,((1<<`L2_T0)|(`FAIL<<`L2_MR0)|(`FAIL<<`L2_NMR0)|(1<<`L2_T1)|(`FAIL<<`L2_MR1)|(`FAIL<<`L2_NMR1)|(1<<`L2_T2)|(`FAIL<<`L2_MR2)|(`FAIL<<`L2_NMR2)),0,0,0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T09] BLOCKALL -> BLOCKED",0);

        $display("--- T10: L0_ALL_DC ---");
        wr((1<<`L0_ALL_DC),0,0,0,0,0,0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T10] ALL_DC -> PASS",1);

        $display("--- T11: L1 CTRL_DC ---");
        wr((1<<`L0_CTRL),(1<<0),0,0,0,0,0,0,0);
        sframe(`FC_CTRL,13,0,0); check("[T11] CTRL_DC -> PASS",1);

        $display("--- T12: L1 DATA_DC ---");
        wr((1<<`L0_DATA),(1<<16),0,0,0,0,0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T12] DATA_DC -> PASS",1);

        $display("--- T13-T14: L2 ADDR1 ---");
        wr((1<<`L0_DATA),(1<<`L1_DSELF),0,((0<<`L2_THIS)|(0<<`L2_T0)|(0<<`L2_T1)|(1<<`L2_T2)|(`PASS<<`L2_MR2)|(`FAIL<<`L2_NMR2)|(0<<`L2_FCL)|(0<<`L2_ENB)|(0<<`L2_ENF)|(0<<`L2_ENA2)|(1<<`L2_ENA1)),mac[31:0],{16'd0,mac[47:32]},0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T13] ADDR1 match -> PASS",1);
        wr((1<<`L0_DATA),(1<<`L1_DSELF),0,((0<<`L2_THIS)|(0<<`L2_T0)|(0<<`L2_T1)|(1<<`L2_T2)|(`PASS<<`L2_MR2)|(`FAIL<<`L2_NMR2)|(0<<`L2_FCL)|(0<<`L2_ENB)|(0<<`L2_ENF)|(0<<`L2_ENA2)|(1<<`L2_ENA1)),48'hDEAD_BEEF_0000,{16'h0000,16'hDEAD},0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T14] ADDR1 mismatch -> FAIL",0);

        $display("--- T15: L2 ADDR2 ---");
        wr((1<<`L0_DATA),(1<<`L1_DSELF),0,((0<<`L2_THIS)|(0<<`L2_T0)|(0<<`L2_T1)|(1<<`L2_T2)|(`PASS<<`L2_MR2)|(`FAIL<<`L2_NMR2)|(0<<`L2_FCL)|(0<<`L2_ENB)|(0<<`L2_ENF)|(1<<`L2_ENA2)|(0<<`L2_ENA1)),0,{16'h0000,16'h0000},32'hCAFE_BEEF,0,0);
        sframe(`FC_DATA,0,mac,48'hCAFE_BEEF_0000); check("[T15] ADDR2 match -> PASS",1);

        $display("--- T16: L2 FC ---");
        wr((1<<`L0_DATA),(1<<`L1_DSELF),0,((0<<`L2_THIS)|(0<<`L2_T0)|(0<<`L2_T1)|(1<<`L2_T2)|(`PASS<<`L2_MR2)|(`FAIL<<`L2_NMR2)|(8'h80<<`L2_FCL)|(0<<`L2_ENB)|(1<<`L2_ENF)|(0<<`L2_ENA2)|(0<<`L2_ENA1)),0,0,0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T16] FC match -> PASS",1);

        $display("--- T17: ADDR1 OK + ADDR2 FAIL ---");
        wr((1<<`L0_DATA),(1<<`L1_DSELF),0,((0<<`L2_THIS)|(0<<`L2_T0)|(0<<`L2_T1)|(1<<`L2_T2)|(`PASS<<`L2_MR2)|(`FAIL<<`L2_NMR2)|(0<<`L2_FCL)|(0<<`L2_ENB)|(0<<`L2_ENF)|(1<<`L2_ENA2)|(1<<`L2_ENA1)),mac[31:0],{16'd0,mac[47:32]},48'hDEAD_0000_0001,0,0);
        sframe(`FC_DATA,0,mac,48'd0); check("[T17] ADDR1 OK + ADDR2 FAIL -> DROP",0);

        $display("--- T18-T19: DONTCARE/DONTTOUCH ---");
        wr((1<<`L0_DATA),(1<<`L1_DSELF),0,((0<<`L2_THIS)|(0<<`L2_T0)|(0<<`L2_T1)|(1<<`L2_T2)|(`PASS<<`L2_MR2)|(`PASS<<`L2_NMR2)),0,0,0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T18] DONTCARE -> PASS",1);
        wr((1<<`L0_DATA),(1<<`L1_DSELF),0,(0<<`L2_THIS)|(0<<`L2_T2),0,0,0,0,0);
        sframe(`FC_DATA,0,mac,0); check("[T19] DONTTOUCH -> PASS",1);

        $display("--- T20: ht_unsupport ---");
        wr((1<<`L0_ALL_DC),0,0,0,0,0,0,0,0);
        @(posedge clk); ht<=1; hdr<=1; fct<=2; fcdi<=1; a1<=mac; a1v<=1; slen<=14;
        @(posedge clk); hdr<=0; fcdi<=0; a1v<=0; ht<=0;
        repeat(5) @(posedge clk);
        if(!valid) begin $display(" [PASS] [T20] ht_unsupport"); pass=pass+1; end
        else begin $display(" [FAIL] [T20]"); fail=fail+1; end

        $display("--- T21: L0 no match ---");
        wr((1<<`L0_CTRL)|(1<<`L0_DATA),(1<<0),0,0,0,0,0,0,0);
        sframe(`FC_MGMT,8,48'hFFFF_FFFF_FFFF,0); check("[T21] MGMT (TOUCH=0 DONTTOUCH) -> PASS",1);

        $display("--- T22: signal_len<14 ABNORMAL (v2.1 NEW) ---");
        wr((1<<`L0_ALL_DC),0,0,0,0,0,0,0,0);
        @(posedge clk); hdr<=1; fct<=2; fcdi<=1; a1<=mac; a1v<=1; slen<=10;
        @(posedge clk); hdr<=0; fcdi<=0; a1v<=0;
        check("[T22] slen<14 -> DROP",0);

        $display("\n==== TEST SUMMARY: %0d PASS, %0d FAIL ====", pass, fail);
        if(fail>0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $stop;
    end
endmodule
