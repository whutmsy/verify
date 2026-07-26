class ahb_base_sequence extends uvm_sequence #(ahb_transaction);
  rand bit[7:0] addr;
  rand bit[31:0] data;
  rand bit hwrite;
  `uvm_object_utils(ahb_base_sequence)
  function new(string name = "ahb_base_sequence");
    super.new(name);
  endfunction
  virtual task body();
    `uvm_info("ahb_base_sequence", "body", UVM_LOW)
    repeat(1) begin
      ahb_transaction tr;
      tr = ahb_transaction::type_id::create("tr");
      start_item(tr);
      tr.HADDR = addr;
      tr.HWDATA = data;
      tr.HTRANS = 2'h3;
      tr.HSIZE = 2'h2;
      tr.HWRITE = hwrite;
      finish_item(tr);
      get_response(tr);
      tr.print();
    end
  endtask
endclass