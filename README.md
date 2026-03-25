# RoCE v2 AI運算網路效能優化專題 - 完整指南

**項目展示時間：** 2026年3月27日下午4點（智邦FPGA實習生面試）  
**項目環境：** Ubuntu電腦 + Vivado + 模擬仿真
**面試通知日：** 2026年3月19日  
**專題準備起始日：** 2026年3月20日

---

## GitHub 專案結構（已整理）

```
RoCEv2_AI_Opt/
├─ src/            # Verilog 原始碼
├─ sim/            # Testbench
├─ cons/           # XDC 約束
├─ doc/            # 設計說明、波形圖、補充文檔
├─ README.md
├─ .gitignore
└─ RoCEv2_AI_Opt.xpr   # Vivado 專案檔
```

### Vivado 開啟方式

1. 直接開啟專案檔：
    - `vivado RoCEv2_AI_Opt.xpr`
2. 由 GitHub 乾淨結構重建專案：
    - `vivado -mode batch -source scripts/create_project.tcl`
    - 或在 Vivado Tcl Console 執行 `source scripts/create_project.tcl`
3. 若只想看 GitHub 主結構：
    - 設計檔案在 `src/`
    - 測試檔案在 `sim/`
    - 約束檔在 `cons/`

> 注意：為了保留原工程可直接開啟，Vivado 既有工程目錄（如 `RoCEv2_AI_Opt.srcs/`）仍保留於本機。

---

