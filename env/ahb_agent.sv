class ahb_agent extends uvm_agent;

    ahb_sequencer ahb_sqr;
    ahb_driver ahb_drv;

    `uvm_component_utils(ahb_agent)

    function new(string name="ahb_agent", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ahb_sqr = ahb_sequencer::type_id::create("ahb_sqr", this);
        ahb_drv = ahb_driver::type_id::create("ahb_drv", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ahb_drv.seq_item_port.connect(ahb_sqr.seq_item_export);
    endfunction

endclass