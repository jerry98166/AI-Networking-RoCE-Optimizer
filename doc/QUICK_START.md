# 🚀 RoCE v2專題 - 快速開始指南

**最後更新：** 2026年3月25日  
**距離面試：** 還有2天（3月27日下午4點）

---

## 📌 您現在的位置

✅ **已完成：**
- ✓ 理解了項目的核心概念
- ✓ 有詳細的README指南
- ✓ 有具體的時間計劃表
- ✓ 有第一個模塊框架 (roce_header_parser.v)

🎯 **現在要做：**
- ► 完成第一個模塊的代碼
- ► 編寫測試台進行驗證
- ► 逐步添加其他模塊

---

## 🔥 立即行動計劃（按優先級）

### ⏱️ 今天（3月25日）- 3-4小時

**目標：** 完成第一個可工作的模塊

```
時間分配：
├─ 30分鐘 ► 理解roce_header_parser.v框架
├─ 60分鐘 ► 完成報頭提取邏輯
├─ 60分鐘 ► 在Vivado中創建簡單測試台
└─ 30分鐘 ► 進行第一次仿真
```

**具體步驟：**

1️⃣ **打開Vivado並創建新源文件**
```bash
# 在Ubuntu終端
cd /home/gml/Vivado_projects/RoCEv2_AI_Opt

# 使用GUI打開Vivado
vivado RoCEv2_AI_Opt.xpr &
```

2️⃣ **複製框架代碼到Vivado**
- 打開 Vivado
- 右擊 `sources_1` → 「Add Sources」
- 選擇剛剛創建的 `roce_header_parser.v`
- 在Vivado編輯器中打開並仔細閱讀

3️⃣ **完成缺失的部分**

在 `roce_header_parser.v` 中，您會看到這些需要調整的部分：

```verilog
// 問題1：確定EtherType的正確位置
ethertype_temp <= {s_axis_tdata[87:80], s_axis_tdata[95:88]};
// ↑ 這個位置可能需要調整！根據您的系統配置

// 解決方法：
// - 如果數據是大端格式：EtherType通常在 tdata[95:80]
// - 如果數據是小端格式：可能在 tdata[111:96]
// - 最好的方法：查看您的MAC IP核心文檔
```

4️⃣ **編寫一個簡單的測試台**

```verilog
// 文件：tb_roce_header_parser_simple.v
`timescale 1ns/1ps

module tb_roce_header_parser_simple;

reg         clk;
reg         rst_n;
reg  [127:0] s_axis_tdata;
reg  [15:0]  s_axis_tkeep;
reg          s_axis_tvalid;
wire         s_axis_tready;
wire [127:0] m_axis_tdata;
wire         m_axis_tvalid;
wire         is_roce_pkt;

// 時鐘生成 (100MHz)
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// DUT例化
roce_header_parser dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .s_axis_tdata     (s_axis_tdata),
    .s_axis_tkeep     (s_axis_tkeep),
    .s_axis_tvalid    (s_axis_tvalid),
    .m_axis_tvalid    (m_axis_tvalid),
    .m_axis_tdata     (m_axis_tdata),
    .is_roce_pkt      (is_roce_pkt)
);

// 測試激勵
initial begin
    rst_n = 0;
    s_axis_tvalid = 0;
    s_axis_tdata = 0;
    s_axis_tkeep = 0;
    
    #20 rst_n = 1;      // 復位持續2個時鐘周期
    #10;
    
    // 發送一個簡單的IPv4數據包（EtherType = 0x0800）
    s_axis_tvalid = 1;
    
    // 構造測試數據
    // 簡化：在適當的位置放置0x0800作為EtherType
    s_axis_tdata = 128'h0000_0000_0000_0800_0000_0000_0000_0000;
    s_axis_tkeep = 16'hFFFF;
    
    #10;
    
    $display("Time: %t, is_roce_pkt: %b, ethertype: 0x%04x",
             $time, is_roce_pkt, dut.ethertype);
    
    #100 $finish;
