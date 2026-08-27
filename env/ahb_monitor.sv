class ahb_monitor extends uvm_monitor;

  virtual ahb_slave_if vif;
  uvm_analysis_port #(ahb_transaction) mon_ap;

  `uvm_component_utils(ahb_monitor)

  function new(string name = "ahb_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon_ap = new("mon_ap", this);
    if(!uvm_config_db#(virtual ahb_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction

  task run_phase(uvm_phase phase);
    ahb_transaction tr;
    forever begin
      @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
      if(vif.HSEL && vif.HTRANS[1] && vif.HREADY) begin
        tr = ahb_transaction::type_id::create("tr");
        tr.HSEL   = vif.HSEL;
        tr.HADDR  = vif.HADDR;
        tr.HTRANS = vif.HTRANS;
        tr.HWRITE = vif.HWRITE;
        tr.HSIZE  = vif.HSIZE;
        if(vif.HWRITE) begin
          tr.HWDATA = vif.HWDATA;
        end else begin
          tr.HRDATA = vif.HRDATA;
        end
        `uvm_info(get_type_name(), $sformatf("Monitored: addr: %0h write: %0b data: %0h", tr.HADDR, tr.HWRITE, vif.HWRITE ? tr.HWDATA : tr.HRDATA), UVM_MEDIUM);
        mon_ap.write(tr);
      end
    end
  endtask

endclass
