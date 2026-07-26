module ahb_slave (
    input wire HCLK,           // AHB总线时钟
    input wire HRESETn,        // AHB总线复位，低电平有效
    input wire HSEL,           // 从设备选择信号
    input wire [31:0] HADDR,   // AHB总线地址
    input wire [1:0] HTRANS,   // 传输类型
    input wire HWRITE,         // 写使能
    input wire [2:0] HSIZE,    // 传输大小
    input wire [31:0] HWDATA,  // 写数据
    output reg [31:0] HRDATA, // 读数据
    output wire HREADY,        // 从设备就绪信号
    output wire HRESP          // 从设备响应信号
);

// 从设备内部寄存器
reg [31:0] ctrl0;
reg [31:0] ctrl1;
reg [31:0] status;

// 从设备行为
always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        // 复位时清零内部寄存器
        ctrl0 <= 32'b0;
    end else if (HSEL && HWRITE && HTRANS[1] && (HADDR == 8'h00)) begin
        // 如果被选中、写使能且传输有效，则写入数据到内部寄存器
        ctrl0 <= HWDATA;
    end
end

always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        // 复位时清零状态寄存器
        ctrl1 <= 32'b0;
    end else if (HSEL && HWRITE && HTRANS[1] && (HADDR == 8'h04)) begin
        // 如果被选中、读操作且传输有效，则读取状态寄存器
        ctrl1 <= HWDATA; 
    end
end

// 读数据输出
//assign HRDATA = (HSEL && (HADDR == 8'h00)) ? ctrl0 : 32'b0;
//assign HRDATA = (HSEL && (HADDR == 8'h04)  ? ctrl1 : 32'b0;
//assign HRDATA = (HSEL && (HADDR == 8'h08)  ? status : 32'b0;
always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        HRDATA <= 32'b0; // 复位时清零读数据
    end else if (HSEL && !HWRITE && HTRANS[1]) begin
        // 如果被选中、读操作且传输有效，则根据地址选择读数据
        case (HADDR)
            8'h00: HRDATA <= ctrl0; // 读取ctrl0寄存器
            8'h04: HRDATA <= ctrl1; // 读取ctrl1寄存器
            default: HRDATA <= 32'b0; // 默认返回0
        endcase
    end else begin
        HRDATA <= 32'b0; // 非读操作时清零读数据
    end
end

// 从设备就绪信号，这里假设从设备总是就绪
assign HREADY = 1'b1;

// 从设备响应信号，这里假设从设备总是给出OKAY响应
assign HRESP = 1'b0;

endmodule
