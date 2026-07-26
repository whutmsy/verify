class ahb_driver extends uvm_driver #(ahb_transaction);
  `uvm_component_utils(ahb_driver)
  virtual ahb_slave_if vif;
  ahb_transaction trans;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual ahb_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(trans);
      drive_ahb(trans);
      seq_item_port.item_done(trans);
    end
  endtask
  task ahb_reset();
    `uvm_info(get_type_name(), "AHB reset", UVM_HIGH);
    vif.HSEL <= 1'b0;
    vif.HADDR <= 32'h0;
    vif.HTRANS <= 2'b00;
    vif.HWRITE <= 1'b0;
    vif.HSIZE <= 2'b00;
    vif.HWDATA <= 32'h0;
  endtask
  task drive_ahb(ref ahb_transaction trans);
    `uvm_info(get_type_name(), $sformatf("Driving AHB transaction addr: %0h data: %0h hwrite: %0h", trans.HADDR, trans.HWDATA, trans.HWRITE), UVM_LOW);
    @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    vif.HSEL <= 1'b1;
    vif.HADDR <= trans.HADDR;
    vif.HTRANS <= trans.HTRANS;
    vif.HWRITE <= trans.HWRITE;
    vif.HSIZE <= trans.HSIZE;
    @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    if(vif.HWRITE) vif.HWDATA <= trans.HWDATA;
    wait(vif.HREADY == 1'b1);
    if(!vif.HWRITE) begin
      repeat(1) @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
      trans.HRDATA = vif.HRDATA;
      `uvm_info(get_type_name(), $sformatf("trans.HRDATA: %0h", trans.HRDATA), UVM_HIGH)
    end
    else begin
      repeat(1) @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
    end
    ahb_reset();
  endtask
endclass