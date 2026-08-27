module ahb_slave (
    input wire HCLK,           // AHB总线时钟
    input wire HRESETn,        // AHB总线复位，低电平有效
    input wire HSEL,           // 从设备选择信号
    input wire [31:0] HADDR,   // AHB总线地址
    input wire [1:0] HTRANS,   // 传输类型
    input wire HWRITE,         // 写使能
    input wire [2:0] HSIZE,    // 传输大小
    input wire [31:0] HWDATA,  // 写数据
    output wire [31:0] HRDATA, // 读数据
    output wire HREADY,        // 从设备就绪信号
    output wire HRESP          // 从设备响应信号
);

// 从设备内部寄存器
reg [31:0] ctrl0;
reg [31:0] ctrl1;

// 从设备行为
always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        // 复位时清零内部寄存器
        ctrl0 <= 32'b0;
    end else if (HSEL && HWRITE && HTRANS[1] && HREADY
                 && (HSIZE == 3'b010) && (HADDR[7:0] == 8'h00)) begin
        // 如果被选中、写使能、传输有效且为整字写，则写入数据到内部寄存器
        ctrl0 <= HWDATA;
    end
end

always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        // 复位时清零ctrl1寄存器
        ctrl1 <= 32'b0;
    end else if (HSEL && HWRITE && HTRANS[1] && HREADY
                 && (HSIZE == 3'b010) && (HADDR[7:0] == 8'h04)) begin
        // 如果被选中、写使能、传输有效且为整字写，则写入数据到ctrl1寄存器
        ctrl1 <= HWDATA;
    end
end

// 读数据输出，组合逻辑输出，数据相即有效
assign HRDATA = (HSEL && !HWRITE && HTRANS[1]) ?
                (HADDR[7:0] == 8'h00 ? ctrl0 :
                 HADDR[7:0] == 8'h04 ? ctrl1 : 32'b0) : 32'b0;

// 从设备就绪信号，这里假设从设备总是就绪
assign HREADY = 1'b1;

// 从设备响应信号，这里假设从设备总是给出OKAY响应
assign HRESP = 1'b0;

endmodule
