//======================================================================
// ahb_slave.v - 完整的 AHB 从设备（AMBA 2.0 AHB 规范）
//
// 功能特性：
//   1. 流水线访问：地址阶段与数据阶段重叠，每个上升沿采样地址
//   2. 传输类型：支持 IDLE / BUSY / NONSEQ / SEQ（NONSEQ 与 SEQ 均按独立访问处理）
//   3. 访问粒度：支持字节(8bit)/半字(16bit)/字(32bit)读写，自动生成写 strobe
//   4. 未对齐检测：半字访问地址 [0] 必须为 0，字访问地址 [1:0] 必须为 00，
//      否则返回 ERROR 响应
//   5. wait state：通过 CTRL2[1:0] 配置每个访问插入的等待拍数(0~3)
//   6. ERROR 响应：访问非法地址/非法 HSIZE/未对齐时，返回 HRESP=1
//
// 地址映射（低 16 位译码，高 16 位必须为 0，否则 ERROR）：
//   0x0000 - 0x000F : 寄存器区（4 个 32bit 寄存器）
//      0x00 CTRL0 : 数据寄存器 0
//      0x04 CTRL1 : 数据寄存器 1
//      0x08 CTRL2 : WAIT_CTRL，[1:0] = 每访问插入的 wait 拍数
//      0x0C CTRL3 : 数据寄存器 3
//   0x0020 - 0x041F : SRAM 存储区（256 word x 32bit = 1KB）
//   其他地址        : ERROR 响应
//
// 时序约定（与验证环境 driver/monitor 对齐）：
//   - 地址阶段：HREADY 为高的上升沿采样 HADDR/HTRANS/HSIZE/HWRITE/HSEL
//   - 数据阶段：采样后的下一拍（或 wait 结束后的拍）HREADY 拉高，
//     写事务在该拍上升沿采样 HWDATA，读事务在该拍输出 HRDATA
//======================================================================
module ahb_slave (
    input  wire        HCLK,        // AHB 总线时钟
    input  wire        HRESETn,     // AHB 总线复位，低电平有效
    input  wire        HSEL,        // 从设备选择信号
    input  wire [31:0] HADDR,       // AHB 总线地址
    input  wire [1:0]  HTRANS,      // 传输类型
    input  wire        HWRITE,      // 写使能
    input  wire [2:0]  HSIZE,       // 传输大小
    input  wire [31:0] HWDATA,      // 写数据
    output wire [31:0] HRDATA,      // 读数据
    output wire        HREADY,      // 从设备就绪信号
    output wire        HRESP        // 从设备响应信号（0=OKAY, 1=ERROR）
);

    //==================================================================
    // 内部寄存器定义
    //==================================================================
    reg [31:0] ctrl0;               // 数据寄存器 0
    reg [31:0] ctrl1;               // 数据寄存器 1
    reg [31:0] ctrl2;               // WAIT_CTRL：[1:0] 控制 wait 拍数
    reg [31:0] ctrl3;               // 数据寄存器 3

    wire [1:0] wait_cycles = ctrl2[1:0];   // 每个访问插入的 wait 拍数

    //==================================================================
    // 地址阶段采样（流水线）
    //   在 HREADY 为高的上升沿采样地址阶段信号。
    //   无 wait 时：地址采样拍 = 前一事务的数据阶段完成拍
    //==================================================================
    reg        a_hsel;
    reg [31:0] a_haddr;
    reg [1:0]  a_htrans;
    reg [2:0]  a_hsize;
    reg        a_hwrite;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            a_hsel   <= 1'b0;
            a_haddr  <= 32'h0;
            a_htrans <= 2'b00;
            a_hsize  <= 3'b000;
            a_hwrite <= 1'b0;
        end else if (HREADY) begin
            a_hsel   <= HSEL;
            a_haddr  <= HADDR;
            a_htrans <= HTRANS;
            a_hsize  <= HSIZE;
            a_hwrite <= HWRITE;
        end
    end

    //==================================================================
    // 地址译码（基于锁存后的地址阶段信号）
    //==================================================================
    wire a_valid    = a_hsel && a_htrans[1];     // NONSEQ/SEQ 传输有效
    wire a_top_ok   = (a_haddr[31:16] == 16'h0); // 高 16 位地址必须为 0
    wire a_is_reg   = a_top_ok && (a_haddr[15:0] <= 16'h000F);
    wire a_is_sram  = a_top_ok && (a_haddr[15:0] >= 16'h0020) &&
                      (a_haddr[15:0] <= 16'h041F);
    wire a_hsize_ok = (a_hsize == 3'b000) || (a_hsize == 3'b001) ||
                      (a_hsize == 3'b010);

    // 未对齐检测：半字访问 addr[0] 必须为 0；字访问 addr[1:0] 必须为 00
    wire a_misalign = (a_hsize == 3'b001 && a_haddr[0]) ||
                      (a_hsize == 3'b010 && a_haddr[1:0] != 2'b00);

    // ERROR 条件：非法地址 / 非法 HSIZE / 未对齐
    wire a_err = a_valid && (!a_hsize_ok || a_misalign || (!a_is_reg && !a_is_sram));

    // 写 strobe 生成（依据 HSIZE 与地址低位）
    //   byte:  仅命中一个 byte lane
    //   half:  命中两个相邻 lane（地址 [1] 选择高低半字）
    //   word:  全部 4 个 lane
    wire [3:0] wstrb;
    assign wstrb = (a_hsize == 3'b000) ? (4'b0001 << a_haddr[1:0]) :
                   (a_hsize == 3'b001) ? (a_haddr[1] ? 4'b1100 : 4'b0011) :
                                         4'b1111;

    //==================================================================
    // 数据阶段状态机
    //   IDLE : 空闲，等待有效事务
    //   WAIT : 插入等待拍（HREADY=0）
    //   FINAL: 数据阶段完成拍（HREADY=1，写采样 / 读输出）
    //   ERR0 : ERROR 响应第 1 拍（HREADY=0, HRESP=1）
    //   ERR1 : ERROR 响应第 2 拍（HREADY=1, HRESP=1，主端采样到 ERROR）
    //==================================================================
    localparam IDLE = 3'd0, WAIT = 3'd1, FINAL = 3'd2, ERR0 = 3'd3, ERR1 = 3'd4;
    reg [2:0]  state;
    reg [1:0]  wait_cnt;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state    <= IDLE;
            wait_cnt <= 2'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (a_valid && a_err) begin
                        state <= ERR0;                    // 非法访问 -> ERROR
                    end else if (a_valid) begin
                        if (wait_cycles > 2'd0) begin     // 需要插入 wait
                            state    <= WAIT;
                            wait_cnt <= wait_cycles - 2'd1;
                        end else begin
                            state <= FINAL;               // 无 wait，直接完成
                        end
                    end
                end
                WAIT: begin
                    if (wait_cnt == 2'd0)
                        state <= FINAL;
                    else
                        wait_cnt <= wait_cnt - 2'd1;
                end
                FINAL: state <= IDLE;
                ERR0:  state <= ERR1;
                ERR1:  state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    //==================================================================
    // 输出信号（组合逻辑）
    //==================================================================
    // HREADY：
    //   - WAIT/ERR0 状态拉低（插入等待/错误响应）
    //   - IDLE 状态但已采样到待处理事务（a_valid=1）时拉低，
    //     表示数据阶段延长（等待进入 FINAL 完成拍）
    //   - 其余状态（空闲、FINAL、ERR1）为高
    assign HREADY = (state == WAIT || state == ERR0) ? 1'b0 :
                    (state == IDLE && a_valid)        ? 1'b0 :
                                                       1'b1;

    // HRESP：ERR0/ERR1 状态输出 ERROR（保持到主端采样沿）
    assign HRESP  = (state == ERR0 || state == ERR1) ? 1'b1 : 1'b0;

    //==================================================================
    // 写数据通路（FINAL 拍上升沿采样 HWDATA）
    //==================================================================
    integer i;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ctrl0 <= 32'h0;
            ctrl1 <= 32'h0;
            ctrl2 <= 32'h0;
            ctrl3 <= 32'h0;
        end else if (state == FINAL && a_valid && !a_err && a_hwrite) begin
            if (a_is_reg) begin
                // 寄存器区：按字节使能写入
                case (a_haddr[4:2])
                    3'd0: for (i = 0; i < 4; i = i + 1)
                            if (wstrb[i]) ctrl0[i*8 +: 8] <= HWDATA[i*8 +: 8];
                    3'd1: for (i = 0; i < 4; i = i + 1)
                            if (wstrb[i]) ctrl1[i*8 +: 8] <= HWDATA[i*8 +: 8];
                    3'd2: for (i = 0; i < 4; i = i + 1)
                            if (wstrb[i]) ctrl2[i*8 +: 8] <= HWDATA[i*8 +: 8];
                    3'd3: for (i = 0; i < 4; i = i + 1)
                            if (wstrb[i]) ctrl3[i*8 +: 8] <= HWDATA[i*8 +: 8];
                    default: ; // 保留寄存器，写无效
                endcase
            end
            // SRAM 区写由 sram 模块在 FINAL 拍完成（sram_we 见下）
        end
    end

    //==================================================================
    // SRAM 存储体例化
    //==================================================================
    wire        sram_ce   = a_valid && a_is_sram && !a_err;  // 地址有效即选中
    wire        sram_we   = sram_ce && (state == FINAL) && a_hwrite;
    wire [7:0]  sram_addr = a_haddr[9:2] - 8'd8;             // 0x20 起始 -> word index 0
    wire [31:0] sram_rdata;

    sram u_sram (
        .clk   (HCLK),
        .rst_n (HRESETn),
        .ce    (sram_ce),
        .we    (sram_we),
        .wstrb (wstrb),
        .addr  (sram_addr),
        .wdata (HWDATA),
        .rdata (sram_rdata)
    );

    //==================================================================
    // 读数据通路（FINAL 拍组合输出）
    //==================================================================
    wire [31:0] reg_rdata;
    assign reg_rdata = (a_haddr[4:2] == 3'd0) ? ctrl0 :
                       (a_haddr[4:2] == 3'd1) ? ctrl1 :
                       (a_haddr[4:2] == 3'd2) ? ctrl2 : ctrl3;

    // 原始读数据（寄存器区或 SRAM 区）
    wire [31:0] rd_word;
    assign rd_word = a_is_reg ? reg_rdata : (a_is_sram ? sram_rdata : 32'h0);

    // lane 对齐：字节/半字读只输出对应 lane 的数据，其余位置 0
    wire [31:0] rd_aligned;
    assign rd_aligned = (a_hsize == 3'b000) ?
                        (rd_word[8*a_haddr[1:0] +: 8] << (8*a_haddr[1:0])) :
                        (a_hsize == 3'b001) ?
                        (a_haddr[1] ? {rd_word[15:0], 16'h0} : {16'h0, rd_word[15:0]}) :
                        rd_word;

    assign HRDATA = (state == FINAL && a_valid && !a_err && !a_hwrite) ?
                    rd_aligned : 32'h0;

endmodule