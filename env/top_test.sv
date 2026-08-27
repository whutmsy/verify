class top_test extends uvm_test;

    env top_env;
    ahb_base_sequence seq0;

    `uvm_component_utils(top_test)
    
    // Constructor
    function new(string name = "top_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    // Build phase
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        top_env = env::type_id::create("top_env", this);
    endfunction
    
    // Run phase
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.phase_done.set_drain_time(this,30000);
        phase.raise_objection(this);
        seq0 = new();
        assert(seq0.randomize() with {addr == 8'h0; data == 32'hff; hwrite == 1'b1;});
        seq0.start(top_env.ahb0.ahb_sqr);
        assert(seq0.randomize() with {addr == 8'h0; data == 32'h0; hwrite == 1'b0;});
        seq0.start(top_env.ahb0.ahb_sqr);
        phase.drop_objection(this);
    endtask

    virtual task main_phase(uvm_phase phase);
        //super.main_phase(phase); 
    endtask

endclass //case extends uvm_test