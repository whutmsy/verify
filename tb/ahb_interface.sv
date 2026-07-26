interface ahb_slave_if;
    // AHB总线时钟
    logic HCLK;
    // AHB总线复位，低电平有效
    logic HRESETn;
    // 从设备选择信号
    logic HSEL;
    // AHB总线地址
    logic [31:0] HADDR;
    // 传输类型
    logic [1:0] HTRANS;
    // 写使能
    logic HWRITE;
    // 传输大小
    logic [2:0] HSIZE;
    // 写数据
    logic [31:0] HWDATA;
    // 读数据
    logic [31:0] HRDATA;
    // 从设备就绪信号
    logic HREADY;
    // 从设备响应信号
    logic HRESP;
endinterface