end

initial begin
    $dumpfile("wave_simple.vcd");
    $dumpvars(0, tb_roce_header_parser_simple);
end

endmodule
```

5️⃣ **在Vivado中運行仿真**
- 選擇 Vivado → Simulation → Run Simulation
- 觀察波形和控制台輸出
- 驗證 `is_roce_pkt` 是否正確

---

### ⏱️ 明天（3月26日上午）- 4小時

**目標：** 實現完整的優先級隊列系統

```
任務分配：
├─ 完成 roce_ecn_marker.v 改進 (已有基礎)
├─ 完成 priority_queue_mgr.v (新建)
├─ 完成 flow_control_unit.v (新建)
└─ 進行集成測試
```

**關鍵提示：**
- 從最簡單的版本開始 (只支持2個優先級)
- 逐漸增加複雜度
- 每完成一個模塊就测試它

---

### ⏱️ 明天下午 + 後天 - 6小時

**目標：** 集成所有模塊 + 詳細仿真

```
└─ 整合所有5個模塊
└─ 運行完整的仿真測試
└─ 收集性能數據
└─ 生成波形截圖
```

---

### ⏱️ 3月27日上午 - 3小時

**目標：** 完成演示準備

```
└─ 製作PPT
└─ 準備波形圖表
└─ 準備演講稿
└─ 預演展示
```

---

## 📚 關鍵學習資源

### 1. 理解Verilog AXI-Stream握手

```verilog
// ✅ 正確的握手實現
always @(posedge clk) begin
    // 只有當tvalid和tready同時為1時才發生轉移
    if (s_axis_tvalid && s_axis_tready) begin
        // 數據被接受
        data_buffer <= s_axis_tdata;
    end
end

// 背壓實現（下游忙時停止上游）
assign s_axis_tready = m_axis_tready && (queue_not_full);
```

### 2. 正確的復位和初始化

```verilog
// ✅ 推薦的復位結構
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 復位所有暫存器到初始值
        state <= IDLE;
        counter <= 0;
        data_reg <= 0;
        // ... 其他暫存器
    end else begin
        // 正常操作
    end
end

// 在仿真中的使用
initial begin
    rst_n = 0;
    #10;        // 保持復位最少1-2個時鐘周期
    rst_n = 1;
    // 開始發送測試激勵
end
```

### 3. FIFO隊列的實現

```verilog
// 空/滿判斷（重要！）
wire fifo_empty = (wr_ptr == rd_ptr);
wire fifo_full = ((wr_ptr + 1) % FIFO_DEPTH == rd_ptr);

// 為什麼不能簡單地比較？
// 因為在環形FIFO中，wr_ptr might wrap around
// 而 rd_ptr 仍在舊值，會錯誤判斷

// ✅ 正確做法：使用額外的計數器
reg [7:0] count;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) count <= 0;
    else if (wr_en && !rd_en) count <= count + 1;
    else if (!wr_en && rd_en) count <= count - 1;
end
wire fifo_empty = (count == 0);
wire fifo_full = (count == FIFO_DEPTH);
```

---

## ⚠️ 常見錯誤及避免方法

### ❌ 錯誤1：忘記握手信號

```verilog
// ❌ 錯誤
always @(posedge clk) begin
    m_axis_tdata <= input_data;  // 什麼時候接收？
end

// ✅ 正確
always @(posedge clk) begin
    if (s_axis_tvalid && s_axis_tready) begin
        m_axis_tdata <= s_axis_tdata;
    end
end
```

### ❌ 錯誤2：不處理背壓

```verilog
// ❌ 錯誤：忽略下游就緒信號
always @(posedge clk) begin
    if (s_axis_tvalid)
        output_data <= input_data;  // 強行輸出，會丟數據！
end

// ✅ 正確：檢查下游是否就緒
assign s_axis_tready = m_axis_tready;
always @(posedge clk) begin
    if (s_axis_tvalid && s_axis_tready) begin
        output_data <= input_data;
    end
