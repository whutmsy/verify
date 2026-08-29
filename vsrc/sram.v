//======================================================================
// sram.v - SRAM 存储体模型（AHB 从设备的存储区）
//   - 256 word x 32bit（1KB）存储阵列
//   - 异步读：ce=1 且 we=0 时，组合输出读数据（数据阶段可直接返回）
//   - 字节使能写：ce=1 且 we=1 时，clk 上升沿按 wstrb[3:0] 逐字节写入
//   - 低电平异步复位清零
//======================================================================
module sram #(
    parameter ADDR_WIDTH = 8,        // 字地址宽度（深度 = 2^ADDR_WIDTH word）
    parameter DATA_WIDTH = 32        // 数据宽度（bit）
)(
    input  wire                   clk,     // 时钟
    input  wire                   rst_n,   // 复位，低电平有效
    input  wire                   ce,      // 片选，高电平有效
    input  wire                   we,      // 写使能，高电平有效
    input  wire [3:0]             wstrb,   // 字节写使能 [3:0] -> 对应 byte lane
    input  wire [ADDR_WIDTH-1:0]  addr,    // 字地址（以 word 为单位）
    input  wire [DATA_WIDTH-1:0]  wdata,   // 写数据
    output wire [DATA_WIDTH-1:0]  rdata    // 读数据（异步组合输出）
);

    localparam DEPTH = (1 << ADDR_WIDTH);   // 字数
    localparam BYTES = DEPTH * (DATA_WIDTH/8); // 总字节数

    // 存储阵列：按字节组织，便于字节使能写
    reg [7:0] mem [0:BYTES-1];
    integer i;

    // 异步读：片选且非写时，组合输出读数据
    assign rdata = (ce && !we) ?
                   {mem[{addr,2'b00}+3], mem[{addr,2'b00}+2],
                    mem[{addr,2'b00}+1], mem[{addr,2'b00}+0]} :
                   {DATA_WIDTH{1'b0}};

    // 写操作：按字节写使能逐字节写入
    always @(posedge clk) begin
        if (ce && we) begin
            for (i = 0; i < (DATA_WIDTH/8); i = i + 1) begin
                if (wstrb[i])
                    mem[{addr,2'b00}+i] <= wdata[i*8 +: 8];
            end
        end
    end

    // 复位清零
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < BYTES; i = i + 1)
                mem[i] <= 8'h0;
        end
    end

endmodule