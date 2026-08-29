class ahb_transaction extends uvm_sequence_item;
    bit HCLK;
    bit HRESETn;
    bit HSEL;
    bit [31:0] HADDR;
    bit [1:0] HTRANS;
    bit HWRITE;
    bit [2:0] HSIZE;
    bit [31:0] HWDATA;
    bit [31:0] HRDATA;
    bit HREADY;
    bit HRESP;
    `uvm_object_utils_begin(ahb_transaction)
      `uvm_field_int(HADDR, UVM_ALL_ON)
      `uvm_field_int(HWDATA, UVM_ALL_ON)
      `uvm_field_int(HRDATA, UVM_ALL_ON)
      `uvm_field_int(HTRANS, UVM_ALL_ON)
      `uvm_field_int(HWRITE, UVM_ALL_ON)
      `uvm_field_int(HSIZE, UVM_ALL_ON)
      `uvm_field_int(HRESP, UVM_ALL_ON)
    `uvm_object_utils_end
    function new(string name = "ahb_transaction");
      super.new(name);
    endfunction
endclass