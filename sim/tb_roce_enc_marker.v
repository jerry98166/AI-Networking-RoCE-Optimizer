`timescale 1ns/1ps
module tb_roce_ecn_marker();
    reg clk, rst_n, congestion_trigger;
    reg [127:0] s_tdata;
    reg [15:0] s_tkeep;
    reg s_tvalid, s_tlast;
    wire m_tready = 1;
    wire [127:0] m_tdata;
    wire m_tvalid, m_tlast, s_tready;

    roce_ecn_marker uut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tkeep(s_tkeep), .s_axis_tvalid(s_tvalid), .s_axis_tlast(s_tlast), .s_axis_tready(s_tready),
        .congestion_trigger(congestion_trigger),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tlast(m_tlast), .m_axis_tready(m_tready)
    );

    initial begin
        clk = 0; rst_n = 0; congestion_trigger = 0; s_tvalid = 0; s_tlast = 0; s_tkeep = 16'hFFFF;
        #20 rst_n = 1;

        #10 congestion_trigger = 1;

        #10 s_tvalid = 1;
        s_tdata = 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0800_4500;
        
        #10 s_tdata = 128'h12B7_0000_0000_0000_0000_0000_0000_0000;
        
        #10 s_tlast = 1; s_tdata = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
        
        #10 s_tvalid = 0; s_tlast = 0; congestion_trigger = 0;
        #100 $finish;
    end
    always #5 clk = ~clk;
endmodule