module roce_ecn_marker (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_axis_tdata,
    input  wire [15:0]  s_axis_tkeep,   // <-- 這次絕對有這行了！
    input  wire         s_axis_tvalid,
    input  wire         s_axis_tlast,
    output wire         s_axis_tready,
    input  wire         congestion_trigger,
    output reg  [127:0] m_axis_tdata,
    output reg          m_axis_tvalid,
    output reg          m_axis_tlast,
    input  wire         m_axis_tready
);

    reg [1:0] state;
    localparam ST_IDLE = 0, ST_HDR = 1, ST_DATA = 2;
    assign s_axis_tready = m_axis_tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            m_axis_tvalid <= 0;
            m_axis_tlast <= 0;
            m_axis_tdata <= 128'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        m_axis_tdata <= s_axis_tdata;
                        
                        // 檢查 EtherType 是否為 IPv4 (0x0800)
                        if (s_axis_tdata[31:16] == 16'h0800) begin
                            if (congestion_trigger) 
                                m_axis_tdata[1:0] <= 2'b11; 
                        end
                        
                        state <= ST_HDR;
                        m_axis_tvalid <= 1;
                        m_axis_tlast <= s_axis_tlast;
                    end else begin
                        m_axis_tvalid <= 0;
                    end
                end
                ST_HDR: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        m_axis_tdata <= s_axis_tdata;
                        m_axis_tvalid <= 1;
                        m_axis_tlast <= s_axis_tlast;
                        if (s_axis_tlast) state <= ST_IDLE;
                        else state <= ST_DATA;
                    end
                end
                ST_DATA: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        m_axis_tdata <= s_axis_tdata;
                        m_axis_tvalid <= 1;
                        m_axis_tlast <= s_axis_tlast;
                        if (s_axis_tlast) state <= ST_IDLE;
                    end
                end
            endcase
        end
    end
endmodule