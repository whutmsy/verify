
`timescale 1ns/1ps

module tb;
`include "uvm_macros.svh"
import uvm_pkg::*;
import top_package::*;

logic clk;
logic rst_n;

initial begin
    clk = 0;
    forever begin
        #5 clk = ~clk;
    end
end

initial begin
    rst_n = 0;
    #10 rst_n = 1;
end

ahb_slave_if ahb_if();

assign ahb_if.HCLK = clk;
assign ahb_if.HRESETn = rst_n;

logic [31:0] hrdata;
assign hrdata = ahb_if.HRDATA;

ahb_slave u_ahb_slave (
    .HCLK(ahb_if.HCLK),
    .HRESETn(ahb_if.HRESETn),
    .HSEL(ahb_if.HSEL),
    .HADDR(ahb_if.HADDR),
    .HTRANS(ahb_if.HTRANS),
    .HWRITE(ahb_if.HWRITE),
    .HSIZE(ahb_if.HSIZE),
    .HWDATA(ahb_if.HWDATA),
    .HRDATA(ahb_if.HRDATA),
    .HREADY(ahb_if.HREADY),
    .HRESP(ahb_if.HRESP)
);

initial begin
    uvm_config_db#(virtual ahb_slave_if)::set(null, "uvm_test_top.top_env.ahb0.*", "vif", ahb_if);
end

initial begin
    run_test("top_test");
end

initial begin
    $dumpfile("dumpfile.vcd");
    $dumpvars(0, tb);
end

endmodule