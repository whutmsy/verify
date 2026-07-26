class env extends uvm_env;

    ahb_agent ahb0;

    `uvm_component_utils(env)

    // Constructor
    function new(string name="env", uvm_component parent);
        super.new(name, parent);
    endfunction

    // Build phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ahb0 = ahb_agent::type_id::create("ahb0", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Add connections between components here if needed
    endfunction

endclass