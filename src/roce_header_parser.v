// ==================================================================================
// 文件：roce_header_parser.v
// 功能：解析RoCE v2協議報頭
// 時間戳：2026-03-25
// 作者：您的姓名
// 
// 說明：
//   该模塊接收原始以太網數據包，提取RoCE v2協議的關鍵字段
//   輸出是否為RoCE數據包，以及各個報頭字段信息
//
// 接口：
//   - AXI-Stream輸入 (128位寬)
//   - AXI-Stream輸出 (128位寬，低延遲通過)
//   - 協議字段提取輸出
// ==================================================================================

`timescale 1ns/1ps

module roce_header_parser (
    // ============ 系統信號 ============
    input  wire         clk,        // 系統時鐘 (100MHz)
    input  wire         rst_n,      // 低電平復位
    
    // ============ AXI-Stream 輸入接口 ============
    input  wire [127:0] s_axis_tdata,    // 輸入數據 (16字節)
    input  wire [15:0]  s_axis_tkeep,    // 字節有效掩碼
    input  wire         s_axis_tvalid,   // 輸入有效
    input  wire         s_axis_tlast,    // 幀最後字
    output reg          s_axis_tready,   // 輸入就緒
    
    // ============ AXI-Stream 輸出接口 ============
    output reg  [127:0] m_axis_tdata,    // 輸出數據 (直通)
    output reg  [15:0]  m_axis_tkeep,    // 字節有效掩碼
    output reg          m_axis_tvalid,   // 輸出有效
    output reg          m_axis_tlast,    // 幀最後字
    input  wire         m_axis_tready,   // 輸出就緒
    
    // ============ 提取的報頭字段 ============
    output reg  [15:0]  ethertype,       // 以太網類型 (0x0800 = IPv4)
    output reg  [7:0]   ip_protocol,     // IP協議字段 (17 = UDP)
    output reg  [15:0]  dst_port,        // UDP目的端口
    output reg  [7:0]   dscp_ecn,        // DSCP/ECN字段
    output reg          is_roce_pkt      // 是否為RoCE v2數據包
);

    // ============ 內部寄存器和狀態機 ============
    
    // 狀態定義
    localparam ST_IDLE = 2'd0;      // 空閑態：等待新幀
    localparam ST_HDR  = 2'd1;      // 報頭處理：提取報頭信息
    localparam ST_DATA = 2'd2;      // 數據轉發：轉發有效載荷
    
    reg [1:0] state, state_next;
    
    // 報頭解析結果暫存
    reg [15:0] ethertype_temp;
    reg [7:0]  ip_protocol_temp;
    reg [15:0] dst_port_temp;
    reg [7:0]  dscp_ecn_temp;
    
    // ============= 狀態機進程 =============
    
    // 狀態轉移邏輯 (組合邏輯)
    always @(*) begin
        state_next = state;
        
        case (state)
            ST_IDLE: begin
                // 在IDLE態等待新的幀開始 (tvalid和tready同時為1)
                if (s_axis_tvalid && s_axis_tready) begin
                    state_next = ST_HDR;
                end
            end
            
            ST_HDR: begin
                // 在HDR態，一旦輸出端口就緒，轉到DATA態
                if (m_axis_tready) begin
                    state_next = ST_DATA;
                end
            end
            
            ST_DATA: begin
                // 在DATA態，當最後一個字被傳輸時，返回到IDLE態
                if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                    state_next = ST_IDLE;
                end
            end
            
            default: state_next = ST_IDLE;
        endcase
    end
    
    // 狀態和輸出寄存器更新 (時序邏輯)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            
            // 復位所有輸出信號
            s_axis_tready  <= 1'b0;
            m_axis_tvalid  <= 1'b0;
            m_axis_tlast   <= 1'b0;
            m_axis_tdata   <= 128'd0;
            m_axis_tkeep   <= 16'd0;
            
            ethertype      <= 16'd0;
            ip_protocol    <= 8'd0;
            dst_port       <= 16'd0;
            dscp_ecn       <= 8'd0;
            is_roce_pkt    <= 1'b0;
        end else begin
            state <= state_next;
            
            case (state)
                ST_IDLE: begin
                    // ====== 第一步：提取以太網報頭 ======
                    // 以太網幀格式（第一次傳輸通常包含以太網報頭）：
                    // 字節0-5: 目的MAC地址
                    // 字節6-11: 源MAC地址
                    // 字節12-13: EtherType (大端格式)
                    
                    // 在Verilog中，tdata[127:120] = 字節0 (最早接收)
                    // 所以 EtherType 在 tdata[95:80]
                    
                    ethertype_temp <= {s_axis_tdata[87:80], s_axis_tdata[95:88]};
                    // 假設：位96-111 包含EtherType (根據您的數據排列)
                    // 調整這個取決于您的系統配置
                    
                    // 暫時設置輸入就緒
                    s_axis_tready <= 1'b1;
                    m_axis_tvalid <= 1'b0;
                end
                
                ST_HDR: begin
                    // ====== 第二步：進一步解析IP和UDP報頭 ======
                    
                    // 檢查EtherType是否為IPv4 (0x0800)
                    if (ethertype_temp == 16'h0800) begin
                        // 提取IPv4協議字段
                        // IPv4協議位置：報頭開始後的第9字節
                        // 在第二個128位數據塊中
                        ip_protocol_temp <= s_axis_tdata[71:64];  // 根據需要調整
                        
                        // 提取DSCP/ECN (ToS字段)
                        // ToS位置：IPv4報頭第2字節
                        dscp_ecn_temp <= s_axis_tdata[79:72];     // 根據需要調整
                        
                        // 提取UDP目的端口 (在UDP報頭中)
                        // UDP目的端口位置：UDP報頭偏移2-3字節
                        // 這通常在第三個數據塊中，需要計算準確位置
                        dst_port_temp <= s_axis_tdata[111:96];    // 調整為實際位置
                        
                    end else begin
                        // 不是IPv4包，清除所有暫存值
                        ip_protocol_temp <= 8'd0;
                        dscp_ecn_temp <= 8'd0;
                        dst_port_temp <= 16'd0;
                    end
                    
                    // 立即在HDR態輸出提取結果
                    m_axis_tdata  <= s_axis_tdata;
                    m_axis_tkeep  <= s_axis_tkeep;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= s_axis_tlast;
                    
                    // 決定下游是否就緒
                    s_axis_tready <= m_axis_tready;
                    
                    // 更新輸出協議字段
                    ethertype   <= ethertype_temp;
                    ip_protocol <= ip_protocol_temp;
                    dst_port    <= dst_port_temp;
                    dscp_ecn    <= dscp_ecn_temp;
                    
                    // ====== 判斷是否為RoCE v2 ======
                    // RoCE v2條件：
                    // 1. EtherType = 0x0800 (IPv4)
                    // 2. IP協議 = 17 (UDP)
                    // 3. UDP目的端口 = 4791
                    
                    is_roce_pkt <= (ethertype_temp == 16'h0800) &&
                                   (ip_protocol_temp == 8'd17) &&
                                   (dst_port_temp == 16'd4791);
                end
                
                ST_DATA: begin
                    // ====== 第三步：轉發數據 ======
                    // 在DATA態，直接轉發輸入到輸出
                    
                    m_axis_tdata  <= s_axis_tdata;
                    m_axis_tkeep  <= s_axis_tkeep;
                    m_axis_tvalid <= s_axis_tvalid;
                    m_axis_tlast  <= s_axis_tlast;
                    
                    // 背壓：只有下游就緒時才從上游接收
                    s_axis_tready <= m_axis_tready;
                    
                    // 保持is_roce_pkt信號（已在HDR態設置）
                end
            endcase
        end
    end

endmodule

// ==================================================================================
// 使用說明：
// 
// 1. 時鐘域：該模塊運行在100MHz時鐘下
// 
// 2. 復位序列：
//    在仿真開始時，保持rst_n=0 (低電平) 至少2個時鐘周期
//    然後設置rst_n=1進行正常操作
// 
// 3. 數據輸入格式：
//    - tdata[127:0] = 128位輸入（16字節以太網幀數據）
//    - tkeep[15:0] = 有效字節掩碼 (1=有效, 0=填充)
//    - tvalid = 1表示tdata有有效數據
//    - tlast = 1表示這是幀的最後一個字
// 
// 4. AXI-Stream握手：
//    - 只有當tvalid和tready都為1時，才發生數據轉移
//    - 模塊會自動根據下游就緒狀態調整上游tready信號
// 
// 5. 協議解析結果：
//    提取的協議字段在ST_HDR態被更新，可在同一時鐘周期讀取
//    is_roce_pkt信號表示數據包是否為有效的RoCE v2包
// 
// 6. 輸出延遲：
//    - 從輸入到輸出有2個時鐘周期延遲 (IDLE->HDR->DATA)
// ==================================================================================