end
```

### ❌ 錯誤3：復位不完全

```verilog
// ❌ 錯誤：只復位了一個暫存器
if (!rst_n) begin
    counter <= 0;  // 其他暫存器沒有初始化！
end

// ✅ 正確：復位所有可能被使用的暫存器
if (!rst_n) begin
    counter <= 0;
    state <= IDLE;
    data_buffer <= 0;
    flags <= 0;
    // ... 所有暫存器
end
```

---

## 🎯 面試時的「殺手鐧」準備

### 1. 一張完整的架構圖
```
準備一張清晰的系統架構圖，顯示：
├─ 5個核心模塊及其功能
├─ 數據流向
├─ 優先級隊列的工作原理
└─ 性能監控點
```

### 2. 3個關鍵波形
```
波形1：基本功能測試
├─ 展示握手信號 (tvalid/tready)
├─ 展示數據正確通過
└─ 說明延遲 = 2個時鐘周期

波形2：擁堵檢測
├─ 高流量導致隊列深度增長
├─ 隊列深度超過閾值時ECN被標記
└─ 說明擁堵信號的及時性

波形3：優先級隊列
├─ 混合優先級數據包
├─ 高優先級優先輸出
└─ 展示仲裁器的動作
```

### 3. 一個「自信的解釋」
```
練習解釋這句話（面試官最可能問）：
「ECN相比傳統WRED有什麼優勢？」

答案框架：
├─ WRED是概率丟包，依賴於TCP超時重傳
├─ ECN是早期通知，在擁堵發生前就標記
├─ 在RoCE場景中，ECN可以實現零丟包
├─ 因為接收方立即反饋，發送方能快速調整
└─ 這對延遲敏感的AI訓練至關重要
```

---

## 💡 專業建議

### 🎓 代碼質量
```
☐ 添加清晰的註釋 (中文+英文)
☐ 遵循命名規則 (s_axis_*, m_axis_*)
☐ 模塊間接口清晰
☐ 狀態機易於理解
☐ 沒有未使用的暫存器
☐ 沒有組合邏輯環
```

### 📊 演示數據
```
☐ 延遲：< 100ns (10周期 @ 100MHz)
☐ 吞吐量：> 800Mbps (達到80%線速)
☐ 丟包率：0% (在有流控制的情況)
☐ 隊列深度波動：< 100個數據包
```

### 💬 溝通技巧
```
☐ 用數據說話 (波形和指標)
☐ 解釋設計選擇 (為什麼用4級優先級？為什麼選這個閾值?)
☐ 誠實承認學習过程 (「這部分我最初做錯了，後來改進了...")
☐ 展示深度理解 (能夠回答「如果改變X會怎樣？」)
```

---

## ✨ 最後的激勵

> **您正在做的是行業前沿的工作！**

- RoCE v2是當今高性能計算的標準
- ECN機制是解決網路擁堵的先進方法
- FPGA實現是硬體加速的核心
- 您的項目展示了完整的系統思維

**信心來自於：**
1. ✅ 有詳細的指南和框架
2. ✅ 技術並不如想象中複雜
3. ✅ 您有充足的時間（2天）
4. ✅ 仿真驗證能夠快速給您反饋

**祝您成功！** 🚀

---

## 📞 遇到問題時的排查順序

```
1️⃣ 檢查Verilog語法
   └─ Vivado會報告編譯錯誤

2️⃣ 檢查模塊連接
   └─ 確保所有端口都被連接

3️⃣ 運行仿真並監控波形
   └─ 查看信號是否按預期變化

4️⃣ 添加調試信號
   └─ 在TestBench中打印關鍵信號

5️⃣ 逐步簡化測試
   └─ 從最簡單的情況開始驗證

6️⃣ 查看參考實現
   └─ 回到README查看示例代碼
```

---

**下一步：** 打開Vivado，開始完成roce_header_parser.v！

**加油！** 💪
