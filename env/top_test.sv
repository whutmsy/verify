class top_test extends uvm_test;

    env top_env;

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
        phase.phase_done.set_drain_time(this, 30000);
        phase.raise_objection(this);

        // 场景 1：寄存器区读写（字/字节访问）
        begin
            reg_seq seq;
            seq = reg_seq::type_id::create("seq");
            seq.start(top_env.ahb0.ahb_sqr);
        end

        // 场景 2：SRAM 存储区读写（字/字节/半字访问）
        begin
            sram_seq seq;
            seq = sram_seq::type_id::create("seq");
            seq.start(top_env.ahb0.ahb_sqr);
        end

        // 场景 3：wait state 测试（配置 CTRL2 插入 1/3 拍等待）
        begin
            wait_seq seq;
            seq = wait_seq::type_id::create("seq");
            seq.start(top_env.ahb0.ahb_sqr);
        end

        // 场景 4：ERROR 响应测试（非法地址/未对齐/非法 HSIZE）
        begin
            err_seq seq;
            seq = err_seq::type_id::create("seq");
            seq.start(top_env.ahb0.ahb_sqr);
        end

        phase.drop_objection(this);
    endtask

endclass