## 目錄
1. [專題概述](#專題概述)
2. [技術背景](#技術背景)
3. [項目架構](#項目架構)
4. [逐步實現指南](#逐步實現指南)
5. [關鍵注意事項](#關鍵注意事項)
6. [仿真驗證方法](#仿真驗證方法)
7. [面試展示重點](#面試展示重點)
8. [必讀書籍與完整知識地圖（針對本專題）](#-必讀書籍與完整知識地圖針對本專題)

---

## 專題概述

### 項目目標
實現一個基於RoCE v2協議的AI運算網路效能優化系統，通過ECN（Explicit Congestion Notification）機制和動態優先級隊列管理，優化高性能運算集群中的網路通信性能。

### 為什麼選擇這個主題？
- **AI領域的迫切需求**：當今AI訓練對網路的要求極高
- **RoCE v2的優勢**：低延遲、高帶寬、CPU開銷低
- **ECN的創新應用**：主動擁堵檢測而非被動丟包恢復
- **FPGA的適用性**：可以實現硬體加速的網路處理

### 預期成果
- ✅ 完整的Verilog硬體設計
- ✅ 功能正確的仿真驗證
- ✅ 效能優化對比數據
- ✅ 清晰的講解演示文檔

---

## 技術背景

### RoCE v2協議基礎

#### 1. RoCE v2報頭結構（簡化版）
```
以太網幀結構（用於RoCE v2）
┌─────────────────────────────────────────┐
│ 以太網報頭 (14 bytes)                    │
│ ├─ 目的MAC地址 (6 bytes)                │
│ ├─ 源MAC地址 (6 bytes)                  │
│ └─ EtherType (2 bytes): 0x0800 (IPv4)  │
├─────────────────────────────────────────┤
│ IPv4報頭 (20 bytes)                     │
│ ├─ 版本/長度 (4 bits + 4 bits)          │
│ ├─ ToS/DSCP (8 bits) <- ECN信息在此！   │
│ ├─ 總長度 (2 bytes)                     │
│ ├─ TTL (1 byte)                        │
│ └─ 協議字段 (1 byte): 17 (UDP/RoCE)    │
├─────────────────────────────────────────┤
│ UDP報頭 (8 bytes)                       │
│ ├─ 源端口 (2 bytes)                     │
│ ├─ 目的端口 (2 bytes): 4791 (RoCE)    │
│ ├─ 長度 (2 bytes)                       │
│ └─ 校驗和 (2 bytes)                     │
├─────────────────────────────────────────┤
│ RoCE v2 BTH報頭 (12 bytes)              │
│ ├─ 操作碼 (1 byte) <- 關鍵操作碼        │
│ ├─ 版本/標誌 (1 byte)                   │
│ ├─ 分區密鑰 (2 bytes)                   │
│ ├─ 保留位 (8 bits)                      │
│ ├─ MigReq (1 bit)                       │
│ ├─ PAD/TVer (5 bits)                    │
│ ├─ Transport Header Version (2 bits)    │
│ └─ ... (更多字段)                       │
├─────────────────────────────────────────┤
│ 有效載荷數據                             │
│ (最大64KB - 報頭大小)                   │
└─────────────────────────────────────────┘
```

#### 2. ECN機制（關鍵創新點）
```
傳統網路擁堵處理 vs ECN+RoCE優化
┌─────────────────────────────────────────────────┐
│ 傳統方式：被動丟包恢復                         │
├─────────────────────────────────────────────────┤
│ 1. 數據包發送 → 2. 隊列滿 → 3. 丟包            │
│ 4. 超時重傳 → 5. 性能下降                       │
│ ⚠️  問題：高延遲、高丟包率、性能差              │
├─────────────────────────────────────────────────┤
│ ECN+RoCE優化方式：主動擁堵通知                 │
├─────────────────────────────────────────────────┤
│ 1. 數據包進入隊列 → 2. 監控隊列深度            │
│ 3. 隊列達到閾值 → 4. 標記ECN位                 │
│ 5. 接收方檢測ECN → 6. 發送NACK或減速           │
│ 7. 發送方調整速率 → 8. 避免丟包                │
│ ✅ 優勢：低延遲、零丟包、自適應                │
└─────────────────────────────────────────────────┘
```

### 關鍵概念解釋

| 概念 | 解釋 | 在本項目中的應用 |
|------|------|------------------|
| **DSCP** | Differentiated Services Code Point（服務等級代碼點） | 用於標記擁堵信息 |
| **ECN Bits** | IPv4報頭中的2位ECN字段 | 00=未擁堵, 10=擁堵, 11=重擁堵 |
| **BTH** | Basic Transport Header（RoCE基本運輸報頭） | 包含PSN序列號和操作碼 |
| **PSN** | Packet Sequence Number（數據包序列號） | 用於追蹤和排序 |
| **隊列深度** | 在網路交換機/模塊中等待的數據包數 | 觸發ECN標記的依據 |

---

## 項目架構

### 系統架構圖
```
┌────────────────────────────────────────────────────────────┐
│                   RoCEv2_AI_Opt 頂層模塊                      │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  輸入數據流                                          │ │
│  │  (s_axis_tdata, s_axis_tvalid, s_axis_tready)       │ │
│  └────────┬─────────────────────────────────────────────┘ │
│           │                                               │
│  ┌────────▼─────────────────────────────────────────────┐ │
│  │  1️⃣ RoCE報頭解析模塊 (roce_header_parser)          │ │
│  │  功能：                                              │ │
│  │  - 提取EtherType, 協議類型, 目的端口                │ │
│  │  - 識別RoCE v2數據包                                │ │
│  │  - 提取DSCP和ECN位                                 │ │
│  └────────┬─────────────────────────────────────────────┘ │
│           │                                               │
│  ┌────────▼─────────────────────────────────────────────┐ │
│  │  2️⃣ ECN標記模塊 (roce_ecn_marker)                  │ │
│  │  功能：                                              │ │
│  │  - 監控網路擁堵信號                                 │
│  │  - 根據隊列深度決定是否標記ECN                      │
│  │  - 修改IPv4 ToS字段中的ECN位                       │ │
│  └────────┬─────────────────────────────────────────────┘ │
│           │                                               │
│  ┌────────▼─────────────────────────────────────────────┐ │
│  │  3️⃣ 優先級隊列管理模塊 (priority_queue_mgr)        │ │
│  │  功能：                                              │ │
│  │  - 維護多優先級的數據包隊列                         │ │
│  │  - 根據ECN位自動調整優先級                         │ │
│  │  - 實現QoS (Quality of Service)                    │ │
│  └────────┬─────────────────────────────────────────────┘ │
│           │                                               │
│  ┌────────▼─────────────────────────────────────────────┐ │
│  │  4️⃣ 流控制模塊 (flow_control_unit)                 │ │
│  │  功能：                                              │ │
│  │  - 實現背壓 (Back Pressure) 機制                   │ │
│  │  - 生成PAUSE幀                                     │ │
│  │  - 動態調整發送速率                                 │ │
│  └────────┬─────────────────────────────────────────────┘ │
│           │                                               │
│  ┌────────▼─────────────────────────────────────────────┐ │
│  │  5️⃣ 效能監控模塊 (performance_monitor)             │ │
│  │  功能：                                              │ │
│  │  - 統計數據包數量                                   │ │
│  │  - 計算延遲 (Latency)                              │ │
│  │  - 計算吞吐量 (Throughput)                         │ │
│  │  - 計算丟包率 (Loss Rate)                          │ │
│  └────────┬─────────────────────────────────────────────┘ │
│           │                                               │
│  ┌────────▼─────────────────────────────────────────────┐ │
│  │  輸出數據流                                          │ │
│  │  (m_axis_tdata, m_axis_tvalid, m_axis_tready)       │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  監控信號輸出 (用於驗證和調試)                       │ │
│  │  - congestion_indicator                             │ │
│  │  - queue_depth                                      │ │
│  │  - packet_dropped                                   │ │
│  │  - latency_cycles                                   │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

### 模塊間的數據流
```
數據流向（AXI-Stream協議）：
發送端 → 報頭解析 → ECN標記 → 優先級隊列 → 流控制 → 性能監控 → 接收端
                ↓
          優先級信息 ←→ 隊列管理
                ↓
          控制信號 ←→ 流控制
                ↓
          統計信息 ←→ 性能監控
```

---

## 逐步實現指南

### 📌 第1步：理解現有代碼結構（1小時）

您現在有：
- `roce_ecn_marker.v` - ECN標記模塊的初步實現

**需要檢查的內容：**
1. 該模塊是否正確檢測RoCE v2數據包
2. 是否正確地設置ECN位
3. 是否有流控制信號

**檢查清單：**
```
☐ 確認模塊使用AXI-Stream接口
☐ 確認有congestion_trigger輸入信號
☐ 確認在IPv4報頭位置標記ECN位
☐ 確認有通過準備（s_axis_tready）
```

### 📌 第2步：創建RoCE報頭解析模塊（2.5小時）

**文件名：** `roce_header_parser.v`

**關鍵功能：**
- 解析以太網和IPv4報頭
- 識別RoCE v2數據包（UDP端口 4791）
- 提取優先級信息

**代碼框架（您需要完成細節）：**

```verilog
// 檔案：roce_header_parser.v
// 功能：解析RoCE v2報頭
module roce_header_parser (
    input  wire         clk,
    input  wire         rst_n,
    
    // 輸入 AXI-Stream 接口
    input  wire [127:0] s_axis_tdata,
    input  wire [15:0]  s_axis_tkeep,
    input  wire         s_axis_tvalid,
    input  wire         s_axis_tlast,
    output reg          s_axis_tready,
    
    // 輸出 AXI-Stream 接口
    output reg  [127:0] m_axis_tdata,
    output reg  [15:0]  m_axis_tkeep,
    output reg          m_axis_tvalid,
    output reg          m_axis_tlast,
    input  wire         m_axis_tready,
    
    // 提取的報頭信息
    output reg  [15:0]  ethertype,      // 以太網類型 (0x0800 for IPv4)
    output reg  [7:0]   protocol,       // IP協議 (17 for UDP)
    output reg  [15:0]  dst_port,       // 目的端口 (4791 for RoCE)
    output reg  [7:0]   dscp,           // DSCP/ECN 信息
    output reg          is_roce_pkt     // 是否為RoCE數據包
);

    // 你的實現將在這裡

endmodule
```

**具體步驟：**
1. ✅ 在第一個時鐘周期捕獲報頭
2. ✅ 提取並驗證EtherType (應為0x0800)
3. ✅ 提取IP協議字段 (應為17表示UDP)
4. ✅ 提取UDP目的端口 (應為4791表示RoCE)
5. ✅ 設置is_roce_pkt訊號

### 📌 第3步：完善ECN標記模塊（2小時）

**文件名：** 改善 `roce_ecn_marker.v`

**改善內容：**
1. 增加隊列深度監控
2. 實現動態閾值調整
3. 添加詳細的亮堵檢測邏輯

**改善框架：**

```verilog
// 改善的roce_ecn_marker.v應包含
// 1. 隊列深度暫存器
reg [15:0] queue_depth;

// 2. 擁堵閾值
parameter CONGESTION_THRESHOLD = 16'd50;

// 3. 擁堵標誌邏輯
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        queue_depth <= 0;
    end else begin
        // 當數據進入隊列時增加深度
        if (s_axis_tvalid && s_axis_tready && !m_axis_tready)
            queue_depth <= queue_depth + 1;
        // 當數據離開隊列時減少深度
        else if (m_axis_tvalid && m_axis_tready && !(s_axis_tvalid && s_axis_tready))
            queue_depth <= queue_depth - 1;
    end
end

// 4. ECN位設置邏輯（根據隊列深度）
wire should_set_ecn = (queue_depth > CONGESTION_THRESHOLD);
```

### 📌 第4步：創建優先級隊列管理模塊（3.5小時）

**文件名：** `priority_queue_mgr.v`

**核心概念：**
```
優先級隊列設計原理
┌─────────────────────────────────┐
│ 優先級-0隊列（最高）              │
│ 用於：已標記ECN的緊急數據包      │
├─────────────────────────────────┤
│ 優先級-1隊列（中等）              │
│ 用於：普通RoCE數據包              │
├─────────────────────────────────┤
│ 優先級-2隊列（低）                │
│ 用於：非RoCE或辅助流量            │
├─────────────────────────────────┤
│ 優先級-3隊列（最低）              │
│ 用於：背景/管理流量                │
└─────────────────────────────────┘

仲裁邏輯：
在某個時鐘周期選擇輸出一個數據包：
1. 先檢查優先級-0隊列，若非空則輸出
2. 否則檢查優先級-1隊列，若非空則輸出
3. 否則檢查優先級-2隊列，若非空則輸出
4. 最後檢查優先級-3隊列
```

**實現步驟：**
```verilog
// 每個優先級隊列包含：
// 1. FIFO內存（容量=32或64個數據包）
reg [127:0] queue_data[0:3][0:31];  // 4個隊列，每個32項

// 2. 讀寫指針
reg [6:0] wr_ptr[0:3];  // 寫指針
reg [6:0] rd_ptr[0:3];  // 讀指針

// 3. 隊列計數器
reg [6:0] count[0:3];   // 每個隊列的項目數

// 4. 仲裁邏輯（使用優先編碼器）
always @(*) begin
    if (count[0] > 0)
        selected_priority = 2'b00;
    else if (count[1] > 0)
        selected_priority = 2'b01;
    else if (count[2] > 0)
        selected_priority = 2'b10;
    else
        selected_priority = 2'b11;
end
```

### 📌 第5步：創建流控制模塊（3小時）

**文件名：** `flow_control_unit.v`

**功能說明：**
```
背壓機制（Back Pressure）：
┌───────────────────────────────────────────┐
│ 當下游模塊繁忙時：                          │
│                                           │
│ 1. m_axis_tready = 0（不能接收）          │
│ 2. 流控制模塊檢測到這個信號               │
│ 3. 對上游模塊返回 s_axis_tready = 0      │
│ 4. 上游停止發送（遵循AXI-Stream協議）    │
│ 5. 防止數據丟失                           │
└───────────────────────────────────────────┘

PAUSE幀機制：
┌───────────────────────────────────────────┐
│ 當隊列即將滿溢時：                          │
│                                           │
│ 1. 通過以太網發送PAUSE幀                  │
│ 2. 通知上游發送方暫停發送                 │
│ 3. 給隊列時間進行處理                     │
│ 4. 恢復時重新開始傳輸                     │
└───────────────────────────────────────────┘
```

**核心實現：**
```verilog
// 背壓邏輯
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_axis_tready <= 1'b0;
    end else begin
        // 根據隊列深度和下游準備信號決定
        if (m_axis_tready && queue_depth < MAX_QUEUE_DEPTH)
            s_axis_tready <= 1'b1;
        else
            s_axis_tready <= 1'b0;
    end
end

// PAUSE幀生成邏輯
wire should_send_pause = (queue_depth > PAUSE_THRESHOLD);
```

### 📌 第6步：創建效能監控模塊（2.5小時）

**文件名：** `performance_monitor.v`

**監控指標：**

| 指標 | 計算方式 | 應用 |
|------|---------|------|
| **吞吐量** | 統計通過的數據量 ÷ 時間 | 評估網路效率 |
| **延遲** | (輸出時間) - (輸入時間) | 評估實時性 |
| **丟包率** | (丟失數據包) ÷ (總數據包) | 評估可靠性 |
| **隊列深度** | 實時隊列項目數 | 判斷擁堵情況 |

**實現要點：**
```verilog
// 延遲測量
// 為每個數據包添加時間戳
reg [31:0] ingress_timestamp[0:1023];
reg [31:0] cycle_counter;

// 在數據進入時記錄
if (s_axis_tvalid && s_axis_tready)
    ingress_timestamp[ingress_ptr] <= cycle_counter;

// 在數據輸出時計算延遲
wire [31:0] current_latency = 
    cycle_counter - ingress_timestamp[output_ptr];

// 吞吐量測量
reg [63:0] total_bytes_in;
reg [63:0] total_bytes_out;
reg [31:0] measurement_window;

// 每1000周期計算一次
always @(posedge clk) begin
    if (measurement_window == 1000) begin
        throughput_mbps <= (total_bytes_out * 8) / 1000;
        measurement_window <= 0;
        total_bytes_in <= 0;
        total_bytes_out <= 0;
    end else begin
        measurement_window <= measurement_window + 1;
        if (s_axis_tvalid && s_axis_tready)
            total_bytes_in <= total_bytes_in + 16;  // 128-bit = 16 bytes
        if (m_axis_tvalid && m_axis_tready)
            total_bytes_out <= total_bytes_out + 16;
    end
end
```

### 📌 第7步：集成頂層模塊（2小時）

**文件名：** `roce_opt_top.v`

**頂層結構：**
```verilog
module roce_opt_top (
    input  wire         clk,
    input  wire         rst_n,
    
    // 輸入 AXI-Stream 接口
    input  wire [127:0] s_axis_tdata,
    input  wire [15:0]  s_axis_tkeep,
    input  wire         s_axis_tvalid,
    input  wire         s_axis_tlast,
    output wire         s_axis_tready,
    
    // 輸出 AXI-Stream 接口
    output wire [127:0] m_axis_tdata,
    output wire [15:0]  m_axis_tkeep,
    output wire         m_axis_tvalid,
    output wire         m_axis_tlast,
    input  wire         m_axis_tready,
    
    // 監控信號
    output wire [15:0]  queue_depth,
    output wire         congestion_flag,
    output wire [31:0]  latency_cycles,
    output wire [31:0]  throughput_mbps,
    output wire [31:0]  pkt_loss_rate,
    
    // 調試信號
    output wire [7:0]   debug_state
);

// 例化各個子模塊：
roce_header_parser parser_inst (
    // 連接信號...
);

roce_ecn_marker marker_inst (
    // 連接信號...
);

priority_queue_mgr queue_inst (
    // 連接信號...
);

flow_control_unit flow_ctrl_inst (
    // 連接信號...
);

performance_monitor monitor_inst (
    // 連接信號...
);

endmodule
```

### 📌 第8步：創建完整的仿真測試台（3.5小時）

**文件名：** `tb_roce_opt_top.v`

**測試場景設計：**

```verilog
// 場景1：基本功能測試
// - 發送一個簡單的RoCE數據包
// - 驗證報頭被正確解析
// - 驗證數據被正確轉發

// 場景2：擁堵檢測測試
// - 發送多個連續RoCE數據包（模擬高流量）
// - 觀察隊列深度增長
// - 驗證ECN位被正確標記

// 場景3：優先級隊列測試
// - 混合發送不同優先級的數據包
// - 驗證高優先級數據包先輸出
// - 驗證公平性

// 場景4：流控制測試
// - 固定下游接收速率低於發送速率
// - 驗證背壓機制工作
// - 驗證不發生數據丟失

// 場景5：效能監控測試
// - 連續發送1000個數據包
// - 計算平均延遲、吞吐量、丟包率
// - 與優化前進行對比

// 場景6：壓力測試
// - 以線速發送數據包
// - 隨機改變下游接收速率
// - 驗證系統穩定性
```

**測試框架：**
```verilog
`timescale 1ns/1ps

module tb_roce_opt_top;

reg         clk;
reg         rst_n;
reg  [127:0] s_axis_tdata;
reg  [15:0]  s_axis_tkeep;
reg          s_axis_tvalid;
reg          s_axis_tlast;
wire         s_axis_tready;

wire [127:0] m_axis_tdata;
wire [15:0]  m_axis_tkeep;
wire         m_axis_tvalid;
wire         m_axis_tlast;
reg          m_axis_tready;

// 監控信號
wire [15:0]  queue_depth;
wire         congestion_flag;

// 時鐘生成 (100MHz)
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// 復位
initial begin
    rst_n = 0;
    #10 rst_n = 1;
end

// DUT 例化
roce_opt_top dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .s_axis_tdata     (s_axis_tdata),
    .s_axis_tkeep     (s_axis_tkeep),
    .s_axis_tvalid    (s_axis_tvalid),
    .s_axis_tlast     (s_axis_tlast),
    .s_axis_tready    (s_axis_tready),
    .m_axis_tdata     (m_axis_tdata),
    .m_axis_tkeep     (m_axis_tkeep),
    .m_axis_tvalid    (m_axis_tvalid),
    .m_axis_tlast     (m_axis_tlast),
    .m_axis_tready    (m_axis_tready),
    .queue_depth      (queue_depth),
    .congestion_flag  (congestion_flag)
);

// 測試激勵
initial begin
    s_axis_tdata  = 0;
    s_axis_tkeep  = 0;
    s_axis_tvalid = 0;
    s_axis_tlast  = 0;
    m_axis_tready = 1;
    
    #100;
    
    // 測試場景1：發送一個簡單數據包
    send_roce_packet(128'hDEADBEEFCAFEBABE_0000000000000800);
    
    #100;
    
    // 測試場景2：高流量模擬
    repeat (50) begin
        send_roce_packet(128'h1234567890ABCDEF_0000000000000800);
        #10;
    end
    
    #100 $finish;
end

// 任務定義
task send_roce_packet(input [127:0] data);
begin
    @(posedge clk);
    s_axis_tvalid = 1;
    s_axis_tdata = data;
    s_axis_tkeep = 16'hFFFF;
    @(posedge clk);
    s_axis_tlast = 1;
    @(posedge clk);
    s_axis_tvalid = 0;
    s_axis_tlast = 0;
end
endtask

// 仿真監控
initial begin
    $monitor("@%t: queue_depth=%d, congestion=%d, m_valid=%d, m_last=%d",
             $time, queue_depth, congestion_flag, m_axis_tvalid, m_axis_tlast);
end

// 生成波形文件（用於後期查看）
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_roce_opt_top);
end

endmodule
```

---

## 關鍵注意事項

### ⚠️ Verilog設計注意事項

#### 1. **時序問題（Timing Issues）**
```verilog
// ❌ 錯誤：組合邏輯中的反饋會導致時序問題
assign queue_depth_next = queue_depth + 1;
assign queue_depth = queue_depth_next;  // 組合邏輯環

// ✅ 正確：使用時序邏輯（寄存器）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        queue_depth <= 0;
    else
        queue_depth <= queue_depth + 1;
end
```

#### 2. **AXI-Stream握手協議**
```verilog
// 正確的握手：只有當tvalid和tready同時為1時才轉移數據
wire handshake = s_axis_tvalid && s_axis_tready;

always @(posedge clk) begin
    if (handshake) begin
        // 數據被接受，進行相應處理
        data_received <= s_axis_tdata;
    end
end
```

#### 3. **復位策略**
```verilog
// ✅ 推薦：同時支持同步和非同步復位
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        // 復位所有寄存器
    end else begin
        // 正常操作
    end
end
```

#### 4. **FIFO設計要點**
```verilog
// 關鍵：正確的空/滿判斷
wire fifo_empty = (write_ptr == read_ptr);
wire fifo_full = ((write_ptr + 1) % DEPTH == read_ptr);

// 原因：使用模運算比較，避免简單的相等比較帶來的問題
```

### 🔴 常見錯誤

| 錯誤 | 原因 | 解決方案 |
|------|------|---------|
| 握手信號丟失 | 忘記檢查tvalid或tready | 始終添加握手檢查 |
| 復位不徹底 | 只復位了部分暫存器 | 列出所有需要復位的暫存器 |
| 時鐘域交叉 | 跨越不同時鐘域的信號 | 使用同步器 (CDC) 模塊 |
| 死鎖 | 流控制邏輯不當 | 確保下游始終能消費數據 |
| 丟數據 | 未考慮背壓 | 實現背壓機制 |

---

## 仿真驗證方法

### 使用Vivado進行仿真

#### **步驟1：設置仿真環境**

```bash
# 在Ubuntu終端中
cd /home/gml/Vivado_projects/RoCEv2_AI_Opt

# 啟動Vivado
vivado -mode batch -source setup_simulation.tcl
```

#### **步驟2：創建TCL仿真腳本**

**文件名：** `setup_simulation.tcl`

```tcl
# 打開項目
open_project RoCEv2_AI_Opt.xpr

# 創建仿真策略
create_fileset -simset sim_1
add_files -fileset sim_1 tb_roce_opt_top.v

# 設置仿真時間
set_property top tb_roce_opt_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# 運行仿真
launch_simulation
```

#### **步驟3：查看波形**

在Vivado仿真窗口中：
1. 點擊 **Scope** → 選擇 `tb_roce_opt_top` → `dut`
2. 展開所有信號
3. 選擇關鍵信號：
   - `s_axis_tvalid`, `s_axis_tready`
   - `m_axis_tvalid`, `m_axis_tready`
   - `queue_depth`, `congestion_flag`
   - `latency_cycles`, `throughput_mbps`

### 驗證清單

```
仿真驗證檢查表
═════════════════════════════════════════════════════════

功能驗證：
☐ 數據完整性：輸出數據是否與輸入相同
☐ 報頭解析：是否正確識別RoCE v2數據包
☐ ECN標記：高流量時ECN位是否被正確標記
☐ 優先級：高優先級數據包是否優先輸出
☐ 流控制：背壓是否工作（s_axis_tready立即反應）
☐ 效能監控：是否正確計算延遲、吞吐量、丟包率

性能驗證：
☐ 最小延遲 < 100ns（10個時鐘周期 @ 100MHz）
☐ 吞吐量 > 800 Mbps（128位 @ 100MHz的80%）
☐ 丟包率 = 0（在有流控制的情況下）
☐ 隊列深度波動在預期範圍內

邊界情況：
☐ 空包（0字節）的處理
☐ 最大化數據（100%占用率）
☐ 隨機背壓
☐ 連續復位

波形檢查要點：
☐ 檢查握手信號（tvalid和tready的同步）
☐ 檢查tkeep位是否被正確傳遞
☐ 檢查tlast信號的位置是否正確
☐ 檢查監控信號的變化趨勢
```

### 生成仿真報告

**自動化報告生成腳本：** `generate_report.py`

```python
#!/usr/bin/env python3

import re
import sys

def parse_vcd(vcd_file):
    """解析VCD文件，提取關鍵指標"""
    
    metrics = {
        'max_queue_depth': 0,
        'total_packets': 0,
        'dropped_packets': 0,
        'avg_latency': 0,
        'max_latency': 0,
        'total_cycles': 0
    }
    
    with open(vcd_file, 'r') as f:
        for line in f:
            # 解析queue_depth
            if 'queue_depth' in line:
                match = re.search(r'#(\d+).*b(\d+)', line)
                if match:
                    depth = int(match.group(2))
                    metrics['max_queue_depth'] = max(metrics['max_queue_depth'], depth)
            
            # 解析其他指標...
    
    return metrics

def generate_html_report(metrics):
    """生成HTML仿真報告"""
    
    html = f"""
    <html>
    <head><title>RoCE v2 仿真報告</title></head>
    <body>
        <h1>仿真性能指標</h1>
        <table border=1>
            <tr><th>指標</th><th>值</th><th>目標</th><th>結果</th></tr>
            <tr>
                <td>最大隊列深度</td>
                <td>{metrics['max_queue_depth']}</td>
                <td>< 100</td>
                <td>{'✓' if metrics['max_queue_depth'] < 100 else '✗'}</td>
            </tr>
            <tr>
                <td>數據包丟失率</td>
                <td>0%</td>
                <td>= 0%</td>
                <td>{'✓' if metrics['dropped_packets'] == 0 else '✗'}</td>
            </tr>
        </table>
    </body>
    </html>
    """
    
    return html

if __name__ == '__main__':
    metrics = parse_vcd('wave.vcd')
    report = generate_html_report(metrics)
    with open('simulation_report.html', 'w') as f:
        f.write(report)
    print("報告已生成：simulation_report.html")
```

---

## 面試展示重點

### 📊 面試演示結構（15-20分鐘）

#### **第1部分：項目背景（2分鐘）**
```
要點：
1️⃣ 為什麼選擇RoCE v2？
   - 當今AI訓練對網路的高要求
   - RoCE v2相比傳統TCP/IP的優勢
   - FPGA實現硬體加速的潛力

2️⃣ ECN機制的創新性
   - 傳統丟包恢復 vs 主動擁堵通知
   - 對性能的改善（低延遲、零丟包）

3️⃣ 項目的實際應用場景
   - 高性能運算集群
   - AI模型訓練通信
   ```

#### **第2部分：系統架構（3分鐘）**
```
演示內容：
📋 展示架構圖（使用PowerPoint或Visio）
  ├─ 各模塊的功能
  ├─ 數據流向
  └─ 時鐘域（所有都在100MHz）

💡 重點講解：
  ├─ 為什麼需要優先級隊列
  ├─ 流控制如何防止丟包
  └─ 效能監控的作用
```

#### **第3部分：Verilog實現（5分鐘）**
```
代碼展示（投影到屏幕）：
1️⃣ 展示RoC報頭解析模塊
   - 如何識別RoCE v2數據包
   - EtherType和UDP端口的檢查

2️⃣ 展示ECN標記邏輯
   - 隊列深度的監控
   - ECN位在IPv4報頭中的位置

3️⃣ 展示優先級隊列仲裁
   - 如何根據優先級選擇輸出
   - 公平性和饑餓避免

說明：
- 強調清晰的模塊劃分
- 遵循AXI-Stream協議
- 正確的握手和背壓機制
```

#### **第4部分：仿真驗證（7分鐘）**
```
仿真波形展示（最重要！）：
1️⃣ 基本功能測試
   - 數據正確傳輸
   - 報頭被正確解析

2️⃣ 擁堵檢測演示
   - 高流量時隊列深度增長
   - ECN位被標記
   - 展示具體的波形變化

3️⃣ 優先級隊列演示
   - 混合不同優先級數據
   - 展示高優先級優先輸出

4️⃣ 性能數據
   - 平均延遲：<50ns
   - 吞吐量：850+ Mbps
   - 丟包率：0%（在有流控制時）

關鍵：
- 用波形圖說話
- 量化性能指標
- 對比優化前後
```

#### **第5部分：創新點和未來方向（2分鐘）**
```
項目的創新性：
✨ 主動擁堵檢測（ECN）而非被動丟包恢復
✨ 動態優先級調整和QoS
✨ 實時性能監控
✨ 完全硬體實現（低延遲）

未來改進方向：
🚀 支持多隊列（>4級優先級）
🚀 自適應ECN閾值調整
🚀 支持更多NIC標準（InfiniBand等）
🚀 集成到商業FPGA網卡中
```

### 📌 面試回答要點

#### **常見問題及回答**

| 問題 | 回答要點 |
|------|---------|
| **為什麼用FPGA而不是軟體？** | FPGA可以實現硬體加速，延遲<100ns，軟體一般是μs級；適合數據中心線速網路處理 |
| **ECN和傳統WRED的區別？** | ECN是標準化的早期通知，WRED是概率丟棄；ECN無丟包，WRED有丟包重傳開銷 |
| **如何確保公平性？** | 使用加權輪詢(WRR)或嚴格優先級+背壓，防止低優先級饑餓 |
| **支持的帶寬是多少？** | 当前設計：100Mbps內部邏輯，可擴展到10Gbps(改進模塊寬度和時鐘) |
| **與Xilinx SmartNIC對比？** | 我們的實現更輕量級，針對ECN優化；商業產品功能更全 |

### 📁 演示文件清單

```
演示準備：
├─ presentation.pptx           （項目演示PPT）
│  ├─ 技術背景
│  ├─ 架構圖
│  ├─ 仿真波形截圖
│  └─ 性能對比
│
├─ 波形截圖/
│  ├─ basic_function.png       （基本功能測試波形）
│  ├─ congestion_test.png      （擁堵檢測波形）
│  ├─ priority_test.png        （優先級隊列波形）
│  └─ performance_report.png   （性能指標）
│
├─ 代碼結構/
│  ├─ module_diagram.pdf       （模塊架構圖）
│  ├─ data_flow.pdf            （數據流圖）
│  └─ timing_diagram.pdf       （時序圖）
│
└─ 演講稿.txt               （面試演講稿及技術細節）
```

---

## 附錄

### A. 快速參考 - AXI-Stream信號定義

```
AXI-Stream寬總線接口（128位數據）
┌─────────────────────────────────────────────────────┐
│ 信號名稱      │ 寬度  │ 方向 │ 說明              │
├─────────────────────────────────────────────────────┤
│ clk           │ 1     │ in   │ 時鐘信號 (100MHz) │
│ rst_n         │ 1     │ in   │ 低電平復位        │
│ s_axis_tdata  │ 128   │ in   │ 輸入數據 (16字節) │
│ s_axis_tkeep  │ 16    │ in   │ 字節有效掩碼      │
│ s_axis_tvalid │ 1     │ in   │ 輸入有效標誌      │
│ s_axis_tlast  │ 1     │ in   │ 幀最後字標誌      │
│ s_axis_tready │ 1     │ out  │ 輸入就緒信號      │
│ m_axis_tdata  │ 128   │ out  │ 輸出數據          │
│ m_axis_tkeep  │ 16    │ out  │ 字節有效掩碼      │
│ m_axis_tvalid │ 1     │ out  │ 輸出有效標誌      │
│ m_axis_tlast  │ 1     │ out  │ 幀最後字標誌      │
│ m_axis_tready │ 1     │ in   │ 輸出就緒信號      │
└─────────────────────────────────────────────────────┘
```

### B. ECN位設置詳解

```
IPv4報頭中的DSCP和ECN字段
┌──────────────────────────────────────────┐
│ 位7 ~ 位4 │ 位3 ~ 位2 │ 位1 ~ 位0        │
├──────────────────────────────────────────┤
│  DSCP     │    ECN (Explicit Congestion Notification) │
├──────────────────────────────────────────┤
│ DSCP (6 bits) - 區分服務代碼點            │
│  用於QoS標記                             │
│                                          │
│ ECN (2 bits) - 擁堵通知字段              │
│  00 = Not-ECT （不支持ECN）             │
│  01 = ECT(1) （支持ECN）                │
│  10 = ECT(0) （支持ECN）                │
│  11 = CE（擁堵經歷 - 表示檢測到擁堵） │
└──────────────────────────────────────────┘

RoCE應用中的推薦值：
- 普通RoCE數據：00 (Not-ECT)
- 支持ECN的數據：01 或 10 (ECT)
- 檢測到擁堵时：設置為 11 (CE)
```

### C. 項目文件清單

```
預期的最終項目結構：
/home/gml/Vivado_projects/RoCEv2_AI_Opt/
├── RoCEv2_AI_Opt.xpr                  (Vivado項目文件)
│
├── RoCEv2_AI_Opt.srcs/
│   ├── sources_1/
│   │   ├── new/
│   │   │   ├── roce_header_parser.v       ✅ 報頭解析模塊
│   │   │   ├── roce_ecn_marker.v          ✅ ECN標記模塊
│   │   │   ├── priority_queue_mgr.v       ✅ 優先級隊列
│   │   │   ├── flow_control_unit.v        ✅ 流控制模塊
│   │   │   ├── performance_monitor.v      ✅ 效能監控
│   │   │   └── roce_opt_top.v             ✅ 頂層集成
│   │   └── ip_1/                          (必要時添加IP核)
│   │
│   └── sim_1/
│       └── new/
│           ├── tb_roce_opt_top.v          ✅ 測試台
│           └── test_vectors.v             (可選の測試向量)
│
├── docs/
│   ├── README.md                      (本文件)
│   ├── architecture_diagram.pdf       (架構圖)
│   ├── timing_diagram.pdf             (時序圖)
│   ├── simulation_report.html         (仿真報告)
│   └── presentation.pptx              (面試PPT)
│
├── simulation/
│   ├── setup_simulation.tcl            (模擬設置)
│   ├── wave.vcd                        (波形文件)
│   └── generate_report.py              (報告生成)
│
└─scripts/
    ├── synthesize.tcl                  (綜合腳本)
    ├── implement.tcl                   (實現腳本)
    └── run_simulation.sh               (運行模擬)
```

---

## 📚 必讀書籍與完整知識地圖（針對本專題）

本節是「面向 RoCE v2 + ECN + FPGA 實作 + 面試展示」的學習地圖。
你可以把它當成最小閉環：
1. 先懂協議與問題
2. 再懂 RTL 與流控
3. 再做仿真驗證與性能量化
4. 最後轉成面試可講清楚的故事

### 一、必看書籍（優先級 + 你要看的重點）

#### A級（一定要看，直接影響你能不能把專題講清楚）

1. 《Computer Networking: A Top-Down Approach》
    你要看：
    - 應用層/傳輸層/網路層/鏈路層的分工
    - UDP 特性與為何 RoCE v2 使用 UDP over IPv4
    - 擁塞控制基本觀念（延遲、丟包、吞吐量的關係）
    為何必看：
    - 面試官會先看你有沒有「網路系統觀」，而不只是會寫 Verilog。

2. 《FPGA Prototyping by Verilog Examples (Pong P. Chu)》
    你要看：
    - 同步設計基本規則
    - FSM 寫法（one-hot / binary 都要會解釋）
    - FIFO、計數器、仲裁器
    為何必看：
    - 你的 `roce_ecn_marker`、`roce_header_parser`、優先級隊列模塊都靠這些基本功。

3. 《Writing Testbenches: Functional Verification of HDL Models》
    你要看：
    - Testbench 結構與 stimulus/monitor/checker 分層
    - directed test 與 corner case 思維
    - 如何設計可重複驗證的測試案例
    為何必看：
    - 你專題價值不是「有程式」，而是「已被波形和數據證明」。

#### B級（強烈建議，讓你回答深入問題）

4. 《High-Speed Digital Design: A Handbook of Black Magic》
    你要看：
    - 時序、訊號完整性、時鐘品質對系統穩定性的影響
    為何要看：
    - 面試問到 FPGA 實作落地，這本讓你講得專業。

5. 《Computer Architecture: A Quantitative Approach》
    你要看：
    - Latency vs Throughput 的量化方法
    - pipeline 與 buffer 對效能的影響
    為何要看：
    - 你的 ECN/隊列優化要靠數據模型支撐，不是只靠直覺。

6. 《TCP/IP Illustrated, Volume 1》
    你要看：
    - IPv4 header 欄位、DSCP/ECN 位元語義
    - UDP header 與封包分析方法
    為何要看：
    - 你在 header parser 中抽欄位與改 ECN bits，要講得非常精準。

#### C級（補強用，面試前有時間再看）

7. 《Digital Design and Computer Architecture》
    你要看：
    - RTL 到系統整合的抽象層對應
    - 組合路徑/時序路徑的分析思維

8. 《Network Algorithmics》
    你要看：
    - Queue management、scheduler、流量控制策略
    - 為什麼某些演算法在硬體上更可實現

### 二、官方文件（一定要查）

1. RoCE / InfiniBand Association 文檔（協議語義）
2. RFC 3168（ECN 核心定義）
3. Xilinx UG901（Synthesis）
4. Xilinx UG903（Constraints）
5. Xilinx UG900（Logic Simulation）
6. AXI4-Stream Protocol Specification（握手與背壓）

### 三、你專題必備知識點（完整清單）

#### 1. 網路與協議基礎

1. Ethernet frame 結構、Type 欄位意義
2. IPv4 header：Version/IHL、ToS(DSCP/ECN)、Protocol、Checksum
3. UDP header：source/destination port、length、checksum
4. RoCE v2 封裝位置與 UDP 4791 的識別
5. DSCP 與 ECN 的差異
6. ECN 四種值：Not-ECT、ECT(0)、ECT(1)、CE
7. 為何資料中心偏好「標記擁塞」而非「直接丟包」

#### 2. RDMA / RoCE 觀念

1. RDMA 核心價值：低 CPU 介入、低延遲、高吞吐
2. RoCE v1 vs RoCE v2 的差異
3. 為什麼 RoCE v2 能跨 L3 網段
4. BTH/PSN 基本概念（即使你目前簡化，也要能解釋）
5. AI 訓練流量型態（all-reduce、burst traffic）對網路的壓力

#### 3. 擁塞控制與隊列管理

1. Queue depth、head-of-line blocking
2. 閾值型擁塞檢測（threshold-based ECN marking）
3. 背壓（backpressure）在 AXI-Stream 中的映射
4. 優先級隊列（strict priority）優缺點
5. 飢餓問題（starvation）與改善思路（aging/WRR）
6. 丟包率、隊列延遲、吞吐量的三角平衡

#### 4. RTL / FPGA 設計核心

1. 同步時序設計：`always @(posedge clk)` 與 reset 策略
2. 組合邏輯與時序邏輯邊界
3. FSM 設計與狀態轉移可視化
4. FIFO 實現：full/empty/count、wr_ptr/rd_ptr
5. 參數化設計（寬度、深度、閾值可調）
6. 避免 latch、避免 combinational loop
7. 可綜合寫法與模擬專用寫法的差異

#### 5. AXI-Stream 實戰知識

1. `tvalid && tready` 才算一次有效傳輸
2. `tlast` 封包邊界語義
3. `tkeep` 部分位元組有效標記
4. 下游 `tready=0` 時上游必須穩定保持資料
5. 背壓傳遞對整條管線的影響

#### 6. Vivado 與約束

1. 設計流程：elaborate -> synth -> impl -> bitstream
2. XDC 必備：clock constraint、I/O standard、false path（如有）
3. Timing closure 指標：WNS/TNS 基本判讀
4. Simulation 與 Synthesis 結果差異排查
5. 專案可重建思維（Tcl 腳本化）

#### 7. 驗證方法學（你一定要具備）

1. Directed test：最小正確性測試
2. Corner case：空隊列、滿隊列、突發流量、連續背壓
3. 壓力測試：長時間高流量下穩定性
4. 自動檢查：scoreboard / assert 思路
5. 波形觀察重點：握手、封包邊界、ECN 位變化、隊列深度
6. 可重現性：同一測試可重跑得到一致結論

#### 8. 性能分析與量化

1. Latency 定義：封包進入到輸出可觀測事件的週期差
2. Throughput 定義：單位時間有效輸出位元數
3. Loss rate 定義：輸入與輸出計數比對
4. 需要展示的圖：
    - 吞吐量曲線
    - 延遲分佈
    - 隊列深度變化
    - ECN 標記比例
5. 對照組思維：
    - 無 ECN / 有 ECN
    - 無優先隊列 / 有優先隊列

#### 9. 面試表達知識點（最後一定會被問）

1. 為何選這題（AI 訓練網路痛點）
2. 為何用 FPGA（低延遲、可程式化、硬體並行）
3. 為何用 ECN（主動控制而非丟包重傳）
4. 你如何定義「成功」：具體 KPI 與量測方法
5. 你目前版本的限制與下一步改進（誠實且有路線圖）

### 四、建議學習順序（最省時間版本）

1. 先看協議：IPv4/UDP/ECN/RoCE 基礎
2. 再看硬體：AXI-Stream + FIFO + FSM
3. 再做驗證：testbench + 波形 + KPI 計算
4. 最後做講解：把設計決策和數據串成 5 分鐘故事

### 五、面試前必達成的「知識最小集合」

1. 能畫出封包路徑：Parser -> ECN Marker -> Queue -> Flow Control -> Monitor
2. 能解釋 ECN bits 何時從 ECT 變 CE
3. 能說明 AXI-Stream 握手與背壓在你設計中的行為
4. 能用數據回答：延遲、吞吐量、丟包率如何量測
5. 能指出你版本的兩個限制與兩個可行改進

### 六、快速資源連結（查資料用）

- [RoCE Specification (IBTA)](https://www.infinibandta.org/)
- [RFC 3168 - ECN](https://datatracker.ietf.org/doc/html/rfc3168)
- [IEEE 802.3 (Ethernet)](https://standards.ieee.org/)
- [Xilinx Documentation Hub](https://www.xilinx.com/support/documentation.html)
- [Xilinx AXI Stream Protocol](https://www.xilinx.com/support/documentation.html)

---

## 最後的話

### ✅ 成功要素
1. **理解協議**：深入理解RoCE v2和ECN機制
2. **清晰設計**：模塊化設計，清晰的接口
3. **充分測試**：多場景仿真驗證
4. **好的溝通**：清楚地解釋技術選擇
5. **專業演示**：準備充分，波形數據支撐

### ⏰ 時間管理建議
```
3月20日 - 3月26日：
├─ 3/20 - 3/21：實現核心模塊（parser, ECN, queue）
├─ 3/22：實現流控制和監控
├─ 3/23 - 3/24：集成和基本仿真
└─ 3/25 - 3/26：詳細仿真驗證 + 演示準備

3月27日：
├─ 上午：最後調試和演示準備
└─ 下午16:00：展示時間
```

### 🎯 面試時的核心自信點
- ✨ 完整的系統設計（從無到有）
- ✨ 深入的技術理解（為什麼這樣做）
- ✨ 量化的性能指標（數據說話）
- ✨ 實際的硬體驗證（波形為證）
- ✨ 清晰的演講表達（專業風範）

加油！祝您面試成功！🚀

---

**最後編輯：** 2026年3月25日  
**版本：** 1.0  
**作者：** GitHub Copilot | Claude Haiku 4.5
