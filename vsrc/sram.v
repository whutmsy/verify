module sram (
    input wire clk,           // 时钟信号
    input wire rst,           // 复位信号，低电平有效
    input wire [9:0] addr,    // 地址输入
    input wire [7:0] data_in, // 写入数据
    output reg [7:0] data_out,// 读出数据
    input wire write_en       // 写使能信号，高电平有效
);

// 定义SRAM存储器数组
reg [7:0] memory [0:255];

// 读操作
always @(posedge clk) begin
    if (!rst) begin
        // 复位时，将data_out清零
        data_out <= 8'b0;
    end else if (!write_en) begin
        // 如果写使能信号为低，执行读操作
        data_out <= memory[addr];
    end
end

// 写操作
always @(posedge clk) begin
    if (!rst) begin
        // 复位时，将所有存储器单元清零
        integer i;
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] <= 8'b0;
        end
    end else if (write_en) begin
        // 如果写使能信号为高，执行写操作
        memory[addr] <= data_in;
    end
end

endmodule
