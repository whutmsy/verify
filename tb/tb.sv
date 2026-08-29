//======================================================================
// tb_selfcheck.v - AHB 从设备独立自检平台（不依赖 UVM）
//   用简单的 AHB master 模型驱动 ahb_slave，覆盖：
//     1. 寄存器区字/字节读写
//     2. SRAM 区字/字节/半字读写
//     3. wait state（配置 CTRL2 插入 1/3 拍等待）
//     4. ERROR 响应（非法地址 / 未对齐 / 非法 HSIZE）
//   运行：iverilog -o sim.out tb_selfcheck.v ../vsrc/ahb_slave.v ../vsrc/sram.v
//         vvp sim.out
//======================================================================
`timescale 1ns/1ps

module tb;

    // 时钟与复位
    reg HCLK;
    reg HRESETn;

    // AHB 总线（master 模型驱动）
    reg        HSEL;
    reg [31:0] HADDR;
    reg [1:0]  HTRANS;
    reg        HWRITE;
    reg [2:0]  HSIZE;
    reg [31:0] HWDATA;
    wire [31:0] HRDATA;
    wire        HREADY;
    wire        HRESP;

    // 统计
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // 被测设计
    ahb_slave dut (
        .HCLK   (HCLK),
        .HRESETn(HRESETn),
        .HSEL   (HSEL),
        .HADDR  (HADDR),
        .HTRANS (HTRANS),
        .HWRITE (HWRITE),
        .HSIZE  (HSIZE),
        .HWDATA (HWDATA),
        .HRDATA (HRDATA),
        .HREADY (HREADY),
        .HRESP  (HRESP)
    );

    // 时钟 10ns
    initial HCLK = 0;
    always #5 HCLK = ~HCLK;

    // 复位：10ns 后释放
    initial begin
        HRESETn = 0;
        #20 HRESETn = 1;
    end

    // 总线初始空闲
    initial begin
        HSEL = 0; HADDR = 0; HTRANS = 2'b00;
        HWRITE = 0; HSIZE = 3'b000; HWDATA = 0;
    end

    //==================================================================
    // AHB master 模型任务（时序与验证环境 driver 一致）
    //==================================================================
    // 等待复位释放
    task wait_reset_done();
        begin
            while (!HRESETn) @(posedge HCLK);
        end
    endtask

    // 写数据 lane 对齐（AHB 规范：数据放在对应 lane）
    function [31:0] align_wdata(input [31:0] data, input [2:0] size, input [1:0] addr_low);
        begin
            case (size)
                3'b000: align_wdata = (data[7:0] << (8*addr_low));
                3'b001: align_wdata = addr_low[1] ? {data[15:0], 16'h0} : {16'h0, data[15:0]};
                default: align_wdata = data;
            endcase
        end
    endfunction

    task ahb_write(input [31:0] addr, input [31:0] data, input [2:0] size, output err);
        begin
            wait_reset_done();
            @(posedge HCLK);
            HSEL <= 1'b1;
            HADDR <= addr;
            HTRANS <= 2'b10;   // NONSEQ
            HWRITE <= 1'b1;
            HSIZE <= size;
            @(posedge HCLK);
            HWDATA <= align_wdata(data, size, addr[1:0]);
            HSEL <= 1'b0;
            HTRANS <= 2'b00;
            #1;
            wait (HREADY == 1'b1);
            #1;  // 等待 HRESP 组合输出传播稳定后再采样
            err = HRESP;
            @(posedge HCLK);
            HSEL <= 1'b0; HTRANS <= 2'b00; HWRITE <= 1'b0;
            HSIZE <= 3'b000; HADDR <= 32'h0; HWDATA <= 32'h0;
        end
    endtask

    task ahb_read(input [31:0] addr, input [2:0] size, output [31:0] data, output err);
        begin
            wait_reset_done();
            @(posedge HCLK);
            HSEL <= 1'b1;
            HADDR <= addr;
            HTRANS <= 2'b10;
            HWRITE <= 1'b0;
            HSIZE <= size;
            @(posedge HCLK);
            HWDATA <= 32'h0;
            HSEL <= 1'b0;
            HTRANS <= 2'b00;
            #1;
            wait (HREADY == 1'b1);
            #1;  // 等待 HRDATA/HRESP 组合输出传播稳定后再采样
            data = HRDATA;
            err = HRESP;
            @(posedge HCLK);
            HSEL <= 1'b0; HTRANS <= 2'b00; HWRITE <= 1'b0;
            HSIZE <= 3'b000; HADDR <= 32'h0; HWDATA <= 32'h0;
        end
    endtask

    // 检查辅助
    task check(input [127:0] name, input [31:0] got, input [31:0] exp, input exp_err, input got_err);
        begin
            if (got_err !== exp_err) begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] %0s: err got=%0b exp=%0b", name, got_err, exp_err);
            end
            else if (got_err) begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %0s: ERROR response as expected", name);
            end
            else if (got === exp) begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %0s: got=%h exp=%h", name, got, exp);
            end
            else begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] %0s: got=%h exp=%h", name, got, exp);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_selfcheck.vcd");
        $dumpvars(0, tb);
    end

    //==================================================================
    // 测试主流程
    //==================================================================
    integer i;
    reg [31:0] rd;
    reg err;

    initial begin
        #30;  // 等复位释放
        $display("==================================================");
        $display(" AHB Slave Self-Check Testbench");
        $display("==================================================");

        // ---- 1. 寄存器区字读写 ----
        ahb_write(32'h0000_0000, 32'hDEAD_BEEF, 3'b010, err);  // 写 CTRL0
        ahb_read (32'h0000_0000, 3'b010, rd, err);
        check("REG0 word write/read", rd, 32'hDEAD_BEEF, 1'b0, err);

        ahb_write(32'h0000_0004, 32'h1234_5678, 3'b010, err);  // 写 CTRL1
        ahb_read (32'h0000_0004, 3'b010, rd, err);
        check("REG1 word write/read", rd, 32'h1234_5678, 1'b0, err);

        // ---- 2. 寄存器区字节写（部分更新）----
        ahb_write(32'h0000_0008, 32'h0000_00AB, 3'b000, err);  // byte 写 CTRL2[7:0]
        ahb_read (32'h0000_0008, 3'b010, rd, err);
        check("REG2 byte write/word read", rd, 32'h0000_00AB, 1'b0, err);

        // ---- 3. SRAM 字读写 ----
        ahb_write(32'h0000_0020, 32'hA5A5_5A5A, 3'b010, err);  // SRAM word0
        ahb_read (32'h0000_0020, 3'b010, rd, err);
        check("SRAM word0 write/read", rd, 32'hA5A5_5A5A, 1'b0, err);

        ahb_write(32'h0000_03FC, 32'h0F0F_F0F0, 3'b010, err);  // SRAM 末尾 word
        ahb_read (32'h0000_03FC, 3'b010, rd, err);
        check("SRAM last word write/read", rd, 32'h0F0F_F0F0, 1'b0, err);

        // ---- 4. SRAM 字节/半字访问 ----
        ahb_write(32'h0000_0100, 32'h0000_00FF, 3'b000, err);  // byte 写
        ahb_read (32'h0000_0100, 3'b000, rd, err);
        check("SRAM byte read", rd, 32'h0000_00FF, 1'b0, err);
        ahb_read (32'h0000_0100, 3'b010, rd, err);
        check("SRAM byte-write word-read", rd, 32'h0000_00FF, 1'b0, err);

        ahb_write(32'h0000_0200, 32'h0000_1234, 3'b001, err);  // half 写（低半字）
        ahb_read (32'h0000_0200, 3'b001, rd, err);
        check("SRAM half read", rd, 32'h0000_1234, 1'b0, err);

        ahb_write(32'h0000_0202, 32'h0000_5678, 3'b001, err);  // half 写（高半字）
        ahb_read (32'h0000_0200, 3'b010, rd, err);
        check("SRAM half-write word-read", rd, 32'h5678_1234, 1'b0, err);

        // ---- 5. ERROR：非法地址 ----
        ahb_write(32'h0000_1000, 32'hCAFE_F00D, 3'b010, err);
        check("ERROR reserved addr write", rd, 32'h0, 1'b1, err);
        ahb_read (32'h0000_1000, 3'b010, rd, err);
        check("ERROR reserved addr read", rd, 32'h0, 1'b1, err);

        // ---- 6. ERROR：未对齐访问 ----
        ahb_write(32'h0000_0002, 32'h1234_5678, 3'b010, err);
        check("ERROR misalign word write", rd, 32'h0, 1'b1, err);
        ahb_write(32'h0000_0201, 32'h0000_5678, 3'b001, err);
        check("ERROR misalign half write", rd, 32'h0, 1'b1, err);

        // ---- 7. ERROR：非法 HSIZE ----
        ahb_read (32'h0000_0000, 3'b100, rd, err);
        check("ERROR illegal hsize read", rd, 32'h0, 1'b1, err);

        // ---- 8. wait state：配置 1 拍 wait ----
        ahb_write(32'h0000_0008, 32'h0000_0001, 3'b010, err);  // CTRL2[1:0]=01
        ahb_write(32'h0000_0040, 32'h1111_2222, 3'b010, err);  // 带 wait 写
        ahb_read (32'h0000_0040, 3'b010, rd, err);
        check("WAIT1 SRAM write/read", rd, 32'h1111_2222, 1'b0, err);

        // ---- 9. wait state：配置 3 拍 wait ----
        ahb_write(32'h0000_0008, 32'h0000_0003, 3'b010, err);  // CTRL2[1:0]=11
        ahb_write(32'h0000_000C, 32'h8888_9999, 3'b010, err);  // 带 3 拍 wait 写
        ahb_read (32'h0000_000C, 3'b010, rd, err);
        check("WAIT3 REG write/read", rd, 32'h8888_9999, 1'b0, err);

        // ---- 10. wait 期间 ERROR 仍正确 ----
        ahb_write(32'h0000_1000, 32'hDEAD_0000, 3'b010, err);  // wait=3 时非法地址
        check("ERROR with wait active", rd, 32'h0, 1'b1, err);

        // ---- 恢复 wait_cycles = 0 ----
        ahb_write(32'h0000_0008, 32'h0000_0000, 3'b010, err);

        // ---- 结果汇总 ----
        $display("==================================================");
        $display(" RESULT: pass=%0d fail=%0d", pass_cnt, fail_cnt);
        $display("==================================================");
        if (fail_cnt == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule